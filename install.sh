#!/usr/bin/env bash
#
# Install the solana-zk-verifier skill into a project that uses the Solana AI Kit.
#
# This is a DOCUMENTATION-ONLY skill: the script copies Markdown files into
# <target>/.claude/skills/ext/solana-zk-verifier. It runs no executables, makes no
# network calls, and needs no sudo. Read it before running it.
#
# Usage:
#   ./install.sh [TARGET_PROJECT_DIR]   # defaults to the current directory
#
set -euo pipefail

SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:-$PWD}"
DEST="$TARGET/.claude/skills/ext/solana-zk-verifier"

if [ ! -d "$TARGET" ]; then
  echo "error: target directory '$TARGET' does not exist" >&2
  exit 1
fi

mkdir -p "$DEST"
cp -R "$SRC/skill"    "$DEST/"
cp -R "$SRC/commands" "$DEST/"
cp    "$SRC/README.md" "$DEST/"
cp    "$SRC/LICENSE"   "$DEST/"

echo "Installed solana-zk-verifier -> $DEST"
echo
echo "Next steps:"
echo "  1. Add the object in '$SRC/skill-registry-entry.json' to the \"entries\" array of"
echo "     $TARGET/.claude/skills/skill-registry.json"
echo "  2. Start a new Claude Code session. The skill loads via skill/SKILL.md and routes"
echo "     ZK-on-Solana questions to the right focus file."
