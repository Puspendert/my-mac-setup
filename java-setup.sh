#!/usr/bin/env bash
#
# setup-jenv-corretto.sh
#
# Installs jenv, wires it into zsh, installs the Amazon Corretto JDK
# versions you specify via Homebrew casks, and registers each with jenv.
# Versions that don't exist as a cask are logged and skipped.
#
# Safe to re-run: every step checks state before acting.
#
# Usage:
#   chmod +x setup-jenv-corretto.sh
#   ./setup-jenv-corretto.sh
#
# After it finishes, open a NEW terminal (or `source ~/.zshrc`) so the
# jenv shell integration takes effect.

set -euo pipefail

REQUESTED_VERSIONS=()   # what the user asked for (validated as numeric)
INSTALLED_VERSIONS=()   # subset that actually exist and got installed
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
# 1. Install jenv
# ---------------------------------------------------------------------------
if brew list jenv >/dev/null 2>&1; then
  log "jenv already installed."
else
  log "Installing jenv..."
  brew install jenv
fi

BREW_PREFIX="$(brew --prefix)"
JENV_BIN="${BREW_PREFIX}/bin/jenv"
[[ -x "$JENV_BIN" ]] || die "jenv binary not found at ${JENV_BIN} after install."

# ---------------------------------------------------------------------------
# 2. Configure zsh (~/.zshrc) — only append lines that are missing
# ---------------------------------------------------------------------------
touch "$ZSHRC"

# Write the entire jenv block atomically so partial state from a prior failed
# run (or a content line that already existed elsewhere in the file) cannot
# produce a structurally incomplete block.
if ! grep -qF "# >>> jenv setup >>>" "$ZSHRC"; then
  printf '\n# >>> jenv setup >>>\nexport PATH="$HOME/.jenv/bin:$PATH"\neval "$(jenv init -)"\n# <<< jenv setup <<<\n' >> "$ZSHRC"
  log "Added jenv setup block to ${ZSHRC}"
else
  log "jenv setup block already in ${ZSHRC}"
fi

# Load jenv into THIS shell so we can run `jenv add` below.
export PATH="${HOME}/.jenv/bin:${PATH}"
eval "$("$JENV_BIN" init -)" || true

# ---------------------------------------------------------------------------
# 3. Ask which Corretto versions to install, then install the valid ones
# ---------------------------------------------------------------------------
printf '\n'
read -r -p "Enter Corretto major versions to install (comma-separated, e.g. 11,17,21,25): " versions_input || true

