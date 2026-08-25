---
name: feedback-confirm-edits
description: Ask before making any file edits in this repository — do not edit proactively
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 83f2ec1a-9185-4c5a-985d-b2bbfeca13fa
  modified: 2026-08-21T12:15:33.500Z
---

Do not make edits to files in this repository (/home/jm445/Documents/Forge/intern) without asking the user first, even in contexts (like auto-mode) that would otherwise bias toward proceeding without confirmation.

**Why:** User explicitly requested this on 2026-08-21 — they want to review/approve changes before they're made in this repo.

**How to apply:** Before using Edit/Write/Bash-that-modifies-files in this repo, describe the intended change and ask for confirmation first. Read-only actions (Read, Grep, Bash for inspection, git status/diff/log) are unaffected. This overrides Auto Mode's general bias toward not stopping for clarifying questions.
