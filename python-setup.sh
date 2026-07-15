#!/usr/bin/env bash
#
# python-setup.sh
#
# Installs pyenv, wires it into zsh, installs the Python versions you specify
# at the prompt, and (optionally) sets one as the global default. pyenv builds
# Python from source, so the required build dependencies are installed first.
# Versions pyenv can't build are logged and skipped.
#
# Safe to re-run: every step checks state before acting.
#
# Written for the stock macOS /bin/bash (3.2) — no bash 4+ features are used.
#
# Usage:
#   chmod +x python-setup.sh
#   ./python-setup.sh
#
# After it finishes, open a NEW terminal (or `source ~/.zshrc`) so the pyenv
# shell integration takes effect.

set -euo pipefail

# Build dependencies pyenv needs to compile CPython (space-delimited).
BUILD_DEPS="openssl readline sqlite3 xz zlib tcl-tk"

REQUESTED_VERSIONS=()   # what the user asked for (validated as X.Y[.Z])
INSTALLED_VERSIONS=()   # subset that pyenv actually has after this run
ZSHRC="${HOME}/.zshrc"

log()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

# Append an item to a space-delimited list variable, avoiding a leading space
# on the first entry (keeps messages tidy under bash 3.2).
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
# 1. Install build dependencies (needed to compile CPython)
# ---------------------------------------------------------------------------
# Validate the hardcoded list up front so a mistyped formula fails fast with a
# clear message instead of a mid-loop install error (BUILD_DEPS is fixed, not
# user input, so any unknown name is a bug in this script).
bad_deps=""
for dep in $BUILD_DEPS; do
  brew info "$dep" >/dev/null 2>&1 || bad_deps="$(append "$bad_deps" "$dep")"
done
[[ -z "$bad_deps" ]] || die "Unknown Homebrew formula(e) in BUILD_DEPS: ${bad_deps}. Fix the list in this script."

for dep in $BUILD_DEPS; do
  if brew list "$dep" >/dev/null 2>&1; then
    log "${dep} already installed."
  else
    log "Installing ${dep}..."
    brew install "$dep" || warn "Failed to install ${dep}; Python builds may fail."
  fi
done

# ---------------------------------------------------------------------------
# 2. Install pyenv
# ---------------------------------------------------------------------------
if brew list pyenv >/dev/null 2>&1; then
  log "pyenv already installed; upgrading so its version list is current..."
  brew upgrade pyenv || warn "brew upgrade pyenv failed; continuing with the installed version (its known-versions list may be stale)."
else
  log "Installing pyenv..."
  brew install pyenv
fi

BREW_PREFIX="$(brew --prefix)"
PYENV_BIN="${BREW_PREFIX}/bin/pyenv"
[[ -x "$PYENV_BIN" ]] || die "pyenv binary not found at ${PYENV_BIN} after install."

# ---------------------------------------------------------------------------
# 3. Configure zsh (~/.zshrc) — only append the block if it's missing
# ---------------------------------------------------------------------------
touch "$ZSHRC"

# Write the entire pyenv block atomically so partial state from a prior failed
# run (or a content line that already existed elsewhere in the file) cannot
# produce a structurally incomplete block.
if ! grep -qF "# >>> pyenv setup >>>" "$ZSHRC"; then
  printf '\n# >>> pyenv setup >>>\nexport PYENV_ROOT="$HOME/.pyenv"\nexport PATH="$PYENV_ROOT/bin:$PATH"\neval "$(pyenv init - zsh)"\n# <<< pyenv setup <<<\n' >> "$ZSHRC"
  log "Added pyenv setup block to ${ZSHRC}"
else
  log "pyenv setup block already in ${ZSHRC}"
fi

# Load pyenv into THIS shell so we can run `pyenv install` below.
export PYENV_ROOT="${HOME}/.pyenv"
export PATH="${PYENV_ROOT}/bin:${PATH}"
eval "$("$PYENV_BIN" init - bash)" || true

# ---------------------------------------------------------------------------
# 4. Ask which Python versions to install, then install the valid ones
# ---------------------------------------------------------------------------
printf '\n'
read -r -p "Enter Python versions to install (comma-separated, e.g. 3.11,3.12,3.13): " versions_input || true

# Parse comma-separated input -> validated X.Y[.Z] versions (trimmed, de-duped).
IFS=',' read -r -a _raw_versions <<< "$versions_input"
for tok in "${_raw_versions[@]-}"; do
  # Trim surrounding whitespace.
  v="${tok#"${tok%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  [[ -z "$v" ]] && continue
  if [[ ! "$v" =~ ^[0-9]+\.[0-9]+(\.[0-9]+)?$ ]]; then
    warn "Ignoring invalid version '${tok}' (expected X.Y or X.Y.Z, e.g. 3.12 or 3.12.4)."
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
  # `pyenv latest` resolves a X.Y prefix to the newest installable patch and an
  # exact X.Y.Z to itself; a non-installable version yields no output.
  resolved="$("$PYENV_BIN" latest -k "$v" 2>/dev/null)" || true
  if [[ -z "$resolved" ]]; then
    warn "pyenv has no installable Python matching '${v}' — skipping."
    continue
  fi

  if "$PYENV_BIN" versions --bare 2>/dev/null | grep -qx "$resolved"; then
    log "Python ${resolved} already installed."
    INSTALLED_VERSIONS+=("$resolved")
  else
    log "Installing Python ${resolved} (compiling from source; this can take a few minutes)..."
    if "$PYENV_BIN" install --skip-existing "$resolved"; then
      INSTALLED_VERSIONS+=("$resolved")
    else
      warn "Failed to build Python ${resolved} — skipping."
    fi
  fi
done

[[ ${#INSTALLED_VERSIONS[@]} -gt 0 ]] || die "None of the requested versions could be installed."
"$PYENV_BIN" rehash >/dev/null 2>&1 || true
log "Installed versions: ${INSTALLED_VERSIONS[*]}"

# ---------------------------------------------------------------------------
# 5. (Optional) Set a global default
# ---------------------------------------------------------------------------
printf '\n'
default_version="${INSTALLED_VERSIONS[0]}"
read -r -p "Set Python ${default_version} as the global default? [y/N] " ans_global || true
case "${ans_global:-N}" in
  [yY] | [yY][eE][sS])
    if "$PYENV_BIN" global "$default_version"; then
      log "Global Python set to ${default_version}."
    else
      warn "Could not set global version; set it manually with 'pyenv global ${default_version}'."
    fi
    ;;
  *)
    log "Leaving the global Python version unchanged."
    ;;
esac

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
log "pyenv versions:"
"$PYENV_BIN" versions || true

cat <<'EOF'

Done.

Next steps:
  1. Open a new terminal, or run:  source ~/.zshrc
  2. Set a global default, e.g.:   pyenv global 3.12
  3. Pin a version per project:    cd my-project && pyenv local 3.11
  4. Confirm:                      python --version

pyenv shims are on your PATH via the setup block, so `python` follows the
active pyenv version once you restart your shell (step 1).
Docs: https://github.com/pyenv/pyenv
EOF
