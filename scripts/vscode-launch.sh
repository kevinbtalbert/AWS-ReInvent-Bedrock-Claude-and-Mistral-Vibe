#!/usr/bin/env bash
# CML editor entrypoint.
# Apply global environment variables to Mistral Vibe and Claude/Bedrock, then start code-server.
set -Eeuo pipefail

if [[ -f /usr/local/bin/configure-vibe-from-env ]]; then
  # shellcheck source=/dev/null
  source /usr/local/bin/configure-vibe-from-env \
    || echo "WARN: Mistral Vibe config failed; VS Code will still start." >&2
fi

if [[ -x /usr/local/bin/configure-bedrock-from-env ]]; then
  /usr/local/bin/configure-bedrock-from-env \
    || echo "WARN: Claude/Bedrock startup failed; VS Code will still start." >&2
fi

export VIBE_HOME="${VIBE_HOME:-${HOME}/.vibe}"
export MISTRAL_API_KEY="${MISTRAL_API_KEY:-${VIBE_API_KEY:-}}"
export MISTRAL_VIBE_ACTIVE_MODEL="${MISTRAL_MODEL:-${MISTRAL_VIBE_ACTIVE_MODEL:-codestral}}"
export MISTRAL_MODEL="${MISTRAL_VIBE_ACTIVE_MODEL}"

# Ignore short-lived AWS tokens if they are also present. Bedrock uses the key pair.
unset AWS_BEARER_TOKEN_BEDROCK AWS_SESSION_TOKEN

CODE_SERVER_BIND="${CODE_SERVER_BIND:-127.0.0.1:8090}"
exec /usr/bin/code-server --auth=none --bind-addr="${CODE_SERVER_BIND}" --disable-telemetry "$@"
