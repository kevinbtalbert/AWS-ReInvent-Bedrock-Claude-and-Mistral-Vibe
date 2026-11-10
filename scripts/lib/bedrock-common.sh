#!/usr/bin/env bash
# Native Amazon Bedrock for Claude Code. Claude Code signs with the long-lived
# IAM key pair. There is no LiteLLM proxy.
#
# The model picker rows map to these Bedrock inference profiles:
#   sonnet  BEDROCK_SONNET_MODEL  (legacy BEDROCK_MODEL still sets Sonnet)
#   opus    BEDROCK_OPUS_MODEL
#   haiku   BEDROCK_HAIKU_MODEL
#   fable   BEDROCK_FABLE_MODEL
#
# Required: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, AWS_REGION

: "${BEDROCK_HOME:?BEDROCK_HOME must be set before sourcing bedrock-common.sh}"

bedrock_log() { printf '%s\n' "$*" >&2; }

bedrock_aws_region() {
    printf '%s' "${AWS_REGION:-${AWS_DEFAULT_REGION:-}}"
}

bedrock_has_base_creds() {
    [[ -n "${AWS_ACCESS_KEY_ID:-}" && -n "${AWS_SECRET_ACCESS_KEY:-}" ]]
}

bedrock_env_ready() {
    [[ -n "$(bedrock_aws_region)" ]] && bedrock_has_base_creds
}

# Inference profile IDs from the Amazon Bedrock model cards. Each global env
# var overrides one Claude Code picker row. BEDROCK_MODEL still overrides Sonnet.
bedrock_resolve_models() {
    BEDROCK_SONNET_MODEL="${BEDROCK_SONNET_MODEL:-${BEDROCK_MODEL:-us.anthropic.claude-sonnet-4-6}}"
    BEDROCK_OPUS_MODEL="${BEDROCK_OPUS_MODEL:-us.anthropic.claude-opus-4-6-v1}"
    BEDROCK_HAIKU_MODEL="${BEDROCK_HAIKU_MODEL:-us.anthropic.claude-haiku-4-5-20251001-v1:0}"
    BEDROCK_FABLE_MODEL="${BEDROCK_FABLE_MODEL:-global.anthropic.claude-fable-5-2}"
    export BEDROCK_SONNET_MODEL BEDROCK_OPUS_MODEL BEDROCK_HAIKU_MODEL BEDROCK_FABLE_MODEL
}

bedrock_export_claude_env() {
    local region
    region="$(bedrock_aws_region)"
    bedrock_resolve_models
    unset AWS_BEARER_TOKEN_BEDROCK AWS_SESSION_TOKEN
    unset ANTHROPIC_BASE_URL ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN
    unset CLAUDE_CODE_ATTRIBUTION_HEADER
    export CLAUDE_CODE_USE_BEDROCK=1
    export AWS_REGION="$region"
    export AWS_DEFAULT_REGION="$region"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="$BEDROCK_SONNET_MODEL"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="$BEDROCK_OPUS_MODEL"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="$BEDROCK_HAIKU_MODEL"
    export ANTHROPIC_DEFAULT_FABLE_MODEL="$BEDROCK_FABLE_MODEL"
    # "sonnet" stays an alias so the picker highlights the Sonnet row and
    # resolves it through ANTHROPIC_DEFAULT_SONNET_MODEL.
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-sonnet}"
    export CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS="${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS:-1}"
}

bedrock_write_claude_settings() {
    local env_json settings_json claude_json
    bedrock_export_claude_env
    mkdir -p "${HOME}/.claude"
    umask 077
    command -v jq >/dev/null 2>&1 || {
        bedrock_log "ERROR: jq is required to write Claude settings."
        return 1
    }

    # The alias "sonnet" is what the picker highlights. The four
    # ANTHROPIC_DEFAULT_* values are the Bedrock ids behind each row.
    env_json="$(jq -n \
        --arg region "${AWS_REGION}" \
        --arg model "${ANTHROPIC_MODEL}" \
        --arg sonnet "${ANTHROPIC_DEFAULT_SONNET_MODEL}" \
        --arg opus "${ANTHROPIC_DEFAULT_OPUS_MODEL}" \
        --arg haiku "${ANTHROPIC_DEFAULT_HAIKU_MODEL}" \
        --arg fable "${ANTHROPIC_DEFAULT_FABLE_MODEL}" \
        --arg betas "${CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS}" \
        '{
          CLAUDE_CODE_USE_BEDROCK: "1",
          AWS_REGION: $region,
          AWS_DEFAULT_REGION: $region,
          ANTHROPIC_MODEL: $model,
          ANTHROPIC_DEFAULT_SONNET_MODEL: $sonnet,
          ANTHROPIC_DEFAULT_OPUS_MODEL: $opus,
          ANTHROPIC_DEFAULT_HAIKU_MODEL: $haiku,
          ANTHROPIC_DEFAULT_FABLE_MODEL: $fable,
          CLAUDE_CODE_DISABLE_EXPERIMENTAL_BETAS: $betas
        }')"

    if [[ -f "${HOME}/.claude/settings.json" ]]; then
        settings_json="$(jq --argjson env "$env_json" '
          .model = "sonnet"
          | .env = ((.env // {}) + $env)
          | .env |= del(
              .ANTHROPIC_BASE_URL,
              .ANTHROPIC_API_KEY,
              .ANTHROPIC_AUTH_TOKEN,
              .CLAUDE_CODE_ATTRIBUTION_HEADER,
              .CLAUDE_CODE_AUTO_MODE_SERVER,
              .CLAUDE_CODE_ENABLE_GATEWAY_MODEL_DISCOVERY
            )
        ' "${HOME}/.claude/settings.json")"
    else
        settings_json="$(jq -n --argjson env "$env_json" \
          '{promptSuggestionEnabled: false, model: "sonnet", env: $env}')"
    fi
    printf '%s\n' "$settings_json" >"${HOME}/.claude/settings.json"

    if [[ -f "${HOME}/.claude.json" ]]; then
        claude_json="$(jq '
          .hasCompletedOnboarding = true
          | del(.primaryApiKey)
        ' "${HOME}/.claude.json")"
    else
        claude_json='{"hasCompletedOnboarding":true}'
    fi
    printf '%s\n' "$claude_json" >"${HOME}/.claude.json"
}

bedrock_apply_config() {
    local verbose="${1:-0}"
    if ! bedrock_env_ready; then
        if [[ "$verbose" == "1" ]]; then
            bedrock_log "Claude/Bedrock: set AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY, and AWS_REGION."
        fi
        return 0
    fi
    bedrock_write_claude_settings
    if [[ "$verbose" == "1" ]]; then
        bedrock_log "Claude Code uses Amazon Bedrock directly (${AWS_REGION})."
        bedrock_log "  sonnet  ${ANTHROPIC_DEFAULT_SONNET_MODEL}"
        bedrock_log "  opus    ${ANTHROPIC_DEFAULT_OPUS_MODEL}"
        bedrock_log "  haiku   ${ANTHROPIC_DEFAULT_HAIKU_MODEL}"
        bedrock_log "  fable   ${ANTHROPIC_DEFAULT_FABLE_MODEL}"
    fi
}

bedrock_launch_claude() {
    command -v claude >/dev/null 2>&1 || {
        bedrock_log "ERROR: Claude Code CLI not installed."
        return 127
    }
    bedrock_apply_config 0 || return 1
    if [[ $# -gt 0 ]]; then
        command claude "$@"
    else
        command claude
    fi
}
