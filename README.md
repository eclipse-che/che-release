# Che release process

## Permissions
 
Contact [repository maintaners](https://github.com/eclipse-che/che-release/blob/main/.github/CODEOWNERS#L2) for any additional permissions for running release scripts manually.
Some scripts may require a GitHub personal access token with read/write access to Eclipse Che repositories.

## Projects Overview
This repository contains a number of key scripts, docs, configurations that pertain to the release of Eclipse Che.

- [che-release.yaml](https://github.com/eclipse-che/che-release/blob/main/che-release.yaml) - this file acts as a source of truth for all release scripts in this repository. It contains information about all projects involved in the release process, their respective workflows, release artifacts, associated pull requests, and other useful information.

In this document, projects are arranged into **phases**. The main purpose of the phase, is to ensure the correct order of release workflows. For example, if Che operands should be released before Che Operator, the operands must belong to the phase, that is lower that the phase for the operator. It should not be possible to begin release of projects of any later phase, if projects in previous phases have not been released.

When the release order is updated, you must ensure that every project is correctly placed in respective phase (add or remove phases if needed).

- [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/scripts/make-release.sh) - a release orchestrator script for starting a release - used in [Release - Orchestration](https://github.com/eclipse-che/che-release/actions/workflows/release-orchestrate-overall.yml) workflow.

It is intended to only work with phases that are specifically marked for orchestration with a respective `orchestration: true` field. Note that you can run this script with a custom phase order, e.g. if you are re-running the release, and all projects in phase 1 have already been released, although the script will still perform verification of existence of release artifacts for any preceding phases.
- [release-info.sh](https://github.com/eclipse-che/che-release/blob/main/scripts/release-info.sh) - a script, that is useful for monitoring the state of ongoing release. It will collect and print out the information about any associated release artifacts, pull requests and other useful information.

The Che projects that are part of the release cycle are orchestrated into a single action: [Orchestrate Overall Release](https://github.com/eclipse-che/che-release/actions/workflows/release-orchestrate-overall.yml), which runs [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/make-release.sh).


## Release Procedure
1. [Create a new release issue and include it into the sprint planning](https://github.com/eclipse-che/che/issues/new?assignees=&labels=kind%2Frelease&template=release.md&title=Release+Eclipse+Che+7.NEWVERSION),

2. Once all pending PRs/blocker issues are resolved, use the [Release - Orchestration](https://github.com/eclipse-che/che-release/actions/workflows/release-orchestrate-overall.yml) workflow to trigger Che release workflows. This should begin the orderly release of all Che Operator dependencies and Che operator itself (create Che operator artifacts and pull requests with CSV files).

    2.1 If one of the workflows has crashed, inspect it. Apply fixes if needed, and restart it. You can restart individual workflow, or whole phase in orchestration job, whichever is simpler.

    2.2 Keep in mind, that sometimes you'll need to [regenerate tags](https://github.com/eclipse-che/che/issues/18879), or skip certain substeps in that job. Also ensure that correct code is in place, whether it is main or bugfix branch.

    2.3 Sometimes, the hotfix changes to the workflow can take too long to get approved and merged. In certain situations, we can use the modified workflow file, which is pushed in its own branch, and then trigger the workflow, while specifying the branch with our modified workflow. 

3. When Che Operator PRs have been generated, you must wait for the approval of PR checks, that are in that repository. The PR checks include running of various tests, so if something is wrong with operator or its dependencies, it should be possible to apply the fixes and re-release any of them if needed, but only at this stage, before operator PRs are merged.
If there are any questions, you can forward them to the [repository maintaners](https://github.com/eclipse-che/che-operator/blob/main/.github/CODEOWNERS#L2). When PRs are merged, the last batch of projects will be triggered to release

    3.1 Chectl PR has to be closed manually, after they're generated, and all its associated PR checks are passed.

    3.2 Community operator PRs are merged by Operator Framework members, as soon as their tests will pass (in some cases they may require some input from us)

    3.3 Docs PR has to be merged by Docs team.

4. When the release is complete, the release notes should be published, as well as any other respective announcements.

    4.1 Ensure that all PRs that were created during the release (like ones that bump the project to the next version). Run the job [Release - Check for unmerged PRs](https://github.com/eclipse-che/che-release/actions/workflows/release-check-unmerged-PRs.yml) to help locate any remaining open PRs.

--------------


### Che projects that are not part of the release process:

Here is the information about projects related to Che, but are not a part of Che release process/versioning 

 - https://github.com/devfile/devworkspace-operator - used in Che operator.
 - https://github.com/che-incubator/kubernetes-image-puller-operator - used in Che operator.
 - https://github.com/eclipse-che/blog - Eclipse Che blog.
 - https://github.com/eclipse-che/che-website - Eclipse Che website sources. [che-website-publish](https://github.com/eclipse-che/che-website-publish) will publish this website, along with Che Docs

