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
Most of the projects that are part of the weekly release cycle are also united in this project's workflow - the [Release - Orchestrate Overall Release Phases](https://github.com/eclipse-che/che-release/actions?query=workflow%3A%22Release+-+Orchestrate+Overall+Release+Phases%22), which runs the [make-release.sh](https://github.com/eclipse-che/che-release/blob/main/make-release.sh) release script.

With the exception of some projects, it allows to perform the bulk of the release process with 1 click, running following projects in the correct order, making them complete a full release process - pushing commits or pull request to respective repositories, deploying artifacts etc. 

The projects that are covered by this workflow release container images:

- [che-e2e](https://github.com/eclipse/che) - https://quay.io/eclipse/che-e2e
- [che-code](https://github.com/che-incubator/che-code) - https://quay.io/che-incubator/che-code
- [che-machine-exec](https://github.com/eclipse-che/che-machine-exec) - https://quay.io/eclipse/che-machine-exec
- [che-devfile-registry](https://github.com/eclipse-che/che-devfile-registry) - https://quay.io/eclipse/che-devfile-registry
- [che-plugin-registry](https://github.com/eclipse-che/che-plugin-registry) - https://quay.io/eclipse/che-plugin-registry
- [che-dashboard](https://github.com/eclipse-che/che-dashboard) - https://quay.io/eclipse/che-dashboard
- [che-operator](https://github.com/eclipse-che/che-operator) - https://quay.io/eclipse/che-operator. 
- [che server](https://github.com/eclipse-che/che-server) - 
  - https://quay.io/eclipse/che-endpoint-watcher,
  - https://quay.io/eclipse/che-keycloak,
  - https://quay.io/eclipse/che-postgres,
  - https://quay.io/eclipse/che-server

Additionally, these slower-moving projects perform branch creation every sprint:
- [configbump](https://github.com/che-incubator/configbump)
- [kubernetes-image-puller](https://github.com/che-incubator/kubernetes-image-puller)
- [che-backup-server-rest](https://github.com/che-dockerfiles/che-backup-server-rest)

Che Operator requires manual verifications by Deploy team (and also various tests run against running Che, so we have a chance to see if it functions). When everything has been verified, after the merging of operator PRs the following projects workflows will be triggered automatically.
- [chectl](https://github.com/che-incubator/chectl) - release artifact is a set of binaries, published to [Releases page]https://github.com/che-incubator/chectl/releases 
- [che-docs](https://github.com/eclipse/che-docs) - only create tag and pull request to update to latest released version of Che
- [community-operator](https://github.com/operator-framework/community-operators/) - [create pull requests](https://github.com/operator-framework/community-operators/pulls?q=%22Update+eclipse-che+operator%22+is%3Aopen) to update to latest released version of Che in OperatorHub

## Release phases

At the moment, [Release - Orchestrate Overall Release Phases]((https://github.com/eclipse-che/che-release/actions?query=workflow%3A%22Release+-+Orchestrate+Overall+Release+Phases%22)) job has the way of ordering the release by utilizing the concept of phases.
Currently there are several phases, representing an order of projects, which we can execute in parallel, as long as their dependent projects have been released. Projects in lower phases are those, on which projects from higher phase will depend.

* Phase 1:
  * [che-code](https://github.com/che-incubator/che-code), 
  * [che-machine-exec](https://github.com/eclipse-che/che-machine-exec), 
  * [che-dashboard](https://github.com/eclipse-che/che-dashboard), 
  * [che-server](https://github.com/eclipse-che/che-server);
* then creation of branches for:
  * [configbump](https://github.com/che-incubator/configbump),
  * [kubernetes-image-puller](https://github.com/che-incubator/kubernetes-image-puller)

* Phase 2:
  * [che-e2e](https://github.com/eclipse/che), 
  * [che-plugin-registry](https://github.com/eclipse-che/che-plugin-registry)

* Phase 3:
  * [che-devfile-registry](https://github.com/eclipse-che/che-devfile-registry)

* Phase 4:
  * [che-operator](https://github.com/eclipse-che/che-operator) - depends on phases 1 to 4 and performs several e2e validation tests

The phases list is a comma-separated list (default, which includes all phases "1,2,3,4"). Removing certain phases is useful, when you rerun the orchestration job, and certain projects shouldn't be released again. 
Note that this approach will change, once a new system will be implemented, where we can more clearly specify dependencies between workflows, using special types of GitHub action.


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

4. When the release is complete, an e-mail should be sent to the `che-dev` mailing list. Additionally, a [Mattermost notification](https://github.com/eclipse-che/che-release/actions/workflows/release-send-mattermost-announcement.yml) can be sent to https://mattermost.eclipse.org/eclipse/channels/eclipse-che-releases

--------------


# Che release gotchas

* https://github.com/eclipse/che/issues/17178 - Changelog generation contains too much information
