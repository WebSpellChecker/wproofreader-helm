SHELL := /usr/bin/env bash

CHART_DIR := wproofreader
PACKAGE_DIR ?= dist

.PHONY: check package secrets validate

check: validate

validate:
	./scripts/validate-chart.sh

secrets:
	pre-commit run --all-files

package: check
	mkdir -p $(PACKAGE_DIR)
	helm package $(CHART_DIR) --destination $(PACKAGE_DIR)
