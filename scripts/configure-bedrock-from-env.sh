#!/usr/bin/env bash
# Non-interactive session start for the VS Code editor entrypoint.
# Global (site) environment variables are already on the process.
# Starts LiteLLM with the long-lived IAM access key pair and writes Claude settings
# so the Claude Code extension and the `claude` CLI share one gateway.
set -Eeuo pipefail

export BEDROCK_HOME="${BEDROCK_HOME:-${HOME}/.claude/bedrock}"
export BEDROCK_VENV_BIN="${BEDROCK_VENV_BIN:-/opt/bedrock-claude/venv/bin}"
export BEDROCK_LITELLM_PORT="${BEDROCK_LITELLM_PORT:-4000}"

mkdir -p "${BEDROCK_HOME}" "${HOME}/.claude"

# shellcheck disable=SC1091
source /opt/bedrock-claude/lib/bedrock-common.sh

if ! bedrock_env_ready; then
  if [[ "${BEDROCK_SYNC_VERBOSE:-1}" == "1" ]]; then
    echo "Claude/Bedrock: set global BEDROCK_MODEL, AWS_REGION, AWS_ACCESS_KEY_ID, and AWS_SECRET_ACCESS_KEY." >&2
  fi
  exit 0
fi

bedrock_sync_config "${BEDROCK_SYNC_VERBOSE:-1}"
