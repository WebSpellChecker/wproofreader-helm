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
7. Use a Conventional Commit subject such as `feat:`, `fix:`, `docs:`, or `refactor:`.

## Version and release metadata

Bump `wproofreader/Chart.yaml` for a change to the packaged chart.
Use Semantic Versioning.
Update `CHANGELOG.md` and the `artifacthub.io/changes` annotation in the same pull request.
A documentation-only change outside `wproofreader/` does not need a chart version bump.

To update `CHANGELOG.md` from the Conventional Commits, run:

```bash
git-cliff --unreleased --tag v<version> --prepend CHANGELOG.md
```

When `appVersion` changes, a `webspellchecker/db-manager` image with the same tag must exist.
The provisioning Job uses it.

The release workflow publishes each new chart version after it reaches `main`.
It creates a `v<version>` GitHub Release and updates the Helm repository index on
the `gh-pages` branch.
The repository administrator must create that branch and configure GitHub Pages
before the first release.

After the first publication, register the repository URL
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
