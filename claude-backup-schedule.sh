#!/usr/bin/env bash
#
# claude-backup-schedule.sh
#
# Schedules claude-backup.sh to run automatically via a per-user launchd
# LaunchAgent. Full lifecycle in one script:
#
#   ./claude-backup-schedule.sh [HOURS]   install or change (default 6 hours)
#   ./claude-backup-schedule.sh status    show whether it's scheduled + interval
#   ./claude-backup-schedule.sh uninstall remove the schedule
#
# Changing the cadence is just re-running with a different number — it
# overwrites the plist and reloads, so there's no separate "change" command.
#
# The agent runs the sibling claude-backup.sh every HOURS hours, logging to
# ~/Library/Logs/claude-backup.log. It honors CLAUDE_BACKUP_DIR (baked into the
# plist so scheduled runs use the same destination as manual runs).
#
# Needs no sudo (a per-user LaunchAgent lives under ~/Library/LaunchAgents) and
# edits no dotfiles. Idempotent: re-running install just re-syncs the plist.
# Written for the stock macOS /bin/bash (3.2) — no bash 4+ features are used.

set -euo pipefail

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Preconditions + shared paths
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS (launchd)."
command -v launchctl >/dev/null 2>&1 || die "launchctl not found."

SELF_DIR="$(cd "$(dirname "$0")" && pwd)"
BACKUP_SCRIPT="$SELF_DIR/claude-backup.sh"
[[ -x "$BACKUP_SCRIPT" ]] || die "Expected an executable claude-backup.sh next to this script at $BACKUP_SCRIPT"

LABEL="com.$(id -un).claude-backup"
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
LOG="$HOME/Library/Logs/claude-backup.log"

# ---------------------------------------------------------------------------
# 1. Dispatch on the first argument
# ---------------------------------------------------------------------------
ACTION="${1:-}"

if [[ "$ACTION" == "uninstall" ]]; then
  launchctl unload "$PLIST" 2>/dev/null || true
  if [[ -f "$PLIST" ]]; then
    rm -f "$PLIST"
    log "Removed schedule: $PLIST"
  else
    log "No schedule was installed — nothing to remove."
  fi
  exit 0
fi

if [[ "$ACTION" == "status" ]]; then
  if launchctl list 2>/dev/null | grep -q "$LABEL"; then
    log "Scheduled: yes (agent $LABEL is loaded)."
  else
    log "Scheduled: no (agent $LABEL is not loaded)."
  fi
  if [[ -f "$PLIST" ]]; then
    SECS="$(plutil -extract StartInterval raw "$PLIST" 2>/dev/null || echo '')"
    if [[ -n "$SECS" ]]; then
      log "Interval:  every $(( SECS / 3600 )) hour(s) (${SECS}s)."
    fi
    log "Plist:     $PLIST"
  fi
  log "Log:       $LOG"
  exit 0
fi

# Otherwise: install or change. Validate the interval (positive integer hours).
HOURS="${ACTION:-6}"
case "$HOURS" in
  ''|*[!0-9]*) die "Interval must be a whole number of hours, e.g. '6'. Got: '$HOURS'" ;;
esac
[[ "$HOURS" -gt 0 ]] || die "Interval must be greater than 0 hours."

SECS=$(( HOURS * 3600 ))
DEST="${CLAUDE_BACKUP_DIR:-$HOME/Documents/claude-backup}"

# ---------------------------------------------------------------------------
# 2. Compose the LaunchAgent plist
# ---------------------------------------------------------------------------
mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$LABEL</string>
  <key>ProgramArguments</key>
  <array>
    <string>$BACKUP_SCRIPT</string>
  </array>
  <key>EnvironmentVariables</key>
  <dict>
    <key>CLAUDE_BACKUP_DIR</key>
    <string>$DEST</string>
  </dict>
  <key>StartInterval</key>
  <integer>$SECS</integer>
  <key>RunAtLoad</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LOG</string>
  <key>StandardErrorPath</key>
  <string>$LOG</string>
</dict>
</plist>
EOF

# ---------------------------------------------------------------------------
# 3. (Re)load the agent — unload first so a re-run updates in place
# ---------------------------------------------------------------------------
launchctl unload "$PLIST" 2>/dev/null || true
launchctl load "$PLIST"

# ---------------------------------------------------------------------------
# 4. Summary
# ---------------------------------------------------------------------------
printf '\n'
log "Scheduled claude-backup.sh every ${HOURS} hour(s)."
log "Backs up to: $DEST"
log "Logs to:     $LOG"
log "Plist:       $PLIST"
printf '\n'
log "Change interval: ./claude-backup-schedule.sh <hours>"
log "Check status:    ./claude-backup-schedule.sh status"
log "Remove:          ./claude-backup-schedule.sh uninstall"
