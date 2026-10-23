#!/usr/bin/env bash
# Copy the Obsidian vault (source of truth in Google Drive) into vault/ before pushing the documentation PR.
# Usage: scripts/sync_vault.sh [path-to-vault]
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
# default: the vault in the first Google Drive account folder (the account name is not written into the repo)
drive_root="$(ls -d "$HOME"/Library/CloudStorage/GoogleDrive-*/"My Drive" 2>/dev/null | head -n 1)"
vault_src="${1:-$drive_root/Learning/enpal_assessment_vault}"
vault_dst="$repo_root/vault"

# mirror the vault; skip per-machine Obsidian state, OS files and the personal learning notes (wiki/ stays in Drive only)
rsync -a --delete \
    --exclude '.obsidian/workspace*.json' \
    --exclude '.obsidian/cache' \
    --exclude '.trash/' \
    --exclude '.DS_Store' \
    --exclude 'wiki/' \
    "$vault_src/" "$vault_dst/"

# the repo is public: replace the local Drive path (it contains the personal account) with a neutral prefix,
# in any form: /Users/<name>/Library/CloudStorage/GoogleDrive-<account>/My Drive or ~/Library/CloudStorage/...
grep -rlE 'CloudStorage/GoogleDrive-[^/]+' "$vault_dst" | while IFS= read -r f; do
    perl -pi -e 's#(?:/Users/[^/]+|~)/Library/CloudStorage/GoogleDrive-[^/]+/My Drive#~/GoogleDrive#g' "$f"
done

echo "synced $vault_src -> $vault_dst"
