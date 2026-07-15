# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A growing collection of **idempotent** macOS Bash setup scripts. Each script owns one
concern and is safe to re-run. There is no build step and no test framework. Current
scripts:

- [`terminal-setup.sh`](terminal-setup.sh) — provisions a WezTerm terminal environment:
  Homebrew, WezTerm, git, Oh My Zsh, the `zsh-autosuggestions` +
  `zsh-syntax-highlighting` plugins, (optionally) Powerlevel10k, and copies
  `wezterm.lua` to `~/.config/wezterm/wezterm.lua`.
- [`java-setup.sh`](java-setup.sh) — installs `jenv`, installs the Amazon Corretto JDK
  versions the user picks (via `corretto@N` casks), registers each with `jenv`, adds a
  guarded jenv block to `~/.zshrc`, enables the jenv `export` plugin, and optionally
  imports `.crt` certificates into each JDK's truststore.
- [`devtools-setup.sh`](devtools-setup.sh) — installs a fixed set of developer tools via
  Homebrew: the formulae `maven`, `git`, `awscli`, `dive` and the casks `docker-desktop`,
  `bruno`. Each is guarded by `brew list` / `brew list --cask`; already-installed tools
  are logged and skipped. Takes no input, needs no `sudo`, and edits no dotfiles.
- [`python-setup.sh`](python-setup.sh) — installs the CPython build dependencies, installs
  `pyenv`, adds a guarded pyenv block to `~/.zshrc`, installs the Python versions the user
  picks (via `pyenv install`, resolving `X.Y` prefixes with `pyenv latest`), and optionally
  sets one as the global default. Compiles Python from source; needs no `sudo`.
- [`node-setup.sh`](node-setup.sh) — installs `fnm` (Fast Node Manager) via Homebrew, adds
  a guarded fnm block to `~/.zshrc`, installs the Node.js versions the user picks (via
  `fnm install`, which resolves a partial like `20` to the latest matching release), and
  optionally sets one as the global default. Downloads prebuilt Node binaries, so there are
  no build dependencies and no compile step; needs no `sudo`.
- [`claude-backup.sh`](claude-backup.sh) — mirrors the user-level Claude Code config that
  makes Claude "know you" into a destination folder (default `~/Documents/claude-backup`,
  overridable via `CLAUDE_BACKUP_DIR`): the single files `CLAUDE.md`, `settings.json`,
  `keybindings.json`; the dirs `memory/`, `commands/`, `agents/`, `skills/`; and every
  `projects/*/memory/`. Directories are mirrored with `rsync -a --delete`, single files
  copied with `cp -p`; each source is copied only if it exists. It writes a `RESTORE.md`
  and `last-backup.txt`, then runs a warn-only secret scan over the backup. Reads nothing
  from `~/.claude.json` (deliberately excluded — MCP tokens + session history) and never
  touches credentials. Takes no input, needs no `sudo`, and edits no dotfiles. On
  interactive runs (`[ -t 1 ]`) it prints a one-line hint pointing at
  `claude-backup-schedule.sh`; the hint is suppressed when output isn't a TTY (so scheduled
  runs don't clutter the log).
- [`claude-backup-schedule.sh`](claude-backup-schedule.sh) — schedules `claude-backup.sh`
  via a per-user launchd LaunchAgent. Three subcommands dispatched on `$1`:
  `[HOURS]` installs or changes the schedule (default `6`; validated as a positive
  integer), `status` reports whether the agent is loaded and its interval, and `uninstall`
  unloads + removes the plist. Writes
  `~/Library/LaunchAgents/com.<user>.claude-backup.plist` (`StartInterval` = HOURS×3600,
  `RunAtLoad` true, logging to `~/Library/Logs/claude-backup.log`) and bakes in
  `CLAUDE_BACKUP_DIR`. Idempotent via overwrite + `launchctl unload`/`load`; needs no
  `sudo` and edits no dotfiles.

More setups are planned (see the roadmap in [README.md](README.md)).
The constraints below apply to **every** script in the repo.

## Hard constraints — do NOT break these

These are deliberate and load-bearing. Preserve them in every change.

