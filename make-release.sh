#!/bin/bash

# overall Che release orchestration script
# see README.md for more info 

REGISTRY="quay.io"
ORGANIZATION="eclipse"

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)
source ${SCRIPTS_DIR}/utils/util.sh

usage ()
{
  echo "Usage: $0  --version [CHE VERSION TO RELEASE] --parent-version [CHE PARENT VERSION] --phases [LIST OF PHASES]

# Comma-separated phases to perform.
#1: Code, Configbump, MachineExec, Server, devworkspace-generator, createBranches (kubernetes-image-puller);
#2: E2E, PluginRegistry, Dashboard;
#3: DevfileRegistry;
#4: Operator;
# Default: 1,2,3,4
# Omit phases that have successfully run.
"
  echo "Example: $0 --version 7.75.0 --phases 1,2,3,4"; echo
  exit 1
}

#################### SETUP ####################

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

#################### PHASE 1 ####################

releaseCheCode() {
    invokeAction che-incubator/che-code "Release Che Code" "34764281" "version=${CHE_VERSION}"
}

releaseConfigbump() {
    invokeAction che-incubator/configbump "Release Che Configbump" "69757177" "version=${CHE_VERSION}"
}

releaseMachineExec() {
    invokeAction eclipse-che/che-machine-exec "Release Che Machine Exec" "7369994" "version=${CHE_VERSION}"
}

releaseCheServer() {
    invokeAction eclipse-che/che-server "Release Che Server" "9230035" "version=${CHE_VERSION},releaseParent=${RELEASE_CHE_PARENT},versionParent=${VERSION_CHE_PARENT}"
}

releaseDevworkspaceGenerator() {
    invokeAction eclipse-che/che-devfile-registry "Release Che Devworkspace Generator" "67742638" "version=${CHE_VERSION}"
}

createBranches() {
    invokeAction che-incubator/kubernetes-image-puller "Create branch" "5409996" "branch=${BRANCH}"
}

#################### PHASE 2 ####################

releaseCheE2E() {
    invokeAction eclipse/che "Release Che E2E" "5536792" "version=${CHE_VERSION}"
}

releasePluginRegistry() {
    invokeAction eclipse-che/che-plugin-registry "Release Che Plugin Registry" "4191251" "version=${CHE_VERSION}"
}

releaseDashboard() {
    invokeAction eclipse-che/che-dashboard "Release Che Dashboard" "3152474" "version=${CHE_VERSION}"
}

#################### PHASE 3 ####################

releaseDevfileRegistry() {
    invokeAction eclipse-che/che-devfile-registry "Release Che Devfile Registry" "4191260" "version=${CHE_VERSION}"
}

#################### PHASE 4 ####################

releaseCheOperator() {
    invokeAction eclipse-che/che-operator "Release Che Operator" "3593082" "version=${CHE_VERSION}"
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

#################### SETUP ####################

checkForBlockerIssues
setupGitconfig
evaluateCheVariables
echo "BASH VERSION = $BASH_VERSION"
set -e

#################### PHASE 1 ####################

# Release projects that don't depend on other projects
set +x 
if [[ ${PHASES} == *"1"* ]]; then
    releaseCheCode
    releaseConfigbump
    releaseMachineExec
    releaseCheServer
    releaseDevworkspaceGenerator
    createBranches
fi
wait
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/che-incubator/che-code:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/che-incubator/configbump:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-machine-exec:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-server:${CHE_VERSION} 60
# shellcheck disable=SC2086
verifyBranchExistsWithTimeoutAndExit "https://github.com/che-incubator/kubernetes-image-puller.git" ${BRANCH} 60
# shellcheck disable=SC2086
verifyNpmJsPackageExistsWithTimeoutAndExit "@eclipse-che/che-devworkspace-generator@${CHE_VERSION}" 60

#################### PHASE 2 ####################

set +x
# Release e2e (depends on che-server, devworkspace-generator)
# Release plugin registry (depends on machine-exec)
if [[ ${PHASES} == *"2"* ]]; then
    releaseCheE2E
    releasePluginRegistry
    releaseDashboard
fi
wait
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-e2e:${CHE_VERSION} 30
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-plugin-registry:${CHE_VERSION} 30
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-dashboard:${CHE_VERSION} 60

#################### PHASE 3 ####################

# Release devfile registry (depends on plugin registry)
if [[ ${PHASES} == *"3"* ]]; then
  releaseDevfileRegistry
fi
wait 
# shellcheck disable=SC2086
verifyContainerExistsWithTimeout ${REGISTRY}/${ORGANIZATION}/che-devfile-registry:${CHE_VERSION} 60

#################### PHASE 4 ####################

# Create operator PRs (depends on devfile registry)
set +x
if [[ ${PHASES} == *"4"* ]]; then
    releaseCheOperator
fi
wait

# downstream steps depends on Che operator PRs being merged by humans, so this is the end of the automation.
# see README.md for more info
