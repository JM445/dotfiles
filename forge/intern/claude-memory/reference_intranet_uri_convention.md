---
name: reference-intranet-uri-convention
description: How URIs vs. slugs work across the EPITA intranet's domain model — URIs are globally unique, built from parent URI + slug
metadata:
  node_type: memory
  type: reference
  originSessionId: 10b2b0f7-23c6-4096-b45e-6a024b8057ae
  modified: 2026-08-26T15:08:58.633Z
---

On this intranet (the monorepo at `/home/jm445/Documents/Forge/intern`), **URIs are globally unique strings**, built as a path that concatenates a parent object's URI with the child's own **slug** (a bare, non-globally-unique name). **Slugs**, by contrast, are only unique within their parent — two assignments in two different activities can share the same slug.

User-confirmed real examples (2026-08-26):
- `assembly-2028` is an activity slug; its URI is `epita-ing/assembly-2028` (tenant slug + activity slug).
- `my_add` is an assignment slug of that activity; its URI is `epita-ing/assembly-2028/root/my_add/my_add` (the `my_add` segment appears twice because the assignment sits in an assignment-group with the same slug — group and assignment slugs aren't deduplicated in the path).
- `my_add-teacher` is a submission-definition slug; its URI is `epita-ing/assembly-2028/root/my_add/my_add/my_add-teacher` — same parent-concatenation pattern.

The user isn't fully certain this holds for *every* activity type/config, but it's held for all activities they've worked with.

**Practical consequences:**
- A child's URI already **contains and implies** its parent's URI as a prefix — no need to store both a "slug" and derive/parse the parent URI from it if you already have the full URI available (which is usually the case, since aggregate payloads carry full URIs at each level already, e.g. `SubmissionDefinitionModel.activityUri`/`assignmentUri` are both plain stored fields, not parsed from each other).
- Because of this, a **composite uniqueness key should not include both a parent URI and a child URI** — the child URI's global uniqueness already subsumes it, so including the parent adds no actual constraint. See [[project_srvc_grades]] for a concrete case: `DiscoveredTest`'s unique key was corrected from `(activityUri, assignmentUri, classname, testKey)` down to `(assignmentUri, classname, testKey)` for exactly this reason — `activityUri` was kept only as a plain (non-key) column for activity-wide query convenience.
- Existing code elsewhere in the repo does rely on this path structure directly via string-splitting (e.g. `resourceUri.split("/")` in `port-frontend/ActivityService`, `activityUri.split("/", 2)` in `srvc-activity-operator/TraceService`) — a sign this convention is load-bearing elsewhere too, not srvc-grades-specific.

**Why:** avoids re-deriving this from scratch next time a data model needs to key or scope by URI/slug — a recurring question across services on this intranet, not just srvc-grades.
**How to apply:** When designing or reviewing any entity keyed by an intranet URI, check whether a "parent scope" field is actually load-bearing for uniqueness or just a query convenience — don't assume both need to be in a composite key. Verify against the actual current URI format for the activity type in question if it matters for correctness, since the user flagged this isn't 100% universally confirmed.
