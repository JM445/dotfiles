---
name: reference-localdocs-symlink
description: LocalDocs/ at the Forge monorepo root is a symlink to an external directory — plain find/grep -r silently skip its contents
metadata:
  node_type: memory
  type: reference
  originSessionId: bde99ba0-7fcd-46bf-b2cf-eb79be38448a
  modified: 2026-09-11T15:07:11.590Z
---

`/home/jm445/Documents/Forge/intern/LocalDocs/` is a symlink to a directory outside the repo (the user confirmed this is expected and readable). It holds design-decision docs for apps in the monorepo — e.g. `LocalDocs/grading-system-data-model-design-decisions.md` for [[project_srvc_grades]].

**Why this matters:** `find` (without `-L`) and `grep -r` do not descend into a symlinked *directory* by default — they see the symlink itself but don't traverse into its target. A search like `find /home/jm445/Documents/Forge/intern -iname "*design*decision*"` will silently return nothing even though a matching file exists under `LocalDocs/`, with no error or warning that anything was skipped.

**How to apply:** When looking for documentation anywhere in this repo and a normal search comes up empty, check `LocalDocs/` directly (`ls LocalDocs/`) or re-run the search with `find -L` before concluding the doc doesn't exist. If a project memory (like [[project_srvc_grades]]) references a path under `LocalDocs/`, read that path directly rather than trying to rediscover it via search.
