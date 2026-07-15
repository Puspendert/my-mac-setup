#!/usr/bin/env bash
#
# devtools-setup.sh
#
# Installs a batch of developer tools via Homebrew:
#   maven, git, awscli, dive (formulae) and docker-desktop, bruno (casks).
#
# Anything already installed is logged and skipped — safe to re-run.
#
# Written for the stock macOS /bin/bash (3.2) — no bash 4+ features are used.
#
# Usage:
#   chmod +x devtools-setup.sh
#   ./devtools-setup.sh

set -euo pipefail

# Homebrew packages to install.
FORMULAE="maven git awscli dive gh"
CASKS="docker-desktop bruno visual-studio-code obsidian"

# Result trackers (space-delimited; guard empty case when appending).
INSTALLED=""
PRESENT=""
FAILED=""

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Append a package name to a space-delimited list variable, avoiding a leading
# space on the first entry (keeps the summary tidy under bash 3.2).
append() {
  # $1 = current list value, $2 = item; echoes the new list.
  if [[ -z "$1" ]]; then
    printf '%s' "$2"
  else
    printf '%s %s' "$1" "$2"
  fi
}

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS."
command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it first: https://brew.sh"

log "Updating Homebrew metadata..."
brew update >/dev/null || warn "brew update failed; continuing with existing metadata."

# ---------------------------------------------------------------------------
# 1. Install formulae
# ---------------------------------------------------------------------------
for f in $FORMULAE; do
  if brew list "$f" >/dev/null 2>&1; then
    log "${f} already installed."
    PRESENT="$(append "$PRESENT" "$f")"
  else
    log "Installing ${f}..."
    if brew install "$f"; then
      INSTALLED="$(append "$INSTALLED" "$f")"
    else
      warn "Failed to install ${f} — skipping."
      FAILED="$(append "$FAILED" "$f")"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 2. Install casks
# ---------------------------------------------------------------------------
for c in $CASKS; do
  if brew list --cask "$c" >/dev/null 2>&1; then
    log "${c} already installed."
    PRESENT="$(append "$PRESENT" "$c")"
  else
    log "Installing ${c}..."
    if brew install --cask "$c"; then
      INSTALLED="$(append "$INSTALLED" "$c")"
    else
      warn "Failed to install ${c} — skipping."
      FAILED="$(append "$FAILED" "$c")"
    fi
  fi
done

# ---------------------------------------------------------------------------
# 3. Summary
# ---------------------------------------------------------------------------
printf '\n'
log "Newly installed: ${INSTALLED:-(none)}"
log "Already present: ${PRESENT:-(none)}"
if [[ -n "$FAILED" ]]; then
  warn "Failed:          ${FAILED}"
fi

cat <<'EOF'

Done.

Notes:
  - AWS CLI provides the `aws` command — verify with:  aws --version
  - Docker Desktop is a GUI app: launch it once from Applications (or run
    `open -a "Docker"`) so the Docker daemon starts before using `docker`.
  - `dive` inspects Docker image layers — needs the Docker daemon running.
EOF
