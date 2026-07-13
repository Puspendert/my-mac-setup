#!/usr/bin/env bash
#
# terminal-setup.sh — Idempotent macOS terminal environment setup for WezTerm.
#
# Configures: Homebrew, WezTerm, git, Oh My Zsh, zsh plugins
# (autosuggestions + syntax-highlighting) and, optionally, Powerlevel10k.
#
# Safe to re-run: every step checks before it installs, clones or edits, so
# nothing is ever duplicated. Fails fast on errors and prints a summary at the end.
#
# Notes / deliberate non-actions:
#   * Does NOT create or modify ~/.wezterm.lua (the user manages that).
#   * Does NOT run chsh and does NOT `source ~/.zshrc` (changes apply on next shell).
#   * Written for the stock macOS /bin/bash (3.2) — no bash 4+ features are used.

set -euo pipefail

# ---------------------------------------------------------------------------
# Do not depend on interactive-shell variables being present.
# ---------------------------------------------------------------------------
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

# ---------------------------------------------------------------------------
# Logging helpers (colored only when stdout is a terminal).
# ---------------------------------------------------------------------------
if [[ -t 1 ]]; then
  C_INFO=$'\033[0;34m'; C_WARN=$'\033[0;33m'; C_ERR=$'\033[0;31m'
  C_OK=$'\033[0;32m';   C_RST=$'\033[0m'
else
  C_INFO=""; C_WARN=""; C_ERR=""; C_OK=""; C_RST=""
fi

info()  { printf '%s[INFO]%s  %s\n'  "$C_INFO" "$C_RST" "$*"; }
warn()  { printf '%s[WARN]%s  %s\n'  "$C_WARN" "$C_RST" "$*" >&2; }
error() { printf '%s[ERROR]%s %s\n'  "$C_ERR"  "$C_RST" "$*" >&2; }

# Returns success if the given command is available on PATH.
command_exists() { command -v "$1" >/dev/null 2>&1; }

# Returns success if $1 is present as a whole word in the space-list $2.
contains_word() {
  case " $2 " in *" $1 "*) return 0 ;; *) return 1 ;; esac
}

# ---------------------------------------------------------------------------
# Backup helper — copies a file to <file>.bak.<timestamp> before it is edited.
# Backs up each file at most once per run (tracked in _BACKED_UP) so multiple
# edits to the same file don't produce a pile of near-identical backups.
# ---------------------------------------------------------------------------
_BACKED_UP=""
backup_file() {
  local f="$1"
  [[ -f "$f" ]] || return 0
  case " $_BACKED_UP " in *" $f "*) return 0 ;; esac   # already backed up this run
  local ts backup
  ts="$(date +%Y%m%d%H%M%S)"
  backup="${f}.bak.${ts}"
  cp -p "$f" "$backup"
  _BACKED_UP="$_BACKED_UP $f"
  mark_touched "$backup" "backup created"
  info "Backed up $f -> $backup"
}

# ---------------------------------------------------------------------------
# Summary bookkeeping — accumulate human-readable lines for the final report.
# (Plain strings, not arrays, to stay bash-3.2 friendly.)
# ---------------------------------------------------------------------------
SUMMARY_INSTALLED=""
SUMMARY_SKIPPED=""
mark_installed() { SUMMARY_INSTALLED="${SUMMARY_INSTALLED}  - $1"$'\n'; info "$1"; }
mark_skipped()   { SUMMARY_SKIPPED="${SUMMARY_SKIPPED}  - $1"$'\n';   info "$1 (skipped)"; }

# Record a filesystem path this run actually created or modified, for the final
# report so the user knows exactly what was touched. Deduped by path (e.g. ~/.zshrc
# is edited by two steps but should be listed once). Space-list membership matches
# the _BACKED_UP convention and assumes paths contain no spaces.
TOUCHED=""            # printable "  - <path>  [<action>]" lines
_TOUCHED_SEEN=""      # paths already recorded
mark_touched() {
  local path="$1" action="$2"
  case " $_TOUCHED_SEEN " in *" $path "*) return 0 ;; esac   # already listed
  _TOUCHED_SEEN="$_TOUCHED_SEEN $path"
  TOUCHED="${TOUCHED}  - ${path}  [${action}]"$'\n'
}

