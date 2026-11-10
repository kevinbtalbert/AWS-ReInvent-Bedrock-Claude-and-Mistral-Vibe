#!/usr/bin/env bash
# Sourced by interactive shells, including the code-server terminal.
# Claude Code calls Amazon Bedrock directly with the IAM key pair.
#
# Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION
# Optional picker overrides: BEDROCK_SONNET_MODEL, BEDROCK_OPUS_MODEL,
#   BEDROCK_HAIKU_MODEL, BEDROCK_FABLE_MODEL
#   BEDROCK_MODEL still overrides the Sonnet row when BEDROCK_SONNET_MODEL is unset.

[[ $- != *i* ]] && return

export BEDROCK_HOME="${BEDROCK_HOME:-${HOME}/.claude/bedrock}"
mkdir -p "${BEDROCK_HOME}" "${HOME}/.claude"

# shellcheck disable=SC1091
source /opt/bedrock-claude/lib/bedrock-common.sh

claude() {
    bedrock_launch_claude "$@"
}

claude-status() {
    bedrock_resolve_models
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
        echo "│  ✓ Bedrock direct, region $(bedrock_aws_region)"
        echo "│    sonnet  ${BEDROCK_SONNET_MODEL}"
        echo "│    opus    ${BEDROCK_OPUS_MODEL}"
        echo "│    haiku   ${BEDROCK_HAIKU_MODEL}"
        echo "│    fable   ${BEDROCK_FABLE_MODEL}"
        echo "│  → Pick a model in Claude Code, or run: claude"
    else
        echo "│  ○ Set global AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION"
        echo "│    then restart the session"
    fi
    echo "└──────────────────────────────────────────────────────────────────────────┘"
    echo ""
}

if [[ -f /usr/local/bin/configure-bedrock-from-env ]]; then
    BEDROCK_SYNC_VERBOSE=0 source /usr/local/bin/configure-bedrock-from-env || true
fi

if [[ -z "${REINVENT_RUNTIME_BANNER_SHOWN:-}" ]]; then
    export REINVENT_RUNTIME_BANNER_SHOWN=1
    claude-status
fi
