die_with() 
{
	echo "$*" >&2
	exit 1
}

# for a given GH repo and action name, compute workflow_id
# warning: variable workflow_id is a global, so don't call this in parallel executions!
computeWorkflowId() {
    this_repo=$1
    this_action_name=$2
    workflow_id=$(curl -sSL "https://api.github.com/repos/${this_repo}/actions/workflows" -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" | jq --arg search_field "${this_action_name}" '.workflows[] | select(.name == $search_field).id'); # echo "workflow_id = $workflow_id"
    if [[ ! $workflow_id ]]; then
        die_with "[ERROR] Could not compute workflow id from https://api.github.com/repos/${this_repo}/actions/workflows - check your GITHUB_TOKEN is active"
    fi
    # echo "[INFO] Got workflow_id $workflow_id for $this_repo action '$this_action_name'"
}

# generic method to call a GH action and pass in a single var=val parameter
invokeAction() {
    this_repo=$1
    this_action_name=$2
    this_workflow_id=$3
    #params is a comma-separated list of key=value entries
    this_params=$4

    # if provided, use previously computed workflow_id; otherwise compute it from the action's name so we can invoke the GH action by id
    # shellcheck disable=SC2086
    if [[ $this_workflow_id ]]; then
        workflow_id=$this_workflow_id
    else
        computeWorkflowId $this_repo "$this_action_name"
        # now we have a global value for $workflow_id
    fi

    WORKFLOW_MAIN_BRANCH="main"
    WORKFLOW_BUGFIX_BRANCH=${BRANCH}

    if [[ ${CHE_VERSION} == *".0" ]]; then
        workflow_ref=${WORKFLOW_MAIN_BRANCH}
    else
        workflow_ref=${WORKFLOW_BUGFIX_BRANCH}
    fi

    inputsJson="{}"

    IFS=',' read -ra paramMap <<< "${this_params}"
    for keyvalue in "${paramMap[@]}"
    do 
        key=${keyvalue%=*}
        value=${keyvalue#*=}
        inputsJson=$(echo "${inputsJson}" | jq ". + {\"${key}\": \"${value}\"}")
    done

    if [[ ${this_repo} == "che-incubator"* ]] || [[ ${this_repo} == "devfile"* ]] || [[ ${this_repo} == "che-dockerfiles"* ]]; then
        this_github_token=${CHE_INCUBATOR_BOT_GITHUB_TOKEN}
    else
        this_github_token=${GITHUB_TOKEN}
    fi

    curl -sSL "https://api.github.com/repos/${this_repo}/actions/workflows/${workflow_id}/dispatches" -X POST -H "Authorization: token ${this_github_token}" -H "Accept: application/vnd.github.v3+json" -d "{\"ref\":\"${workflow_ref}\",\"inputs\": ${inputsJson} }" || die_with "[ERROR] Problem invoking action https://github.com/${this_repo}/actions?query=workflow%3A%22${this_action_name// /+}%22"
    echo "[INFO] Invoked '${this_action_name}' action ($workflow_id) - see https://github.com/${this_repo}/actions?query=workflow%3A%22${this_action_name// /+}%22"
}

verifyBranchExistsWithTimeout()
{
    this_repo=$1
    this_branch=$2
    this_timeout=$3
    branchExists=0
    count=1
    (( timeout_intervals=this_timeout*3 ))
    while [[ $count -le $timeout_intervals ]]; do # echo $count
        echo -n "       [$count/$timeout_intervals] Check ${this_repo%.git}/tree/${this_branch} ..." 
        # check if the branch exists
        branchExists=$(git ls-remote --heads "${this_repo}" "${this_branch}" | wc -l)
        if [[ ${branchExists} -eq 1 ]]; then echo " found."; return 0; break; fi
        (( count=count+1 ))
        sleep 20s
        echo ""
    done
    # or report an error
    if [[ ${branchExists} -eq 0 ]]; then
        echo "[ERROR] Branch ${this_repo%.git}/tree/${this_branch} not found after ${this_timeout} minutes"
        return 1
    fi
}

verifyBranchExistsWithTimeoutAndExit()
{
    verifyBranchExistsWithTimeout "$@"
    if [[ $? -gt 0 ]]; then
        exit 1
    fi
}

# for a given container URL, check if it exists and its digest can be read
# verifyContainerExists quay.io/crw/pluginregistry-rhel8:2.6 # schemaVersion = 1, look for tag
# verifyContainerExists quay.io/eclipse/che-plugin-registry:7.24.2 # schemaVersion = 2, look for arches
verifyContainerExists()
{
    this_containerURL="${1}"
    this_image=""; this_tag=""
    this_image=${this_containerURL#*/}
    this_tag=${this_image##*:}
    this_image=${this_image%%:*}
    this_url="https://quay.io/v2/${this_image}/manifests/${this_tag}"
    # echo $this_url

    # get result=tag if tag found, result="null" if not
    result="$(curl -sSL "${this_url}"  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" 2>&1 || true)"
    if [[ $(echo "$result" | jq -r '.schemaVersion' || true) == "1" ]] && [[ $(echo "$result" | jq -r '.tag' || true) == "$this_tag" ]]; then
        echo "[INFO] Found ${this_containerURL} (tag = $this_tag)"
        containerExists=1
    elif [[ $(echo "$result" | jq -r '.schemaVersion' || true) == "2" ]]; then
        arches=$(echo "$result" | jq -r '.manifests[].platform.architecture')
        if [[ $arches ]]; then
            echo "[INFO] Found ${this_containerURL} (arches = $arches)"
        fi
        containerExists=1
    else
        # echo "[INFO] Did not find ${this_containerURL}"
        containerExists=0
    fi
}

verifyContainerExistsWithTimeout()
{
    this_containerURL=$1
    this_timeout=$2
    containerExists=0
    count=1
    (( timeout_intervals=this_timeout*3 ))
    while [[ $count -le $timeout_intervals ]]; do # echo $count
        echo "       [$count/$timeout_intervals] Verify ${1} exists..." 
        # check if the container exists
        verifyContainerExists "$1"
        if [[ ${containerExists} -eq 1 ]]; then break; fi
        (( count=count+1 ))
        sleep 20s
    done
    # or report an error
    if [[ ${containerExists} -eq 0 ]]; then
        echo "[ERROR] Did not find ${1} after ${this_timeout} minutes - script must exit!"
        exit 1;
    fi
}
