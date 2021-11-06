#!/bin/bash

# overall Che release orchestration script
# see README.md for more info 

REGISTRY="quay.io"
ORGANIZATION="eclipse"

die_with() 
{
	echo "$*" >&2
	exit 1
}

usage ()
{
  echo "Usage: $0  --version [CHE VERSION TO RELEASE] --parent-version [CHE PARENT VERSION] --phases [LIST OF PHASES]

# Comma-separated phases to perform.
#1: CheServer, MachineExec, DevfileRegistry, Dashboard, createBranches;
#2: CheTheia;
#3: ChePluginRegistry;
#5: CheOperator;
# Default: 1,2,3,4
# Omit phases that have successfully run.
"
  echo "Example: $0 --version 7.29.0 --phases 1,2,3,4"; echo
  exit 1
}

checkForBlockerIssues()
{
    # check for blockers only if doing a 7.yy.0 release
    if [[ ${CHE_VERSION} == *".0" ]]; then 
        # If in future we want to find blockers for a given milestone, here's how:
        ## OPTION 1: gh cli
            # BLOCKERS_THIS_MILESTONE="$(gh issue list -R eclipse/che -l "severity/blocker" -s "open" -m "${CHE_VERSION%.*}" --json "createdAt,updatedAt,author,title,url,milestone" | jq -r '.[]')"
        ## OPTION 2: gh api
            # milestone="${CHE_VERSION%.*}"
            # 7.39 :: 151
            # milestoneID="$(curl -s "https://api.github.com/repos/eclipse/che/milestones?sort_on=due_on&direction=desc&state=open" | jq -r --arg milestone $milestone '.[]|select(.title==$milestone)|.number' 2>&1)" 
            # BLOCKERS_THIS_MILESTONE="$(curl -s "https://api.github.com/repos/eclipse/che/issues?labels=severity/blocker&state=open&milestone=${milestoneID}" | jq -r '.[]|[.created_at,.updated_at,.milestone.title,.url,.user.login,.title] | @tsv')"
        # if [[ $BLOCKERS_THIS_MILESTONE ]]; then
        #     echo "[ERROR] Blocker issue(s) found for this milestone ${CHE_VERSION%.*}!"
        #     echo $BLOCKERS_THIS_MILESTONE
        #     exit 1
        # fi

        # Mario and Florent would prefer to search for ANY open blockers, including those unassigned to milestones
        ## OPTION 1: gh cli
            # BLOCKERS_ANY="$(gh issue list -R eclipse/che -l "severity/blocker" -s "open" --json "createdAt,updatedAt,author,title,url,milestone" | jq -r '.[]')"
        ## OPTION 2: gh api
        BLOCKERS_ANY="$(curl -s "https://api.github.com/repos/eclipse/che/issues?labels=severity/blocker&state=open" | jq -r '.[]|[.created_at,.updated_at,.milestone.title,.url,.user.login,.title] | @tsv')"
        if [[ $BLOCKERS_ANY ]]; then
            echo "[ERROR] Blocker issue(s) found!"
            echo "$BLOCKERS_ANY"
            exit 1
        fi
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

verifyBranchExistsWithTimeout()
{
    this_repo=$1
    this_branch=$2
    this_timeout=$3
    branchExists=0
    count=1
    (( timeout_intervals=this_timeout*3 ))
    while [[ $count -le $timeout_intervals ]]; do # echo $count
        echo "       [$count/$timeout_intervals] Verify branch ${2} in repo ${1} exists..." 
        # check if the branch exists
        branchExists=$(git ls-remote --heads "${this_repo}" "${this_branch}" | wc -l)
        if [[ ${branchExists} -eq 1 ]]; then break; fi
        (( count=count+1 ))
        sleep 20s
    done
    # or report an error
    if [[ ${branchExists} -eq 0 ]]; then
        echo "[ERROR] Did not find branch ${2} in repo ${1} after ${this_timeout} minutes - script must exit!"
        exit 1;
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

installDebDeps(){
    set +x
    # TODO should this be node 12?
    curl -sL https://deb.nodesource.com/setup_10.x | sudo -E bash -
    sudo apt-get install -y nodejs
}

evaluateCheVariables() {
    echo "Che version: ${CHE_VERSION}"
    # derive branch from version
    BRANCH=${CHE_VERSION%.*}.x
    echo "Branch: ${BRANCH}"

    if [[ ${CHE_VERSION} == *".0" ]]; then
        BASEBRANCH="master"
    else
        BASEBRANCH="${BRANCH}"
    fi

    if [[ ${RELEASE_CHE_PARENT} != "true" ]]; then
        RELEASE_CHE_PARENT="false"
    fi

    if [[ -z ${VERSION_CHE_PARENT} ]]; then
        # get latest higher 7.yy.z tag of Che Parent as version
        # shellcheck disable=SC2062
        VERSION_CHE_PARENT=$(git -c 'versionsort.suffix=-' ls-remote --tags  https://github.com/eclipse/che-parent.git | cut --delimiter='/' --fields=3 | grep 7.* | sort --version-sort | tail --lines=1)
    fi
    echo "Basebranch: ${BASEBRANCH}" 
    echo "Release Process Phases: '${PHASES}'"
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

releaseMachineExec() {
    invokeAction eclipse-che/che-machine-exec "Release Che Machine Exec" "7369994" "version=${CHE_VERSION}"
}

releaseCheTheia() {
    invokeAction eclipse-che/che-theia "Release Che Theia" "5717988" "version=${CHE_VERSION}"
}

releaseDevfileRegistry() {
    invokeAction eclipse-che/che-devfile-registry "Release Che Devfile Registry" "4191260" "version=${CHE_VERSION}"
}
releasePluginRegistry() {
    invokeAction eclipse-che/che-plugin-registry "Release Che Plugin Registry" "4191251" "version=${CHE_VERSION}"
}

createBranches() {
    invokeAction che-incubator/configbump "Create branch" "11029799" "branch=${BRANCH}"
    invokeAction eclipse/che-jwtproxy "Create branch" "5410230" "branch=${BRANCH}"
    invokeAction che-incubator/kubernetes-image-puller "Create branch" "5409996" "branch=${BRANCH}"
    invokeAction che-dockerfiles/che-backup-server-rest  "Create branch" "11838866" "branch=${BRANCH}"
}

releaseDashboard() {
    invokeAction eclipse-che/che-dashboard "Release Che Dashboard" "3152474" "version=${CHE_VERSION}"
}

releaseCheE2E() {
    invokeAction eclipse/che "Release Che E2E" "5536792" "version=${CHE_VERSION}"
}

releaseCheServer() {
    invokeAction eclipse-che/che-server "Release Che Server" "9230035" "version=${CHE_VERSION},releaseParent=${RELEASE_CHE_PARENT},versionParent=${VERSION_CHE_PARENT}"
}

releaseCheOperator() {
    invokeAction eclipse-che/che-operator "Release Che Operator" "3593082" "version=${CHE_VERSION}"
}

# TODO change it to someone else?
# TODO use a different token?
setupGitconfig() {
  git config --global user.name "Mykhailo Kuznietsov"
  git config --global user.email mkuznets@redhat.com

  # hub CLI configuration
  git config --global push.default matching

  # suppress warnings about how to reconcile divergent branches
  git config --global pull.ff only 

  # NOTE when invoking action from che-incubator/* repos (not eclipse/che* repos), must use CHE_INCUBATOR_BOT_GITHUB_TOKEN
  # default to CHE_BOT GH token
  export GITHUB_TOKEN="${CHE_BOT_GITHUB_TOKEN}"
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-v'|'--version') CHE_VERSION="$2"; shift 1;;
    '-p'|'--phases') PHASES="$2"; shift 1;;
    '--release-parent') RELEASE_CHE_PARENT="true"; shift 0;;
    '--parent-version') VERSION_CHE_PARENT="$2"; shift 1;;
  esac
  shift 1
done

if [[ ! ${CHE_VERSION} ]] || [[ ! ${PHASES} ]] ; then
  usage
fi

set +x
mkdir "$HOME/.ssh/"
echo "$CHE_GITHUB_SSH_KEY" | base64 -d > "$HOME/.ssh/id_rsa"
chmod 0400 "$HOME/.ssh/id_rsa"
ssh-keyscan github.com >> ~/.ssh/known_hosts
set -x

installDebDeps
checkForBlockerIssues
setupGitconfig

evaluateCheVariables
echo "BASH VERSION = $BASH_VERSION"
set -e

# Release projects that don't depend on other projects
set +x
if [[ ${PHASES} == *"1"* ]]; then
    releaseMachineExec
    releaseDevfileRegistry
    releaseDashboard
    createBranches
    releaseCheServer
    releaseCheE2E
fi
wait
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-machine-exec:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-devfile-registry:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-dashboard:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyBranchExistsWithTimeout "https://github.com/che-incubator/configbump.git" ${BRANCH}
# shellcheck disable=SC2086
verifyBranchExistsWithTimeout "https://github.com/eclipse/che-jwtproxy.git" ${BRANCH}
# shellcheck disable=SC2086
verifyBranchExistsWithTimeout "https://github.com/che-incubator/kubernetes-image-puller.git" ${BRANCH}
# shellcheck disable=SC2086
verifyBranchExistsWithTimeout "https://github.com/che-dockerfiles/che-backup-server-rest.git" ${BRANCH}

IMAGES_LIST=(
    quay.io/eclipse/che-endpoint-watcher
    quay.io/eclipse/che-keycloak
    quay.io/eclipse/che-postgres
    quay.io/eclipse/che-server
)

for image in "${IMAGES_LIST[@]}"; do
    verifyContainerExistsWithTimeout "${image}:${CHE_VERSION}" 60
done

set +x
# Release server (depends on dashboard)
if [[ ${PHASES} == *"2"* ]]; then
    releaseCheTheia
    releaseCheE2E
fi

# shellcheck disable=SC2086
if [[ ${PHASES} == *"2"* ]] || [[ ${PHASES} == *"5"* ]]; then
  verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-theia:${CHE_VERSION} 60
  verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-theia-dev:${CHE_VERSION} 60
  verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-theia-endpoint-runtime-binary:${CHE_VERSION} 60
  verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-e2e:${CHE_VERSION} 60
fi

# Release plugin-registry (depends on che-theia and machine-exec)
if [[ ${PHASES} == *"3"* ]]; then
    releasePluginRegistry
fi

# shellcheck disable=SC2086
if [[ ${PHASES} == *"3"* ]] || [[ ${PHASES} == *"5"* ]]; then
  verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-plugin-registry:${CHE_VERSION} 30
fi

# Release Che operator (create PRs)
set +x
if [[ ${PHASES} == *"4"* ]]; then
    releaseCheOperator
fi
wait

# downstream steps depends on Che operator PRs being merged by humans, so this is the end of the automation.
# see README.md for more info
