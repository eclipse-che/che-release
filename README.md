# Che release process

## Permissions
 
1. Get push permission from @fbenoit to push applications
    * https://quay.io/organization/eclipse-che-operator-kubernetes/teams/pushers
    * https://quay.io/organization/eclipse-che-operator-openshift/teams/pushers 
    * https://quay.io/application/eclipse-che-operator-kubernetes
    * https://quay.io/application/eclipse-che-operator-openshift

2. Get commit rights from @fbenoit to push community PRs
    * https://github.com/che-incubator/community-operators


## Automated release workflows

Currently all projects have automated release process, that consists of GitHub Actions workflow.
Additionally, release logic is mostly contained within `make-release.sh` file, which allows to perform the release outside of GitHub Actions framework, should the need for it arises.
For example, in the [Che server](https://github.com/eclipse-che/che-server) repo, GitHub action [release.yml](https://github.com/eclipse-che/che-server/actions/workflows/release.yml) runs the [make-release.sh](https://github.com/eclipse-che/che-server/blob/main/make-release.sh) release script.

GitHub Actions release workflows can be run by any user with write access to the repo in which the workflow is located. They use repository secrets, such as Quay or Docker.io credentials, that are required by most of the release workflows. If run outside GitHub, authorized users will need to provide their own secrets.

## Projects overview
The Che projects that are part of the release cycle are orchestrated into a single action:  [Orchestrate Overall Release](https://github.com/eclipse-che/che-release/actions/workflows/release-orchestrate-overall.yml), which runs [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/make-release.sh).

The projects covered by this workflow release container images, NPM artifacts, or CLI binaries versioned 7.yy.0 every sprint:

| Phase       | Project | Workflow Status | Quay Image | Other Artifact |
| :---        | :---    | :---            | :---       | :---           |
| **Phase 1** | [che-code](https://github.com/che-incubator/che-code) | [![Release](https://github.com/che-incubator/che-code/actions/workflows/release.yml/badge.svg)](https://github.com/che-incubator/che-code/actions/workflows/release.yml) | [che-code](https://quay.io/che-incubator/che-code) |
| | [configbump](https://github.com/che-incubator/configbump) | [![Release](https://github.com/che-incubator/configbump/actions/workflows/release.yml/badge.svg)](https://github.com/che-incubator/configbump/actions/workflows/release.yml) | [configbump](https://quay.io/che-incubator/configbump) |
| | [che-machine-exec](https://github.com/eclipse-che/che-machine-exec) | [![Release](https://github.com/eclipse-che/che-machine-exec/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-machine-exec/actions/workflows/release.yml) | [che-machine-exec](https://quay.io/eclipse/che-machine-exec) |
| | [che server](https://github.com/eclipse-che/che-server) | [![Release](https://github.com/eclipse-che/che-server/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-server/actions/workflows/release.yml) | [che-server](https://quay.io/eclipse/che-server) |
| | [devworkspace-generator](https://github.com/eclipse-che/che-devfile-registry/tree/main/tools/devworkspace-generator ) | [![Release](https://github.com/eclipse-che/che-devfile-registry/actions/workflows/devworkspace-generator-release.yml/badge.svg)](https://github.com/eclipse-che/che-devfile-registry/actions/workflows/devworkspace-generator-release.yml) | | NPM [@eclipse-che/che-devworkspace-generator](https://www.npmjs.com/package/@eclipse-che/che-devworkspace-generator)
| | [kubernetes-image-puller](https://github.com/che-incubator/kubernetes-image-puller) | [![Branch](https://github.com/che-incubator/kubernetes-image-puller/actions/workflows/make-branch.yaml/badge.svg)](https://github.com/che-incubator/kubernetes-image-puller/actions/workflows/make-branch.yaml) | [kubernetes-image-puller/branches](https://github.com/che-incubator/kubernetes-image-puller/branches/active)
| | | 
| **Phase 2** | [che-e2e](https://github.com/eclipse/che) | [![Release](https://github.com/eclipse/che/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse/che/actions/workflows/devworkspace-generator-release.yml) | [che-e2e](https://quay.io/eclipse/che-e2e) |
| | [che-plugin-registry](https://github.com/eclipse-che/che-plugin-registry) | [![Release](https://github.com/eclipse-che/che-plugin-registry/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-plugin-registry/actions/workflows/release.yml) | [che-plugin-registry](https://quay.io/eclipse/che-plugin-registry) |
| | [che-dashboard](https://github.com/eclipse-che/che-dashboard) | [![release latest stable](https://github.com/eclipse-che/che-dashboard/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-dashboard/actions/workflows/release.yml) | [che-dashboard](https://quay.io/eclipse/che-dashboard) |
| | | 
| **Phase 3** | [che-devfile-registry](https://github.com/eclipse-che/che-devfile-registry) | [![Release](https://github.com/eclipse-che/che-devfile-registry/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-devfile-registry/actions/workflows/release.yml) | [che-devfile-registry](https://quay.io/eclipse/che-devfile-registry) |
| |
| **Phase 4** | [che-operator](https://github.com/eclipse-che/che-operator) | [![Release](https://github.com/eclipse-che/che-operator/actions/workflows/release.yml/badge.svg)](https://github.com/eclipse-che/che-operator/actions/workflows/release.yml) | [che-operator](https://quay.io/eclipse/che-operator) |

Che Operator requires PR checks and manual approvals. When everything has been verified, and the PRs generated in the previous step are merged, the following workflows will be triggered.

| Phase       | Project | Workflow Status | Other Artifact |
| :---        | :---    | :---            | :---           |
| **Phase 5** | [community-operator](https://github.com/operator-framework/community-operators/) | [![Release](https://github.com/eclipse-che/che-operator/actions/workflows/release-community-operator-PRs.yml/badge.svg)](https://github.com/eclipse-che/che-operator/actions/workflows/release-community-operator-PRs.yml) | [create pull requests](https://github.com/operator-framework/community-operators/pulls?q=%22Update+eclipse-che+operator%22+is%3Aopen) to update to latest released version of Che in OperatorHub
| | [chectl](https://github.com/che-incubator/chectl) | [![Release](https://github.com/eclipse-che/che-operator/actions/workflows/release-chectl.yml/badge.svg)](https://github.com/eclipse-che/che-operator/actions/workflows/release-chectl.yml) | [CLI tarballs](https://github.com/che-incubator/chectl/releases)
| | [che-docs](https://github.com/eclipse/che-docs) | [![Release](https://github.com/eclipse-che/che-docs/actions/workflows/publication-builder.yaml/badge.svg)](https://github.com/eclipse-che/che-docs/actions/workflows/publication-builder.yaml) | tag and pull request to update to [latest Che](https://github.com/eclipse-che/che-docs/tree/publication)

## Release phases

The [Release - Orchestrate Overall Release Phases]((https://github.com/eclipse-che/che-release/actions?query=workflow%3A%22Release+-+Orchestrate+Overall+Release+Phases%22)) action runs [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/make-release.sh) to release the various Che containers and packages in the correct order. This ensures that dependencies between containers or packages can be met. See [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/make-release.sh) for these dependencies. The list of phases is above. 


## Release procedure
1. Original procedure was to [create new release issue to report status and collect any blocking issues](https://github.com/eclipse/che/issues/new?assignees=&labels=kind%2Frelease&template=release.md&title=Release+Che+7.FIXME), however the issue was usually empty since problems are resolved via Mattermost and Slack so communication is done there. 

2. To start a release, use the [Release - Orchestrate Overall Release Phases](https://github.com/eclipse-che/che-release/actions/workflows/release-orchestrate-overall.yml) workflow to trigger workflows in other Che repos. Workflows triggered align to the repos noted in the previous section. In the input, provide the version of Che, and phases to run. 

    2.1 If one of the workflows has crashed, inspect it. Apply fixes if needed, and restart it. You can restart individual workflow, or whole phase in orchestration job, whichever is simpler.

    2.2 Keep in mind, that sometimes you'll need to [regenerate tags](https://github.com/eclipse/che/issues/18879), or skip certain substeps in that job. Also ensure that correct code is in place, whether it is main or bugfix branch.

    2.3 Sometimes, the hotfix changes to the workflow can take too long to get approved and merged. In certain situations, we can use the modified workflow file, which is pushed in its own branch, and then trigger the workflow, while specifying the branch with our modified workflow. 

3. When Che Operator PRs have been generated, you must wait for the approval of PR checks, that are in that repository. If there are any questions, you can forward them to the check maintaners (Deploy team). When PRs are merged, the last batch of projects will be triggered to release

    3.1 Chectl PR has to be closed manually, after they're generated, and all its associated PR checks are passed.

    3.2 Community operator PRs are merged by Operator Framework members, as soon as their tests will pass (in some cases they may require some input from us)

    3.3 Docs PR has to be merged by Docs team.

4. When the release is complete, an e-mail should be sent to the `che-dev` mailing list. 

5. TODO: a Slack notification should be sent to the ECD Slack. See https://github.com/eclipse/che/issues/22551

--------------


# Che release known issues

* Enable slack notifications #[22551](https://github.com/eclipse/che/issues/22551)
* Autorelease the Che Release Notes after chectl release #[22550](https://github.com/eclipse/che/issues/22550)
