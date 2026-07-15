#!/usr/bin/env bash
#
# node-setup.sh
#
# Installs fnm (Fast Node Manager), wires it into zsh, installs the Node.js
# versions you specify at the prompt, and (optionally) sets one as the global
# default. fnm downloads prebuilt Node binaries, so there are no build
# dependencies and no compile step. Versions fnm can't install are logged and
# skipped.
#
# Safe to re-run: every step checks state before acting.
#
# Written for the stock macOS /bin/bash (3.2) — no bash 4+ features are used.
#
# Usage:
#   chmod +x node-setup.sh
#   ./node-setup.sh
#
# After it finishes, open a NEW terminal (or `source ~/.zshrc`) so the fnm
# shell integration takes effect.

set -euo pipefail

REQUESTED_VERSIONS=()   # what the user asked for (validated as N[.N[.N]])
INSTALLED_VERSIONS=()   # subset that fnm actually has after this run
ZSHRC="${HOME}/.zshrc"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# 0. Preconditions
# ---------------------------------------------------------------------------
[[ "$(uname -s)" == "Darwin" ]] || die "This script targets macOS."
command -v brew >/dev/null 2>&1 || die "Homebrew not found. Install it first: https://brew.sh"

log "Updating Homebrew metadata..."
brew update >/dev/null || warn "brew update failed; continuing with existing metadata."

# ---------------------------------------------------------------------------
# 1. Install fnm
# ---------------------------------------------------------------------------
if brew list fnm >/dev/null 2>&1; then
  log "fnm already installed."
else
  log "Installing fnm..."
  brew install fnm
fi

BREW_PREFIX="$(brew --prefix)"
FNM_BIN="${BREW_PREFIX}/bin/fnm"
[[ -x "$FNM_BIN" ]] || die "fnm binary not found at ${FNM_BIN} after install."

# ---------------------------------------------------------------------------
# 2. Configure zsh (~/.zshrc) — only append the block if it's missing
# ---------------------------------------------------------------------------
touch "$ZSHRC"

# Write the entire fnm block atomically so partial state from a prior failed
# run (or a content line that already existed elsewhere in the file) cannot
# produce a structurally incomplete block.
if ! grep -qF "# >>> fnm setup >>>" "$ZSHRC"; then
  printf '\n# >>> fnm setup >>>\neval "$(fnm env --use-on-cd --shell zsh)"\n# <<< fnm setup <<<\n' >> "$ZSHRC"
  log "Added fnm setup block to ${ZSHRC}"
else
  log "fnm setup block already in ${ZSHRC}"
fi

# Load fnm into THIS shell so we can run `fnm install` below.
eval "$("$FNM_BIN" env --use-on-cd --shell bash)" || true

# ---------------------------------------------------------------------------
# 3. Ask which Node.js versions to install, then install the valid ones
# ---------------------------------------------------------------------------
printf '\n'
read -r -p "Enter Node.js versions to install (comma-separated, e.g. 20,22,24): " versions_input || true

# Parse comma-separated input -> validated N[.N[.N]] versions (trimmed, de-duped).
IFS=',' read -r -a _raw_versions <<< "$versions_input"
for tok in "${_raw_versions[@]-}"; do
  # Trim surrounding whitespace.
  v="${tok#"${tok%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  [[ -z "$v" ]] && continue
  if [[ ! "$v" =~ ^[0-9]+(\.[0-9]+){0,2}$ ]]; then
    warn "Ignoring invalid version '${tok}' (expected a major like 20, or 20.11, or 20.11.0)."
    continue
  fi
  # De-duplicate.
  if [[ " ${REQUESTED_VERSIONS[*]-} " == *" ${v} "* ]]; then
    continue
  fi
  REQUESTED_VERSIONS+=("$v")
done

[[ ${#REQUESTED_VERSIONS[@]} -gt 0 ]] || die "No valid versions provided. Nothing to do."

log "Requested versions: ${REQUESTED_VERSIONS[*]}"

for v in "${REQUESTED_VERSIONS[@]}"; do
  # `fnm install` resolves a partial (e.g. 20) to the latest matching release
  # and is a no-op if that release is already installed.
  log "Installing Node.js ${v} (fnm resolves a partial to the latest matching release)..."
  if "$FNM_BIN" install "$v"; then
    INSTALLED_VERSIONS+=("$v")
  else
    warn "fnm could not install Node.js '${v}' — skipping."
  fi
done

[[ ${#INSTALLED_VERSIONS[@]} -gt 0 ]] || die "None of the requested versions could be installed."
log "Installed versions: ${INSTALLED_VERSIONS[*]}"

# ---------------------------------------------------------------------------
# 4. (Optional) Set a global default
# ---------------------------------------------------------------------------
printf '\n'
default_version="${INSTALLED_VERSIONS[0]}"
read -r -p "Set Node.js ${default_version} as the global default? [y/N] " ans_default || true
case "${ans_default:-N}" in
  [yY] | [yY][eE][sS])
    if "$FNM_BIN" default "$default_version"; then
      log "Global Node.js set to ${default_version}."
    else
      warn "Could not set default version; set it manually with 'fnm default ${default_version}'."
    fi
    ;;
  *)
    log "Leaving the global Node.js version unchanged."
    ;;
esac

# ---------------------------------------------------------------------------
# 5. Summary
# ---------------------------------------------------------------------------
log "fnm versions:"
"$FNM_BIN" list || true

cat <<'EOF'

Done.

Next steps:
  1. Open a new terminal, or run:  source ~/.zshrc
  2. Set a global default, e.g.:   fnm default 22
  3. Pin a version per project:    cd my-project && echo "22" > .node-version
     (fnm's --use-on-cd switches automatically on cd; a .nvmrc works too)
  4. Confirm:                      node --version

fnm shims are on your PATH via the setup block, so `node` follows the active
fnm version once you restart your shell (step 1).
Docs: https://github.com/Schniz/fnm
EOF
