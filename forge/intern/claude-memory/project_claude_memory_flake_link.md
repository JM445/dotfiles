---
name: project-claude-memory-flake-link
description: How this repo's Claude Code auto-memory directory is wired up via the dotfiles flake/linker, and the self-path bug that was fixed here
metadata:
  node_type: memory
  type: project
  originSessionId: 10b2b0f7-23c6-4096-b45e-6a024b8057ae
  modified: 2026-08-25T14:20:00.000Z
---

Claude Code's auto-memory for `/home/jm445/Documents/Forge/intern` is redirected (via `.claude/settings.local.json`'s `autoMemoryDirectory`) into this git-synced dotfiles directory (`~/Documents/Github/dotfiles/forge/intern/claude-memory/`) instead of the per-machine default, so memories follow the dotfiles repo across hosts. The 6+ memory files here (including this one) are what that setting points at.

**2026-08-25 bug + fix:** the original setup did this in `forge/intern/flake.nix`'s `shellHook`, using `CLAUDE_MEMORY_DIR="${self}/claude-memory"`. This was broken: in a Nix flake, `self` resolves to the **read-only Nix store copy** of the flake's source (created for hermetic evaluation), never the live writable git checkout — so every shell entry pointed `autoMemoryDirectory` at a path like `/nix/store/<hash>-source/forge/intern/claude-memory`, which is mounted `ro` and can't be written to. Claude Code's memory-save tool failed with `EROFS` when trying to write a new memory file there. (The 6 pre-existing memory files still *read* fine from the store copy since Nix mirrors tracked repo content into it — the bug only surfaced on a *write*.)

**Fix:** moved this responsibility out of `flake.nix`'s `shellHook` entirely and into `forge/intern/link.sh` (invoked via `~/Documents/Github/dotfiles/scripts/linker.sh forge/intern`, run from inside the target project checkout). `link.sh` already knows its own real `$SCRIPT_DIR` (proven by the pre-existing `.envrc` generation there), so it now also: `mkdir -p "$SCRIPT_DIR/claude-memory"` (defensive, non-destructive — the dir is git-tracked data, never deleted/recreated) and merges `autoMemoryDirectory` into `.claude/settings.local.json` via `jq` (creating the file fresh only if absent) rather than blindly overwriting the whole file — so re-running the linker later never destroys unrelated settings (e.g. permission allowlists) that might accumulate in that same file. Verified idempotent by re-running twice and by injecting a dummy `permissions` key and confirming it survives a rerun.

**Why:** this eats a session's context if rediscovered from scratch, and the fix pattern (generated-config-file vs. data-directory, `jq`-merge vs. blind overwrite) is the house style for `link.sh`/`linker.sh` across this dotfiles repo, worth reusing verbatim in other `forge/*` link scripts if the same auto-memory pattern is added there.
**How to apply:** If `autoMemoryDirectory` in `.claude/settings.local.json` for this project ever points at a `/nix/store/...` path again (memory writes will fail with `EROFS`), re-run `~/Documents/Github/dotfiles/scripts/linker.sh forge/intern` from inside the project checkout — it's safe to rerun any time. Related: [[project_maven_build_cache_gotcha]] (the memory whose write failure surfaced this bug), [[project_srvc_grades]].
