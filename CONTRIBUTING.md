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

1. Create a branch from `development`.
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
7. Open the pull request to `development`, with a Conventional Commits title.
   See [Commit messages](#commit-messages).

## Commit messages

Use [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/)
for the title of every pull request.
Pull requests into `development` are merged with **Squash and merge**:
the title becomes the commit subject, and the description becomes the commit body.
The release workflow reads these commits to select the next version
and to write the changelog.

The `pull-request` check rejects a title that does not follow the format.

| Type | Use it for | Version change |
| --- | --- | --- |
| `feat` | A new option or behavior | Minor, for example 1.0.0 to 1.1.0 |
| `fix` | A bug fix | Patch, for example 1.0.0 to 1.0.1 |
| `perf`, `refactor`, `revert` | A change that users can see in the changelog | Patch |
| `docs`, `chore`, `ci`, `test`, `build`, `style` | A change that does not affect the packaged chart | None |

For a breaking change, add `!` after the type,
for example `feat!: remove the legacy routing values`,
and end the description with a `BREAKING CHANGE:` line that tells operators what they must change.
A breaking change selects the next major version.

To deploy a new WProofreader Server image, change `appVersion`.
The type follows the part of the WProofreader Server version A.B.C.D that changes:
A gives `feat!`, B gives `feat`, and C or D gives `fix`.
A `webspellchecker/db-manager` image with the same tag must exist,
because the provisioning Job uses it.

Do not change the chart `version` in `wproofreader/Chart.yaml` or `wproofreader/CHANGELOG.md`
in your pull request: the check rejects it.
The release pull request changes them.

## Release a new chart version

`main` holds only released versions.
The release is the pull request from `development` to `main`.
The release workflow uses [git-cliff](https://git-cliff.org/) with `cliff.toml`.
It reads the commits that change `wproofreader/` since the last `v<version>` tag.

1. Merge the pull requests of the release into `development`.
2. Open a pull request from `development` to `main`.
   The release workflow commits `chore(release): <version>` to `development`.
   This commit sets the chart version in `wproofreader/Chart.yaml`
   and adds the release notes to `wproofreader/CHANGELOG.md`.
   The workflow changes the title and the description of the pull request,
   and sets the `release-ready` status.
   When only changes of the types `docs`, `chore`, `ci`, `test`, `build`, and `style` are waiting,
   the merge publishes no release.
3. Review the pull request.
   Make sure that the version and the release notes are correct.
   To change the notes or to add a fix, merge a pull request into `development`:
   the workflow prepares the release again.
   Do not merge other pull requests into `development` until the release is published.
4. Merge the pull request with **Create a merge commit**.
5. The release workflow then does these steps:
   - It runs `make check`.
   - It creates the `v<version>` tag and the GitHub Release.
     The release notes are the section of the version in `wproofreader/CHANGELOG.md`.
   - It packages the chart and attaches `wproofreader-<version>.tgz` to the release.
   - It adds the package to `index.yaml` on the `gh-pages` branch.
   - It brings `development` up to `main`.
   - It checks that users can download the package and that `helm search repo` finds the version.
6. Make sure that the workflow run is successful,
   and that the GitHub Release has the `.tgz` file.
   If a step fails, fix the cause and select **Re-run failed jobs** on the run.
   The publish steps skip work that is already done.

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
