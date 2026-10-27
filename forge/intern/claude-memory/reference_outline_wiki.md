---
name: reference-outline-wiki
description: "Team Outline wiki (wiki.forge.epita.fr) is connected via the \"claude.ai EPITA Internal Wiki\" MCP connector; where the grading docs live"
metadata:
  node_type: memory
  type: reference
  originSessionId: 29840675-b6d6-430f-8e95-38392cf83797
  modified: 2026-10-27T09:27:57.422Z
---

The team's Outline wiki is https://wiki.forge.epita.fr, reachable through the claude.ai connector "EPITA Internal Wiki" (org-level, added by a team admin; user authenticated via `/mcp` on 2026-10-27). Tools: `list_documents` (full-text search), `fetch`, `list_collection_documents`, plus write tools.

- Team docs live in the **Forge - Interne** collection.
- Grading design docs: Forge - Interne › Développement › Backends › Intern › Grading System (children: "Data Model: Grading Scheme", "Grading System - Endpoints definition"). Related to [[project-srvc-grades]].
- Search the wiki before guessing team conventions.
- For the grading system, LocalDocs is the source of truth; the wiki pages are outdated and the user syncs them manually when ready. Never treat the wiki grading pages as authoritative or update them.

**How to apply:** treat it as read-only. Never create/update/delete/comment unless the user explicitly asks, same as [[feedback-confirm-edits]]. If the tools are missing, the user needs to re-auth via `/mcp`.
