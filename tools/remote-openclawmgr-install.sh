#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Run OpenClawMgr installer on a remote box and save logs locally.

Requires env (recommended via .it-runner/.env.local):
  DEPLOY_HOST, DEPLOY_USER, DEPLOY_PORT
Optional:
  DEPLOY_SSH_KEY, DEPLOY_SSH_OPTS

Outputs:
  .it-runner/logs/openclawmgr-install/<timestamp>.session.log
  .it-runner/logs/openclawmgr-install/<timestamp>.taskd.log (best-effort)
  .it-runner/logs/openclawmgr-install/<timestamp>.installer.log (best-effort)
EOF
}

die() { echo "error: $*" >&2; exit 2; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

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

main() {
  need_cmd ssh
  need_cmd scp
  need_cmd tee
  need_cmd date

  local no_env="0"
  while [[ $# -gt 0 ]]; do
    case "$1" in
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

  local host="${DEPLOY_HOST:-}"
  local user="${DEPLOY_USER:-root}"
  local port="${DEPLOY_PORT:-22}"
  local ssh_key="${DEPLOY_SSH_KEY:-}"
  local ssh_opts="${DEPLOY_SSH_OPTS:-}"

  [[ -n "$host" ]] || die "DEPLOY_HOST is required (set in .it-runner/.env.local)"

  mkdir -p "${project_root}/.it-runner/logs/openclawmgr-install"
  mkdir -p "${project_root}/.it-runner/cache"

  local ts
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  local outdir="${project_root}/.it-runner/logs/openclawmgr-install"
  local session_log="${outdir}/${ts}.session.log"
  local taskd_log="${outdir}/${ts}.taskd.log"
  local installer_log="${outdir}/${ts}.installer.log"

  local ssh_args=(-p "$port" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="${project_root}/.it-runner/cache/known_hosts" -o LogLevel=ERROR)
  local scp_args=(-P "$port" -o BatchMode=yes -o StrictHostKeyChecking=no -o UserKnownHostsFile="${project_root}/.it-runner/cache/known_hosts" -o LogLevel=ERROR)

  if [[ -n "$ssh_key" ]]; then
    ssh_args+=(-i "$ssh_key")
    scp_args+=(-i "$ssh_key")
  fi
  if [[ -n "$ssh_opts" ]]; then
    # shellcheck disable=SC2206
    ssh_args+=($ssh_opts)
    # shellcheck disable=SC2206
    scp_args+=($ssh_opts)
  fi

  local remote="${user}@${host}"

  {
    echo "== target: ${remote}:${port}"
    echo "== time: $(date -u)"
    echo "== command: /usr/libexec/istorec/openclawmgr.sh install"
    echo ""
    ssh "${ssh_args[@]}" "$remote" sh -seu <<'EOSH'
echo "== uname"
uname -a || true
echo ""

echo "== routes"
ip route 2>/dev/null || true
echo ""

echo "== openclawmgr uci"
uci -q show openclawmgr.main 2>/dev/null || true
echo ""

script="/usr/libexec/istorec/openclawmgr.sh"
[ -x "$script" ] || { echo "missing: $script" >&2; exit 127; }

if [ -x /etc/init.d/tasks ]; then
  echo "== run via taskd (streaming /var/log/tasks/openclawmgr.log)"
  /etc/init.d/tasks task_del openclawmgr >/dev/null 2>&1 || true
  /etc/init.d/tasks task_add openclawmgr "\"$script\" install" >/dev/null 2>&1
  touch /var/log/tasks/openclawmgr.log 2>/dev/null || true
  tail -n 0 -f /var/log/tasks/openclawmgr.log &
  tailpid="$!"
  while :; do
    st="$(/etc/init.d/tasks task_status openclawmgr 2>/dev/null || true)"
    running="$(printf "%s" "$st" | jsonfilter -e '@.running' 2>/dev/null || echo false)"
    [ "$running" = "true" ] || break
    sleep 1
  done
  kill "$tailpid" 2>/dev/null || true
  echo ""
  echo "== task final status"
  /etc/init.d/tasks task_status openclawmgr 2>/dev/null || true
else
  echo "== run directly (taskd missing)"
  "$script" install
fi

echo ""
echo "== installer.log tail"
base_dir="$(uci -q get openclawmgr.main.base_dir 2>/dev/null || echo /opt/openclawmgr)"
tail -n 200 "$base_dir/log/installer.log" 2>/dev/null || true
EOSH
  } |& tee "$session_log"

  local base_dir
  base_dir="$(ssh "${ssh_args[@]}" "$remote" 'uci -q get openclawmgr.main.base_dir 2>/dev/null || echo /opt/openclawmgr' | tr -d '\r\n' || true)"
  [[ -n "$base_dir" ]] || base_dir="/opt/openclawmgr"

  scp "${scp_args[@]}" "${remote}:/var/log/tasks/openclawmgr.log" "$taskd_log" >/dev/null 2>&1 || true
  scp "${scp_args[@]}" "${remote}:${base_dir}/log/installer.log" "$installer_log" >/dev/null 2>&1 || true

  echo ""
  echo "Saved logs:"
  echo "  ${session_log}"
  echo "  ${taskd_log} (best-effort)"
  echo "  ${installer_log} (best-effort)"
}

main "$@"

