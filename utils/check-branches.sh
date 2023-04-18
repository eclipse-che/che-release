#!/bin/bash -e


# this script is checking all projects, so that they contain a branch, that is passed as parameter.

BRANCH=$1

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)
source ${SCRIPTS_DIR}/util.sh

REPO_LIST=(
    che-incubator/chectl
    che-incubator/configbump
    che-incubator/kubernetes-image-puller
    eclipse-che/che-dashboard
    eclipse-che/che-devfile-registry
    eclipse-che/che-machine-exec
    eclipse-che/che-operator
    eclipse-che/che-plugin-registry
    eclipse-che/che-server
    eclipse/che
)

MISSING_BRANCHES=
numprojects=0
set -e
for repo in "${REPO_LIST[@]}"; do
    EXIT_CODE=0
    verifyBranchExistsWithTimeout "https://github.com/${repo}.git" "${BRANCH}" 1 || EXIT_CODE=$?
    if [[ ${EXIT_CODE} -eq 1 ]]; then
        MISSING_BRANCHES="${MISSING_BRANCHES} $repo"
    fi
    let numprojects=numprojects+1
done
set -e

if [ -n "${MISSING_BRANCHES}" ];then
    echo "[ERROR] Branch ${BRANCH} is not present in following projects: ${MISSING_BRANCHES}"
else
    echo "[INFO] Branch ${BRANCH} is present in all $numprojects Che projects"
fi