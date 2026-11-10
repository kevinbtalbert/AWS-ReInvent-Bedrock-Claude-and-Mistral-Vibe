# Cloudera ML runtime for AWS re:Invent
# Browser VS Code (code-server) with both:
#   - Claude Code (CLI + VS Code extension) → LiteLLM → Amazon Bedrock
#   - Mistral Vibe (CLI + VS Code extension), default model codestral
#
# Do not bake credentials into the image. Set them as Cloudera AI global
# environment variables: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY,
# MISTRAL_API_URL, MISTRAL_API_KEY, and MISTRAL_MODEL.
# Claude also needs BEDROCK_MODEL and AWS_REGION.
FROM --platform=linux/amd64 docker.repository.cloudera.com/cloudera/cdsw/ml-runtime-pbj-workbench-python3.13-standard:2026.08.1-b5

# Catalog version is 1.1.1. Bump ML_RUNTIME_MAINTENANCE_VERSION to iterate (1.1.2, ...).
# That version is independent of code-server and of the Claude / Mistral extension versions.
ARG CODE_SERVER_VERSION=4.141.0
ARG MISTRAL_VIBE_EXTENSION_VERSION=1.27.5
ARG CLAUDE_CODE_EXTENSION_VERSION=2.1.322

USER root

# ── System dependencies ─────────────────────────────────────────────────────
RUN apt-get update && apt-get install -y --no-install-recommends \
        vim nano curl wget less tree jq unzip zip git ca-certificates \
        ripgrep fd-find bat netcat-openbsd dnsutils iputils-ping \
        pciutils htop procps lsof \
        ssh-client rsync socat \
    && rm -rf /var/lib/apt/lists/* \
    && ln -sf /usr/bin/fdfind /usr/local/bin/fd \
    && ln -sf /usr/bin/batcat /usr/local/bin/bat

# ── code-server (browser VS Code) ───────────────────────────────────────────
# Pattern from https://github.com/cloudera/community-ml-runtimes/tree/main/vscode
RUN curl -fsSL https://code-server.dev/install.sh | sh -s -- --version "${CODE_SERVER_VERSION}"

COPY scripts/vscode-launch.sh /usr/local/bin/vscode
COPY scripts/configure-vibe-from-env.sh /usr/local/bin/configure-vibe-from-env
COPY scripts/configure-bedrock-from-env.sh /usr/local/bin/configure-bedrock-from-env
COPY scripts/link-vibe-cli.sh /usr/local/bin/link-vibe-cli
COPY scripts/install-mistral-vibe-cli.sh /usr/local/bin/install-mistral-vibe-cli
COPY scripts/install-vscode-extension.sh /usr/local/bin/install-vscode-extension
COPY scripts/mistral-vibe-shell.sh /etc/profile.d/mistral-vibe.sh
COPY scripts/bedrock-runtime-startup.sh /etc/profile.d/zz-claude-bedrock.sh
COPY scripts/lib/bedrock-common.sh /opt/bedrock-claude/lib/bedrock-common.sh
COPY scripts/verify-litellm-install.sh /opt/bedrock-claude/verify-litellm-install.sh
COPY requirements-litellm.txt /opt/bedrock-claude/requirements-litellm.txt

RUN chmod +x /usr/local/bin/vscode \
      /usr/local/bin/configure-vibe-from-env \
      /usr/local/bin/configure-bedrock-from-env \
      /usr/local/bin/link-vibe-cli \
      /usr/local/bin/install-mistral-vibe-cli \
      /usr/local/bin/install-vscode-extension \
      /etc/profile.d/zz-claude-bedrock.sh \
      /opt/bedrock-claude/lib/bedrock-common.sh \
      /opt/bedrock-claude/verify-litellm-install.sh && \
    ln -sf /usr/local/bin/vscode /usr/local/bin/ml-runtime-editor && \
    mkdir -p /home/cdsw/.local/share/code-server/User \
             /home/cdsw/.vibe/logs/session \
             /home/cdsw/.claude/bedrock \
             /opt/bedrock-claude/lib && \
    if ! grep -q 'reinvent-runtime-shell' /home/cdsw/.bashrc 2>/dev/null; then \
      printf '%s\n' \
        '# reinvent-runtime-shell' \
        '[ -f /etc/profile.d/mistral-vibe.sh ] && . /etc/profile.d/mistral-vibe.sh' \
        '[ -f /etc/profile.d/zz-claude-bedrock.sh ] && . /etc/profile.d/zz-claude-bedrock.sh' \
        >> /home/cdsw/.bashrc; \
    fi && \
    chown -R cdsw:cdsw /home/cdsw

# ── Node.js 22 (Claude Code's npm package asks for >= 22; the claude binary does not use it at runtime) ─
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
    apt-get install -y nodejs && \
    rm -rf /var/lib/apt/lists/*

# ── Claude Code CLI (integrated terminal; the extension bundles its own binary) ─
RUN npm install -g @anthropic-ai/claude-code \
    && command -v claude >/dev/null

# ── LiteLLM proxy (Anthropic API → AWS Bedrock) ────────────────────────────────
RUN python3 -m venv /opt/bedrock-claude/venv && \
    /opt/bedrock-claude/venv/bin/pip install --no-cache-dir --upgrade pip wheel packaging && \
    /opt/bedrock-claude/venv/bin/pip install --no-cache-dir -r /opt/bedrock-claude/requirements-litellm.txt && \
    SKIP_LITELLM_SMOKE=1 /opt/bedrock-claude/verify-litellm-install.sh /opt/bedrock-claude/venv

# ── Mistral Vibe CLI ──────────────────────────────────────────────────────────
RUN /usr/local/bin/install-mistral-vibe-cli

ENV PATH="/usr/local/bin:${PATH}" \
    VIBE_HOME="/home/cdsw/.vibe" \
    MISTRAL_VIBE_ACTIVE_MODEL="codestral" \
    CODE_SERVER_BIND="127.0.0.1:8090" \
    BEDROCK_HOME="/home/cdsw/.claude/bedrock" \
    BEDROCK_VENV_BIN="/opt/bedrock-claude/venv/bin" \
    BEDROCK_LITELLM_PORT="4000" \
    BEDROCK_MAX_OUTPUT_TOKENS="8192" \
    BEDROCK_MAX_INPUT_TOKENS="192000"

ARG ML_RUNTIME_SHORT_VERSION=1.1
ARG ML_RUNTIME_MAINTENANCE_VERSION=1

ENV ML_RUNTIME_EDITION="re:Invent VS Code + Claude Bedrock + Mistral Vibe" \
    ML_RUNTIME_EDITOR="VsCode" \
    ML_RUNTIME_KERNEL="Python 3.13" \
    ML_RUNTIME_SHORT_VERSION="${ML_RUNTIME_SHORT_VERSION}" \
    ML_RUNTIME_MAINTENANCE_VERSION="${ML_RUNTIME_MAINTENANCE_VERSION}" \
    ML_RUNTIME_FULL_VERSION="${ML_RUNTIME_SHORT_VERSION}.${ML_RUNTIME_MAINTENANCE_VERSION}" \
    ML_RUNTIME_DESCRIPTION="Browser VS Code with Claude Code on AWS Bedrock and Mistral Vibe (Codestral). Extensions preinstalled. Credentials from global environment variables."

RUN set -eux; \
    test "${ML_RUNTIME_FULL_VERSION}" = "${ML_RUNTIME_SHORT_VERSION}.${ML_RUNTIME_MAINTENANCE_VERSION}"; \
    echo "Cloudera ML runtime version (tag images as): ${ML_RUNTIME_FULL_VERSION}"

LABEL com.cloudera.ml.runtime.edition=$ML_RUNTIME_EDITION \
      com.cloudera.ml.runtime.full-version=$ML_RUNTIME_FULL_VERSION \
      com.cloudera.ml.runtime.short-version=$ML_RUNTIME_SHORT_VERSION \
      com.cloudera.ml.runtime.maintenance-version=$ML_RUNTIME_MAINTENANCE_VERSION \
      com.cloudera.ml.runtime.description=$ML_RUNTIME_DESCRIPTION \
      com.cloudera.ml.runtime.editor=$ML_RUNTIME_EDITOR

WORKDIR /home/cdsw
USER cdsw

# ── Extensions baked into the runtime (not installed by the attendee) ────────
# https://marketplace.visualstudio.com/items?itemName=anthropic.claude-code
# https://marketplace.visualstudio.com/items?itemName=mistralai.mistral-vibe-code
ARG MISTRAL_VIBE_EXTENSION_VERSION=1.27.5
ARG CLAUDE_CODE_EXTENSION_VERSION=2.1.322
RUN /usr/local/bin/install-vscode-extension anthropic.claude-code "${CLAUDE_CODE_EXTENSION_VERSION}" \
    && /usr/local/bin/install-vscode-extension mistralai.mistral-vibe-code "${MISTRAL_VIBE_EXTENSION_VERSION}"

COPY --chown=cdsw:cdsw config/code-server-settings.json /home/cdsw/.local/share/code-server/User/settings.json
