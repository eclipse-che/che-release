#!/bin/bash

aggregate_status() {
    local workflow_status="$1"
    local workflow_conclusion="$2"
    local artifacts_total="$3"
    local artifacts_found="$4"
    local branches_total="$5"
    local branches_found="$6"
    local prs_required="$7"
    local prs_merged="$8"

    # Failed takes precedence
    if [[ "$workflow_status" == "completed" ]] && [[ "$workflow_conclusion" == "failure" ]]; then
        echo "failed"
        return 0
    fi

    # Workflow running or queued
    if [[ "$workflow_status" == "in_progress" ]] || [[ "$workflow_status" == "queued" ]]; then
        echo "in_progress"
        return 0
    fi

    # No workflow found
    if [[ "$workflow_status" == "not_found" ]]; then
        if [[ "$artifacts_found" -gt 0 ]] || [[ "$branches_found" -gt 0 ]]; then
            echo "in_progress"
        else
            echo "not_started"
        fi
        return 0
    fi

    # Workflow completed successfully
    if [[ "$workflow_status" == "completed" ]] && [[ "$workflow_conclusion" == "success" ]]; then
        if [[ "$artifacts_found" -lt "$artifacts_total" ]]; then
            echo "in_progress"
            return 0
        fi
        if [[ "$branches_found" -lt "$branches_total" ]]; then
            echo "in_progress"
            return 0
        fi
        if [[ "$prs_required" -gt "$prs_merged" ]]; then
            echo "in_progress"
            return 0
        fi
        echo "done"
        return 0
    fi

    # Unknown state
    echo "in_progress"
}
