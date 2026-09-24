#!/bin/bash

RELEASE_CONFIG_FILE=""

parse_release_config() {
    local release_config="$1"

    if [[ ! -f "$release_config" ]]; then
        echo "[ERROR] File not found: $release_config" >&2
        return 1
    fi

    RELEASE_CONFIG_FILE=$(mktemp /tmp/release-config-XXXXXX.yaml)
    yq -y '.' "$release_config" > "$RELEASE_CONFIG_FILE"

    if [[ ! -s "$RELEASE_CONFIG_FILE" ]]; then
        echo "[ERROR] No YAML frontmatter found in $release_config" >&2
        rm -f "$RELEASE_CONFIG_FILE"
        return 1
    fi

    local phase_count
    phase_count=$(yq '.release_config.phases | keys | length' "$RELEASE_CONFIG_FILE")
    if [[ "$phase_count" -eq 0 ]]; then
        echo "[ERROR] No phases found in release_config" >&2
        rm -f "$RELEASE_CONFIG_FILE"
        return 1
    fi
}

get_phase_keys() {
    yq -r '.release_config.phases | keys | .[]' "$RELEASE_CONFIG_FILE"
}

get_phase_description() {
    local phase_key="$1"
    yq -r ".release_config.phases.${phase_key}.description" "$RELEASE_CONFIG_FILE"
}

get_phase_projects_json() {
    local phase_key="$1"
    yq ".release_config.phases.${phase_key}.projects" "$RELEASE_CONFIG_FILE"
}

get_project_count() {
    local phase_key="$1"
    yq ".release_config.phases.${phase_key}.projects | length" "$RELEASE_CONFIG_FILE"
}

expand_placeholders() {
    local template="$1"
    local version="$2"
    local branch="$3"
    echo "$template" | sed "s/{version}/$version/g; s/{branch}/$branch/g"
}
