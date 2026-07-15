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