# ---------------------------------------------------------------------------
# Cleanup trap — always tear down the sudo keep-alive loop on exit.
# ---------------------------------------------------------------------------
SUDO_KEEPALIVE_PID=""
cleanup() {
  local ec=$?
  if [[ -n "${SUDO_KEEPALIVE_PID:-}" ]]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
  fi
  return $ec
}
trap cleanup EXIT

# ===========================================================================
# PREFLIGHT — detect Homebrew, decide whether sudo is required, get consent.
# ===========================================================================

# Locate Homebrew. Prefer one already on PATH; otherwise probe the two standard
# install locations and, if found there, wire it into THIS session via shellenv
# rather than reinstalling it.
BREW_BIN=""
BREW_FOUND="false"
if command_exists brew; then
  BREW_BIN="$(command -v brew)"
  BREW_FOUND="true"
elif [[ -x /opt/homebrew/bin/brew ]]; then          # Apple Silicon default
  BREW_BIN="/opt/homebrew/bin/brew"
  BREW_FOUND="true"
  eval "$(/opt/homebrew/bin/brew shellenv)"
  info "Found Homebrew at /opt/homebrew/bin/brew (not on PATH); loaded it for this session."
elif [[ -x /usr/local/bin/brew ]]; then             # Intel default
  BREW_BIN="/usr/local/bin/brew"
  BREW_FOUND="true"
  eval "$(/usr/local/bin/brew shellenv)"
  info "Found Homebrew at /usr/local/bin/brew (not on PATH); loaded it for this session."
fi

# sudo is only needed when Homebrew is genuinely absent and must be installed.
SUDO_NEEDED="false"
if [[ "$BREW_FOUND" != "true" ]]; then
  SUDO_NEEDED="true"
fi

# Preflight summary + explicit go/no-go gate.
echo
echo "================ Preflight ================"
if [[ "$BREW_FOUND" == "true" ]]; then
  echo "  Homebrew:    found ($BREW_BIN)"
else
  echo "  Homebrew:    absent (will install)"
fi
echo "  sudo needed: $([[ "$SUDO_NEEDED" == "true" ]] && echo yes || echo no)"
echo "==========================================="
echo

if [[ -t 0 ]]; then
  read -r -p "Press Enter to proceed, or Ctrl-C to abort... " _ || true
else
  info "Non-interactive stdin; proceeding without an interactive confirmation."
fi

# ---------------------------------------------------------------------------
# Cache the admin password up front (only if a step actually needs sudo) and
# keep it warm for the duration of the run so long installs don't stall on a
# re-prompt. If no sudo is needed, we never prompt at all.
# ---------------------------------------------------------------------------
if [[ "$SUDO_NEEDED" == "true" ]]; then
  echo
  info "Administrator access is required for ONE reason: Homebrew is not installed,"
  info "and its installer needs sudo to create its prefix (/opt/homebrew or"
  info "/usr/local) and set ownership. You'll be prompted for your macOS login"
  info "password now, and it will be cached only for this run."
  echo
  sudo -v   # prompt for + cache credentials now

  # Background keep-alive: refresh the sudo timestamp every 60s until this
  # script exits (or credentials can no longer be refreshed). The EXIT trap
  # kills this loop; the parent-alive check is a backstop.
  ( while true; do
      sudo -n true 2>/dev/null || exit
      sleep 60
      kill -0 "$$" 2>/dev/null || exit
    done ) &
  SUDO_KEEPALIVE_PID=$!
  info "Cached admin credentials; keep-alive running (pid $SUDO_KEEPALIVE_PID)."
fi

# ===========================================================================
# STEP 1 — Ensure Homebrew is installed (the sudo-requiring step).
# ===========================================================================
BREW_FRESHLY_INSTALLED="false"
if [[ "$BREW_FOUND" == "true" ]]; then
  mark_skipped "Homebrew already installed"
