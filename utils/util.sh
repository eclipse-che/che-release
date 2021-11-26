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
        if [[ ${branchExists} -eq 1 ]]; then echo " found."; break; fi
        (( count=count+1 ))
        sleep 20s
        echo ""
    done
    # or report an error
    if [[ ${branchExists} -eq 0 ]]; then
        echo "[ERROR] Branch ${this_repo%.git}/tree/${this_branch} not found after ${this_timeout} minutes"
        return 1;
    fi
}

verifyBranchExistsWithTimeoutAndExit()
{
    if verifyBranchExistsWithTimeoutAndExit "$@"; then
        exit 1;
    fi
}