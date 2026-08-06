#!/bin/bash

ARTIFACT_CHECKER_UTIL_SOURCED=false

_source_util() {
    if [[ "$ARTIFACT_CHECKER_UTIL_SOURCED" == "false" ]]; then
        local script_dir
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.."; pwd)"
        source "$script_dir/utils/util.sh"
        ARTIFACT_CHECKER_UTIL_SOURCED=true
    fi
}

check_quay_image() {
    local image_with_tag="$1"
    _source_util
    containerExists=0
    verifyContainerExists "$image_with_tag" 2>/dev/null
    if [[ "$containerExists" -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}

check_npm_package() {
    local package_at_version="$1"
    _source_util
    packageExists=0
    verifyNpmJsPackageExists "$package_at_version" 2>/dev/null
    if [[ "$packageExists" -eq 1 ]]; then
        return 0
    else
        return 1
    fi
}

check_github_release() {
    local repo="$1"
    local tag="$2"
    local token
    token=$(get_github_token "$repo")

    if [[ -z "$token" ]]; then
        return 1
    fi

    local http_code
    http_code=$(curl -sSL -o /dev/null -w "%{http_code}" \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${repo}/releases/tags/${tag}" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

check_website() {
    local url="$1"
    local http_code
    http_code=$(curl -sSL -o /dev/null -w "%{http_code}" --max-time 10 "$url" 2>/dev/null || echo "000")

    if [[ "$http_code" == "200" ]]; then
        return 0
    else
        return 1
    fi
}

check_branch() {
    local repo="$1"
    local branch="$2"
    local count
    count=$(git ls-remote --heads "https://github.com/${repo}.git" "$branch" 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$count" -ge 1 ]]; then
        return 0
    else
        return 1
    fi
}
