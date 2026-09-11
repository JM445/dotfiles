---
name: project-stale-target-resources
description: Deleting a source file (e.g. a Flyway migration) in this repo can leave a stale compiled copy in target/classes that mvn never removes short of a clean
metadata:
  node_type: memory
  type: project
  originSessionId: bde99ba0-7fcd-46bf-b2cf-eb79be38448a
  modified: 2026-09-11T15:07:23.619Z
---

In the Forge monorepo, deleting a file from `src/main/resources/...` doesn't remove its compiled copy from `target/classes/...`. Maven's `resources:resources` goal copies/overwrites but never deletes orphaned files that no longer have a source counterpart — so a stale file keeps being picked up at runtime (or by Flyway/Quarkus at test-boot) until `target/classes` is wiped.

First hit on `apps/srvc-grades` (branch 44-srvc-grades-new-app): `V2__GroupMemberUniqueConstraint.sql` had been merged into `V1__Init.sql` and deleted from `src/main/resources/db/migration`, but a stale copy remained under `target/classes/db/migration`. Flyway picked it up on `@QuarkusTest` boot and failed with `relation "..." already exists` (the index it created was already applied via `V1`), which reads exactly like a real migration/DB-state bug but isn't one.

**Fix:** `mvnw clean` (or delete the specific stale file under `target/classes`).

**This is a different bug from [[project_maven_build_cache_gotcha]]** — don't reach for `-Dmaven.build.cache.skipCache=true` here, it does nothing for this symptom. Distinguish by trigger and symptom: the build-cache issue follows a `pom.xml` edit and manifests as install/packaging errors (`did not assign a file to the build artifact`, `No tests to run`); this one follows deleting/renaming a source file and manifests as the *old file's content* still being in effect at runtime, with no error suggesting staleness at all.

**Side effect worth knowing:** after running `mvnw clean`, IntelliJ's own indices can go stale relative to the new state and throw bogus syntax-looking errors (e.g. flagging a valid for-each `:` as needing a `;`). Not a real code problem — fix with a Maven reimport or `File > Invalidate Caches / Restart`, not by touching the code.

**Why:** cost real confusion time at the start of a session — the Flyway error message gives no hint that a deleted, still-compiled file is the cause, and looks identical in shape to a genuine migration-state problem.
**How to apply:** If a test/boot failure in this repo references a file, migration, or resource you're sure was deleted or changed in `src/`, check `target/classes` for a stale copy before debugging the "current" behavior as if the deleted version were still real. `mvnw clean` first, investigate further only if that doesn't resolve it.
