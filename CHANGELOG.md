# Changelog

This file records changes to the WProofreader Helm chart.
The chart follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
`version` tracks the chart, while `appVersion` tracks the WProofreader Server image.

## [1.4.0] (2026-09-28)

### Added

- **database:** Optional database connection and db-manager provisioning
  with a `pre-install,pre-upgrade` hook Job.
- **database:** TLS for provisioning, and the Admin-panel database user.
- **license:** Use a pre-existing Secret for the license ticket (`licenseExistingSecret`).

### Changed

- WProofreader Server 6.18.1.0 (`appVersion`).
  The db-manager image uses the same version.

## [1.3.1] (2026-04-01)

### Fixed

- **templates:** Fix double slashes in paths when `virtualDir` is set to root.

### Documentation

- **values:** Replace the removed `WPR_DOMAIN_NAME` with a valid `extraEnv` example.

## [1.3.0] (2025-07-21)

### Changed

- Use the WProofreader namespace for all service variables.

## Earlier releases

See the [GitHub Releases](https://github.com/WebSpellChecker/wproofreader-helm/releases).
