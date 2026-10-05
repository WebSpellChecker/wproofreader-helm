## Summary

Describe the change and why it is needed.

## Operator impact

Describe changes to installation, upgrades, configuration, security, or runtime behavior.
Write `None` when the change has no operator impact.

## Validation

- [ ] `make check`
- [ ] `pre-commit run --all-files`
- [ ] I tested each affected feature with its enabled and disabled settings.
- [ ] I added or updated a `ci/*-values.yaml` scenario when the change affects configuration.
- [ ] Each commit is a Conventional Commit (`./scripts/check-commit-messages.sh origin/main HEAD`),
  and the branch has no fixup or work-in-progress commits.
- [ ] I did not change the chart version or the changelog; the release pull request does it.

List any additional commands and relevant rendered-manifest excerpts:

```text

```

## Related issue

Link the issue, or write `None`.
