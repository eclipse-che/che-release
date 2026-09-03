#!/bin/bash
# shellcheck disable=SC1091,SC2155
# SC1091: Source files are in lib/ directory
# SC2155: Declare and assign separately - acceptable here as jq/yq failures are caught by set -e

# overall Che release orchestration script
# see README.md for more info

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)
REPO_ROOT="$(cd "$SCRIPTS_DIR/.."; pwd)"
source "${SCRIPTS_DIR}"/lib/util.sh
source "${SCRIPTS_DIR}"/lib/github-api.sh
source "${SCRIPTS_DIR}"/lib/artifact-checker.sh
source "${SCRIPTS_DIR}"/lib/yaml-parser.sh

usage ()
{
  echo "Usage: $0  --version [CHE VERSION TO RELEASE] --parent-version [CHE PARENT VERSION] --phases [LIST OF PHASES]

# Comma-separated phases to perform.
# Default: 1,2,3
# Omit phases that have successfully run.
"
  echo "Example: $0 --version 7.75.0 --phases 1,2,3"; echo
  exit 1
}

#################### SETUP ####################

checkForBlockerIssues()
{
    # check for blockers only if doing a 7.yy.0 release
    if [[ ${CHE_VERSION} == *".0" ]]; then 
        BLOCKERS_ANY="$(curl -s "https://api.github.com/repos/eclipse/che/issues?labels=severity/blocker&state=open" | jq -r '.[]|[.created_at,.updated_at,.milestone.title,.url,.user.login,.title] | @tsv')"
        if [[ $BLOCKERS_ANY ]]; then
            echo "[ERROR] Blocker issue(s) found!"
            echo "$BLOCKERS_ANY"
            exit 1
        fi
    fi
}

setupGitconfig() {
  ne else?
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

    echo "Basebranch: ${BASEBRANCH}" 
    echo "Release Process Phases: '${PHASES}'"
}

#################### YAML-DRIVEN PHASE EXECUTION ####################

executePhaseWorkflows() {
    local phase_key="$1"
    local version="$2"
    local branch="$3"

    echo "[INFO] Executing workflows for ${phase_key}..."

    local projects_json=$(get_phase_projects_json "$phase_key")
    local project_count=$(echo "$projects_json" | jq -r 'length')

    local i=0
    while [[ $i -lt $project_count ]]; do
        local project=$(echo "$projects_json" | jq -c ".[$i]")
        local name=$(echo "$project" | jq -r '.name')
        local repo=$(echo "$project" | jq -r '.repo')
        local wf_name=$(echo "$project" | jq -r '.workflow.name')
        local wf_id=$(echo "$project" | jq -r '.workflow.id')

        # Build parameters from YAML
        local params=""
        local param_array=$(echo "$project" | jq -c '.workflow.parameters // []')
        local param_count=$(echo "$param_array" | jq -r 'length')

        local j=0
        while [[ $j -lt $param_count ]]; do
            local key=$(echo "$param_array" | jq -r ".[$j].key")
            local value_template=$(echo "$param_array" | jq -r ".[$j].value")
            local value=$(expand_placeholders "$value_template" "$version" "$branch")

            if [ -n "$params" ]; then params="${params},"; fi
            params="${params}${key}=${value}"
            j=$((j + 1))
        done

        # Invoke workflow in background
        echo "[INFO] Invoking ${name} workflow..."
        invokeAction "$repo" "$wf_name" "$wf_id" "$params" &

        i=$((i + 1))
    done

    wait
    echo "[INFO] All ${phase_key} workflows invoked."
}

verifyPhaseArtifacts() {
    local phase_key="$1"
    local version="$2"
    local branch="$3"

    echo "[INFO] Verifying artifacts for ${phase_key}..."

    local projects_json=$(get_phase_projects_json "$phase_key")
    local project_count=$(echo "$projects_json" | jq -r 'length')

    local i=0
    while [[ $i -lt $project_count ]]; do
        local project=$(echo "$projects_json" | jq -c ".[$i]")
        local name=$(echo "$project" | jq -r '.name')
        local repo=$(echo "$project" | jq -r '.repo')

        # Verify artifacts
        local artifacts_json=$(echo "$project" | jq -c '.artifacts // []')
        local artifact_count=$(echo "$artifacts_json" | jq -r 'length')

        local j=0
        while [[ $j -lt $artifact_count ]]; do
            local artifact=$(echo "$artifacts_json" | jq -c ".[$j]")
            local type=$(echo "$artifact" | jq -r '.type')
            local artifact_name=$(echo "$artifact" | jq -r '.name')
            local timeout=$(echo "$artifact" | jq -r '.timeout // 30')

            case "$type" in
                image)
                    # shellcheck disable=SC2086
                    verifyContainerExistsWithTimeout "${artifact_name}:${version}" $timeout
                    ;;
                npmjs)
                    # shellcheck disable=SC2086
                    verifyNpmJsPackageExistsWithTimeoutAndExit "${artifact_name}@${version}" $timeout
                    ;;
            esac
            j=$((j + 1))
        done

        # Verify branches
        local branches_json=$(echo "$project" | jq -c '.branches // []')
        local branch_count=$(echo "$branches_json" | jq -r 'length')

        local k=0
        while [[ $k -lt $branch_count ]]; do
            local branch_pattern=$(echo "$branches_json" | jq -r ".[$k]")
            local expanded_branch=$(expand_placeholders "$branch_pattern" "$version" "$branch")
            local timeout=60

            # shellcheck disable=SC2086
            verifyBranchExistsWithTimeoutAndExit "https://github.com/${repo}.git" $expanded_branch $timeout
            k=$((k + 1))
        done

        i=$((i + 1))
    done

    echo "[INFO] All ${phase_key} artifacts verified."
}

while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-v'|'--version') CHE_VERSION="$2"; shift 1;;
    '-p'|'--phases') PHASES="$2"; shift 1;;
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

#################### SETUP ####################

checkForBlockerIssues
setupGitconfig
evaluateCheVariables
echo "BASH VERSION = $BASH_VERSION"
set -e

# Parse YAML config
parse_release_config "$REPO_ROOT/che-release.yaml"

#################### DYNAMIC PHASE EXECUTION ####################

# Execute requested phases, stopping after any phase with a "pause" workflow
for phase_key in $(get_phase_keys); do
    phase_num="${phase_key#phase-}"
    phase_desc=$(get_phase_description "$phase_key")

    # Check if this phase is requested
    if [[ ${PHASES} == *"${phase_num}"* ]]; then
        echo "[INFO] =========================================="
        echo "[INFO] Phase ${phase_num}: ${phase_desc}"
        echo "[INFO] =========================================="

        set +x
        executePhaseWorkflows "$phase_key" "$CHE_VERSION" "$BRANCH"
        verifyPhaseArtifacts "$phase_key" "$CHE_VERSION" "$BRANCH"

        # Check if any workflow in this phase has pause:true
        projects_json=$(get_phase_projects_json "$phase_key")
        if echo "$projects_json" | jq -e '.[] | select(.workflow.pause == true)' > /dev/null 2>&1; then
            echo "[INFO] Phase ${phase_num} contains a workflow with pause=true, stopping here."
            break
        fi
    fi
done

# Cleanup
rm -f "$RELEASE_CONFIG_FILE"

# downstream steps depends on Che operator PRs being merged by humans, so this is the end of the automation.
# see README.md for more info
