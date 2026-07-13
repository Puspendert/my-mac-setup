# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

[`terminal-setup.sh`](terminal-setup.sh) is a single, **idempotent** macOS Bash script that provisions a
WezTerm terminal environment: Homebrew, WezTerm, git, Oh My Zsh, the
`zsh-autosuggestions` + `zsh-syntax-highlighting` plugins, and (optionally)
Powerlevel10k. It is the only source file — there is no build step and no test framework.

## Hard constraints — do NOT break these

These are deliberate and load-bearing. Preserve them in every change.

1. **Bash 3.2 compatible.** macOS ships `/bin/bash` 3.2.57 and the script targets it.
   Do **not** introduce bash 4+ features: no associative arrays (`declare -A`), no
   `${var,,}` / `${var^^}`, no `mapfile` / `readarray`, no `|&`, no unguarded
   `"${arr[@]}"` under `set -u`. Prefer space-delimited strings plus the `contains_word`
   helper over associative arrays. Always syntax-check with the **stock** bash:
   `/bin/bash -n terminal-setup.sh`.
2. **Idempotent.** Re-running must never duplicate anything — installs, git clones, or
   lines in `~/.zshrc`. Every step checks before it acts. When you touch any
   `~/.zshrc`-editing logic, confirm that a second run is a no-op.
3. **Fail fast.** Keep `set -euo pipefail` at the top. Watch for constructs that trip
   `set -e` (see Gotchas).
4. **Deliberate non-actions** — never add these:
   - Do not create or modify `~/.wezterm.lua` (the user owns it). Powerlevel10k font
     guidance is *printed* to the user, never written to that file.
   - Do not run `chsh`.
   - Do not `source ~/.zshrc` (changes apply on the next shell).
   - Do not prompt for `sudo` unless Homebrew is genuinely absent — that is the only
     step that needs it. When it is needed, a background keep-alive refreshes the
     credential and an `EXIT` trap tears it down.

## Layout

- `terminal-setup.sh` — the whole thing. Banner-commented sections: helpers → preflight →
  sudo keep-alive → STEP 1–7 → summary.
- `.claude/settings.json` — shared, safe verification permissions (committed).
- `.claude/settings.local.json` — per-machine, auto-generated, **gitignored**.

## How to verify changes safely

Do **not** run `terminal-setup.sh` end-to-end to test it — it installs Homebrew and casks.
Instead:

- `/bin/bash -n terminal-setup.sh` — syntax check (use stock bash to catch 3.2 issues).
- `shellcheck terminal-setup.sh` — if installed.
- Unit-test the two risky `~/.zshrc`-editing functions in isolation. Extract one with
  `awk` and source it against a throwaway `$HOME` with a sample `.zshrc`, then assert a
  second call is a no-op:
  ```sh
  awk '/^configure_plugins_line\(\) \{/{f=1} f{print} f&&/^\}/{exit}' terminal-setup.sh > fn.sh
  # stub backup_file / mark_installed / mark_skipped / info / warn,
  # define the real contains_word, point HOME at a temp dir, call the function twice.
  ```
  The functions that must stay idempotent: **`configure_plugins_line`** and
  **`set_zsh_theme`**.

## Gotchas already found (don't reintroduce)

- **Same-statement `local`:** in bash 3.2, `local a="$1" b="/x/$a"` leaves `b="/x/"` —
  earlier names aren't bound yet within one `local`. Reference `$1` directly, or split
  into two `local` lines.
- **`grep | head` + pipefail:** `head -1` closing the pipe early sends `grep` SIGPIPE
  (exit 141), which `pipefail` + `set -e` turn into an abort. Use
  `awk '/re/{print; exit}'` to grab the first match / line number instead.
- **Space-list building:** guard the empty case, or you get leading/double spaces that
  break the "already configured?" equality check and therefore idempotency.
- **BSD sed:** in-place edits need the explicit empty backup arg — `sed -i '' ...`
  (this is macOS, not GNU sed).

## Conventions

- Log via `info` / `warn` / `error`; record outcomes with `mark_installed` /
  `mark_skipped` (they feed the final summary).
- Back up any file before editing it with `backup_file` (→ `<file>.bak.<timestamp>`,
  at most once per file per run).