else
  info "Installing Homebrew..."
  # NONINTERACTIVE=1 stops the installer from waiting on RETURN; it relies on
  # the sudo credentials we cached above.
  NONINTERACTIVE=1 /bin/bash -c \
    "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

  # Wire the freshly installed brew into THIS session.
  if [[ -x /opt/homebrew/bin/brew ]]; then
    BREW_BIN="/opt/homebrew/bin/brew"
    eval "$(/opt/homebrew/bin/brew shellenv)"
  elif [[ -x /usr/local/bin/brew ]]; then
    BREW_BIN="/usr/local/bin/brew"
    eval "$(/usr/local/bin/brew shellenv)"
  fi

  if ! command_exists brew; then
    error "Homebrew installation appears to have failed (brew not found on PATH)."
    exit 1
  fi
  BREW_FOUND="true"
  BREW_FRESHLY_INSTALLED="true"
  mark_installed "Homebrew"
fi

# ===========================================================================
# STEP 2 — Install WezTerm (cask). Skip if brew already manages it or the app
# is already present in /Applications.
# ===========================================================================
if brew list --cask wezterm >/dev/null 2>&1 || [[ -d "/Applications/WezTerm.app" ]]; then
  mark_skipped "WezTerm already installed"
else
  info "Installing WezTerm..."
  brew install --cask wezterm
  mark_installed "WezTerm"
fi

# ===========================================================================
# STEP 3 — Install git. Skip if a working git is already present.
# ===========================================================================
if command_exists git; then
  mark_skipped "git already present ($(command -v git))"
else
  info "Installing git..."
  brew install git
  mark_installed "git"
fi

# ===========================================================================
# STEP 4 — Install Oh My Zsh non-interactively. Skip if ~/.oh-my-zsh exists.
# RUNZSH=no  -> don't drop into a new zsh at the end.
# CHSH=no    -> don't change the login shell.
# --unattended -> no prompts.
# ===========================================================================
if [[ -d "$HOME/.oh-my-zsh" ]]; then
  mark_skipped "Oh My Zsh already installed"
else
  info "Installing Oh My Zsh..."
  RUNZSH=no CHSH=no sh -c \
    "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" \
    "" --unattended
  mark_touched "$HOME/.oh-my-zsh" "added"
  # Oh My Zsh moves any pre-existing ~/.zshrc aside; record that backup if it happened.
  if [[ -f "$HOME/.zshrc.pre-oh-my-zsh" ]]; then
    mark_touched "$HOME/.zshrc.pre-oh-my-zsh" "added (Oh My Zsh saved your original ~/.zshrc here)"
  fi
  mark_installed "Oh My Zsh"
fi

# ===========================================================================
# STEP 5 — Install zsh plugins and wire them into ~/.zshrc.
# ===========================================================================

# Clone a plugin only if its target directory does not already exist.
clone_plugin() {
  # NB: reference $1 (not $name) here — within a single `local` statement bash 3.2
  # has not yet bound $name when $dest is evaluated.
  local name="$1" url="$2" dest="$ZSH_CUSTOM/plugins/$1"
  if [[ -d "$dest" ]]; then
    mark_skipped "plugin $name already cloned"
  else
    info "Cloning plugin $name..."
    git clone --depth=1 "$url" "$dest"
    mark_touched "$dest" "added (git clone)"
    mark_installed "plugin $name"
  fi
}

mkdir -p "$ZSH_CUSTOM/plugins"
clone_plugin "zsh-autosuggestions"     "https://github.com/zsh-users/zsh-autosuggestions"
clone_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"

