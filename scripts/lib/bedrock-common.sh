#!/usr/bin/env bash
# bedrock-common.sh — shared helpers for Claude Code + AWS Bedrock in Workbench runtime.
# Sourced by bedrock-runtime-startup.sh. Do not execute directly.
#
# Authentication:
#   AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY (long-lived IAM key pair).
#   LiteLLM signs Bedrock requests with those keys. No short-lived bearer token.
#
# Required:
#   BEDROCK_MODEL — Bedrock model id (e.g. us.anthropic.claude-sonnet-4-6)
#   AWS_REGION    — Bedrock region (falls back to AWS_DEFAULT_REGION)
#
# Optional:
#   BEDROCK_LITELLM_PORT — local LiteLLM proxy port (default: 4000)

: "${BEDROCK_HOME:?BEDROCK_HOME must be set before sourcing bedrock-common.sh}"

LITELLM_CONFIG="${BEDROCK_LITELLM_CONFIG:-${BEDROCK_HOME}/litellm-config.yaml}"
LITELLM_PID_FILE="${BEDROCK_LITELLM_PID_FILE:-${BEDROCK_HOME}/litellm.pid}"
LITELLM_LOG="${BEDROCK_LITELLM_LOG:-${BEDROCK_HOME}/litellm.log}"
LITELLM_PORT="${BEDROCK_LITELLM_PORT:-4000}"
LITELLM_MASTER_KEY="${BEDROCK_LITELLM_MASTER_KEY:-sk-bedrock-local-proxy}"
PROXY_URL="http://127.0.0.1:${LITELLM_PORT}"

BEDROCK_MAX_OUTPUT_TOKENS="${BEDROCK_MAX_OUTPUT_TOKENS:-8192}"
BEDROCK_MAX_INPUT_TOKENS="${BEDROCK_MAX_INPUT_TOKENS:-192000}"

CLAUDE_OPUS_ALIAS="${BEDROCK_CLAUDE_OPUS_ALIAS:-claude-opus-4-6}"
CLAUDE_SONNET_ALIAS="${BEDROCK_CLAUDE_SONNET_ALIAS:-claude-sonnet-4-6}"
CLAUDE_HAIKU_ALIAS="${BEDROCK_CLAUDE_HAIKU_ALIAS:-claude-haiku-4-5-20251001}"

bedrock_log() { printf '%s\n' "$*" >&2; }
bedrock_die() { bedrock_log "ERROR: $*"; return 1; }

bedrock_have_cmd() { command -v "$1" >/dev/null 2>&1; }

bedrock_aws_region() {
    printf '%s' "${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
}

bedrock_has_base_creds() {
    [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]
}

bedrock_env_ready() {
    [[ -n "${BEDROCK_MODEL:-}" && -n "$(bedrock_aws_region)" ]] && bedrock_has_base_creds
}