1. **Bash 3.2 compatible.** macOS ships `/bin/bash` 3.2.57 and the script targets it.
   Do **not** introduce bash 4+ features: no associative arrays (`declare -A`), no
   `${var,,}` / `${var^^}`, no `mapfile` / `readarray`, no `|&`, no unguarded
   `"${arr[@]}"` under `set -u`. Prefer space-delimited strings plus the `contains_word`
   helper over associative arrays. Always syntax-check with the **stock** bash:
   `/bin/bash -n terminal-setup.sh`.
2. **Idempotent.** Re-running any script must never duplicate anything — installs, git
   clones, jenv registrations, or lines in `~/.zshrc`. Every step checks before it acts.
   When you touch any `~/.zshrc`-editing logic, confirm that a second run is a no-op.
   `java-setup.sh` guards its `~/.zshrc` edit with a `# >>> jenv setup >>>` marker and
   guards the export plugin on the `~/.jenv/plugins/export` symlink — preserve both.
3. **Fail fast.** Keep `set -euo pipefail` at the top. Watch for constructs that trip
   `set -e` (see Gotchas).
4. **Deliberate non-actions** — never add these:
   - Do not create or modify `~/.wezterm.lua` (the user owns it). Powerlevel10k font
     guidance is *printed* to the user, never written to that file. Note: STEP 7 copies
     `wezterm.lua` to `~/.config/wezterm/wezterm.lua` — that is intentional and distinct.
   - Do not run `chsh`.
   - Do not `source ~/.zshrc` (changes apply on the next shell).
   - `terminal-setup.sh`: do not prompt for `sudo` unless Homebrew is genuinely absent —
     that is the only step that needs it. When it is needed, a background keep-alive
     refreshes the credential and an `EXIT` trap tears it down.
   - `java-setup.sh`: only the optional truststore import needs `sudo` (writing to each
     JDK's `cacerts`); everything else runs unprivileged. Keep it that way.

## Layout

- `terminal-setup.sh` — the terminal setup. Banner-commented sections: helpers →
  preflight → sudo keep-alive → STEP 1–7 → STEP 8 (summary). STEP 7 copies `wezterm.lua`
  to `~/.config/wezterm/wezterm.lua` (skipped if the destination already exists).
- `java-setup.sh` — the Java setup. Numbered sections: 0 preconditions → 1 install jenv →
  2 configure `~/.zshrc` → 3 pick + install Corretto versions → 4 register with jenv +
  enable export plugin → 5 optional cert import → 6 summary.
- `devtools-setup.sh` — the developer-tools setup. Numbered sections: 0 preconditions →
  1 install formulae → 2 install casks → 3 summary. Package lists live in the
  space-delimited `FORMULAE` / `CASKS` vars near the top; the `append` helper builds the
  installed/present/failed summary strings without leading spaces.
- `python-setup.sh` — the Python setup. Numbered sections: 0 preconditions → 1 install
  build deps → 2 install pyenv → 3 configure `~/.zshrc` → 4 pick + install Python versions
  → 5 optional global default → 6 summary. The build-dep list lives in the space-delimited
  `BUILD_DEPS` var near the top; the `~/.zshrc` edit is guarded by a `# >>> pyenv setup >>>`
  marker.
- `node-setup.sh` — the Node.js setup. Numbered sections: 0 preconditions → 1 install fnm
  → 2 configure `~/.zshrc` → 3 pick + install Node versions → 4 optional global default →
  5 summary. No build deps and no compile step (fnm downloads prebuilt binaries); the
  `~/.zshrc` edit is guarded by a `# >>> fnm setup >>>` marker.
- `claude-backup.sh` — the Claude Code config backup. Numbered sections: 0 preconditions →
  1 copy single files → 2 copy directories → 3 per-project memory → 4 restore notes →
  5 secret scan → 6 summary. The `SRC`/`DEST`/`FILES`/`DIRS` vars near the top drive it
  (`DEST` defaults to `~/Documents/claude-backup`, overridable via `CLAUDE_BACKUP_DIR`).
  `copy_file` (cp -p) and `copy_dir` (rsync -a --delete) both guard on the source
  existing; the `append` helper builds the copied/skipped summary strings. Edits no
  dotfiles and reads nothing from `~/.claude.json`. STEP 7 prints the automation hint,
  gated on `[ -t 1 ]`.
- `claude-backup-schedule.sh` — the launchd scheduler. Sections: 0 preconditions + shared
  paths (`SELF_DIR`, `BACKUP_SCRIPT`, `LABEL`, `PLIST`, `LOG`) → 1 dispatch on `$1`
  (`uninstall` / `status` / else install) → 2 compose plist → 3 (re)load → 4 summary.
  Uses the same `log`/`warn`/`die` helpers. Note: don't name the seconds variable
  `SECONDS` (a bash special var) — it uses `SECS`.
- `wezterm.lua` — WezTerm config; copied to `~/.config/wezterm/wezterm.lua` by
  `terminal-setup.sh` STEP 7.
- `.claude/settings.json` — shared, safe verification permissions (committed).
- `.claude/settings.local.json` — per-machine, auto-generated, **gitignored**.

## How to verify changes safely

Do **not** run either script end-to-end to test it — they install Homebrew, casks, and
JDKs. Instead:

- `/bin/bash -n <script>.sh` — syntax check (use stock bash to catch 3.2 issues). Run it
  for whichever script(s) you touched, e.g. `terminal-setup.sh` and/or `java-setup.sh`.
- `shellcheck <script>.sh` — if installed.
- For `terminal-setup.sh`, unit-test the two risky `~/.zshrc`-editing functions in
  isolation. Extract one with
  `awk` and source it against a throwaway `$HOME` with a sample `.zshrc`, then assert a
  second call is a no-op:
  ```sh
  awk '/^configure_plugins_line\(\) \{/{f=1} f{print} f&&/^\}/{exit}' terminal-setup.sh > fn.sh
  # stub backup_file / mark_installed / mark_skipped / info / warn,
  # define the real contains_word, point HOME at a temp dir, call the function twice.
  ```
  The functions that must stay idempotent: **`configure_plugins_line`** and
  **`set_zsh_theme`**.
- For `java-setup.sh`, the idempotency guards to re-check by hand: the
  `# >>> jenv setup >>>` block is appended only when `grep -qF` doesn't find its marker,
  and the export plugin is enabled only when `~/.jenv/plugins/export` is absent. Confirm
  a second run re-triggers neither.
- For `devtools-setup.sh`, the idempotency guard is the per-package `brew list` /
  `brew list --cask` check in each install loop — confirm an already-installed package is
  logged and skipped, so a second run installs nothing.
- For `python-setup.sh`, the idempotency guards to re-check by hand: the
  `# >>> pyenv setup >>>` block is appended only when `grep -qF` doesn't find its marker;
  the build-dep loop skips any dep `brew list` already reports; and each Python version is
  installed only when `pyenv versions --bare` doesn't already list the resolved version.
  Confirm a second run re-triggers none of them.
- For `node-setup.sh`, the idempotency guards to re-check by hand: fnm is installed only
  when `brew list fnm` fails; the `# >>> fnm setup >>>` block is appended only when
  `grep -qF` doesn't find its marker; and `fnm install` is itself a no-op when the resolved
  release is already present. Confirm a second run re-triggers none of them.
- For `claude-backup.sh`, idempotency comes from mirroring rather than guards: `rsync -a
  --delete` makes each backed-up directory an exact mirror of its source (a re-run
  re-syncs, never duplicates, and prunes files removed at the source), and single files
  are overwritten in place. Safe to run without an installer since it copies files only.
  You can exercise it end-to-end against a throwaway `$HOME`: build a fake `~/.claude`
  with a couple of files, point `HOME` at a temp dir, run it twice, and confirm the
  destination tree is identical after both runs. The secret scan is warn-only (`|| true`),
  so a match never aborts the backup.
- For `claude-backup-schedule.sh`, do **not** run it directly to test — it invokes
  `launchctl` against your real user session. Instead exercise it against a throwaway
  `$HOME` with a stub `launchctl` on `PATH` (a tiny script that just echoes its args, so
  `set -e` doesn't abort): copy both scripts into a temp dir so they're siblings, then
  assert with `plutil -lint` / `plutil -extract StartInterval raw` that install writes a
  valid plist with the right interval, a re-run updates it in place (no duplicate agent),
  `uninstall` removes it and is a safe no-op the second time, and non-integer / zero
  intervals `die`.

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
