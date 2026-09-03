#!/bin/bash
# shellcheck disable=SC1091
# SC1091: Source files are in lib/ directory
set -euo pipefail

# NOTE: Workflow status checking is currently DISABLED (see line ~111)
# To re-enable: uncomment the get_workflow_status call and comment out the hardcoded wf_status="not_checked"

SCRIPTS_DIR="$(cd "$(dirname "$0")"; pwd)"
REPO_ROOT="$(cd "$SCRIPTS_DIR/.."; pwd)"

source "$SCRIPTS_DIR/lib/yaml-parser.sh"
source "$SCRIPTS_DIR/lib/github-api.sh"
source "$SCRIPTS_DIR/lib/artifact-checker.sh"
source "$SCRIPTS_DIR/lib/status-aggregator.sh"

DEBUG=false

usage() {
    echo "Usage: $0 <version> [--debug]"
    echo ""
    echo "Display release status for all Eclipse Che components."
    echo ""
    echo "Arguments:"
    echo "  version    Version in format X.Y.Z (e.g., 7.120.0)"
    echo "  --debug    Show detailed API call information"
    echo ""
    echo "Example: $0 7.120.0"
    exit 1
}

debug_log() {
    if [[ "$DEBUG" == "true" ]]; then
        echo "[DEBUG] $*" >&2
    fi
}

validate_version() {
    local version="$1"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        echo "[ERROR] Invalid version format: '$version'. Expected X.Y.Z (e.g., 7.120.0)" >&2
        exit 1
    fi
}

calculate_branch() {
    local version="$1"
    echo "${version%.*}.x"
}

# Counters for summary
TOTAL_PROJECTS=0
COUNT_DONE=0
COUNT_IN_PROGRESS=0
COUNT_FAILED=0
COUNT_NOT_STARTED=0
BLOCKERS=()

# Phase-specific counters (associative arrays)
declare -A PHASE_TOTAL
declare -A PHASE_DONE
declare -A PHASE_IN_PROGRESS
declare -A PHASE_FAILED
declare -A PHASE_NOT_STARTED
declare -A PHASE_DESCRIPTIONS
PHASE_ORDER=()

print_header() {
    local version="$1"
    local branch="$2"
    echo "Eclipse Che Release Status: ${version}"
    echo "Branch: ${branch}"
    echo "================================================================================"
    echo ""
}

status_icon() {
    case "$1" in
        done)        echo "✓" ;;
        in_progress) echo "⚙" ;;
        failed)      echo "✗" ;;
        not_started) echo "○" ;;
        waiting)     echo "⧗" ;;
        *)           echo "?" ;;
    esac
}

status_label() {
    case "$1" in
        done)        echo "DONE" ;;
        in_progress) echo "IN PROGRESS" ;;
        failed)      echo "FAILED" ;;
        not_started) echo "NOT STARTED" ;;
        *)           echo "UNKNOWN" ;;
    esac
}

item_icon() {
    local found="$1"
    local parent_status="$2"
    if [[ "$found" == "true" ]]; then
        echo "✓"
    elif [[ "$parent_status" == "not_started" ]]; then
        echo "○"
    elif [[ "$parent_status" == "failed" ]]; then
        echo "✗"
    else
        echo "⧗"
    fi
}

