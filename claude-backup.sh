#!/usr/bin/env bash
#
# claude-backup.sh
#
# Backs up the *user-level* Claude Code configuration that makes Claude "know
# you" on a fresh machine, into a destination folder (default:
# ~/Documents/claude-backup, which OneDrive syncs).
#
# What it copies (Tier 1 — config-as-code + your persistent memory):
#   ~/.claude/CLAUDE.md            global instructions
#   ~/.claude/settings.json        global settings (model, hooks, permissions)
#   ~/.claude/keybindings.json     custom keybindings
#   ~/.claude/memory/              global memory facts
#   ~/.claude/commands/            custom slash commands
#   ~/.claude/agents/              custom subagents
#   ~/.claude/skills/              custom skills
#   ~/.claude/projects/*/memory/   per-project memory facts
#
# Deliberately NOT backed up: ~/.claude.json (holds MCP tokens, session history
# and confidential context — re-add MCP servers by hand on the new machine),
# credentials/tokens (re-run `claude login`), caches, transcripts, and other
# regenerable/noisy state.
#
# Idempotent: it mirrors sources to the destination (rsync --delete), so
# re-running just re-syncs — nothing is duplicated. Needs no sudo, edits no
# dotfiles. Written for the stock macOS /bin/bash (3.2) — no bash 4+ features.
#
# Usage:
#   chmod +x claude-backup.sh
#   ./claude-backup.sh                       # -> ~/Documents/claude-backup
#   CLAUDE_BACKUP_DIR=~/some/dir ./claude-backup.sh

set -euo pipefail

SRC="$HOME/.claude"
DEST="${CLAUDE_BACKUP_DIR:-$HOME/Documents/claude-backup}"

# Single files (relative to $SRC) worth restoring.
FILES="CLAUDE.md settings.json keybindings.json"
# Whole directories (relative to $SRC) worth restoring.
DIRS="memory commands agents skills"

# Result trackers (space-delimited; guard empty case when appending).
COPIED=""
SKIPPED=""

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Append an item to a space-delimited list, avoiding a leading space on the
# first entry (keeps the summary tidy under bash 3.2).
append() {
  # $1 = current list value, $2 = item; echoes the new list.
  if [[ -z "$1" ]]; then
    printf '%s' "$2"
  else
    printf '%s %s' "$1" "$2"
  fi
}

# Mirror a directory into the destination, preserving its path under $SRC.
# rsync --delete keeps the backup an exact mirror (prunes files removed at
# the source), which is what makes a re-run idempotent.
copy_dir() {
  # $1 = path relative to $SRC
  if [[ -d "$SRC/$1" ]]; then
    mkdir -p "$DEST/$1"
    rsync -a --delete "$SRC/$1/" "$DEST/$1/"
    log "Synced dir: $1/"
    COPIED="$(append "$COPIED" "$1/")"
  else
    SKIPPED="$(append "$SKIPPED" "$1/")"
  fi
}

copy_file() {
  # $1 = path relative to $SRC
  if [[ -f "$SRC/$1" ]]; then
    mkdir -p "$DEST/$(dirname "$1")"
    cp -p "$SRC/$1" "$DEST/$1"
    log "Copied file: $1"
    COPIED="$(append "$COPIED" "$1")"
  else
    SKIPPED="$(append "$SKIPPED" "$1")"
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS."
[[ -d "$SRC" ]] || die "No Claude config found at $SRC — nothing to back up."
command -v rsync >/dev/null 2>&1 || die "rsync not found (ships with macOS)."

mkdir -p "$DEST"
log "Backing up Claude config from $SRC"
log "Destination: $DEST"

# ---------------------------------------------------------------------------
# 1. Copy single files
# ---------------------------------------------------------------------------
for f in $FILES; do
  copy_file "$f"
done

# ---------------------------------------------------------------------------
# 2. Copy directories
# ---------------------------------------------------------------------------
for d in $DIRS; do
  copy_dir "$d"
done

# ---------------------------------------------------------------------------
# 3. Per-project memory (~/.claude/projects/<name>/memory/)
# ---------------------------------------------------------------------------
# If the glob matches nothing it stays literal, so the -d test skips it.
for m in "$SRC"/projects/*/memory; do
  [[ -d "$m" ]] || continue
  rel="${m#$SRC/}"                     # e.g. projects/<name>/memory
  mkdir -p "$DEST/$rel"
  rsync -a --delete "$m/" "$DEST/$rel/"
  log "Synced project memory: $rel/"
  COPIED="$(append "$COPIED" "$rel/")"
done

# ---------------------------------------------------------------------------
# 4. Restore notes
# ---------------------------------------------------------------------------
cat > "$DEST/RESTORE.md" <<'EOF'
# Claude Code — restore notes

This folder is a backup of user-level Claude Code config (`~/.claude/`),
produced by `claude-backup.sh`. To restore on a new machine:

1. Install Claude Code, then run `claude login` to re-authenticate.
   (Credentials/tokens are intentionally NOT in this backup.)
2. Copy the files/dirs here back into `~/.claude/` (same relative paths):
   CLAUDE.md, settings.json, keybindings.json, memory/, commands/, agents/,
   skills/, and projects/<name>/memory/.
3. Re-add your MCP servers by hand (they are NOT in this backup — they live in
   ~/.claude.json, which is deliberately excluded). Use `claude mcp add ...`
   or reconnect them from the app.
4. Review settings.json before trusting it: an `env` block or hook command
   may contain a secret you'll want to rotate rather than reuse.

NOTE: This backup can contain personal and work context (memory, instructions).
Keep it in an approved private location only.
EOF
date > "$DEST/last-backup.txt"

# ---------------------------------------------------------------------------
# 5. Secret scan (warn only — never blocks the backup)
# ---------------------------------------------------------------------------
log "Scanning backup for likely secrets..."
PATTERN='(sk-[A-Za-z0-9]{10,}|ghp_[A-Za-z0-9]{20,}|gho_[A-Za-z0-9]{20,}|xox[baprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|-----BEGIN [A-Z ]*PRIVATE KEY-----|eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}|(token|secret|password|api[_-]?key|authorization)"?[[:space:]]*[:=])'
HITS="$(grep -rIEn "$PATTERN" "$DEST" 2>/dev/null || true)"
if [[ -n "$HITS" ]]; then
  warn "Possible secrets found in the backup — review before it syncs:"
  printf '%s\n' "$HITS"
  warn "Redact/rotate anything real before it syncs."
else
  log "No obvious secrets matched."
fi

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
printf '\n'
log "Backed up:  ${COPIED:-(none)}"
log "Not present:${SKIPPED:+ $SKIPPED}"
log "Location:   $DEST"

# ---------------------------------------------------------------------------
# 7. Automation hint (interactive runs only — keeps scheduled logs clean)
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
  if [[ -x "$SELF_DIR/claude-backup-schedule.sh" ]]; then
    printf '\n'
    log "To run this automatically every few hours (launchd):"
    printf '      %s 6      # hours between runs (default 6)\n' "$SELF_DIR/claude-backup-schedule.sh"
  fi
fi
