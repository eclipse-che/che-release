#!/bin/bash

# for a given GH repo and action name, compute workflow_id
# warning: variable workflow_id is a global, so don't call this in parallel executions!
computeWorkflowId() {
    this_repo=$1
    this_action_name=$2
    workflow_id=$(curl -sSL "https://api.github.com/repos/${this_repo}/actions/workflows" -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" | jq --arg search_field "${this_action_name}" '.workflows[] | select(.name == $search_field).id');
    # echo "workflow_id = $workflow_id"
    if [[ ! $workflow_id ]]; then
        echo "[ERROR] Could not compute workflow id from https://api.github.com/repos/${this_repo}/actions/workflows - check your GITHUB_TOKEN is active"
        exit 1;
    fi
    echo "[INFO] Got workflow_id $workflow_id for $this_repo action '$this_action_name'"
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
        if [[ ${branchExists} -eq 1 ]]; then echo " found."; return 0; fi
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
    if ! verifyBranchExistsWithTimeout "$@"; then
        exit 1
    fi
}

get_github_token() {
    local repo="$1"
    if [[ "$repo" == "che-incubator"* ]] || [[ "$repo" == "devfile"* ]] || [[ "$repo" == "che-dockerfiles"* ]]; then
        echo "${CHE_INCUBATOR_BOT_GITHUB_TOKEN:-}"
    else
        echo "${CHE_BOT_GITHUB_TOKEN:-}"
    fi
}

check_rate_limit() {
    local token="$1"
    local response
    response=$(curl -sSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/rate_limit" 2>/dev/null || echo '{}')
    local remaining
    remaining=$(echo "$response" | jq -r '.rate.remaining // "unknown"')
    echo "$remaining"
    if [[ "$remaining" == "0" ]]; then
        return 1
    fi
    return 0
}

get_workflow_status() {
    local repo="$1"
    local workflow_name="$2"
    local version="$3"
    local workflow_id="${4:-}"
    local token
    token=$(get_github_token "$repo")

    if [[ -z "$token" ]]; then
        echo '{"status":"error","conclusion":null,"run_url":"","run_id":"","error":"no token"}'
        return 0
    fi

    local api_url
    if [[ -n "$workflow_id" ]]; then
        api_url="https://api.github.com/repos/${repo}/actions/workflows/${workflow_id}/runs?per_page=20"
    else
        api_url="https://api.github.com/repos/${repo}/actions/runs?per_page=50"
    fi

    local response
    response=$(curl -sSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null || echo '{"workflow_runs":[]}')

    local run_json
    run_json=$(echo "$response" | jq -r --arg version "$version" --arg wf_name "$workflow_name" '
        [.workflow_runs[] |
         select(
            (.name == $wf_name or .display_title == $wf_name) and
            ((.display_title | contains($version)) or
             (.name | contains($version)) or
             (.head_branch | contains($version)))
         )] |
        if length == 0 then
            [.workflow_runs[] | select(.name == $wf_name)] |
            [.[] | select(.display_title | contains($version))] |
            if length > 0 then .[0] else null end
        else .[0] end
    ' 2>/dev/null)

    if [[ -z "$run_json" ]] || [[ "$run_json" == "null" ]]; then
        echo '{"status":"not_found","conclusion":null,"run_url":"","run_id":""}'
        return 0
    fi

    echo "$run_json" | jq '{
        status: .status,
        conclusion: .conclusion,
        run_url: .html_url,
        run_id: (.id | tostring)
    }'
}

find_pull_requests() {
    local repo="$1"
    local title_pattern="$2"
    local target_branch="${3:-}"
    local token
    token=$(get_github_token "$repo")

    if [[ -z "$token" ]]; then
        echo '[]'
        return 0
    fi

    # First try: list recent PRs (fastest, works for recent PRs)
    local api_url="https://api.github.com/repos/${repo}/pulls?state=all&sort=created&direction=desc&per_page=100"
    local response
    response=$(curl -sSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null || echo '[]')

    local result
    result=$(echo "$response" | jq -r --arg pattern "$title_pattern" --arg branch "$target_branch" '
        [.[] | select(
            (.title | contains($pattern)) and
            (if $branch != "" then .base.ref == $branch else true end)
        )] | map({
            number: .number,
            title: .title,
            state: .state,
            merged: (.merged_at != null),
            url: .html_url
        })
    ' 2>/dev/null || echo '[]')

    # If found, return result
    if [[ "$(echo "$result" | jq 'length')" -gt 0 ]]; then
        echo "$result"
        return 0
    fi

    # Second try: use search API for older PRs
    local search_url="https://api.github.com/search/issues?q=repo:${repo}+in:title+type:pr"
    # URL-encode the pattern for search (simple approach: replace spaces with +)
    local encoded_pattern="${title_pattern// /+}"
    search_url="${search_url}+${encoded_pattern}&per_page=10"

    local search_response
    search_response=$(curl -sSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github.v3+json" \
        "$search_url" 2>/dev/null || echo '{"items":[]}')

    echo "$search_response" | jq -r --arg pattern "$title_pattern" --arg branch "$target_branch" '
        [.items[] | select(
            (.title | contains($pattern)) and
            (if $branch != "" then .pull_request.base.ref == $branch else true end)
        )] | map({
            number: .number,
            title: .title,
            state: .state,
            merged: (.pull_request.merged_at != null),
            url: .html_url
        })
    ' 2>/dev/null || echo '[]'
}
