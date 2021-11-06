#!/bin/bash -e


# this script is checking all projects, so that they contain a branch, that is passed as parameter.

BRANCH=$1

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
        sleep 5s
    done
    # or report an error
    if [[ ${branchExists} -eq 0 ]]; then
        echo "[ERROR] Did not find branch ${2} in repo ${1} after ${this_timeout} minutes - script must exit!"
        exit 1;
    fi
}

REPO_LIST=(
    eclipse/che-jwtproxy
    eclipse/che
    eclipse/che-docs
    eclipse-che/che-dashboard
    eclipse-che/che-server
    eclipse-che/che-devfile-registry
    eclipse-che/che-plugin-registry
    eclipse-che/che-machine-exec
    eclipse-che/che-operator
    eclipse-che/che-theia
    che-incubator/kubernetes-image-puller
    che-incubator/configbump
    che-incubator/chectl
    che-dockerfiles/che-backup-server-rest
)

for repo in "${REPO_LIST[@]}"; do
    verifyBranchExistsWithTimeout "https://github.com/${repo}.git" "${BRANCH}" 1
done

echo "[INFO] Branch ${BRANCH} is present in all Che Projects"