SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help
.RECIPEPREFIX := >

GO ?= go
BIN_DIR ?= bin
SYNCAPPS_BIN := $(BIN_DIR)/syncapps
SYNCAPPS_CONFIG ?= syncapps.yaml
APPCATALOG_BIN := $(BIN_DIR)/appcatalog

TOOLS_GO_SRCS := $(shell find tools -type f -name '*.go' -print 2>/dev/null) tools/go.mod tools/go.sum

.PHONY: help
help:
>@bash -ceu 'printf "%s\n" \
  "Targets:" \
  "  make build-syncapps         Build $(SYNCAPPS_BIN)" \
  "  make build-syncapps-autogen Build $(BIN_DIR)/syncapps-autogen" \
  "  make build-appcatalog       Build $(APPCATALOG_BIN)" \
  "  make apps-catalog           Generate docs/apps-catalog*.{md,json}" \
  "  make deploy-app             Deploy one app to remote (APP=..., uses .it-runner/.env.local if present)" \
  "  make deploy-app-dry         Show what would be deployed (APP=...)" \
  "  make deploy-single-app      Deploy DEPLOY_SINGLE_APP to remote" \
  "  make deploy-single-app-dry  Dry-run for DEPLOY_SINGLE_APP" \
  "  make tidy-tools             Run go mod tidy (tools)" \
  "  make syncapps-autogen       Scan legacy -> update config" \
  "  make syncapps-autogen-dry   Dry-run autogen" \
  "  make syncapps-list          List apps in config" \
  "  make syncapps-dry-all       Dry-run sync all configured apps" \
  "  make syncapps-all           Sync all configured apps" \
  "  make syncapps-app           Sync one app (set APP=..., optional SLOT=..., DIRECTION=..., DRY=1, DELETE=1)" \
  "" \
  "Variables:" \
  "  APP=<name>                  App name (required for syncapps-app)" \
  "  SLOT=services|luci|meta     Optional, repeat not supported in Make target" \
  "  DIRECTION=both|push|pull    Default: both" \
  "  DRY=1                       Enable --dry-run" \
  "  DELETE=1                    Enable --delete (dangerous)" \
  "  SYNCAPPS_CONFIG=<path>      Default: syncapps.yaml" \
  "" \
  "Remote deploy env (optional):" \
  "  DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT, DEPLOY_SINGLE_APP"'

$(BIN_DIR):
>@mkdir -p "$(BIN_DIR)"

.PHONY: build-syncapps
build-syncapps: $(SYNCAPPS_BIN)

.PHONY: build-syncapps-autogen
build-syncapps-autogen: $(BIN_DIR)/syncapps-autogen

$(SYNCAPPS_BIN): $(BIN_DIR) $(TOOLS_GO_SRCS)
>@$(GO) -C tools build -o "../$(SYNCAPPS_BIN)" ./cmd/syncapps

$(BIN_DIR)/syncapps-autogen: $(BIN_DIR) $(TOOLS_GO_SRCS)
>@$(GO) -C tools build -o "../$(BIN_DIR)/syncapps-autogen" ./cmd/syncapps-autogen

.PHONY: build-appcatalog
build-appcatalog: $(APPCATALOG_BIN)

$(APPCATALOG_BIN): $(BIN_DIR) $(TOOLS_GO_SRCS)
>@$(GO) -C tools build -o "../$(APPCATALOG_BIN)" ./cmd/appcatalog

.PHONY: apps-catalog
apps-catalog: build-appcatalog
>@"./$(APPCATALOG_BIN)" --apps-root apps --out-json docs/apps-catalog.json --out-md docs/apps-catalog.min.md --out-md-full docs/apps-catalog.md

.PHONY: tidy-tools
tidy-tools:
>@$(GO) -C tools mod tidy

.PHONY: deploy-app
deploy-app:
>@bash -ceu 'app="$${APP:-$${DEPLOY_SINGLE_APP:-}}"; \
	[[ -n "$$app" ]] || { echo "error: APP is required (e.g. make $@ APP=kai)"; exit 2; }; \
	./tools/deploy-to-remote.sh --app "$$app"'

.PHONY: deploy-app-dry
deploy-app-dry:
>@bash -ceu 'app="$${APP:-$${DEPLOY_SINGLE_APP:-}}"; \
	[[ -n "$$app" ]] || { echo "error: APP is required (e.g. make $@ APP=kai)"; exit 2; }; \
	./tools/deploy-to-remote.sh --app "$$app" --dry-run'

.PHONY: deploy-single-app
deploy-single-app:
>@./tools/deploy-to-remote.sh

.PHONY: deploy-single-app-dry
deploy-single-app-dry:
>@./tools/deploy-to-remote.sh --dry-run

.PHONY: syncapps-autogen
syncapps-autogen: build-syncapps-autogen
>@"./$(BIN_DIR)/syncapps-autogen" --config "$(SYNCAPPS_CONFIG)"

.PHONY: syncapps-autogen-dry
syncapps-autogen-dry: build-syncapps-autogen
>@"./$(BIN_DIR)/syncapps-autogen" --config "$(SYNCAPPS_CONFIG)" --dry-run

.PHONY: syncapps-list
syncapps-list: build-syncapps
>@"./$(SYNCAPPS_BIN)" --config "$(SYNCAPPS_CONFIG)" --list

.PHONY: syncapps-dry-all
syncapps-dry-all: build-syncapps
>@"./$(SYNCAPPS_BIN)" --config "$(SYNCAPPS_CONFIG)" --dry-run --all

.PHONY: syncapps-all
syncapps-all: build-syncapps
>@"./$(SYNCAPPS_BIN)" --config "$(SYNCAPPS_CONFIG)" --all

.PHONY: syncapps-app
syncapps-app: build-syncapps
>@[[ -n "$(APP)" ]] || { echo "error: APP is required (e.g. make $@ APP=istorepanel)"; exit 2; }
>@bash -ceu 'args=(--config "$(SYNCAPPS_CONFIG)" --app "$(APP)"); \
	if [[ -n "$(SLOT)" ]]; then args+=(--slot "$(SLOT)"); fi; \
	if [[ -n "$(DIRECTION)" ]]; then args+=(--direction "$(DIRECTION)"); fi; \
	if [[ "$(DRY)" == "1" ]]; then args+=(--dry-run); fi; \
	if [[ "$(DELETE)" == "1" ]]; then args+=(--delete); fi; \
	"./$(SYNCAPPS_BIN)" "$${args[@]}"'
