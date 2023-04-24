#!/bin/bash -e


# this script is checking all projects, so that they contain a branch, that is passed as parameter.

BRANCH=$1

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)
source ${SCRIPTS_DIR}/util.sh

REPO_LIST=(
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
    exit 1
else
    echo "[INFO] Branch ${BRANCH} is present in all $numprojects Che projects"
fi
