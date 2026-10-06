# Contributing

This repository contains the WProofreader Server Helm chart.
Image changes belong in the [wproofreader-docker](https://github.com/WebSpellChecker/wproofreader-docker) repository.

## Report an issue

Search the [open issues](https://github.com/WebSpellChecker/wproofreader-helm/issues)
before you open a new one.
Include the chart version, Kubernetes version, relevant values with secrets removed,
the command that failed, and the complete error message.

Use the [security policy](SECURITY.md) for a suspected vulnerability.
Do not put credentials, license data, or customer data in an issue.

## Prepare a change

You need Helm 3, kubeconform, and pre-commit.
Run all commands from the repository root.

1. Create a branch from `main`.
2. Make one focused change.
   Use two-space YAML indentation and kebab-case filenames.
3. Add a comment for each public value in `wproofreader/values.yaml`.
   Update `values.yaml`, the relevant templates, and `README.md` together.
4. Add or update a scenario in `ci/` when the change affects configuration.
   Each `*-values.yaml` file there is one scenario.
   `make check` and chart-testing validate every scenario.
   The scenarios are outside the chart, so a scenario change does not need a chart version bump.
5. Run the checks:

   ```bash
   make check
   pre-commit run --all-files
   ```

6. Test invalid combinations that the chart must reject.
   Test both the enabled and disabled forms of the feature you changed.
7. Use a Conventional Commit subject.
   See [Commit messages](#commit-messages).

## Stack test

`scripts/stack-test.sh` installs the chart on a temporary k3d cluster with MySQL and checks it.
It installs MySQL (mysql-server-helm) and then WProofreader Server with the db-manager provisioning Job.
It checks the db-manager Job, the `cmd=ver`, `cmd=status`, and `cmd=license_status` answers, and the database users.
It then upgrades each release with the same values.
The release names, Secret names, and keys are the same as in the Kubernetes installation guide.
CI runs the same test before a new WProofreader Server version goes into the chart.

You need Docker and a valid license ticket: WProofreader Server does not get ready without a license.
While mysql-server-helm is private, set `GITHUB_TOKEN` to a token that can read it,
or give a local copy of the chart with `--mysql path:<dir>`.

```bash
export STACK_TOOLS_DIR="$PWD/.tools/bin"
scripts/ci/install-tools.sh   # k3d, kubectl, helm, and crane with checksum checks
export WPR_LICENSE_TICKET_ID='<license_ticket_id>'
scripts/stack-test.sh --wproofreader-version 6.18.1.0
```

`--wproofreader-version` sets the WProofreader Server and db-manager image tag.
Without it, the test uses the chart `appVersion`.
On a slow connection, add `--preload-images`: the local Docker pulls the images once and keeps them.
The script deletes the cluster at the end, also when a check fails.
When a check fails, the script writes the Pod logs, events, and release status to the `diag` directory.

To show each stage as a separate CI step, give the stage names.
The stages share their state through a private file in `STACK_STATE_DIR`.
Run `preflight` first, `diagnostics` after a failed step, and `teardown` always:

```bash
scripts/stack-test.sh --wproofreader-version 6.18.1.0 preflight
scripts/stack-test.sh cluster
scripts/stack-test.sh secrets
scripts/stack-test.sh mysql
scripts/stack-test.sh wproofreader
scripts/stack-test.sh upgrade
scripts/stack-test.sh diagnostics   # after a failed step
scripts/stack-test.sh teardown      # always
```

Run `scripts/stack-test.sh --help` for all options and stages.

### Promote a WProofreader Server version

`scripts/update-app-version.sh VERSION` changes `appVersion` in `wproofreader/Chart.yaml`,
the image tag in `examples/values-dev.yaml`, and the version in the example `manifests/`.
Without `--open-pr`, it shows the change and the commit message and changes nothing.
With `--open-pr`, it commits on the branch `update/wproofreader-VERSION`, pushes it,
and opens a pull request to `main`.
It needs `GITHUB_TOKEN` with write access to the repository contents and pull requests.
The commit type follows the changed version part:
`feat!` for the first number, `feat` for the second, and `fix` for the third or fourth.

CI runs the stack test with `--wproofreader-version VERSION` first
and opens the pull request only when all checks pass.
The pull request needs an approval like any other change.

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
for every commit and for every pull request title.
The release tooling reads the commit messages on `main` to select the next version
and to write the changelog.

Pull requests are merged with a merge commit, so every commit of your branch goes to `main`.
Each `feat` and `fix` commit becomes one line in the changelog.
Before you ask for a review, clean the branch:

- Squash fixups and work-in-progress commits with `git rebase -i origin/main`.
- Give each remaining commit a Conventional Commits subject.
- Update the branch with `git rebase origin/main`, not with a merge from `main`.

The `commit-messages` check rejects a pull request with a commit that does not follow the format.
Run the same check before you push:

```bash
./scripts/check-commit-messages.sh origin/main HEAD
```

| Type | Use it for | Version change |
| --- | --- | --- |
| `feat` | A new option or behavior, or a new `appVersion` | Minor, for example 1.0.0 to 1.1.0 |
| `fix` | A bug fix | Patch, for example 1.0.0 to 1.0.1 |
| `perf`, `refactor`, `revert` | A change that users can see in the changelog | Patch |
| `docs`, `chore`, `ci`, `test`, `build`, `style` | A change that does not affect the packaged chart | None |

For a breaking change, add `!` after the type,
for example `feat!: remove the legacy routing values`,
and add a `BREAKING CHANGE:` footer that tells operators what they must change.
A breaking change selects the next major version.

Do not change the chart `version` in `wproofreader/Chart.yaml` or `wproofreader/CHANGELOG.md`
in your pull request.
The release pull request changes them.
To deploy a new WProofreader Server image, change `appVersion` in a `feat:` pull request.
A `webspellchecker/db-manager` image with the same tag must exist,
because the provisioning Job uses it.

## Release a new chart version

Releases use a release pull request.
No workflow pushes commits to `main`, so every change to `main` has an approved pull request.
The release workflow uses [git-cliff](https://git-cliff.org/) with `cliff.toml`.
It reads the commits that change `wproofreader/` since the last `v<version>` tag.
It skips merge commits, so each commit of a branch is counted one time.

1. Merge your pull requests into `main` as usual.
2. The release workflow opens or updates one pull request with the title
   `chore(release): <version>`, from the `release/next` branch.
   It changes the chart `version` in `wproofreader/Chart.yaml` and adds the release notes
   to `wproofreader/CHANGELOG.md`.
   Changes of the types `docs`, `chore`, `ci`, `test`, `build`, and `style` do not open a release
   pull request.
3. Review the release pull request.
   Make sure that the version and the release notes are correct.
   Do not edit the release pull request: the workflow writes it again after each merge to `main`.
   To change the notes, change the commits in a new pull request.
4. Approve and merge the release pull request when you want to publish the release.
5. The release workflow then does these steps:
   - It runs `make check`.
   - It creates the `v<version>` tag and the GitHub Release.
     The release notes are the section of the version in `wproofreader/CHANGELOG.md`.
   - It packages the chart and attaches `wproofreader-<version>.tgz` to the release.
   - It adds the package to `index.yaml` on the `gh-pages` branch.
6. Make sure that the workflow run is successful,
   and that the GitHub Release has the `.tgz` file.
   If a step fails, fix the cause and select **Re-run failed jobs** on the run.
   The publish steps skip work that is already done.

To release several changes together, wait with step 4.
The release pull request collects all changes until you merge it.

To select the version yourself, for example 1.2.3 instead of 1.1.0,
run the **Release chart** workflow manually from the **Actions** tab
with the version in the **version** field.
The version must be higher than the last release.
The workflow sets this version in the release pull request.
The next merge to `main` selects the version from the commits again,
so run the workflow again if necessary.

Do not move or delete a published release tag.
To correct a release, publish a new version.

GitHub Pages serves `index.yaml` from the `gh-pages` branch.
After the first publication, you can register the repository URL
with [Artifact Hub](https://artifacthub.io/docs/topics/repositories/helm-charts/).
If you claim ownership or request verified-publisher status,
put `artifacthub-repo.yml` next to `index.yaml` on `gh-pages`,
using the repository ID that Artifact Hub provides.

## Pull requests

Explain the operator impact and link the issue.
Include the validation commands you ran.
For a manifest change, include the relevant rendered output.
Keep examples and user documentation in the same pull request as
the behavior they describe.
