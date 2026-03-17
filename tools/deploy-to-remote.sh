#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Deploy (partial) app code to a remote OpenWrt/iStoreOS box for debugging.

What it deploys (best-effort):
  - LuCI code from apps/<id>/luci-app-*/:
      luasrc/{controller,model,view} -> /usr/lib/lua/luci/{controller,model,view}
      root/                          -> /
      htdocs/                        -> /www
      po/<lang>/*.po                 -> compile on target to /usr/lib/lua/luci/i18n/*.lmo (if po2lmo available)
  - Non-LuCI package "files/" that are explicitly installed by its Makefile:
      $(INSTALL_*) ./files/<src> $(1)/<dst> -> /<dst>
  - Non-LuCI package root/ overlays -> /
  - Non-LuCI package files/ overlays (when files/ contains nested paths) -> /

Env (recommended in .it-runner/.env.local):
  DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT
Optional env:
  DEPLOY_SSH_KEY, DEPLOY_SSH_OPTS, DEPLOY_BACKUP=1|0, DEPLOY_RESTART=1|0
  DEPLOY_SERVICES="kai other_service", DEPLOY_RESTART_UHTTPD=1|0

Examples:
  APP=kai make deploy-app
  DEPLOY_BACKUP=0 APP=kai make deploy-app
  ./tools/deploy-to-remote.sh --app kai --dry-run
EOF
}

die() { echo "error: $*" >&2; exit 2; }
warn() { echo "warn: $*" >&2; }

STAGING_DIR=""
TARBALL_PATH=""

cleanup() {
  set +e
  [[ -n "${STAGING_DIR:-}" ]] && rm -rf "${STAGING_DIR}" || true
  [[ -n "${TARBALL_PATH:-}" ]] && rm -f "${TARBALL_PATH}" || true
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

load_dotenv_if_present() {
  local dotenv_path="$1"
  [[ -f "$dotenv_path" ]] || return 0
  local had_nounset="0"
  case "$-" in
    *u*) had_nounset="1"; set +u;;
  esac
  set -a
  # shellcheck disable=SC1090
  . "$dotenv_path"
  set +a
  if [[ "$had_nounset" == "1" ]]; then
    set -u
  fi
}

parse_install_map_from_makefile() {
  local makefile_path="$1"
  awk '
    {
      line = $0
      sub(/#.*/, "", line)
    }
    match(line, /\$\((INSTALL_(BIN|CONF|DATA))\)[[:space:]]+([^[:space:]]+)[[:space:]]+([^[:space:]]+)/, m) {
      src = m[3]
      dst = m[4]
      gsub(/[[:space:]]+$/, "", src)
      gsub(/[[:space:]]+$/, "", dst)
      sub(/^\.\/+/, "", src)
      sub(/^\.\/+/, "", dst)
      if (src ~ /^files\// && dst ~ /^\$\(1\)\//) {
        sub(/^\$\(1\)\//, "", dst)
        print src "\t" dst
      }
    }
  ' "$makefile_path"
}

copy_tree_into() {
  local src_dir="$1"
  local dst_dir="$2"
  [[ -d "$src_dir" ]] || return 0
  mkdir -p "$dst_dir"
  tar -C "$src_dir" -cf - . | tar -C "$dst_dir" -xf -
}

copy_file_into() {
  local src_path="$1"
  local dst_path="$2"
  mkdir -p "$(dirname "$dst_path")"
  cp -a "$src_path" "$dst_path"
}

