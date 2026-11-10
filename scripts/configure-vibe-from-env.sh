#!/usr/bin/env bash
# Map Cloudera AI global (site) or project environment variables into Vibe config.
# Sourced by the editor entrypoint and interactive shells — do not enable set -e.

# On Cloudera AI, /home/cdsw is the project mount — keep all Vibe state there so
# chat history survives closing the panel or starting a new workbench session.
VIBE_HOME="${VIBE_HOME:-${HOME}/.vibe}"
export VIBE_HOME
mkdir -p "${VIBE_HOME}/logs/session"

# Global environment variables for re:Invent (canonical names), plus aliases.
# MISTRAL_MODEL is the "Mistral model" value. When set, it overrides the image default.
MISTRAL_API_KEY="${MISTRAL_API_KEY:-${VIBE_API_KEY:-}}"
MISTRAL_API_URL="${MISTRAL_API_URL:-${MISTRAL_API_ADDRESS:-${VIBE_API_URL:-${MISTRAL_API_BASE:-}}}}"
MISTRAL_CONSOLE_URL="${MISTRAL_CONSOLE_URL:-${MISTRAL_CONSOLE_BASE_URL:-${VIBE_CONSOLE_URL:-}}}"
if [[ -n "${MISTRAL_MODEL:-}" ]]; then
  MISTRAL_VIBE_ACTIVE_MODEL="${MISTRAL_MODEL}"
else
  MISTRAL_VIBE_ACTIVE_MODEL="${MISTRAL_VIBE_ACTIVE_MODEL:-${VIBE_ACTIVE_MODEL:-codestral}}"
fi
if [[ -n "${MISTRAL_API_URL}" ]]; then
  export MISTRAL_API_URL
fi
export MISTRAL_VIBE_ACTIVE_MODEL
export MISTRAL_MODEL="${MISTRAL_VIBE_ACTIVE_MODEL}"
export VIBE_ACTIVE_MODEL="${MISTRAL_VIBE_ACTIVE_MODEL}"

if [[ -n "${MISTRAL_API_KEY}" ]]; then
  export MISTRAL_API_KEY
fi

# Map friendly alias -> Mistral API model id for [[models]].name (see Mistral model docs).
resolve_model_api_id() {
  case "$1" in
    glm-5-3 | zai-glm-5-3) echo "zai-glm-5-3" ;;
    glm-5-2 | zai-glm-5-2) echo "zai-glm-5-2" ;;
    codestral | codestral-latest) echo "codestral-latest" ;;
    codestral-2508) echo "codestral-2508" ;;
    mistral-small-4 | mistral-small-latest) echo "mistral-small-latest" ;;
    mistral-large-4 | mistral-large-latest) echo "mistral-large-latest" ;;
    mistral-large-4-0-3) echo "mistral-large-4-0-3" ;;
    devstral-2512) echo "devstral-2512" ;;
    *) echo "$1" ;;
  esac
}

# Write sed output to a temp file. GNU sed -i is not required (image sed is GNU; this also works on BSD for substitutions).
sed_edit() {
  local file="$1"
  shift
  local tmp="${file}.sed.$$"
  sed "$@" "${file}" >"${tmp}" && mv "${tmp}" "${file}"
}

ensure_model_preset() {
  local alias="$1"
  local api_id
  api_id="$(resolve_model_api_id "${alias}")"
  config_file="${VIBE_HOME}/config.toml"
  touch "${config_file}"
  if grep -q "^alias = \"${alias}\"" "${config_file}" 2>/dev/null; then
    return 0
  fi
  cat >>"${config_file}" <<EOF

[[models]]
name = "${api_id}"
provider = "mistral"
alias = "${alias}"
EOF
}

if [[ -n "${MISTRAL_API_URL}" || -n "${MISTRAL_CONSOLE_URL}" ]]; then
  api_base=""
  if [[ -n "${MISTRAL_API_URL}" ]]; then
    api_base="${MISTRAL_API_URL%/}"
  fi
  console_url=""
  if [[ -n "${MISTRAL_CONSOLE_URL}" ]]; then
    console_url="${MISTRAL_CONSOLE_URL%/}"
  fi
  config_file="${VIBE_HOME}/config.toml"

  if [[ ! -f "${config_file}" ]]; then
    cat >"${config_file}" <<EOF
# Generated at session start from global environment.
EOF
    if [[ -n "${MISTRAL_VIBE_ACTIVE_MODEL}" ]]; then
      printf 'active_model = "%s"\n' "${MISTRAL_VIBE_ACTIVE_MODEL}" >>"${config_file}"
    fi
    if [[ -n "${console_url}" ]]; then
      printf 'browser_auth_base_url = "%s"\n' "${console_url}" >>"${config_file}"
    fi
    if [[ -n "${api_base}" ]]; then
      cat >>"${config_file}" <<EOF

[[providers]]
name = "mistral"
backend = "mistral"
api_style = "openai"
api_base = "${api_base}"
api_key_env_var = "MISTRAL_API_KEY"
EOF
    fi
  else
    if [[ -n "${api_base}" ]]; then
      if grep -q '^name = "mistral"' "${config_file}" 2>/dev/null; then
        if grep -q '^api_base = ' "${config_file}"; then
          sed_edit "${config_file}" "s|^api_base = .*|api_base = \"${api_base}\"|"
        else
          sed_edit "${config_file}" "/^name = \"mistral\"/a api_base = \"${api_base}\""
        fi
      else
        cat >>"${config_file}" <<EOF

[[providers]]
name = "mistral"
backend = "mistral"
api_style = "openai"
api_base = "${api_base}"
api_key_env_var = "MISTRAL_API_KEY"
EOF
      fi
    fi
    if [[ -n "${console_url}" ]]; then
      if grep -q '^browser_auth_base_url = ' "${config_file}"; then
        sed_edit "${config_file}" "s|^browser_auth_base_url = .*|browser_auth_base_url = \"${console_url}\"|"
      else
        sed_edit "${config_file}" "1a browser_auth_base_url = \"${console_url}\""
      fi
    fi
  fi
fi

config_file="${VIBE_HOME}/config.toml"
touch "${config_file}"
if grep -q '^active_model = "devstral-2512"' "${config_file}"; then
  sed_edit "${config_file}" '/^active_model = "devstral-2512"/d'
fi
if grep -q '^active_model = ' "${config_file}"; then
  sed_edit "${config_file}" "s|^active_model = .*|active_model = \"${MISTRAL_VIBE_ACTIVE_MODEL}\"|"
else
  active_tmp="${config_file}.active.$$"
  {
    printf 'active_model = "%s"\n' "${MISTRAL_VIBE_ACTIVE_MODEL}"
    cat "${config_file}"
  } >"${active_tmp}"
  mv "${active_tmp}" "${config_file}"
fi
ensure_model_preset "${MISTRAL_VIBE_ACTIVE_MODEL}"

if [[ -n "${MISTRAL_API_KEY}" ]]; then
  env_file="${VIBE_HOME}/.env"
  tmp_file="${env_file}.tmp.$$"
  if [[ -f "${env_file}" ]]; then
    grep -v '^MISTRAL_API_KEY=' "${env_file}" >"${tmp_file}" || true
  else
    : >"${tmp_file}"
  fi
  printf 'MISTRAL_API_KEY=%s\n' "${MISTRAL_API_KEY}" >>"${tmp_file}"
  mv "${tmp_file}" "${env_file}"
  chmod 600 "${env_file}" 2>/dev/null || true
fi