bedrock_litellm_model_id() {
    local model="${1:-${BEDROCK_MODEL}}"
    case "$model" in
        bedrock/*) printf '%s' "$model" ;;
        *) printf 'bedrock/invoke/%s' "$model" ;;
    esac
}

bedrock_litellm_bin() {
    local bin="${BEDROCK_VENV_BIN:-/opt/bedrock-claude/venv/bin}/litellm"
    [ -x "$bin" ] || { bedrock_die "LiteLLM not installed at ${bin}"; return 1; }
    printf '%s' "$bin"
}

bedrock_write_litellm_config() {
    local litellm_model region max_out max_in
    litellm_model="$(bedrock_litellm_model_id)"
    region="$(bedrock_aws_region)"
    max_out="${BEDROCK_MAX_OUTPUT_TOKENS:-8192}"
    max_in="${BEDROCK_MAX_INPUT_TOKENS:-192000}"

    mkdir -p "$(dirname "$LITELLM_CONFIG")"

    cat >"$LITELLM_CONFIG" <<YAML
# Generated at session start. Signs with the long-lived IAM access key pair.
model_list:
  - model_name: ${CLAUDE_OPUS_ALIAS}
    litellm_params:
      model: ${litellm_model}
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: ${region}
      max_tokens: ${max_out}
    model_info:
      max_tokens: 200000
      max_input_tokens: ${max_in}
      max_output_tokens: ${max_out}
  - model_name: ${CLAUDE_SONNET_ALIAS}
    litellm_params:
      model: ${litellm_model}
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: ${region}
      max_tokens: ${max_out}
    model_info:
      max_tokens: 200000
      max_input_tokens: ${max_in}
      max_output_tokens: ${max_out}
  - model_name: ${CLAUDE_HAIKU_ALIAS}
    litellm_params:
      model: ${litellm_model}
      aws_access_key_id: os.environ/AWS_ACCESS_KEY_ID
      aws_secret_access_key: os.environ/AWS_SECRET_ACCESS_KEY
      aws_region_name: ${region}
      max_tokens: ${max_out}
    model_info:
      max_tokens: 200000
      max_input_tokens: ${max_in}
      max_output_tokens: ${max_out}

litellm_settings:
  master_key: ${LITELLM_MASTER_KEY}
  drop_params: true
  modify_params: true
  request_timeout: 600
YAML
}

bedrock_proxy_health_ok() {
    curl -sf --connect-timeout 2 --max-time 5 \
        -H "Authorization: Bearer ${LITELLM_MASTER_KEY}" \
        "${PROXY_URL}/health/liveliness" >/dev/null 2>&1 \
        || curl -sf --connect-timeout 2 --max-time 5 "${PROXY_URL}/health" >/dev/null 2>&1
}

bedrock_stop_proxy() {
    if [ -f "$LITELLM_PID_FILE" ]; then
        local pid
        pid="$(cat "$LITELLM_PID_FILE" 2>/dev/null || true)"
        if [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
            wait "$pid" 2>/dev/null || true
        fi
        rm -f "$LITELLM_PID_FILE"
    fi
}

bedrock_start_litellm_proxy() {
    local litellm_bin new_hash="" old_hash=""
    bedrock_env_ready || {
        bedrock_die "Bedrock env not ready — set BEDROCK_MODEL, AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY."
        return 1
    }

    litellm_bin="$(bedrock_litellm_bin)" || return 1
    bedrock_write_litellm_config

    if bedrock_have_cmd sha256sum; then
        new_hash="$(sha256sum "$LITELLM_CONFIG" | awk '{print $1}')"
        old_hash="$(cat "${LITELLM_CONFIG}.hash" 2>/dev/null || true)"
    elif bedrock_have_cmd shasum; then
        new_hash="$(shasum -a 256 "$LITELLM_CONFIG" | awk '{print $1}')"
        old_hash="$(cat "${LITELLM_CONFIG}.hash" 2>/dev/null || true)"
    fi

    if bedrock_proxy_health_ok && [ -n "$new_hash" ] && [ "$new_hash" = "$old_hash" ]; then
        return 0
    fi

    bedrock_stop_proxy
    region="$(bedrock_aws_region)"
    export AWS_REGION="$region"
    export AWS_DEFAULT_REGION="$region"
    : >"$LITELLM_LOG"

    # nohup ignores SIGHUP so the proxy keeps running after the editor entrypoint
    # replaces itself with code-server. The proxy receives only the long-lived key pair.
    nohup env -u AWS_BEARER_TOKEN_BEDROCK -u AWS_SESSION_TOKEN \
        AWS_REGION="$region" AWS_DEFAULT_REGION="$region" \
        AWS_ACCESS_KEY_ID="$AWS_ACCESS_KEY_ID" \
        AWS_SECRET_ACCESS_KEY="$AWS_SECRET_ACCESS_KEY" \
        "$litellm_bin" --config "$LITELLM_CONFIG" --host 127.0.0.1 --port "$LITELLM_PORT" \
        >>"$LITELLM_LOG" 2>&1 </dev/null &
    local pid=$!
    echo "$pid" >"$LITELLM_PID_FILE"

    local i
    for i in $(seq 1 30); do
        if bedrock_proxy_health_ok; then
            [ -n "$new_hash" ] && printf '%s' "$new_hash" >"${LITELLM_CONFIG}.hash"
            return 0
        fi
        if ! kill -0 "$pid" 2>/dev/null; then
            bedrock_log "LiteLLM failed to start. Last log lines:"
            tail -20 "$LITELLM_LOG" >&2 || true
            bedrock_die "LiteLLM proxy exited unexpectedly." || return 1
        fi
        sleep 0.5
    done
    bedrock_die "LiteLLM proxy did not become healthy within 15s. See ${LITELLM_LOG}" || return 1
}

bedrock_write_claude_settings() {
    mkdir -p "$HOME/.claude"
    umask 077

    cat >"$HOME/.claude.json" <<EOF
{
  "hasCompletedOnboarding": true,
  "primaryApiKey": "${LITELLM_MASTER_KEY}"
}
EOF

    cat >"$HOME/.claude/settings.json" <<EOF
{
  "promptSuggestionEnabled": false,
  "model": "${CLAUDE_SONNET_ALIAS}",
  "env": {
    "ANTHROPIC_BASE_URL": "${PROXY_URL}",
    "ANTHROPIC_DEFAULT_OPUS_MODEL": "${CLAUDE_SONNET_ALIAS}",
    "ANTHROPIC_DEFAULT_SONNET_MODEL": "${CLAUDE_SONNET_ALIAS}",
    "ANTHROPIC_DEFAULT_HAIKU_MODEL": "${CLAUDE_HAIKU_ALIAS}",
    "CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY": "1",
    "CLAUDE_CODE_DISABLE_1M_CONTEXT": "1",
    "CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS": "1",
    "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "${BEDROCK_MAX_OUTPUT_TOKENS:-8192}",
    "CLAUDE_CODE_ATTRIBUTION_HEADER": "0",
    "CLAUDE_CODE_ENABLE_TELEMETRY": "0",
    "CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC": "1"
  },
  "attribution": { "commit": "", "pr": "" }
}
EOF
}

bedrock_export_claude_env() {
    unset AWS_BEARER_TOKEN_BEDROCK AWS_SESSION_TOKEN
    export ANTHROPIC_BASE_URL="$PROXY_URL"
    export ANTHROPIC_API_KEY="$LITELLM_MASTER_KEY"
    unset ANTHROPIC_AUTH_TOKEN
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$CLAUDE_SONNET_ALIAS"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$CLAUDE_SONNET_ALIAS"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$CLAUDE_HAIKU_ALIAS"
    export CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY="${CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY:-1}"
    export CLAUDE_CODE_DISABLE_1M_CONTEXT="${CLAUDE_CODE_DISABLE_1M_CONTEXT:-1}"
    export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS="${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:-1}"
    export CLAUDE_CODE_MAX_OUTPUT_TOKENS="${BEDROCK_MAX_OUTPUT_TOKENS:-8192}"
}

# Hash of the long-lived key pair, model, and region for this session.
bedrock_env_fingerprint() {
    local material
    material="${BEDROCK_MODEL}|$(bedrock_aws_region)|${AWS_ACCESS_KEY_ID:-}|${AWS_SECRET_ACCESS_KEY:-}|${LITELLM_PORT}|${BEDROCK_MAX_OUTPUT_TOKENS:-}|${BEDROCK_MAX_INPUT_TOKENS:-}"
    if bedrock_have_cmd sha256sum; then
        printf '%s' "$material" | sha256sum | awk '{print $1}'
    elif bedrock_have_cmd shasum; then
        printf '%s' "$material" | shasum -a 256 | awk '{print $1}'
    else
        printf '%s' "$material" | cksum | awk '{print $1}'
    fi
}

bedrock_sync_config() {
    local verbose="${1:-0}" litellm_model region fingerprint="" previous=""

    if ! bedrock_env_ready; then
        bedrock_log "Bedrock: set BEDROCK_MODEL, AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY."
        bedrock_log "Restart the session after changing global environment variables."
        return 1
    fi

    fingerprint="$(bedrock_env_fingerprint)"
    previous="$(cat "${BEDROCK_HOME}/env.fingerprint" 2>/dev/null || true)"
    if [[ -n "$fingerprint" && "$fingerprint" == "$previous" ]] \
        && [[ -f "${HOME}/.claude/settings.json" ]] \
        && bedrock_proxy_health_ok; then
        bedrock_export_claude_env
        if [[ "$verbose" == "1" ]]; then
            bedrock_log "Bedrock gateway already matches this session environment (${PROXY_URL})."
        fi
        return 0
    fi

    litellm_model="$(bedrock_litellm_model_id)"
    region="$(bedrock_aws_region)"

    bedrock_write_claude_settings
    bedrock_start_litellm_proxy || return 1
    bedrock_export_claude_env
    printf '%s' "$fingerprint" > "${BEDROCK_HOME}/env.fingerprint"

    if [[ "$verbose" == "1" ]]; then
        bedrock_log "Applied session environment."
        bedrock_log "LiteLLM proxy: ${PROXY_URL} → ${litellm_model} (${region})"
        bedrock_log "Model: ${BEDROCK_MODEL}"
        bedrock_log "Auth: IAM access key"
        bedrock_log "Output cap: ${BEDROCK_MAX_OUTPUT_TOKENS:-8192} tokens"
        bedrock_log "Claude Code and Mistral Vibe are ready in VS Code."
    fi
}

bedrock_launch_claude() {
    bedrock_have_cmd claude || { bedrock_die "Claude Code CLI not installed."; return 127; }
    bedrock_sync_config 0 || return 1

    if [ $# -gt 0 ]; then
        command claude "$@"
    else
        command claude
    fi
}
