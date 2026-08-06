#!/bin/bash

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
            ((.display_title | test($version)) or
             (.name | test($version)) or
             (.head_branch | test($version)))
         )] |
        if length == 0 then
            [.workflow_runs[] | select(.name == $wf_name)] |
            [.[] | select(.display_title | test($version))] |
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

    local api_url="https://api.github.com/repos/${repo}/pulls?state=all&sort=created&direction=desc&per_page=30"
    local response
    response=$(curl -sSL -H "Authorization: token ${token}" -H "Accept: application/vnd.github.v3+json" \
        "$api_url" 2>/dev/null || echo '[]')

    echo "$response" | jq -r --arg pattern "$title_pattern" --arg branch "$target_branch" '
        [.[] | select(
            (.title | test($pattern)) and
            (if $branch != "" then .base.ref == $branch else true end)
        )] | map({
            number: .number,
            title: .title,
            state: .state,
            merged: (.merged_at != null),
            url: .html_url
        })
    ' 2>/dev/null || echo '[]'
}
