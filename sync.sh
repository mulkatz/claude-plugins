#!/usr/bin/env bash
set -euo pipefail

# Syncs plugin files from source repos into the marketplace.
# Run this after updating a plugin to keep the marketplace current.
#
# Usage: ./sync.sh [plugin-name]
#   ./sync.sh          # sync all plugins
#   ./sync.sh spark    # sync spark only
#   ./sync.sh anvil    # sync anvil only

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PLUGINS_DIR="$SCRIPT_DIR/plugins"

# Plugin source repos (relative to parent of this repo)
declare -A SOURCES=(
  [anvil]="$SCRIPT_DIR/../anvil"
  [spark]="$SCRIPT_DIR/../spark"
)

# Directories to sync (only what the plugin needs at runtime)
SYNC_DIRS=(.claude-plugin commands hooks prompts scripts)
SYNC_FILES=(CLAUDE.md)

sync_plugin() {
  local name="$1"
  local source="${SOURCES[$name]}"
  local target="$PLUGINS_DIR/$name"

  if [[ ! -d "$source" ]]; then
    echo "ERROR: Source repo not found: $source" >&2
    return 1
  fi

  echo "Syncing $name from $source..."

  # Clean target
  rm -rf "$target"
  mkdir -p "$target"

  # Copy directories
  for dir in "${SYNC_DIRS[@]}"; do
    if [[ -d "$source/$dir" ]]; then
      cp -R "$source/$dir" "$target/"
    fi
  done

  # Copy individual files
  for file in "${SYNC_FILES[@]}"; do
    if [[ -f "$source/$file" ]]; then
      cp "$source/$file" "$target/"
    fi
  done

  echo "  Done. $(find "$target" -type f | wc -l | tr -d ' ') files synced."
}

# Determine which plugins to sync
if [[ $# -eq 0 ]]; then
  plugins=("${!SOURCES[@]}")
else
  plugins=("$@")
fi

for plugin in "${plugins[@]}"; do
  if [[ -z "${SOURCES[$plugin]+x}" ]]; then
    echo "ERROR: Unknown plugin: $plugin" >&2
    echo "Available: ${!SOURCES[*]}" >&2
    exit 1
  fi
  sync_plugin "$plugin"
done

echo ""
echo "Sync complete. Don't forget to commit and push."
