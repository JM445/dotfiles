---
name: feedback_spec_driven_tests
description: "When asked for tests, write them from the agreed spec/design, not from the user's implementation, and report failures as design questions"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 0fd7d4dc-d060-489d-b154-803293eea21b
  modified: 2026-10-09T16:14:06.550Z
---

When the user asks for tests on code they wrote, write them from the agreed spec (LocalDocs, Endpoints.md, decisions recorded in [[project_srvc_grades]]) without deriving expectations from their implementation, then run them and report each failure as a spec-vs-code question rather than silently fixing either side.

**Why:** the user asked for this explicitly on 2026-10-09 ("from what you know of the project, not from the code I wrote, this way we can catch inconsistencies between your vision of the project and mine"); it caught a real gap (write permission not implying read) and the user called it a good catch.

**How to apply:** for any test-writing request in this repo, assert behaviour as specified; leave failing tests in place and explain the disagreement, letting the user decide which side changes.