stage_luci_po_files() {
  local luci_dir="$1"
  local staging_dir="$2"
  local po_file lang domain

  [[ -d "${luci_dir}/po" ]] || return 0

  shopt -s nullglob
  for po_file in "${luci_dir}"/po/*/*.po; do
    [[ -f "$po_file" ]] || continue
    lang="$(basename "$(dirname "$po_file")")"
    domain="$(basename "$po_file")"
    copy_file_into "$po_file" "${staging_dir}/.istore-deploy-meta/luci-po/${lang}/${domain}"
  done
  shopt -u nullglob
}

main() {
  need_cmd ssh
  need_cmd scp
  need_cmd tar

  local app_id=""
  local dry_run="0"
  local no_env="0"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --app) app_id="${2:-}"; shift 2;;
      --dry-run) dry_run="1"; shift;;
      --no-env) no_env="1"; shift;;
      -h|--help) usage; exit 0;;
      *) die "unknown arg: $1 (use --help)";;
    esac
  done

  local project_root
  project_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"

  if [[ "$no_env" != "1" ]]; then
    load_dotenv_if_present "${project_root}/.it-runner/.env.local"
  fi

  if [[ -z "${app_id:-}" ]]; then
    die "--app is required"
  fi
  [[ -n "$app_id" ]] || die "--app is required"

  local deploy_host="${DEPLOY_HOST:-}"
  local deploy_user="${DEPLOY_USER:-root}"
  local deploy_port="${DEPLOY_PORT:-22}"
  local deploy_backup="${DEPLOY_BACKUP:-1}"
  local deploy_restart="${DEPLOY_RESTART:-0}"
  local deploy_services="${DEPLOY_SERVICES:-}"
  local deploy_restart_uhttpd="${DEPLOY_RESTART_UHTTPD:-0}"
  local deploy_check_luci_compat="${DEPLOY_CHECK_LUCI_COMPAT:-1}"
  local deploy_check_ubus="${DEPLOY_CHECK_UBUS:-1}"
  local deploy_ssh_key="${DEPLOY_SSH_KEY:-}"
  local deploy_ssh_opts="${DEPLOY_SSH_OPTS:-}"

  [[ -n "$deploy_host" ]] || die "DEPLOY_HOST is required (set in .it-runner/.env.local)"

  local ssh_args=(-p "$deploy_port")
  local scp_args=(-P "$deploy_port")

  if [[ -n "$deploy_ssh_key" ]]; then
    ssh_args+=(-i "$deploy_ssh_key")
    scp_args+=(-i "$deploy_ssh_key")
  fi

  if [[ -n "$deploy_ssh_opts" ]]; then
    # Split on spaces intentionally; if you need quoting, prefer DEPLOY_SSH_KEY and defaults.
    # shellcheck disable=SC2206
    ssh_args+=($deploy_ssh_opts)
    # shellcheck disable=SC2206
    scp_args+=($deploy_ssh_opts)
  fi

  local app_dir="${project_root}/apps/${app_id}"
  [[ -d "$app_dir" ]] || die "app not found: $app_dir"

  STAGING_DIR="$(mktemp -d)"
  TARBALL_PATH="$(mktemp -t "deploy-${app_id}.XXXXXX.tgz")"
  trap cleanup EXIT

  local any="0"

  # LuCI packages (luci-app-*)
  shopt -s nullglob
  local luci_dir
  for luci_dir in "${app_dir}"/luci-app-*; do
    [[ -d "$luci_dir" ]] || continue

    if [[ -d "${luci_dir}/luasrc/controller" ]]; then
      mkdir -p "${STAGING_DIR}/usr/lib/lua/luci/controller"
      cp -a "${luci_dir}/luasrc/controller/." "${STAGING_DIR}/usr/lib/lua/luci/controller/"
      any="1"
    fi
    if [[ -d "${luci_dir}/luasrc/model" ]]; then
      copy_tree_into "${luci_dir}/luasrc/model" "${STAGING_DIR}/usr/lib/lua/luci/model"
      any="1"
    fi
    if [[ -d "${luci_dir}/luasrc/view" ]]; then
      copy_tree_into "${luci_dir}/luasrc/view" "${STAGING_DIR}/usr/lib/lua/luci/view"
      any="1"
    fi
    if [[ -d "${luci_dir}/root" ]]; then
      copy_tree_into "${luci_dir}/root" "${STAGING_DIR}"
      any="1"
    fi
    if [[ -d "${luci_dir}/htdocs" ]]; then
      copy_tree_into "${luci_dir}/htdocs" "${STAGING_DIR}/www"
      any="1"
    fi
    if [[ -d "${luci_dir}/po" ]]; then
      stage_luci_po_files "${luci_dir}" "${STAGING_DIR}"
      any="1"
    fi
  done

  # Non-LuCI packages under apps/<id>/*
  local pkg_dir
  for pkg_dir in "${app_dir}"/*; do
    [[ -d "$pkg_dir" ]] || continue
    local base
    base="$(basename "$pkg_dir")"
    [[ "$base" == app-meta-* ]] && continue
    [[ "$base" == luci-app-* ]] && continue

    if [[ -d "${pkg_dir}/root" ]]; then
      copy_tree_into "${pkg_dir}/root" "${STAGING_DIR}"
      any="1"
    fi

    if [[ -f "${pkg_dir}/Makefile" ]]; then
      while IFS=$'\t' read -r src_rel dst_rel; do
        [[ -n "${src_rel:-}" && -n "${dst_rel:-}" ]] || continue
        if [[ -f "${pkg_dir}/${src_rel}" ]]; then
          copy_file_into "${pkg_dir}/${src_rel}" "${STAGING_DIR}/${dst_rel}"
          any="1"
        else
          warn "skipped missing file referenced by Makefile: ${pkg_dir}/${src_rel}"
        fi
      done < <(parse_install_map_from_makefile "${pkg_dir}/Makefile")
    fi

    if [[ -d "${pkg_dir}/files" ]]; then
      if find "${pkg_dir}/files" -mindepth 2 -type f -print -quit 2>/dev/null | grep -q .; then
        copy_tree_into "${pkg_dir}/files" "${STAGING_DIR}"
        any="1"
      fi
    fi
  done
  shopt -u nullglob

  [[ "$any" == "1" ]] || die "no deployable files found for app: ${app_id}"

  tar -C "$STAGING_DIR" -czf "$TARBALL_PATH" .

  echo "Local payload contents:"
  local payload_list
  payload_list="$(tar -tzf "$TARBALL_PATH" | sed 's#^\./##' | sed '/^$/d' | sort)"
  printf "%s\n" "$payload_list"

  local payload_has_lua_luci="0"
  if printf "%s\n" "$payload_list" | grep -q '^usr/lib/lua/luci/'; then
    payload_has_lua_luci="1"
  fi

  if [[ "$dry_run" == "1" ]]; then
    echo "Dry-run: not deploying."
    return 0
  fi

  local remote="${deploy_user}@${deploy_host}"
  local remote_tmp
  remote_tmp="$(ssh "${ssh_args[@]}" "$remote" "mktemp -d /tmp/istore-deploy-${app_id}.XXXXXX")"
  [[ -n "$remote_tmp" ]] || die "failed to allocate remote tmp dir"

  scp "${scp_args[@]}" "$TARBALL_PATH" "${remote}:${remote_tmp}/payload.tgz" >/dev/null

  ssh "${ssh_args[@]}" "$remote" sh -seu <<EOF
set -eu
cd "$remote_tmp"

payload="payload.tgz"
backup_enabled="${deploy_backup}"
restart_enabled="${deploy_restart}"
restart_uhttpd="${deploy_restart_uhttpd}"
services="${deploy_services}"
check_luci_compat="${deploy_check_luci_compat}"
check_ubus="${deploy_check_ubus}"
payload_has_lua_luci="${payload_has_lua_luci}"
overwrite_config="${DEPLOY_OVERWRITE_CONFIG:-0}"

files="\$(tar -tzf "\$payload" | sed 's#^\\./##' | sed '/\\/\$/d' | sed '/^$/d')"

if [ "\$check_luci_compat" = "1" ] && [ "\$payload_has_lua_luci" = "1" ]; then
  if command -v opkg >/dev/null 2>&1; then
    if ! opkg status luci-compat >/dev/null 2>&1; then
      echo "error: deploying Lua LuCI files but luci-compat is not installed on target." >&2
      echo "hint: opkg update && opkg install luci-compat" >&2
      echo "hint: or set DEPLOY_CHECK_LUCI_COMPAT=0 to bypass this check" >&2
      exit 3
    fi
  fi
fi

if [ "\$check_ubus" = "1" ] && [ "\$payload_has_lua_luci" = "1" ]; then
  ubus_ok="0"

  if command -v ubus >/dev/null 2>&1; then
    if ubus -s /var/run/ubus/ubus.sock list >/dev/null 2>&1; then
      ubus_ok="1"
    fi
  elif command -v lua >/dev/null 2>&1; then
    # Some builds don't ship the ubus CLI, but LuCI still requires a working ubus.
    if lua -e 'local ok,ubus=pcall(require,"ubus"); if not ok then os.exit(2) end; local c=ubus.connect("/var/run/ubus/ubus.sock"); if not c then os.exit(3) end; local r=c:call("system","board",{}); os.exit(r and 0 or 1)' >/dev/null 2>&1; then
      ubus_ok="1"
    fi
  fi

  if [ "\$ubus_ok" != "1" ]; then
    echo "error: ubus is not reachable or missing required objects on target (Lua LuCI bridge requires ubus system.board)." >&2
    echo "hint: try fixing ubus/rpcd, e.g.:" >&2
    echo "  rm -f /var/run/ubus/ubus.sock" >&2
    echo "  /sbin/ubusd -s /var/run/ubus/ubus.sock &" >&2
    echo "  killall rpcd; /sbin/rpcd -s /var/run/ubus/ubus.sock -t 30 &" >&2
    echo "hint: or reboot the router" >&2
    echo "hint: or set DEPLOY_CHECK_UBUS=0 to bypass this check" >&2
    exit 4
  fi
fi

backup_dir=""
if [ "\$backup_enabled" = "1" ]; then
  backup_dir="\$(mktemp -d "/tmp/istore-deploy-backup-${app_id}.XXXXXX")"
  echo "Backup dir: \$backup_dir"
echo "\$files" | while IFS= read -r p; do
  [ -n "\$p" ] || continue
  case "\$p" in
    .istore-deploy-meta/*) continue ;;
  esac
  if [ -e "/\$p" ] || [ -L "/\$p" ]; then
    mkdir -p "\$backup_dir/\$(dirname "\$p")"
    cp -a "/\$p" "\$backup_dir/\$p"
    fi
  done
fi

staging_dir="\$(mktemp -d "/tmp/istore-deploy-staging-${app_id}.XXXXXX")"
tar -xzf "\$payload" -C "\$staging_dir"

# Copy files into / but avoid clobbering existing UCI configs by default.
# Deploying via tar extraction bypasses opkg conffile semantics, so this keeps
# local runtime settings intact unless DEPLOY_OVERWRITE_CONFIG=1 is set.
echo "\$files" | while IFS= read -r p; do
  [ -n "\$p" ] || continue
  case "\$p" in
    .istore-deploy-meta/*) continue ;;
  esac
  src="\$staging_dir/\$p"
  dst="/\$p"

  case "\$p" in
    etc/config/*)
      if [ "\$overwrite_config" != "1" ] && [ -e "\$dst" ]; then
        echo "Skip existing config: \$dst"
        continue
      fi
      ;;
  esac

  mkdir -p "\$(dirname "\$dst")"
  cp -a "\$src" "\$dst"
done

po2lmo_bin=""
if command -v po2lmo >/dev/null 2>&1; then
  po2lmo_bin="po2lmo"
elif command -v luci-po2lmo >/dev/null 2>&1; then
  po2lmo_bin="luci-po2lmo"
fi

if [ -d "\$staging_dir/.istore-deploy-meta/luci-po" ]; then
  if [ -n "\$po2lmo_bin" ]; then
    find "\$staging_dir/.istore-deploy-meta/luci-po" -type f -name '*.po' | while IFS= read -r po; do
      rel="\${po#\$staging_dir/.istore-deploy-meta/luci-po/}"
      lang="\${rel%%/*}"
      domain="\$(basename "\$po" .po)"
      out="/usr/lib/lua/luci/i18n/\${domain}.\${lang}.lmo"
      mkdir -p "\$(dirname "\$out")"
      "\$po2lmo_bin" "\$po" "\$out"
      echo "Compiled i18n: \$out"
    done
  else
    echo "warn: target has no po2lmo/luci-po2lmo; LuCI translations were not deployed" >&2
  fi
fi

rm -rf "\$staging_dir" || true

echo "\$files" | while IFS= read -r p; do
  case "\$p" in
    etc/init.d/*) [ -f "/\$p" ] && chmod +x "/\$p" || true;;
  esac
done

rm -rf /tmp/luci-* /tmp/luci-indexcache || true

if [ "\$restart_uhttpd" = "1" ]; then
  /etc/init.d/uhttpd reload 2>/dev/null || /etc/init.d/uhttpd restart 2>/dev/null || true
fi

if [ "\$restart_enabled" = "1" ]; then
  for svc in \$services; do
    [ -x "/etc/init.d/\$svc" ] || continue
    /etc/init.d/"\$svc" restart 2>/dev/null || /etc/init.d/"\$svc" reload 2>/dev/null || true
  done
fi

echo "Deployed to / (app: ${app_id})."
echo "Remote tmp: $remote_tmp"
EOF
}

main "$@"
