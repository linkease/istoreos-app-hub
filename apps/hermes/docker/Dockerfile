FROM python:3.12-slim-bookworm

ARG HERMES_AGENT_REPO=https://github.com/NousResearch/hermes-agent.git
ARG HERMES_WEBUI_REPO=https://github.com/nesquena/hermes-webui.git

ENV TZ=Asia/Shanghai \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PATH=/root/.local/bin:/root/.cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin \
    HERMES_HOME=/data/.hermes \
    HERMES_AGENT_DIR=/opt/hermes-agent \
    HERMES_WEBUI_DIR=/opt/hermes-webui \
    HERMES_WEBUI_HOST=0.0.0.0 \
    HERMES_WEBUI_PORT=8787 \
    HERMES_WEBUI_STATE_DIR=/data/.hermes/webui \
    HERMES_WEBUI_AGENT_DIR=/workspace \
    HERMES_WEBUI_DEFAULT_WORKSPACE=/workspace

WORKDIR /workspace

RUN apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
        bash \
        ca-certificates \
        curl \
        git \
        tini \
        tzdata \
        xz-utils \
    && update-ca-certificates \
    && ln -snf /usr/share/zoneinfo/"$TZ" /etc/localtime \
    && echo "$TZ" > /etc/timezone \
    && git config --global http.version HTTP/1.1 \
    && mkdir -p "$HERMES_HOME" "$HERMES_WEBUI_STATE_DIR" /workspace \
    && rm -rf /var/lib/apt/lists/*

RUN git clone --depth=1 "$HERMES_AGENT_REPO" "$HERMES_AGENT_DIR" \
    && python -m pip install --no-cache-dir "$HERMES_AGENT_DIR" \
    && command -v hermes

RUN git clone --depth=1 "$HERMES_WEBUI_REPO" "$HERMES_WEBUI_DIR" \
    && python -m pip install --no-cache-dir -r "$HERMES_WEBUI_DIR/requirements.txt"

COPY entrypoint.sh /usr/local/bin/hermes-entrypoint

RUN chmod +x /usr/local/bin/hermes-entrypoint

EXPOSE 8787

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
  CMD curl -fsS "http://127.0.0.1:${HERMES_WEBUI_PORT}/health" || exit 1

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hermes-entrypoint"]