# Idempotently ensure the plugins=(...) line lists:
#   <any existing plugins> git zsh-autosuggestions zsh-syntax-highlighting
# with zsh-syntax-highlighting LAST and no duplicates / no second plugins line.
configure_plugins_line() {
  local zshrc="$HOME/.zshrc"

  if [[ ! -f "$zshrc" ]]; then
    warn "~/.zshrc not found; cannot configure the plugins line. Skipping."
    return 0
  fi

  # No uncommented plugins line at all -> just append a correct one.
  if ! grep -qE '^[[:space:]]*plugins=\(' "$zshrc"; then
    backup_file "$zshrc"
    printf 'plugins=(git zsh-autosuggestions zsh-syntax-highlighting)\n' >> "$zshrc"
    mark_touched "$zshrc" "edited (plugins line)"
    mark_installed "added plugins=(...) line to ~/.zshrc"
    return 0
  fi

  # Grab the first uncommented plugins line (awk exits cleanly -> no pipefail traps).
  local line
  line="$(awk '/^[[:space:]]*plugins=\(/{print; exit}' "$zshrc")"

  # A multi-line plugins array (no ')' on the opening line) is risky to rewrite
  # blindly, so warn and leave it for the user rather than corrupt it.
  case "$line" in
    *")"*) : ;;   # single-line form — safe to rewrite
    *)
      warn "~/.zshrc uses a multi-line plugins=(...) array."
      warn "Please add these manually (keep zsh-syntax-highlighting last):"
      warn "  git zsh-autosuggestions zsh-syntax-highlighting"
      return 0
      ;;
  esac

  # Extract the current plugin names from between the parentheses.
  local inner
  inner="${line#*plugins=(}"
  inner="${inner%%)*}"

  # Rebuild the list: keep existing non-managed plugins (deduped, order kept),
  # guarantee git, then append the two managed plugins with highlighting last.
  local result="" p
  for p in $inner; do
    case "$p" in
      zsh-autosuggestions|zsh-syntax-highlighting) continue ;;   # re-added below
    esac
    if ! contains_word "$p" "$result"; then
      if [[ -z "$result" ]]; then result="$p"; else result="$result $p"; fi
    fi
  done
  # Guarantee git is present (prepend if it was missing).
  if ! contains_word "git" "$result"; then
    if [[ -z "$result" ]]; then result="git"; else result="git $result"; fi
  fi
  # Append the two managed plugins, keeping zsh-syntax-highlighting last.
  if [[ -z "$result" ]]; then
    result="zsh-autosuggestions zsh-syntax-highlighting"
  else
    result="$result zsh-autosuggestions zsh-syntax-highlighting"
  fi

  local new_line="plugins=($result)"

  # Already exactly right? Do nothing (true idempotency, no needless backup).
  if [[ "$line" == "$new_line" ]]; then
    mark_skipped "~/.zshrc plugins line already configured"
    return 0
  fi

  # Replace the first plugins line in place, addressed by line number.
  backup_file "$zshrc"
  local n
  n="$(awk '/^[[:space:]]*plugins=\(/{print NR; exit}' "$zshrc")"
  sed -i '' "${n}s|.*|${new_line}|" "$zshrc"
  mark_touched "$zshrc" "edited (plugins line)"
  mark_installed "updated ~/.zshrc plugins line -> $new_line"
}
configure_plugins_line

# ===========================================================================
# STEP 6 — Optionally install Powerlevel10k.
# ===========================================================================
INSTALL_P10K="false"
if [[ -t 0 ]]; then
  reply=""
  read -r -p "Install the Powerlevel10k theme? [y/N] " reply || reply=""
  case "$reply" in
    [yY]|[yY][eE][sS]) INSTALL_P10K="true" ;;
    *)                 INSTALL_P10K="false" ;;
  esac
else
  info "Non-interactive stdin; skipping the Powerlevel10k prompt (defaulting to No)."
fi

P10K_DONE="false"
if [[ "$INSTALL_P10K" == "true" ]]; then
  P10K_DONE="true"

  # 6a. Clone the theme (skip if already there).
  p10k_dir="$ZSH_CUSTOM/themes/powerlevel10k"
  if [[ -d "$p10k_dir" ]]; then
    mark_skipped "Powerlevel10k already cloned"
  else
    info "Cloning Powerlevel10k..."
    mkdir -p "$ZSH_CUSTOM/themes"
    git clone --depth=1 "https://github.com/romkatv/powerlevel10k" "$p10k_dir"
    mark_touched "$p10k_dir" "added (git clone)"
    mark_installed "Powerlevel10k theme"
  fi

  # 6b. Set ZSH_THEME, replacing any existing line (never appending a duplicate).
  set_zsh_theme() {
    local zshrc="$HOME/.zshrc" theme="powerlevel10k/powerlevel10k"
    local desired="ZSH_THEME=\"$theme\""

    if [[ ! -f "$zshrc" ]]; then
      warn "~/.zshrc not found; cannot set ZSH_THEME. Skipping."
      return 0
    fi
    # Already set to exactly this theme? Nothing to do.
    if grep -qE "^[[:space:]]*ZSH_THEME=\"?${theme}\"?[[:space:]]*\$" "$zshrc"; then
      mark_skipped "ZSH_THEME already set to $theme"
      return 0
    fi
    backup_file "$zshrc"
    if grep -qE '^[[:space:]]*ZSH_THEME=' "$zshrc"; then
      local n
      n="$(awk '/^[[:space:]]*ZSH_THEME=/{print NR; exit}' "$zshrc")"
      sed -i '' "${n}s|.*|${desired}|" "$zshrc"
    else
      printf '%s\n' "$desired" >> "$zshrc"
    fi
    mark_touched "$zshrc" "edited (ZSH_THEME)"
    mark_installed "set ZSH_THEME=\"$theme\" in ~/.zshrc"
  }
  set_zsh_theme

  # 6c. Install the recommended Nerd Font (skip if already installed).
  if brew list --cask font-meslo-lg-nerd-font >/dev/null 2>&1; then
    mark_skipped "MesloLGS Nerd Font already installed"
  else
    info "Installing MesloLGS Nerd Font..."
    brew install --cask font-meslo-lg-nerd-font
    mark_installed "MesloLGS Nerd Font"
  fi
