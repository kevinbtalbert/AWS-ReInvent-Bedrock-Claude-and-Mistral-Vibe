#!/usr/bin/env bash
# Install Mistral Vibe CLI so `vibe` is always /usr/local/bin/vibe for session user cdsw.
set -Eeuo pipefail

log() { echo "[install-mistral-vibe-cli] $*"; }

symlink_vibe() {
  local vibe_bin vibe_acp
  vibe_bin="$(command -v vibe 2>/dev/null || true)"
  if [[ -z "${vibe_bin}" ]]; then
    vibe_bin="$(python3 -c "import shutil; print(shutil.which('vibe') or '')" 2>/dev/null || true)"
  fi
  if [[ -z "${vibe_bin}" || ! -x "${vibe_bin}" ]]; then
    return 1
  fi
  ln -sf "${vibe_bin}" /usr/local/bin/vibe
  log "vibe -> ${vibe_bin}"
  vibe_acp="$(dirname "${vibe_bin}")/vibe-acp"
  if [[ -x "${vibe_acp}" ]]; then
    ln -sf "${vibe_acp}" /usr/local/bin/vibe-acp
    log "vibe-acp -> ${vibe_acp}"
  fi
  return 0
}

install_with_pip() {
  log "Installing mistral-vibe with pip (python3 -m pip install mistral-vibe)"
  if python3 -m pip install --no-cache-dir mistral-vibe; then
    return 0
  fi
  log "Retrying pip with --break-system-packages"
  python3 -m pip install --no-cache-dir --break-system-packages mistral-vibe
}

install_with_official_script() {
  local cdsw_home
  cdsw_home="$(getent passwd cdsw | cut -d: -f6)"
  log "Installing mistral-vibe via https://mistral.ai/vibe/install.sh (user cdsw)"
  su cdsw -s /bin/bash -c 'curl -LsSf https://mistral.ai/vibe/install.sh | bash'
  if [[ -x /usr/local/bin/link-vibe-cli ]]; then
    /usr/local/bin/link-vibe-cli cdsw
  elif [[ -n "${cdsw_home}" ]]; then
    export PATH="${cdsw_home}/.local/bin:${PATH}"
    if command -v uv >/dev/null 2>&1; then
      export PATH="$(su cdsw -s /bin/bash -c 'uv tool dir --bin' 2>/dev/null || true):${PATH}"
    fi
    symlink_vibe || true
  fi
}

if symlink_vibe; then
  log "vibe already on PATH"
elif install_with_pip && symlink_vibe; then
  log "pip install succeeded"
else
  install_with_official_script
fi

if ! /usr/local/bin/vibe --version; then
  log "ERROR: vibe is not runnable after install" >&2
  exit 1
fi

log "OK: $(command -v vibe) ($(vibe --version 2>&1 | head -1))"
