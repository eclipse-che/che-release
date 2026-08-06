---
name: release-info
description: |
  Display the current state of an Eclipse Che release across all phases.
  Shows workflow status, artifact publication, branch creation, and PR status
  for each component in the release process.
  Triggers: "release info", "release status", "show release status",
  "what's the status of release", "release-info 7.120.0"
version: 1.0.0
tools:
  - Read
  - Bash
---

# Eclipse Che Release Status

This skill displays comprehensive release status for all Eclipse Che components across all release phases.

## Usage

The user should provide a version number in the format `X.Y.Z` (e.g., 7.120.0).

**Examples**:
- `release-info 7.120.0`
- "Show release status for 7.120.0"
- "What's the status of release 7.75.0?"

## Execution

### Step 1: Extract and Validate Version

Extract the version from the user's input:
- Expected format: `MAJOR.MINOR.BUGFIX` (e.g., 7.120.0)
- Pattern: `\d+\.\d+\.\d+`
- If no version provided or invalid format, ask the user to provide one

### Step 2: Check Environment

Verify required environment variables are set:
- `CHE_BOT_GITHUB_TOKEN` - required
- `CHE_INCUBATOR_BOT_GITHUB_TOKEN` - optional (falls back to CHE_BOT_GITHUB_TOKEN)

If `CHE_BOT_GITHUB_TOKEN` is not set, check if `GITHUB_TOKEN` is available and use that:

```bash
if [[ -z "${CHE_BOT_GITHUB_TOKEN:-}" ]]; then
    if [[ -n "${GITHUB_TOKEN:-}" ]]; then
        export CHE_BOT_GITHUB_TOKEN="$GITHUB_TOKEN"
    else
        echo "Error: No GitHub token available."
        echo "Set CHE_BOT_GITHUB_TOKEN or GITHUB_TOKEN environment variable."
    fi
fi
```

### Step 3: Run release-info.sh

Execute the main script from the repository root:

```bash
cd /home/mkuznets/projects/claude/che-release
./scripts/release-info.sh <VERSION>
```

For debug output:
```bash
./scripts/release-info.sh <VERSION> --debug
```

### Step 4: Present Results

Display the script output directly to the user. The script produces formatted output with:
- Per-phase grouping with descriptions
- Per-project status (DONE / IN PROGRESS / FAILED / NOT STARTED)
- Detailed item status for workflows, branches, artifacts, and PRs
- Summary with counts and blocking issues

## Error Handling

- If the script is not found, report that the release-info scripts need to be set up
- If tokens are missing, guide the user on how to set them
- If the script fails, show the error output and suggest running with `--debug`

## Configuration

All project and phase configuration is in `AGENTS.md` YAML frontmatter.
To add or modify projects, edit the `release-config` section in `AGENTS.md`.