process_project() {
    local project_json="$1"
    local version="$2"
    local branch="$3"
    local phase_key="$4"

    local name repo wf_name
    name=$(echo "$project_json" | jq -r '.name')
    repo=$(echo "$project_json" | jq -r '.repo')
    wf_name=$(echo "$project_json" | jq -r '.workflow.name')
    # wf_id is unused since workflow checking is disabled
    # wf_id=$(echo "$project_json" | jq -r '.workflow.id // empty')
    debug_log "Processing project: $name ($repo)"

    # --- Check workflow status ---
    # TEMPORARILY DISABLED - workflow checking is skipped
    local wf_status wf_conclusion
    # wf_result=$(get_workflow_status "$repo" "$wf_name" "$version" "$wf_id")
    # wf_status=$(echo "$wf_result" | jq -r '.status')
    # wf_conclusion=$(echo "$wf_result" | jq -r '.conclusion // empty')
    wf_status="not_checked"
    wf_conclusion=""

    debug_log "  workflow: status=$wf_status (checking disabled)"

    # --- Check branches ---
    local branches_json branches_total branches_found branch_details
    branches_json=$(echo "$project_json" | jq -r '.branches // []')
    branches_total=$(echo "$branches_json" | jq -r 'length')
    branches_found=0
    branch_details=()

    local i=0
    while [[ $i -lt $branches_total ]]; do
        local branch_pattern expanded_branch
        branch_pattern=$(echo "$branches_json" | jq -r ".[$i]")
        expanded_branch=$(expand_placeholders "$branch_pattern" "$version" "$branch")
        debug_log "  checking branch: $expanded_branch in $repo"
        if check_branch "$repo" "$expanded_branch" 2>/dev/null; then
            branch_details+=("found:${expanded_branch}")
            branches_found=$((branches_found + 1))
        else
            branch_details+=("missing:${expanded_branch}")
        fi
        i=$((i + 1))
    done

    # --- Check artifacts ---
    local artifacts_json artifacts_total artifacts_found artifact_details
    artifacts_json=$(echo "$project_json" | jq -r '.artifacts // []')
    artifacts_total=$(echo "$artifacts_json" | jq -r 'length')
    artifacts_found=0
    artifact_details=()

    i=0
    while [[ $i -lt $artifacts_total ]]; do
        local art_type art_name art_repo art_url
        art_type=$(echo "$artifacts_json" | jq -r ".[$i].type")
        art_name=$(echo "$artifacts_json" | jq -r ".[$i].name // empty")
        art_repo=$(echo "$artifacts_json" | jq -r ".[$i].repo // empty")
        art_url=$(echo "$artifacts_json" | jq -r ".[$i].url // empty")

        debug_log "  checking artifact: type=$art_type name=$art_name"

        case "$art_type" in
            image)
                local full_image="${art_name}:${version}"
                if check_quay_image "$full_image" 2>/dev/null; then
                    artifact_details+=("found:image:${full_image}")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:image:${full_image}")
                fi
                ;;
            npmjs)
                local full_package="${art_name}@${version}"
                if check_npm_package "$full_package" 2>/dev/null; then
                    artifact_details+=("found:npmjs:${full_package}")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:npmjs:${full_package}")
                fi
                ;;
            github-release)
                local release_repo="${art_repo:-$repo}"
                if check_github_release "$release_repo" "$version" 2>/dev/null; then
                    artifact_details+=("found:github-release:${release_repo}@${version}")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:github-release:${release_repo}@${version}")
                fi
                ;;
            website)
                if check_website "$art_url" 2>/dev/null; then
                    artifact_details+=("found:website:${art_url}")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:website:${art_url}")
                fi
                ;;
            website-version)
                if check_website_version "$art_url" "$version" 2>/dev/null; then
                    artifact_details+=("found:website-version:${art_url} (version ${version})")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:website-version:${art_url} (version ${version})")
                fi
                ;;
            github-release-notes)
                local release_repo="${art_repo:-$repo}"
                if check_github_release_notes "$release_repo" "$version" 2>/dev/null; then
                    artifact_details+=("found:github-release-notes:${release_repo}@${version}")
                    artifacts_found=$((artifacts_found + 1))
                else
                    artifact_details+=("missing:github-release-notes:${release_repo}@${version}")
                fi
                ;;
        esac
        i=$((i + 1))
    done

    # --- Check pull requests ---
    local prs_json prs_count prs_required prs_merged pr_details
    prs_json=$(echo "$project_json" | jq -r '.["pull-requests"] // []')
    prs_count=$(echo "$prs_json" | jq -r 'length')
    prs_required=0
    prs_merged=0
    pr_details=()

    i=0
    while [[ $i -lt $prs_count ]]; do
        local pr_title_pattern pr_target_branch pr_target_repo pr_expected_count pr_required_flag
        pr_title_pattern=$(echo "$prs_json" | jq -r ".[$i][\"title-pattern\"]")
        pr_target_branch=$(echo "$prs_json" | jq -r ".[$i][\"target-branch\"] // empty")
        pr_target_repo=$(echo "$prs_json" | jq -r ".[$i][\"target-repo\"] // empty")
        pr_expected_count=$(echo "$prs_json" | jq -r ".[$i].count // 1")
        pr_required_flag=$(echo "$prs_json" | jq -r ".[$i][\"required-for-completion\"] // false")

        local expanded_title expanded_target_branch search_repo
        expanded_title=$(expand_placeholders "$pr_title_pattern" "$version" "$branch")
        expanded_target_branch=$(expand_placeholders "${pr_target_branch}" "$version" "$branch")
        search_repo="${pr_target_repo:-$repo}"

        debug_log "  checking PRs: pattern='$expanded_title' target='$expanded_target_branch' repo='$search_repo'"

        if [[ "$pr_required_flag" == "true" ]]; then
            prs_required=$((prs_required + 1))
        fi

        local found_prs
        found_prs=$(find_pull_requests "$search_repo" "$expanded_title" "$expanded_target_branch")
        local found_count merged_count
        found_count=$(echo "$found_prs" | jq -r 'length')
        merged_count=$(echo "$found_prs" | jq -r '[.[] | select(.merged == true)] | length')

        if [[ "$found_count" -gt 0 ]]; then
            if [[ "$merged_count" -ge "$pr_expected_count" ]]; then
                pr_details+=("merged|${search_repo}|${expanded_title}|$(echo "$found_prs" | jq -r '.[0].number')|$(echo "$found_prs" | jq -r '.[0].url')|${pr_required_flag}")
                if [[ "$pr_required_flag" == "true" ]]; then
                    prs_merged=$((prs_merged + 1))
                fi
            else
                local first_pr_number first_pr_url
                first_pr_number=$(echo "$found_prs" | jq -r '.[0].number')
                first_pr_url=$(echo "$found_prs" | jq -r '.[0].url')
                pr_details+=("open|${search_repo}|${expanded_title}|#${first_pr_number}|${first_pr_url}|${expanded_target_branch}|${pr_required_flag}")
            fi
        else
            pr_details+=("not_found|${search_repo}|${expanded_title}|${pr_required_flag}")
        fi
        i=$((i + 1))
    done

    # --- Aggregate status ---
    local overall_status
    overall_status=$(aggregate_status "$wf_status" "$wf_conclusion" "$artifacts_total" "$artifacts_found" \
        "$branches_total" "$branches_found" "$prs_required" "$prs_merged")

    TOTAL_PROJECTS=$((TOTAL_PROJECTS + 1))
    case "$overall_status" in
        done)        COUNT_DONE=$((COUNT_DONE + 1)) ;;
        in_progress) COUNT_IN_PROGRESS=$((COUNT_IN_PROGRESS + 1)) ;;
        failed)      COUNT_FAILED=$((COUNT_FAILED + 1)) ;;
        not_started) COUNT_NOT_STARTED=$((COUNT_NOT_STARTED + 1)) ;;
    esac

    # Update phase-specific counters
    PHASE_TOTAL[$phase_key]=$((${PHASE_TOTAL[$phase_key]:-0} + 1))
    case "$overall_status" in
        done)        PHASE_DONE[$phase_key]=$((${PHASE_DONE[$phase_key]:-0} + 1)) ;;
        in_progress) PHASE_IN_PROGRESS[$phase_key]=$((${PHASE_IN_PROGRESS[$phase_key]:-0} + 1)) ;;
        failed)      PHASE_FAILED[$phase_key]=$((${PHASE_FAILED[$phase_key]:-0} + 1)) ;;
        not_started) PHASE_NOT_STARTED[$phase_key]=$((${PHASE_NOT_STARTED[$phase_key]:-0} + 1)) ;;
    esac

    # --- Print project status ---
    local icon label
    icon=$(status_icon "$overall_status")
    label=$(status_label "$overall_status")
    printf "%s %s (%s) %*s\n" "$icon" "$name" "$repo" $((60 - ${#name} - ${#repo})) "$label"

    # Workflow line
    local wf_detail_icon
    if [[ "$wf_status" == "not_checked" ]]; then
        wf_detail_icon="○"
        echo "  $wf_detail_icon Workflow: $wf_name (checking disabled)"
    elif [[ "$wf_status" == "completed" ]] && [[ "$wf_conclusion" == "success" ]]; then
        wf_detail_icon="✓"
        echo "  $wf_detail_icon Workflow: $wf_name (completed)"
    elif [[ "$wf_status" == "completed" ]] && [[ "$wf_conclusion" == "failure" ]]; then
        wf_detail_icon="✗"
        echo "  $wf_detail_icon Workflow: $wf_name (failed)"
        BLOCKERS+=("$name workflow failed - requires attention")
    elif [[ "$wf_status" == "in_progress" ]]; then
        wf_detail_icon="⚙"
        echo "  $wf_detail_icon Workflow: $wf_name (running)"
    elif [[ "$wf_status" == "queued" ]]; then
        wf_detail_icon="⧗"
        echo "  $wf_detail_icon Workflow: $wf_name (queued)"
    else
        wf_detail_icon=$(item_icon "false" "$overall_status")
        echo "  $wf_detail_icon Workflow: $wf_name (no runs found)"
    fi

    # Branch lines
    for bd in "${branch_details[@]+"${branch_details[@]}"}"; do
        local bd_status bd_name
        bd_status="${bd%%:*}"
        bd_name="${bd#*:}"
        if [[ "$bd_status" == "found" ]]; then
            echo "  ✓ Branch: $bd_name"
        else
            local bd_icon
            bd_icon=$(item_icon "false" "$overall_status")
            echo "  $bd_icon Branch: $bd_name (not found)"
        fi
    done

    # Artifact lines
    for ad in "${artifact_details[@]+"${artifact_details[@]}"}"; do
        local ad_status ad_type ad_value
        ad_status="${ad%%:*}"
        ad_type="${ad#*:}"
        ad_type="${ad_type%%:*}"
        ad_value="${ad#*:*:}"
        if [[ "$ad_status" == "found" ]]; then
            case "$ad_type" in
                image)   echo "  ✓ Image: $ad_value" ;;
                npmjs)   echo "  ✓ NPM: $ad_value" ;;
                github-release) echo "  ✓ GitHub Release: $ad_value" ;;
                github-release-notes) echo "  ✓ GitHub Release Notes: $ad_value" ;;
                website) echo "  ✓ Website: $ad_value" ;;
                website-version) echo "  ✓ Website Version: $ad_value" ;;
            esac
        else
            local ad_icon
            ad_icon=$(item_icon "false" "$overall_status")
            case "$ad_type" in
                image)   echo "  $ad_icon Image: $ad_value (not found)" ;;
                npmjs)   echo "  $ad_icon NPM: $ad_value (not found)" ;;
                github-release) echo "  $ad_icon GitHub Release: $ad_value (not found)" ;;
                github-release-notes) echo "  $ad_icon GitHub Release Notes: $ad_value (not published or draft)" ;;
                website) echo "  $ad_icon Website: $ad_value (not accessible)" ;;
                website-version) echo "  $ad_icon Website Version: $ad_value (mismatch)" ;;
            esac
        fi
    done

    # PR lines
    for pd in "${pr_details[@]+"${pr_details[@]}"}"; do
        local pd_status pd_rest
        pd_status="${pd%%|*}"
        pd_rest="${pd#*|}"
        if [[ "$pd_status" == "merged" ]]; then
            local pd_title pd_num pd_required
            IFS='|' read -r _ pd_title pd_num _ pd_required <<< "$pd_rest"
            echo "  ✓ PR #${pd_num}: ${pd_title} (merged)"
        elif [[ "$pd_status" == "open" ]]; then
            local pd_title pd_num pd_branch pd_required
            IFS='|' read -r _ pd_title pd_num _ pd_branch pd_required <<< "$pd_rest"
            if [[ "$pd_required" == "true" ]]; then
                echo "  ⧗ PR ${pd_num}: ${pd_title} → ${pd_branch} (open, required)"
                BLOCKERS+=("$name PR ${pd_num} must be merged")
            else
                echo "  ⧗ PR ${pd_num}: ${pd_title} → ${pd_branch} (open)"
            fi
        else
            local pd_title pd_required
            IFS='|' read -r _ pd_title pd_required <<< "$pd_rest"
            local pd_icon
            pd_icon=$(item_icon "false" "$overall_status")
            echo "  $pd_icon PR: ${pd_title} (not found)"
        fi
    done

    echo ""
}

