#!/bin/bash -e


# this script is checking all projects, so that they contain a branch, that is passed as parameter.

BRANCH=$1

SCRIPTS_DIR=$(cd "$(dirname "$0")"; pwd)
source ${SCRIPTS_DIR}/util.sh

REPO_LIST=(
    che-dockerfiles/che-backup-server-rest
    che-incubator/chectl
    che-incubator/configbump
    che-incubator/kubernetes-image-puller
    eclipse-che/che-dashboard
    eclipse-che/che-devfile-registry
    eclipse-che/che-machine-exec
    eclipse-che/che-operator
    eclipse-che/che-plugin-registry
    eclipse-che/che-server
    eclipse-che/che-theia
    eclipse/che
    eclipse/che-docs
    eclipse/che-jwtproxy
)

for repo in "${REPO_LIST[@]}"; do
    verifyBranchExistsWithTimeout "https://github.com/${repo}.git" "${BRANCH}" 1
done

echo "[INFO] Branch ${BRANCH} is present in all Che Projects"