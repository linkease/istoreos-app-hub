#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'USAGE'
Usage:
  scripts/sync-from-legacy.sh --app <name>
  scripts/sync-from-legacy.sh --all

Options:
  --app <name>         Sync one app into apps/<name>
  --all                Sync all apps under apps/
  --dry-run            Show what would change, do not write
  --no-delete          Do not pass --delete to rsync
  --apps-dir <path>    Override apps root (default: <repo>/apps)
  --services-dir <p>   Override legacy services dir (default: ../istore/luci)
  --luci-dir <path>    Override legacy luci dir (default: ../nas-packages-luci/luci)
  --meta-dir <path>    Override legacy meta dir (default: ../openwrt-app-meta/applications)
  -h, --help           Show this help

Notes:
  - Target layout must be: apps/<app>/{services,luci,meta}
  - This script uses package directories already present in hub as mapping source.
USAGE
}

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
DEFAULT_APPS_DIR="${REPO_ROOT}/apps"
DEFAULT_SERVICES_DIR="${REPO_ROOT}/../istore/luci"
DEFAULT_LUCI_DIR="${REPO_ROOT}/../nas-packages-luci/luci"
DEFAULT_META_DIR="${REPO_ROOT}/../openwrt-app-meta/applications"

APPS_DIR="${DEFAULT_APPS_DIR}"
SERVICES_DIR="${DEFAULT_SERVICES_DIR}"
LUCI_DIR="${DEFAULT_LUCI_DIR}"
META_DIR="${DEFAULT_META_DIR}"

MODE=""
APP_NAME=""
DRY_RUN=0
USE_DELETE=1

while [[ $# -gt 0 ]]; do
  case "$1" in
    --app)
      [[ $# -ge 2 ]] || { echo "error: --app requires a value" >&2; exit 1; }
      MODE="app"
      APP_NAME="$2"
      shift 2
      ;;
    --all)
      MODE="all"
      shift
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --no-delete)
      USE_DELETE=0
      shift
      ;;
    --apps-dir)
      [[ $# -ge 2 ]] || { echo "error: --apps-dir requires a value" >&2; exit 1; }
      APPS_DIR="$2"
      shift 2
      ;;
    --services-dir)
      [[ $# -ge 2 ]] || { echo "error: --services-dir requires a value" >&2; exit 1; }
      SERVICES_DIR="$2"
      shift 2
      ;;
    --luci-dir)
      [[ $# -ge 2 ]] || { echo "error: --luci-dir requires a value" >&2; exit 1; }
      LUCI_DIR="$2"
      shift 2
      ;;
    --meta-dir)
      [[ $# -ge 2 ]] || { echo "error: --meta-dir requires a value" >&2; exit 1; }
      META_DIR="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

if [[ -z "${MODE}" ]]; then
  echo "error: must pass exactly one of --app or --all" >&2
  usage >&2
  exit 1
fi

if [[ "${MODE}" == "app" && -z "${APP_NAME}" ]]; then
  echo "error: --app requires a non-empty name" >&2
  exit 1
fi

if [[ "${MODE}" == "all" && -n "${APP_NAME}" ]]; then
  echo "error: --app and --all cannot be used together" >&2
  exit 1
fi

for d in "${APPS_DIR}" "${SERVICES_DIR}" "${LUCI_DIR}" "${META_DIR}"; do
  if [[ ! -d "${d}" ]]; then
    echo "error: directory not found: ${d}" >&2
    exit 1
  fi
done

RSYNC_ARGS=("-av")
if [[ ${USE_DELETE} -eq 1 ]]; then
  RSYNC_ARGS+=("--delete")
fi
if [[ ${DRY_RUN} -eq 1 ]]; then
  RSYNC_ARGS+=("--dry-run")
fi

RSYNC_ARGS+=(
  "--exclude=.git"
  "--exclude=.DS_Store"
  "--exclude=.idea"
  "--exclude=.vscode"
  "--exclude=node_modules"
)

SYNC_COUNT=0
WARN_COUNT=0

sync_component_from_legacy() {
  local app_dir="$1"
  local component="$2"
  local legacy_root="$3"

  local hub_component_dir="${app_dir}/${component}"
  if [[ ! -d "${hub_component_dir}" ]]; then
    return 0
  fi

  shopt -s nullglob
  local entries=("${hub_component_dir}"/*)
  shopt -u nullglob

  if [[ ${#entries[@]} -eq 0 ]]; then
    return 0
  fi

  for hub_pkg in "${entries[@]}"; do
    [[ -d "${hub_pkg}" ]] || continue

    local pkg_name legacy_pkg
    pkg_name="$(basename "${hub_pkg}")"
    legacy_pkg="${legacy_root}/${pkg_name}"

    if [[ ! -d "${legacy_pkg}" ]]; then
      echo "warn: missing legacy ${component} package: ${legacy_pkg}" >&2
      WARN_COUNT=$((WARN_COUNT + 1))
      continue
    fi

    mkdir -p "${hub_pkg}"
    echo "sync ${component}: ${legacy_pkg} -> ${hub_pkg}"
    rsync "${RSYNC_ARGS[@]}" "${legacy_pkg}/" "${hub_pkg}/"
    SYNC_COUNT=$((SYNC_COUNT + 1))
  done
}

collect_apps() {
  local out=()
  if [[ "${MODE}" == "app" ]]; then
    local app_path="${APPS_DIR}/${APP_NAME}"
    if [[ ! -d "${app_path}" ]]; then
      echo "error: app not found: ${APP_NAME} (${app_path})" >&2
      exit 1
    fi
    out+=("${app_path}")
  else
    shopt -s nullglob
    local dirs=("${APPS_DIR}"/*)
    shopt -u nullglob
    for d in "${dirs[@]}"; do
      [[ -d "${d}" ]] || continue
      out+=("${d}")
    done
  fi

  if [[ ${#out[@]} -gt 0 ]]; then
    printf '%s\n' "${out[@]}"
  fi
}

echo "== sync-from-legacy =="
echo "apps-dir     : ${APPS_DIR}"
echo "services-dir : ${SERVICES_DIR}"
echo "luci-dir     : ${LUCI_DIR}"
echo "meta-dir     : ${META_DIR}"
echo "mode         : ${MODE}${APP_NAME:+ (${APP_NAME})}"
echo "dry-run      : ${DRY_RUN}"
echo "delete       : ${USE_DELETE}"

mapfile -t app_dirs < <(collect_apps)
if [[ ${#app_dirs[@]} -eq 0 ]]; then
  echo "error: no apps found under ${APPS_DIR}" >&2
  exit 1
fi

for app_dir in "${app_dirs[@]}"; do
  app_name="$(basename "${app_dir}")"
  echo ""
  echo "-- app: ${app_name} --"

  sync_component_from_legacy "${app_dir}" "services" "${SERVICES_DIR}"
  sync_component_from_legacy "${app_dir}" "luci" "${LUCI_DIR}"
  sync_component_from_legacy "${app_dir}" "meta" "${META_DIR}"
done

if [[ ${SYNC_COUNT} -eq 0 ]]; then
  echo "error: no package directories were synced" >&2
  echo "hint: add package directories under apps/<app>/{services,luci,meta} first" >&2
  exit 1
fi

echo ""
echo "Done. synced=${SYNC_COUNT}, warnings=${WARN_COUNT}"
