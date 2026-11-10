#!/usr/bin/env bash
# Apply global AWS credentials and per-tier Bedrock model ids for Claude Code.
# Safe to source from the editor entrypoint so the exports reach code-server.
export BEDROCK_HOME="${BEDROCK_HOME:-${HOME}/.claude/bedrock}"
mkdir -p "${BEDROCK_HOME}" "${HOME}/.claude"

# shellcheck disable=SC1091
source /opt/bedrock-claude/lib/bedrock-common.sh
bedrock_apply_config "${BEDROCK_SYNC_VERBOSE:-1}"
