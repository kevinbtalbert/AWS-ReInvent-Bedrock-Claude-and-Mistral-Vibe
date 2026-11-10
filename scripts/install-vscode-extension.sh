#!/usr/bin/env bash
# Download a VSIX from the Visual Studio Marketplace and install it into code-server.
# Usage: install-vscode-extension.sh <publisher.extension> <version> [targetPlatform]
# The runtime image is linux/amd64, so the default platform is linux-x64 (not a universal VSIX).
set -Eeuo pipefail

ext_id="${1:?extension id (publisher.name)}"
version="${2:?extension version}"
platform="${3:-linux-x64}"
name="${ext_id#*.}"
dest="/tmp/${name}-${version}-${platform}.vsix"

echo "[install-vscode-extension] ${ext_id}@${version} (${platform})"

payload="$(jq -n --arg id "${ext_id}" \
  '{filters:[{criteria:[{filterType:7,value:$id}],pageNumber:1,pageSize:1}],assetTypes:["Microsoft.VisualStudio.Services.VSIXPackage"],flags:131}')"

vsix_url="$(curl -fsSL "https://marketplace.visualstudio.com/_apis/public/gallery/extensionquery" \
  -H "Content-Type: application/json" \
  -H "Accept: application/json;api-version=7.1-preview.1" \
  -d "${payload}" \
  | jq -r --arg ver "${version}" --arg platform "${platform}" '
      def vsix($ver; $platform):
        .results[0].extensions[0].versions[]
        | select(.version == $ver)
        | select((.targetPlatform // "") == $platform)
        | .files[]
        | select(.assetType == "Microsoft.VisualStudio.Services.VSIXPackage")
        | .source;
      ([vsix($ver; $platform)][0] // [vsix($ver; "")][0] // empty)
    ')"

if [[ -z "${vsix_url}" || "${vsix_url}" == "null" ]]; then
  echo "[install-vscode-extension] ERROR: no VSIX for ${ext_id}@${version}" >&2
  exit 1
fi

cs_args=()
if [[ -n "${CODE_SERVER_EXTENSIONS_DIR:-}" ]]; then
  mkdir -p "${CODE_SERVER_EXTENSIONS_DIR}"
  cs_args+=(--extensions-dir "${CODE_SERVER_EXTENSIONS_DIR}")
fi
if [[ -n "${CODE_SERVER_USER_DATA_DIR:-}" ]]; then
  mkdir -p "${CODE_SERVER_USER_DATA_DIR}"
  cs_args+=(--user-data-dir "${CODE_SERVER_USER_DATA_DIR}")
fi

curl -fsSL "${vsix_url}" -o "${dest}"
code-server "${cs_args[@]}" --install-extension "${dest}"
rm -f "${dest}"

found=0
while IFS= read -r line; do
  case "${line}" in
    "${ext_id}" | "${ext_id}@"*) found=1 ;;
  esac
done < <(code-server "${cs_args[@]}" --list-extensions || true)
if [[ "${found}" -ne 1 ]]; then
  echo "[install-vscode-extension] ERROR: ${ext_id} is not listed after install" >&2
  code-server "${cs_args[@]}" --list-extensions >&2 || true
  exit 1
fi
echo "[install-vscode-extension] installed ${ext_id}@${version}"
