# Changelog

## [1.4.0](https://github.com/WebSpellChecker/wproofreader-helm/compare/v1.3.1...v1.4.0) (2026-09-28)


### Features

* **database:** optional database connection and db-manager provisioning with a `pre-install,pre-upgrade` hook Job ([eba5010](https://github.com/WebSpellChecker/wproofreader-helm/commit/eba50109360a28a644fd93e53c560019d1f1c8f5))
* **database:** TLS for the db-manager connection to MySQL (`databaseProvisioning.tls`, needs db-manager 6.18.0.0 or later), and the Admin-panel database user `app_service` ([9925066](https://github.com/WebSpellChecker/wproofreader-helm/commit/992506667ecb6030a4da0f9f47abba25f3f29d9a))
* **license:** use a pre-existing Secret for the license ticket (`licenseExistingSecret`) ([#10](https://github.com/WebSpellChecker/wproofreader-helm/issues/10)) ([311a63f](https://github.com/WebSpellChecker/wproofreader-helm/commit/311a63fdcdc7855906ab954b797d3b4be9ddcb18))
* WProofreader Server 6.18.1.0 (`appVersion`, was 6.11.0.0); the db-manager image uses the same version ([#12](https://github.com/WebSpellChecker/wproofreader-helm/issues/12)) ([4d675f7](https://github.com/WebSpellChecker/wproofreader-helm/commit/4d675f79c7fc746d13e7929f113345c2bb87f26a))

## [1.3.1](https://github.com/WebSpellChecker/wproofreader-helm/compare/v1.3.0...v1.3.1) (2026-04-01)


### Features

* WProofreader Server 6.11.0.0 (`appVersion`, was 6.2.0.0) ([2a515da](https://github.com/WebSpellChecker/wproofreader-helm/commit/2a515daaeb04254b3e483aee4048aea2a88b5403))

### Bug fixes

* **templates:** fix double slashes in paths when `virtualDir` is set to root ([dcd8af9](https://github.com/WebSpellChecker/wproofreader-helm/commit/dcd8af9d20d887030c5ae9f40336768bd590dea9))

## [1.3.0](https://github.com/WebSpellChecker/wproofreader-helm/compare/v1.2.0...v1.3.0) (2025-07-21)


### ⚠ BREAKING CHANGES

* the chart sets the service environment variables with the `WPR_` prefix, for example `WPR_PROTOCOL`, `WPR_WEB_PORT`, `WPR_VIRTUAL_DIR`, and `WPR_LICENSE_TICKET_ID`; use WProofreader Server 6.2.0.0 or later

### Features

* use the `WPR_` prefix for all service environment variables ([#6](https://github.com/WebSpellChecker/wproofreader-helm/issues/6)) ([4195c1f](https://github.com/WebSpellChecker/wproofreader-helm/commit/4195c1ffd266e92638f51976653fa01bb2ce8a6c))
* WProofreader Server 6.2.0.0 (`appVersion`, was 5.39.1.0)

## Earlier releases

See the [GitHub Releases](https://github.com/WebSpellChecker/wproofreader-helm/releases).
