#!/usr/bin/env bash
# Resolve mistral-vibe executables for cdsw and symlink into /usr/local/bin.
set -Eeuo pipefail

target_user="${1:-cdsw}"
home_dir="$(getent passwd "${target_user}" | cut -d: -f6)"

if [[ -z "${home_dir}" || ! -d "${home_dir}" ]]; then
  echo "link-vibe-cli: unknown user ${target_user}" >&2
  exit 1
fi

find_vibe_bin() {
  su "${target_user}" -s /bin/bash -c '
    set -Eeuo pipefail
    export PATH="${HOME}/.local/bin:${PATH}"
    if command -v uv >/dev/null 2>&1; then
      uv_bin="$(uv tool dir --bin 2>/dev/null || true)"
      if [[ -n "${uv_bin}" ]]; then
        export PATH="${uv_bin}:${PATH}"
      fi
    fi
    command -v vibe
  '
}

vibe_bin="$(find_vibe_bin || true)"
if [[ -z "${vibe_bin}" || ! -x "${vibe_bin}" ]]; then
  echo "link-vibe-cli: vibe not found for ${target_user}; install mistral-vibe first" >&2
  exit 1
fi

ln -sf "${vibe_bin}" /usr/local/bin/vibe
echo "Linked vibe -> ${vibe_bin}"

vibe_acp_src="$(dirname "${vibe_bin}")/vibe-acp"
if [[ -x "${vibe_acp_src}" ]]; then
  ln -sf "${vibe_acp_src}" /usr/local/bin/vibe-acp
  echo "Linked vibe-acp -> ${vibe_acp_src}"
fi
