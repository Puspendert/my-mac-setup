# my-mac-setup

An **idempotent** macOS setup script that provisions a
[WezTerm](https://wezfurlong.org/wezterm/) terminal environment: Homebrew, WezTerm,
git, [Oh My Zsh](https://ohmyz.sh/), the `zsh-autosuggestions` and
`zsh-syntax-highlighting` plugins, and (optionally) the
[Powerlevel10k](https://github.com/romkatv/powerlevel10k) prompt.

It's all one script — [`terminal-setup.sh`](terminal-setup.sh) — and it's **safe to
re-run**. Every step checks before it acts, so nothing is ever installed, cloned, or
appended to `~/.zshrc` twice.

## What it sets up

| Component | Notes |
| --- | --- |
| **Homebrew** | Installed only if missing — the one step that needs `sudo`. |
| **WezTerm** | `brew install --cask wezterm` (skipped if already present). |
| **git** | Installed via Homebrew if not already available. |
| **Oh My Zsh** | Unattended install; does **not** change your login shell or open a new shell. |
| **zsh-autosuggestions** | Cloned into `$ZSH_CUSTOM/plugins` and added to your `plugins=(…)`. |
| **zsh-syntax-highlighting** | Same — and kept **last** in the plugin list (it must load last). |
| **Powerlevel10k** | Optional (you're prompted). Also installs the MesloLGS Nerd Font. |
| **WezTerm config** | Copies `wezterm.lua` from the repo to `~/.config/wezterm/wezterm.lua` (skipped if already present). |

## Requirements

- macOS (Apple Silicon or Intel).
- `zsh` as your shell (the macOS default).
- An internet connection.
- Administrator rights — **only** if Homebrew is not already installed.

## Usage

From inside the repo:

```sh
chmod +x terminal-setup.sh
./terminal-setup.sh
```

The script pauses for input at two points:

1. **Preflight gate** — it prints what it found (Homebrew present? is `sudo` needed?)
   and waits for you to press **Enter**, or **Ctrl-C** to abort.
2. **Powerlevel10k** — a `y/N` prompt asking whether to install the theme.

If Homebrew is missing, the script explains why it needs your password, caches it up
front with `sudo -v`, and keeps it warm in the background for the duration of the run
(the keep-alive is torn down automatically when the script exits).

## After it runs

- **Restart WezTerm** (or open a new tab/window). Changes to `~/.zshrc` apply to new
  shells — the script never `source`s it for you.
- If you installed **Powerlevel10k**:
  - Run `p10k configure` in a new shell to build your prompt.
  - Set a Nerd Font in your `~/.wezterm.lua` so the icons render, e.g.:
    ```lua
    config.font = wezterm.font("MesloLGS NF")
    ```
- If Homebrew was **freshly installed**, add it to your `PATH` for future shells (the
  script prints the exact line), e.g.:
  ```sh
  echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
  ```

At the end, the script prints a summary of what was **installed**, what was **skipped**,
and every **file it created or modified** so you can see exactly what changed.

## What it deliberately does NOT do

- Never creates or modifies **`~/.wezterm.lua`** — your WezTerm config is yours (the
  Powerlevel10k font tip is *printed*, never written).
- Never runs **`chsh`** — your login shell is left untouched.
- Never **`source`s** `~/.zshrc`.
- Only asks for **`sudo`** when Homebrew genuinely needs installing.

## Safety & rollback

There is no built-in uninstall, but the script leaves you clear restore points:

- Before editing `~/.zshrc`, it backs the file up to `~/.zshrc.bak.<timestamp>` (once
  per run).
- On a first-time Oh My Zsh install, your original `~/.zshrc` is preserved by OMZ as
  `~/.zshrc.pre-oh-my-zsh`.

To revert manually:

- Restore a `~/.zshrc` backup (or `~/.zshrc.pre-oh-my-zsh`).
- Remove the cloned directories under `~/.oh-my-zsh/custom/plugins` and
  `~/.oh-my-zsh/custom/themes`.
- Uninstall Homebrew packages with `brew uninstall` / `brew uninstall --cask` if you
  want them gone.

## Repository layout

```
.
├── terminal-setup.sh        # the entire setup script
├── README.md                # this file
├── CLAUDE.md                # guidance for Claude Code / contributors
├── .gitignore
└── .claude/
    ├── settings.json        # shared, safe verification permissions
    └── settings.local.json  # per-machine, auto-generated (gitignored)
```

## Development

The script targets the **stock macOS `/bin/bash` (3.2)** and must stay compatible with
it. Verify changes *without* running the installer end-to-end:

```sh
/bin/bash -n terminal-setup.sh   # syntax check on bash 3.2
shellcheck terminal-setup.sh     # if installed
```

See [CLAUDE.md](CLAUDE.md) for the full list of constraints, the gotchas already found,
and how to unit-test the `~/.zshrc`-editing functions in isolation.

## Key bindings

These are defined in `~/.config/wezterm/wezterm.lua`.

### Keyboard

| Shortcut | Action |
| --- | --- |
| `Cmd+T` | New tab (opens at `~`) |
| `Cmd+W` | Close current pane |
| `Cmd+Shift+W` | Close current tab |
| `Cmd+D` | Split pane horizontally (opens at `~`) |
| `Cmd+Shift+D` | Split pane vertically (opens at `~`) |
| `Cmd+K` | Clear scrollback and viewport |
| `Cmd+F` | Search (uses current selection if any) |
| `Cmd+Shift+P` | Open command palette |
| `Cmd+,` | Open `wezterm.lua` in VS Code |
| `Cmd+Shift+E` | Rename current tab |
| `Cmd+A` | Select semantic zone (smart select-all) |
| `Cmd+←` | Move to beginning of line |
| `Cmd+→` | Move to end of line |
| `Cmd+Backspace` | Delete to beginning of line |
| `Opt+Backspace` | Delete previous word |
| `Opt+←` | Move one word backward |
| `Opt+→` | Move one word forward |
| `Cmd+Q` | Disabled (prevents accidental quit) |

### Mouse

| Action | Shortcut |
| --- | --- |
| Open link | `Cmd+Click` |
| Extend selection | `Cmd+Drag` |

## Optional

If WezTerm doesn't show any separator in between the path and the command (see image for reference), then add the below line to `~/.zshrc` after `source $ZSH/oh-my-zsh.sh`.

![WezTerm no separator](images/wezterm-no-separator.png)

```
PROMPT+='%{$fg_bold[white]%}»%{$reset_color%} '
```
Use icon of your choice, I am using »

After the fix:
![WezTerm with separator](images/wezterm-with-separator.png)

> [!NOTE]
> **Disclaimer:** This shouldn't be needed for Powerlevel10k