#!/usr/bin/env bash
set -euo pipefail

gateway_pid=""
webui_pid=""

cleanup() {
  local exit_code=$?

  if [[ -n "${webui_pid}" ]] && kill -0 "${webui_pid}" 2>/dev/null; then
    kill "${webui_pid}" 2>/dev/null || true
  fi

  if [[ -n "${gateway_pid}" ]] && kill -0 "${gateway_pid}" 2>/dev/null; then
    kill "${gateway_pid}" 2>/dev/null || true
  fi

  wait "${webui_pid}" 2>/dev/null || true
  wait "${gateway_pid}" 2>/dev/null || true

  exit "${exit_code}"
}

trap cleanup INT TERM EXIT

mkdir -p "${HERMES_WEBUI_STATE_DIR}" "${HERMES_HOME}" "${HERMES_WEBUI_DEFAULT_WORKSPACE:-/workspace}"

if [[ ! -d "${HERMES_WEBUI_AGENT_DIR}" ]]; then
  echo "warning: HERMES_WEBUI_AGENT_DIR not found at ${HERMES_WEBUI_AGENT_DIR}" >&2
fi

(
  exec hermes gateway run
) &
gateway_pid=$!

(
  cd "${HERMES_WEBUI_AGENT_DIR:-/hermes}" 2>/dev/null || cd /hermes
  exec python3 "${HERMES_WEBUI_DIR}/server.py"
) &
webui_pid=$!

wait -n "${gateway_pid}" "${webui_pid}"