else
  mark_skipped "Powerlevel10k (declined)"
fi

# ===========================================================================
# STEP 7 — Copy wezterm.lua to ~/.config/wezterm/wezterm.lua.
# ===========================================================================
WEZTERM_CONFIG_SRC="$(cd "$(dirname "$0")" && pwd)/wezterm.lua"
WEZTERM_CONFIG_DEST="$HOME/.config/wezterm/wezterm.lua"

if [[ -f "$WEZTERM_CONFIG_DEST" ]]; then
  mark_skipped "~/.config/wezterm/wezterm.lua already exists"
elif [[ ! -f "$WEZTERM_CONFIG_SRC" ]]; then
  warn "wezterm.lua not found at $WEZTERM_CONFIG_SRC; skipping WezTerm config copy."
else
  mkdir -p "$HOME/.config/wezterm"
  cp "$WEZTERM_CONFIG_SRC" "$WEZTERM_CONFIG_DEST"
  mark_touched "$WEZTERM_CONFIG_DEST" "added"
  mark_installed "WezTerm config -> $WEZTERM_CONFIG_DEST"
fi

# ===========================================================================
# STEP 8 — Final summary and next steps.
# ===========================================================================
echo
echo "================ Summary =================="
echo "Installed / changed:"
if [[ -n "$SUMMARY_INSTALLED" ]]; then printf '%s' "$SUMMARY_INSTALLED"; else echo "  (none)"; fi
echo
echo "Skipped (already present / declined):"
if [[ -n "$SUMMARY_SKIPPED" ]]; then printf '%s' "$SUMMARY_SKIPPED"; else echo "  (none)"; fi
echo
echo "Files created / modified this run (inspect these to see exactly what changed):"
if [[ -n "$TOUCHED" ]]; then printf '%s' "$TOUCHED"; else echo "  (none)"; fi
echo "==========================================="
echo

printf '%sNext steps:%s\n' "$C_OK" "$C_RST"
echo "  * Restart WezTerm (or open a new tab/window) to load the changes."
echo "    Changes to ~/.zshrc apply to new shells; this script does not source it."

if [[ "$BREW_FRESHLY_INSTALLED" == "true" ]]; then
  echo "  * Homebrew was just installed. To make 'brew' available in future login"
  echo "    shells, add its shellenv to ~/.zprofile, e.g.:"
  if [[ -x /opt/homebrew/bin/brew ]]; then
    echo "        echo 'eval \"\$(/opt/homebrew/bin/brew shellenv)\"' >> ~/.zprofile"
  else
    echo "        echo 'eval \"\$(/usr/local/bin/brew shellenv)\"' >> ~/.zprofile"
  fi
fi

if [[ "$P10K_DONE" == "true" ]]; then
  echo "  * Run 'p10k configure' in a new shell to set up the Powerlevel10k prompt."
  echo "  * Set a Nerd Font in ~/.wezterm.lua so Powerlevel10k icons render, e.g.:"
  echo "        config.font = wezterm.font(\"MesloLGS NF\")"
  echo "    (This script intentionally does not modify ~/.wezterm.lua.)"
fi

echo
info "Done."
