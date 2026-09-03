#!/bin/bash

# for a given container URL, check if it exists and its digest can be read
# verifyContainerExists quay.io/crw/pluginregistry-rhel8:2.6 # schemaVersion = 1, look for tag
# verifyContainerExists quay.io/eclipse/che-plugin-registry:7.24.2 # schemaVersion = 2, look for arches
verifyContainerExists()
{
    this_containerURL="${1}"
    this_image=""; this_tag=""
    this_image=${this_containerURL#*/}
    this_tag=${this_image##*:}
    this_image=${this_image%%:*}
    this_url="https://quay.io/v2/${this_image}/manifests/${this_tag}"
    # echo $this_url

    # get result=tag if tag found, result="null" if not
    result="$(curl -sSL "${this_url}"  -H "Accept: application/vnd.docker.distribution.manifest.list.v2+json" 2>&1 || true)"
    if [[ $(echo "$result" | jq -r '.schemaVersion' || true) == "1" ]] && [[ $(echo "$result" | jq -r '.tag' || true) == "$this_tag" ]]; then
        echo "[INFO] Found ${this_containerURL} (tag = $this_tag)"
        containerExists=1
    elif [[ $(echo "$result" | jq -r '.schemaVersion' || true) == "2" ]]; then
        arches=$(echo "$result" | jq -r '[.manifests[].platform.architecture]|@csv' | tr -d "\"")
        if [[ $arches ]]; then
            echo "[INFO] Found ${this_containerURL} (arches = $arches)"
        fi
        containerExists=1
    else
        # echo "[INFO] Did not find ${this_containerURL}"
        containerExists=0
    fi
}

verifyContainerExistsWithTimeout()
{
    this_containerURL=$1
    this_timeout=$2
    containerExists=0
    count=1
    (( timeout_intervals=this_timeout*3 ))
    while [[ $count -le $timeout_intervals ]]; do # echo $count
        echo "       [$count/$timeout_intervals] Verify ${1} exists..."
        # check if the container exists
        verifyContainerExists "$1"
        if [[ ${containerExists} -eq 1 ]]; then break; fi
        (( count=count+1 ))
        sleep 20s
    done
    # or report an error
    if [[ ${containerExists} -eq 0 ]]; then
        echo "[ERROR] Did not find ${1} after ${this_timeout} minutes - script must exit!"
        exit 1;
    fi
}

# for a given url of project hosten on NPMJS, check if it exists
# package name must be in format "<scope>/name@version"
# e.g. "@eclipse-che/che-devworkspace-generator@7.70.0"
verifyNpmJsPackageExists()
{
    this_package=${1}
    this_name="${this_package%@*}"
    this_version="${this_package##*@}"
    registry_json="$(curl -s https://registry.npmjs.org/"${this_name}"/)"
    if echo "$registry_json" | jq -e '."versions"."'"${this_version}"'"' > /dev/null; then
        echo "[INFO] Found ${this_package}"
        packageExists=1
    else
        # echo "[INFO] Did not find ${this_package}"
        packageExists=0
    fi
}

verifyNpmJsPackagexistsWithTimeout()
{
    this_package=$1
    this_timeout=$2
    packageExists=0
    count=1
    (( timeout_intervals=this_timeout*3 ))
    while [[ $count -le $timeout_intervals ]]; do # echo $count
        echo "       [$count/$timeout_intervals] Verify ${1} exists..."
        # check if the package exists
        verifyNpmJsPackageExists "$1"
        if [[ ${containerExists} -eq 1 ]]; then break; fi
        (( count=count+1 ))
        sleep 20s
    done
    # or report an error
    if [[ ${packageExists} -eq 0 ]]; then
        echo "[ERROR] Did not find ${1} after ${this_timeout} minutes - script must exit!"
        exit 1;
    fi
}

verifyNpmJsPackageExistsWithTimeoutAndExit() {
    if ! verifyNpmJsPackagexistsWithTimeout "$@"; then
        exit 1
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

check_github_release_notes() {
    local repo="$1"
    local tag="$2"
    local token
    token=$(get_github_token "$repo")

    if [[ -z "$token" ]]; then
        return 1
    fi

    # Fetch the full release JSON to check draft status
    local response
    response=$(curl -sSL \
        -H "Authorization: token ${token}" \
        -H "Accept: application/vnd.github.v3+json" \
        "https://api.github.com/repos/${repo}/releases/tags/${tag}" 2>/dev/null || echo "")

    if [[ -z "$response" ]]; then
        return 1
    fi

    # Check if it's a 404 error
    if echo "$response" | jq -e '.message == "Not Found"' > /dev/null 2>&1; then
        return 1
    fi

    # Check if draft is false (release is published)
    # Note: Don't use '.draft // true' because jq's // operator returns the RHS when LHS is false,
    # which would incorrectly treat published releases (draft=false) as drafts
    local draft
    draft=$(echo "$response" | jq -r 'if .draft == null then true else .draft end')

    if [[ "$draft" == "false" ]]; then
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

check_website_version() {
    local url="$1"
    local expected_version="$2"

    # Fetch the HTML content (curl -L follows HTTP redirects)
    local html_content
    html_content=$(curl -sSL --max-time 10 "$url" 2>/dev/null || echo "")

    if [[ -z "$html_content" ]]; then
        return 1
    fi

    # Extract content from element with class "version-menu-toggle"
    # Pattern: <button class="version-menu-toggle" ...>VERSION</button>
    local version_text
    version_text=$(echo "$html_content" | grep 'version-menu-toggle' | sed -n 's/.*version-menu-toggle[^>]*>\([^<]*\)<.*/\1/p' | head -1 | xargs)

    # If version not found, check if this is a redirect page with canonical link
    if [[ -z "$version_text" ]]; then
        local canonical_url
        canonical_url=$(echo "$html_content" | grep -o '<link rel="canonical" href="[^"]*"' | sed -n 's/.*href="\([^"]*\)".*/\1/p')

        if [[ -n "$canonical_url" ]]; then
            # Fetch the canonical URL
            html_content=$(curl -sSL --max-time 10 "$canonical_url" 2>/dev/null || echo "")
            version_text=$(echo "$html_content" | grep 'version-menu-toggle' | sed -n 's/.*version-menu-toggle[^>]*>\([^<]*\)<.*/\1/p' | head -1 | xargs)
        fi
    fi

    if [[ -z "$version_text" ]]; then
        return 1
    fi

    # Calculate the branch format from version (e.g., 7.121.0 -> 7.121.x)
    local expected_branch
    expected_branch="${expected_version%.*}.x"

    # Check if the website shows either the full version or the branch format
    if [[ "$version_text" == "$expected_version" ]] || [[ "$version_text" == "$expected_branch" ]]; then
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
