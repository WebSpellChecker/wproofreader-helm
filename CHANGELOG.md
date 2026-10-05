# Changelog

This file records changes to the WProofreader Helm chart.
The chart follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html):
`version` tracks the chart, while `appVersion` tracks the WProofreader Server image.

## [1.4.0] (2026-09-28)

### Added

- **database:** Optional database connection and db-manager provisioning
  with a `pre-install,pre-upgrade` hook Job.
- **database:** TLS for the db-manager connection to MySQL (`databaseProvisioning.tls`).
  Needs db-manager 6.18.0.0 or later.
- **database:** The Admin-panel database user `app_service`
  (`databaseProvisioning.adminPanelUsername`, `adminPanelPassword`,
  Secret key `admin-panel-password`).
- **license:** Use a pre-existing Secret for the license ticket (`licenseExistingSecret`).

### Changed

- WProofreader Server 6.18.1.0 (`appVersion`, was 6.11.0.0).
  The db-manager image uses the same version.

## [1.3.1] (2026-04-01)

### Changed

- WProofreader Server 6.11.0.0 (`appVersion`, was 6.2.0.0).

### Fixed

- **templates:** Fix double slashes in paths when `virtualDir` is set to root.

### Documentation

- **values:** Replace the removed `WPR_DOMAIN_NAME` with a valid `extraEnv` example.

## [1.3.0] (2025-07-21)

### Changed

- The chart sets the service environment variables with the `WPR_` prefix,
  for example `WPR_PROTOCOL`, `WPR_WEB_PORT`, `WPR_VIRTUAL_DIR`, and `WPR_LICENSE_TICKET_ID`.
  Use WProofreader Server 6.2.0.0 or later.
- WProofreader Server 6.2.0.0 (`appVersion`, was 5.39.1.0).

## Earlier releases

See the [GitHub Releases](https://github.com/WebSpellChecker/wproofreader-helm/releases).
