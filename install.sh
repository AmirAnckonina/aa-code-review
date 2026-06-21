#!/usr/bin/env bash
# aa-code-review installer — symlinks agents/skills/commands into ~/.claude/.
#
# Edits in this repo land instantly in your Claude config via the symlinks,
# so there is no separate build or sync step.
#
# Idempotent: re-running is safe. Existing symlinks pointing at our targets
# are skipped; any other file/symlink at the destination triggers an abort.
#
# Set CLAUDE_HOME to override the default of ~/.claude.

set -euo pipefail
shopt -s nullglob

readonly SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
readonly CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"
readonly KINDS=(agents skills commands)
readonly PERMISSION_RULES=(
  'Read(~/.claude/skills/aa-*/**)'
  'Read(~/.claude/agents/aa-*)'
)

link_one() {
  local src="$1" dest="$2"
  if [[ -L "$dest" && "$(readlink "$dest")" == "$src" ]]; then
    echo "  = $dest (already linked)"
    return 0
  fi
  if [[ -e "$dest" || -L "$dest" ]]; then
    echo "  ! $dest exists and is not our symlink — aborting." >&2
    exit 1
  fi
  ln -s "$src" "$dest"
  echo "  + $dest -> $src"
}

# merge_permissions adds the package's required Read allow-rules to
# ~/.claude/settings.json. Idempotent: the jq `unique` filter dedupes
# on re-run. Falls back to a printed instruction if jq is unavailable.
merge_permissions() {
  local settings="$CLAUDE_HOME/settings.json"

  if ! command -v jq &>/dev/null; then
    echo "[aa-code-review] jq not found — add these allow-rules manually to $settings under .permissions.allow:" >&2
    printf '  - %s\n' "${PERMISSION_RULES[@]}" >&2
    return 0
  fi

  if [[ ! -f "$settings" ]]; then
    echo '{}' > "$settings"
  fi

  local rules_json
  rules_json=$(printf '%s\n' "${PERMISSION_RULES[@]}" | jq -R . | jq -s .)

  local tmp; tmp="$(mktemp)"
  jq --argjson rules "$rules_json" \
    '.permissions = (.permissions // {}) | .permissions.allow = ((.permissions.allow // []) + $rules | unique)' \
    "$settings" > "$tmp"
  mv "$tmp" "$settings"

  echo "[aa-code-review] permissions merged into $settings"
  printf '  + %s\n' "${PERMISSION_RULES[@]}"
}

main() {
  echo "[aa-code-review] installing into $CLAUDE_HOME"
  for kind in "${KINDS[@]}"; do
    mkdir -p "$CLAUDE_HOME/$kind"
    for entry in "$SCRIPT_DIR/$kind"/*; do
      local name; name="$(basename -- "$entry")"
      [[ "$name" == ".gitkeep" ]] && continue
      link_one "$entry" "$CLAUDE_HOME/$kind/$name"
    done
  done
  merge_permissions
  echo "[aa-code-review] done."
}

main "$@"
