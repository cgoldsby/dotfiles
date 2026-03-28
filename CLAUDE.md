# CLAUDE.md

## Repo Overview

Personal dotfiles for macOS. Managed via symlinks — edits to `~/.zshrc`, `~/.config/starship.toml`, and `~/.config/ghostty/config` write directly into this repo.

## File Locations

| Config | Repo source | Symlinked to |
|--------|-------------|--------------|
| Shell | `shell/zshrc` | `~/.zshrc` |
| Aliases | `shell/shell_aliases` | `~/.shell_aliases` |
| Starship | `starship/starship.toml` | `~/.config/starship.toml` |
| Ghostty | `ghostty/config` | `~/.config/ghostty/config` |
| Vim | `vim/vimrc` | `~/.vimrc` |

Ghostty icons (`*.icns`) are **copied**, not symlinked — they're referenced by absolute path in the Ghostty config.

`~/.zshrc.local` is machine-specific and intentionally not tracked.

## Rules

**Keep README and install.sh in sync.** Any tool added to `install.sh` must be reflected in the README's install steps, and vice versa.

**Adding a Homebrew tool:**
1. Add to the `formulae` or `casks` array in `setup_tools()` — one per line, alphabetical within group
2. Update the README install steps

**Adding a tool that needs its own setup:**
1. Create a `setup_<tool>()` function following the existing pattern
2. Wire it into `main()` in logical order
3. Update the README

## Testing Changes

- **Shell** (`zshrc`, `shell_aliases`): `source ~/.zshrc`
- **Starship**: changes apply immediately on next prompt
- **Ghostty**: picks up config changes live, no restart needed
- **install.sh**: safe to re-run — all steps check before acting

## Commit Style

Prefer amending or squashing unpushed commits rather than stacking many small ones.
