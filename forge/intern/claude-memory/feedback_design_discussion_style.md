---
name: feedback-design-discussion-style
description: During open-ended design/architecture discussion, prefer plain conversational questions over the AskUserQuestion multiple-choice tool
metadata:
  node_type: memory
  type: feedback
  originSessionId: bde99ba0-7fcd-46bf-b2cf-eb79be38448a
  modified: 2026-09-11T15:07:33.249Z
---

Mid-way through a design discussion on `srvc-grades`'s absence-status computation, the assistant used `AskUserQuestion` with three concrete options to resolve an ambiguity. The user rejected the tool call and said they wanted to clarify instead — they had additional context/reasoning to contribute that a fixed multiple-choice framing would have foreclosed (in this case, a design-decisions doc existed that answered the question, which only came out through continued free-form conversation).

**Why:** for this user, in the middle of actively reasoning through a design (not yet a settled decision with a few known options), a structured multiple-choice question presumes the option space is already understood by the assistant. It often isn't — the user may have context (a doc, a prior decision, a half-formed idea they're still working out) that doesn't map onto pre-generated options, and forcing a pick short-circuits them surfacing it.

**How to apply:** During active design/architecture exploration with this user — especially early, before the shape of a decision is clear — ask in plain prose and let the conversation continue, rather than reaching for `AskUserQuestion`. Save `AskUserQuestion` for narrower, more mechanical choices where the option space is genuinely already fixed and known (e.g. picking between two already-understood implementation approaches, not still-being-defined business/domain semantics). Related: [[project_srvc_grades]] for the session this came from, [[feedback_confirm_edits]] for this user's other general preference to slow down and confirm rather than act.