print_summary() {
    echo "================================================================================"
    echo "Summary"
    echo "────────────────────────────────────────────────────────────────────────────────"
    echo "Overall Status:"
    echo "  Total Projects: ${TOTAL_PROJECTS}"
    echo "    ✓ Done: ${COUNT_DONE}"
    echo "    ⚙ In Progress: ${COUNT_IN_PROGRESS}"
    echo "    ✗ Failed: ${COUNT_FAILED}"
    echo "    ○ Not Started: ${COUNT_NOT_STARTED}"
    echo ""
    echo "By Phase:"

    for phase_key in "${PHASE_ORDER[@]}"; do
        local phase_num="${phase_key#phase-}"
        local phase_desc="${PHASE_DESCRIPTIONS[$phase_key]}"
        local phase_total="${PHASE_TOTAL[$phase_key]:-0}"
        local phase_done="${PHASE_DONE[$phase_key]:-0}"
        local phase_in_progress="${PHASE_IN_PROGRESS[$phase_key]:-0}"
        local phase_failed="${PHASE_FAILED[$phase_key]:-0}"
        local phase_not_started="${PHASE_NOT_STARTED[$phase_key]:-0}"

        # Determine phase status icon
        local phase_icon
        if [[ $phase_total -eq $phase_done ]] && [[ $phase_total -gt 0 ]]; then
            phase_icon="✓"
        elif [[ $phase_failed -gt 0 ]]; then
            phase_icon="✗"
        elif [[ $phase_in_progress -gt 0 ]]; then
            phase_icon="⚙"
        elif [[ $phase_not_started -eq $phase_total ]] && [[ $phase_total -gt 0 ]]; then
            phase_icon="○"
        else
            phase_icon="⧗"
        fi

        echo "  ${phase_icon} Phase ${phase_num}: ${phase_desc} (${phase_done}/${phase_total} done)"
        if [[ $phase_in_progress -gt 0 ]] || [[ $phase_failed -gt 0 ]] || [[ $phase_not_started -gt 0 ]]; then
            echo "      ⚙ In Progress: ${phase_in_progress}  ✗ Failed: ${phase_failed}  ○ Not Started: ${phase_not_started}"
        fi
    done

    if [[ ${#BLOCKERS[@]} -gt 0 ]]; then
        echo ""
        echo "Blocking Issues:"
        for blocker in "${BLOCKERS[@]}"; do
            echo "  - $blocker"
        done
    fi
}

# --- Main ---

VERSION=""
while [[ $# -gt 0 ]]; do
    case $1 in
        --debug) DEBUG=true ;;
        --help|-h) usage ;;
        *) VERSION="$1" ;;
    esac
    shift
done

if [[ -z "$VERSION" ]]; then
    usage
fi

validate_version "$VERSION"
BRANCH=$(calculate_branch "$VERSION")

# Check tokens
if [[ -z "${CHE_BOT_GITHUB_TOKEN:-}" ]]; then
    echo "[ERROR] CHE_BOT_GITHUB_TOKEN is not set" >&2
    echo "Set it with: export CHE_BOT_GITHUB_TOKEN=<your-token>" >&2
    exit 1
fi

if [[ -z "${CHE_INCUBATOR_BOT_GITHUB_TOKEN:-}" ]]; then
    echo "[WARN] CHE_INCUBATOR_BOT_GITHUB_TOKEN is not set, using CHE_BOT_GITHUB_TOKEN for all repos" >&2
    export CHE_INCUBATOR_BOT_GITHUB_TOKEN="$CHE_BOT_GITHUB_TOKEN"
fi

# Check rate limit
remaining=$(check_rate_limit "$CHE_BOT_GITHUB_TOKEN") || true
if [[ "$remaining" == "0" ]]; then
    echo "[ERROR] GitHub API rate limit exhausted. Try again later." >&2
    exit 1
elif [[ "$remaining" != "unknown" ]] && [[ "$remaining" -lt 100 ]]; then
    echo "[WARN] GitHub API rate limit low: ${remaining} requests remaining" >&2
fi

# Parse config
parse_release_config "$REPO_ROOT/che-release.yaml"

# Print header
print_header "$VERSION" "$BRANCH"

# Process each phase
for phase_key in $(get_phase_keys); do
    local_phase_num="${phase_key#phase-}"
    local_phase_desc=$(get_phase_description "$phase_key")
    echo "Phase ${local_phase_num}: ${local_phase_desc}"
    echo "────────────────────────────────────────────────────────────────────────────────"

    # Store phase info for summary
    PHASE_ORDER+=("$phase_key")
    PHASE_DESCRIPTIONS[$phase_key]="$local_phase_desc"
    PHASE_TOTAL[$phase_key]=0
    PHASE_DONE[$phase_key]=0
    PHASE_IN_PROGRESS[$phase_key]=0
    PHASE_FAILED[$phase_key]=0
    PHASE_NOT_STARTED[$phase_key]=0

    local_projects_json=$(get_phase_projects_json "$phase_key")
    local_project_count=$(echo "$local_projects_json" | jq -r 'length')

    local_i=0
    while [[ $local_i -lt $local_project_count ]]; do
        local_project=$(echo "$local_projects_json" | jq -c ".[$local_i]")
        process_project "$local_project" "$VERSION" "$BRANCH" "$phase_key"
        local_i=$((local_i + 1))
    done
done

# Print summary
print_summary

# Cleanup
rm -f "$RELEASE_CONFIG_FILE"
