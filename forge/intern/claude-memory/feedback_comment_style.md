---
name: feedback-comment-style
description: Keep code comments/javadocs short and human-sounding; never reference LocalDocs from code
metadata:
  node_type: memory
  type: feedback
  originSessionId: fae214b5-629f-418f-8d3b-014f1f385228
  modified: 2026-10-23T15:58:49.608Z
---

Keep comments and javadocs short and human-sounding, at roughly the density of the surrounding code. No
multi-paragraph javadoc essays on small helpers. **Never reference the LocalDocs design docs from code comments.**

**Why:** the user asked for this explicitly (2026-09-17). LocalDocs/ is personal and not tracked by the repo, so a
comment pointing at it is a dangling reference for anyone else reading the code.

**How to apply:** when writing or editing code in this repo, explain the why in one or two sentences inline; put the
long rationale in the design doc instead. Related: [[project-srvc-grades]].
