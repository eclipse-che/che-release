# AGENTS.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Repository Purpose

This is the Eclipse Che release orchestration repository. It automates the coordinated release of Eclipse Che components across multiple GitHub repositories in a specific order based on dependencies.

## Release Commands

### Orchestrate full release
```bash
./make-release.sh --version 7.75.0 --phases 1,2,3
```
- `--version` (-v): Version to release in format 7.y.z
- `--phases` (-p): Comma-separated list of phases to run (default: 1,2,3)

### Create a release branch
```bash
./make-branch.sh --branch 7.75.x --branchfrom main --repo <GITHUB_REPO_URL>
```
- Use `--force` to delete and recreate an existing branch

## Release Architecture

### Release Configuration

The release configuration is defined in `che-release.yaml` at the repository root. This YAML file contains:
- **Phases**: All release phases with descriptions
- **Projects**: Project metadata including repository, workflow ID, expected artifacts
- **Workflows**: GitHub Actions workflow names and IDs to trigger
- **Artifacts**: Container images, NPM packages, GitHub releases, and websites to verify
- **Branches**: Expected branches for each project
- **Pull Requests**: Expected PRs with patterns, targets, and completion requirements

The `scripts/release-info.sh` script reads this configuration to display comprehensive release status.

### Multi-Phase Release Process

The release process is divided into phases based on project dependencies:

**Phase 1** - Independent projects (no Che dependencies):
- che-code
- jetbrains-ide-dev-server
- configbump
- che-machine-exec
- che-server
- devworkspace-generator (NPM package)
- kubernetes-image-puller (branch creation only)

**Phase 2** - Projects depending on Phase 1:
- che-e2e (depends on che-server, devworkspace-generator)
- che-plugin-registry (depends on che-machine-exec)
- che-dashboard

**Phase 3** - Operator (depends on all previous phases):
- che-operator

**Phase 4+** - Downstream releases (manual steps required):
- community-operators PRs
- chectl CLI
- che-docs

**Phase 5+** - Website and verification:
- che-website-publish
- release-check-unmerged-PRs

### Version and Branch Strategy

- **Version format**: 7.yy.z (e.g., 7.75.0, 7.75.1)
- **Branch format**: 7.yy.x (e.g., 7.75.x)
- **For .0 releases** (7.yy.0): Release from `main` branch
- **For bugfix releases** (7.yy.1+): Release from the corresponding .x branch (e.g., 7.75.x)

### GitHub Action Invocation

The `make-release.sh` script triggers GitHub Actions workflows in each project repository using the GitHub API. The `invokeAction()` function in `utils/util.sh`:

1. Computes the workflow ID from the action name
2. Determines the correct branch to run from (main for .0 releases, .x branch for bugfixes)
3. Uses personal GitHub token `GITHUB_TOKEN` for authentication
4. Dispatches the workflow with version parameters

### Verification Steps

After each phase, the script verifies that artifacts were published before proceeding:

- **Container images**: Checks Quay.io using `verifyContainerExistsWithTimeout()`
- **NPM packages**: Checks npmjs.org using `verifyNpmJsPackageExistsWithTimeout()`
- **Git branches**: Checks GitHub using `verifyBranchExistsWithTimeout()`
- **GitHub releases**: Checks for release tags via GitHub API
- **Websites**: Checks HTTP accessibility (status 200)
- **Website version**: Checks that the HTML element with class "version-menu-toggle" displays the correct version

Verification retries every 20 seconds for the specified timeout period (30-60 minutes depending on the artifact).

## Key Files

- `che-release.yaml`: Release configuration defining all phases, projects, workflows, artifacts, and PRs
- `make-release.sh`: Main orchestration script
- `utils/util.sh`: Reusable functions for GitHub API calls, verification, error handling
- `.github/workflows/release-orchestrate-overall.yml`: GitHub workflow that runs make-release.sh
- `scripts/release-info.sh`: Status reporting script that reads from che-release.yaml
- `README.md`: Detailed release procedure and project status

## Environment Variables Required

When running manually (outside GitHub Actions):

- `CHE_VERSION`: Version being released
- `CHE_GITHUB_SSH_KEY`: SSH key for Git operations (base64 encoded)
- `CHE_BOT_GITHUB_TOKEN`: Token for eclipse-che/* repos
- `CHE_INCUBATOR_BOT_GITHUB_TOKEN`: Token for che-incubator/* and devfile/* repos
- `QUAY_ECLIPSE_CHE_USERNAME`: Quay.io username
- `QUAY_ECLIPSE_CHE_PASSWORD`: Quay.io password

## Blocker Issue Check

For .0 releases, the script checks for open blocker issues in eclipse/che before proceeding:
```bash
curl -s "https://api.github.com/repos/eclipse/che/issues?labels=severity/blocker&state=open"
```

## Lint and Type-Check Commands

### Single-file bash script checks

**Syntax check**:
```bash
bash -n <script.sh>
```
Validates bash syntax without executing the script.

**ShellCheck** (if installed):
```bash
shellcheck <script.sh>
```
Static analysis for shell scripts. Install with: `dnf install ShellCheck` or `apt-get install shellcheck`

**Format check** (if shfmt installed):
```bash
shfmt -d <script.sh>
```
Check formatting. Install from: https://github.com/mvdan/sh

**All scripts at once**:
```bash
find . -name "*.sh" -type f -exec bash -n {} \;
```

## Common Troubleshooting

- If a workflow fails, you can restart individual workflows or re-run specific phases by providing the phase number to `--phases`
- Sometimes you may need to regenerate tags or skip certain steps
- Modified workflow files can be tested from feature branches by triggering the workflow on that branch
- Che Operator PRs must be manually approved and merged before Phase 4+ can proceed

## Red Hat Compliance and Responsible AI Rules

See [redhat-compliance-and-responsible-ai.md](redhat-compliance-and-responsible-ai.md) and the Cursor rules file under `.cursor/rules/`.