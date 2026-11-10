#!/usr/bin/env bash
# /etc/profile.d/claude-bedrock.sh
#
# Sourced on every interactive shell in the VS Code / Workbench runtime image
# (including the code-server integrated terminal).
#
# Configures Claude Code to reach AWS Bedrock via a local LiteLLM proxy.
# Credentials come from Cloudera AI global (site) environment variables.
#
# Authentication: AWS_ACCESS_KEY_ID + AWS_SECRET_ACCESS_KEY.
#
# Required:
#   BEDROCK_MODEL, AWS_REGION, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
#
# Session start applies the global environment. These helpers are optional.
#   claude                — open Claude Code (gateway already started)
#   claude-status         — show env + proxy health
#   claude-stop-proxy     — stop background LiteLLM
#   claude-logs           — tail LiteLLM log

[[ $- != *i* ]] && return

export BEDROCK_HOME="${BEDROCK_HOME:-${HOME}/.claude/bedrock}"
export BEDROCK_VENV_BIN="${BEDROCK_VENV_BIN:-/opt/bedrock-claude/venv/bin}"
export BEDROCK_LITELLM_PORT="${BEDROCK_LITELLM_PORT:-4000}"

# shellcheck disable=SC1091
source /opt/bedrock-claude/lib/bedrock-common.sh

claude() {
    bedrock_launch_claude "$@"
}

claude-status() {
    echo ""
    echo "┌─ re:Invent — Claude (Bedrock) + Mistral Vibe ────────────────────────────┐"
    claude_bin="$(type -P claude 2>/dev/null || true)"
    if [[ -n "${claude_bin}" ]]; then
        echo "│  ✓ claude: ${claude_bin} ($(command claude --version 2>/dev/null | head -1 || true))"
    else
        echo "│  ✗ claude CLI not found"
    fi
    echo "│  ✓ VS Code extensions: Claude Code, Mistral Vibe"
    if [[ -n "${MISTRAL_API_KEY:-${VIBE_API_KEY:-}}" ]]; then
        echo "│  ✓ Mistral Vibe: ${MISTRAL_MODEL:-${MISTRAL_VIBE_ACTIVE_MODEL:-codestral}} (${MISTRAL_API_URL:-https://api.mistral.ai/v1})"
    else
        echo "│  ○ Mistral Vibe: set global MISTRAL_API_KEY, MISTRAL_API_URL, and MISTRAL_MODEL"
    fi
    if bedrock_env_ready; then
        echo "│  ✓ Bedrock env set (model: ${BEDROCK_MODEL})"
        echo "│  ✓ region: $(bedrock_aws_region)"
        echo "│  ✓ auth: IAM access key"
        if bedrock_proxy_health_ok; then
            echo "│  ✓ LiteLLM proxy: http://127.0.0.1:${BEDROCK_LITELLM_PORT}"
        else
            echo "│  ○ LiteLLM proxy did not start. See ${BEDROCK_HOME}/litellm.log"
        fi
        echo "│  → Open Claude Code in the activity bar, or run: claude"
    else
        echo "│  ○ Set global BEDROCK_MODEL, AWS_REGION, and AWS keys, then restart the session"
    fi
    echo "│  BEDROCK_HOME=${BEDROCK_HOME}"
    echo "│  Log: ${BEDROCK_HOME}/litellm.log"
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

claude-stop-proxy() {
    bedrock_stop_proxy
    bedrock_log "Stopped LiteLLM proxy."
}

claude-logs() {
    tail -f "${BEDROCK_HOME}/litellm.log"
}

_claude_banner() {
    claude-status
}

# Re-read the live environment. No-op when this session already started the gateway.
if [[ -x /usr/local/bin/configure-bedrock-from-env ]]; then
    BEDROCK_SYNC_VERBOSE=0 /usr/local/bin/configure-bedrock-from-env || true
fi

# Login shells source profile.d and may also source bashrc. Print once.
if [[ -z "${REINVENT_RUNTIME_BANNER_SHOWN:-}" ]]; then
    export REINVENT_RUNTIME_BANNER_SHOWN=1
    _claude_banner
fi
