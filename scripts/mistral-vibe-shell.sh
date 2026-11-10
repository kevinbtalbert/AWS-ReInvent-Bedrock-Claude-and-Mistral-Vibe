# Global or project env -> ~/.vibe/ for the Mistral Vibe CLI and VS Code extension.
if [[ -f /usr/local/bin/configure-vibe-from-env ]]; then
  # shellcheck source=/dev/null
  source /usr/local/bin/configure-vibe-from-env || true
fi
