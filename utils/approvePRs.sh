#!/bin/bash
#
# Copyright (c) 2022-2023 Red Hat, Inc.
# This program and the accompanying materials are made
# available under the terms of the Eclipse Public License 2.0
# which is available at https://www.eclipse.org/legal/epl-2.0/
#
# SPDX-License-Identifier: EPL-2.0
#
# attempt to approve generated PRs via GH api
# will fail if GH token not exported first

# list copied from .github/workflows/update-base-images.yml
DEFAULT_REPOS="\
che-incubator/chectl \
che-incubator/che-code \
che-incubator/configbump \
che-incubator/jetbrains-editor-images \
che-incubator/jetbrains-ide-dev-server \
che-incubator/kubernetes-image-puller \
che-incubator/kubernetes-image-puller-operator \
devfile/devworkspace-operator \
devfile/developer-images \
eclipse-che/che-dashboard \
eclipse-che/che-machine-exec \
eclipse-che/che-operator \
eclipse-che/che-plugin-registry \
eclipse-che/che-server \
eclipse/che \
"

usageGHT() {
    echo 'Setup:

First, export your GITHUB_TOKEN:

  export GITHUB_TOKEN="...github-token..."'
  usage
}
usage () {
    echo "
Usage:

  $0 -b BRANCH [--quiet]
"
}

QUIET=0
while [[ "$#" -gt 0 ]]; do
  case $1 in
    '-q'|'--quiet') QUIET=1;;
    '-b') BRANCH="$2"; shift 1;;
    '-h') usage; exit 0;;
  esac
  shift 1
done

if [[ ! "${GITHUB_TOKEN}" ]]; then usageGHT; exit 1; fi
if [[ ! "${BRANCH}" ]]; then usage; exit 1; fi

for ownerRepo in $DEFAULT_REPOS; do
    if [[ $QUIET -eq 0 ]]; then echo "Check for open $ownerRepo PRs in branch ${BRANCH}"; fi
    # get open PRs, reported by che-incubator bot, with head.ref like pr-update-base-images-1651279364
    curl -sSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${ownerRepo}/pulls?state=open&base=${BRANCH}" | jq -r \
        '.[] | select((.user.login == "che-incubator-bot") or (.user.login == "che-bot")) | select(.head.ref|test("pr-update-base-images-.|pr-main-to-")) | [.user.login, .head.ref, ._links.self.href, ._links.html.href] | @tsv'
    # process PRs
    unmerged_PRs_string="$(curl -sSL -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${ownerRepo}/pulls?state=open&base=${BRANCH}" | jq -r \
        '.[] | select((.user.login == "che-incubator-bot") or (.user.login == "che-bot")) | select(.head.ref|test("pr-update-base-images-.|pr-main-to-")) | ._links.self.href')"
    unmerged_PRs=($unmerged_PRs_string); # echo $unmerged_PRs_string; echo "${#unmerged_PRs[@]}"

    if [[ ${#unmerged_PRs[@]} -gt 0 ]]; then
        PR_URL=${unmerged_PRs[0]}
        # approve it
        reviewResult="$(curl -sSL -X POST -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" -d '{"event":"APPROVE"}' ${PR_URL}/reviews)"
        if [[ $QUIET -eq 0 ]]; then 
            echo -n "${PR_URL}: "
            echo $reviewResult | jq -r '[.state, .commit_id] | @tsv'
        fi
        # squash-merge it
        mergeResult="$(curl -sSL -X PUT -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" -d '{"merge_method":"squash"}' ${PR_URL}/merge)"
        echo -n "${PR_URL}: "
        echo $mergeResult | jq -r '[.message, .sha] | @tsv'

        # if more than one, approve the first and close the older ones
        if [[ ${#unmerged_PRs[@]} -gt 1 ]]; then
            unset "unmerged_PRs[0]"
            for PR_URL in "${unmerged_PRs[@]}"; do 
                closeResult="$(curl -sSL -X PATCH -H "Authorization: token ${GITHUB_TOKEN}" -H "Accept: application/vnd.github.v3+json" -d '{"state":"closed"}' ${PR_URL})"
                echo -n "${PR_URL}: "
                echo $closeResult | jq -r '[.state, .closed_at] | @tsv'
            done
        fi
        echo
    fi
done