# Parse comma-separated input -> validated numeric majors (trimmed, de-duped).
IFS=',' read -r -a _raw_versions <<< "$versions_input"
for tok in "${_raw_versions[@]-}"; do
  # Trim surrounding whitespace.
  v="${tok#"${tok%%[![:space:]]*}"}"
  v="${v%"${v##*[![:space:]]}"}"
  [[ -z "$v" ]] && continue
  if [[ ! "$v" =~ ^[0-9]+$ ]]; then
    warn "Ignoring invalid version '${tok}' (major version must be a number)."
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
  cask="corretto@${v}"

  # Confirm the cask exists before trying to install it.
  if ! brew info --cask "$cask" >/dev/null 2>&1; then
    warn "No Homebrew cask '${cask}' exists — skipping version ${v}."
    continue
  fi

  if brew list --cask "$cask" >/dev/null 2>&1; then
    log "${cask} already installed."
    INSTALLED_VERSIONS+=("$v")
  else
    log "Installing ${cask}..."
    if brew install --cask "$cask"; then
      INSTALLED_VERSIONS+=("$v")
    else
      warn "Failed to install ${cask} — skipping version ${v}."
    fi
  fi
done

[[ ${#INSTALLED_VERSIONS[@]} -gt 0 ]] || die "None of the requested versions could be installed."
log "Installed versions: ${INSTALLED_VERSIONS[*]}"

# ---------------------------------------------------------------------------
# 4. Register each JDK with jenv
#    Resolve paths via java_home so we don't depend on exact folder names.
# ---------------------------------------------------------------------------
for v in "${INSTALLED_VERSIONS[@]}"; do
  home="$(/usr/libexec/java_home -v "$v" 2>/dev/null)" || true
  if [[ -z "$home" ]]; then
    warn "Could not resolve a JDK for version ${v} via java_home. Skipping."
    continue
  fi
  if [[ "$home" != *amazon* && "$home" != *corretto* ]]; then
    warn "JDK ${v}: java_home returned a non-Corretto path (${home}) — skipping to avoid registering the wrong vendor."
    continue
  fi
  if jenv add "$home" >/dev/null 2>&1; then
    log "Registered JDK ${v}: ${home}"
  else
    warn "Failed to register JDK ${v} with jenv (path may already be registered): ${home}"
  fi
done

jenv rehash >/dev/null 2>&1 || true

# Enable the export plugin so JAVA_HOME automatically tracks the active jenv
# version. Enabling just creates a symlink under ~/.jenv/plugins, so check for
# it to stay idempotent. It takes effect on the NEXT shell (via jenv init).
if [[ -e "${HOME}/.jenv/plugins/export" ]]; then
  log "jenv export plugin already enabled."
elif jenv enable-plugin export >/dev/null 2>&1; then
  log "Enabled jenv export plugin (JAVA_HOME will follow the active version)."
else
  warn "Could not enable jenv export plugin; run 'jenv enable-plugin export' manually."
fi

# ---------------------------------------------------------------------------
# 5. (Optional) Import certificates into each JDK's truststore
#    Imports every .crt in a folder you choose, using the file name
#    (without extension) as the alias, into the cacerts of all four JDKs.
# ---------------------------------------------------------------------------
printf '\n'
read -r -p "Import certificates into the Corretto truststores? [y/N] " ans_certs || true
case "${ans_certs:-N}" in
  [yY] | [yY][eE][sS])
    read -r -p "Paste the folder path containing the .crt files: " CERT_DIR || true
    # Expand a leading ~ if the user typed one.
    CERT_DIR="${CERT_DIR/#\~/$HOME}"

    if [[ ! -d "$CERT_DIR" ]]; then
      warn "Not a directory: ${CERT_DIR}. Skipping certificate import."
    else
      # Collect .crt files (case-insensitive) without failing on none.
      shopt -s nullglob nocaseglob
      cert_files=("$CERT_DIR"/*.crt)
      shopt -u nullglob nocaseglob

      if [[ ${#cert_files[@]} -eq 0 ]]; then
        warn "No .crt files found in ${CERT_DIR}. Skipping."
      else
        log "Found ${#cert_files[@]} certificate file(s). Importing into ${#INSTALLED_VERSIONS[@]} JDK(s)."
        warn "Writing to system truststores requires sudo; you may be prompted for your password."

        for v in "${INSTALLED_VERSIONS[@]}"; do
          home="$(/usr/libexec/java_home -v "$v" 2>/dev/null)" || true
          if [[ -z "$home" ]]; then
            warn "No JDK ${v} resolved; skipping its truststore."
            continue
          fi
          if [[ "$home" != *amazon* && "$home" != *corretto* ]]; then
            warn "JDK ${v}: java_home returned a non-Corretto path (${home}) — skipping truststore."
            continue
          fi
          keytool="${home}/bin/keytool"
          [[ -x "$keytool" ]] || { warn "keytool not found for JDK ${v}; skipping."; continue; }

          log "JDK ${v} (${home})"
          for cert in "${cert_files[@]}"; do
            base="$(basename "$cert")"
            cert_alias="${base%.*}"
            if [[ "$cert_alias" == -* ]]; then
              warn "Skipping cert '${base}': filename starts with '-' which would inject a keytool flag."
              continue
            fi

            sudo "$keytool" -delete -alias "$cert_alias" -cacerts \
              -storepass changeit >/dev/null 2>&1 || true

            if sudo "$keytool" -importcert -trustcacerts -cacerts -noprompt \
                 -file "$cert" -alias "$cert_alias" -storepass changeit >/dev/null 2>&1; then
              printf '    imported %-40s as alias "%s"\n' "$base" "$cert_alias"
            else
              warn "    failed to import ${base} into JDK ${v}"
            fi
          done
        done
        log "Certificate import complete."
      fi
    fi
    ;;
  *)
    log "Skipping certificate import."
    ;;
esac

# ---------------------------------------------------------------------------
# 6. Summary
# ---------------------------------------------------------------------------
log "Registered jenv versions:"
jenv versions || true

cat <<'EOF'

Done.

Next steps:
  1. Open a new terminal, or run:  source ~/.zshrc
  2. Set a global default, e.g.:   jenv global 21
  3. Pin a version per project:    cd my-project && jenv local 17
  4. Confirm:                      java -version

The jenv export plugin is enabled, so JAVA_HOME automatically follows the
active jenv version once you restart your shell (step 1).
EOF