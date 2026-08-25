---
name: project-hibernate-persist-ordering-gotcha
description: Hibernate/Panache footguns hit while testing srvc-grades — persist() field-ordering, and EntityManager scope across @Transactional calls in one test
metadata:
  node_type: memory
  type: project
  originSessionId: 18425905-8bc2-493e-a7e8-3de44290e15b
  modified: 2026-08-25T12:55:32.597Z
---

Two Hibernate/Quarkus-Panache behaviors discovered while writing ingestion tests for `srvc-grades`, both non-obvious from reading the code alone, both likely to recur in other apps in this Forge monorepo that follow the same repository/service patterns:

**1. `persist()` snapshots field values immediately, not at flush time.** Hibernate captures the values used for an entity's `INSERT` statement at the moment `persist()` enqueues the insert action — not lazily re-read when the flush actually executes at commit. So this ordering is broken whenever any of the mutated columns are `NOT NULL`:
```java
var e = new SomeModel();
e.id = id;
repo.persist(e);        // INSERT locked in now: only id set
e.requiredField = x;     // meant to become a follow-up UPDATE...
```
...the initial `INSERT` (missing `requiredField`) fails the `NOT NULL` constraint before that `UPDATE` ever runs. Fix: set every field first, call `persist()` once at the end (only for genuinely new entities). This is exactly the bug found in `DataIngestionService.onSubmissionAggregate`/`ingestJob` — `ingestSubmissionDefinition` in the same file already did it correctly (fields-then-persist), which is what made the inconsistency easy to spot once found.

**2. The Hibernate persistence context (L1 cache) survives across separate `@Transactional` service calls within one `@QuarkusTest` method** — not scoped per-transaction as might be assumed. A test that reads an entity (even indirectly, e.g. via a different repository injected into a service method called earlier), then triggers a *separate* `@Transactional` call that deletes that same row and commits, then asserts via `repository.findByIdOptional(...)` — will get back the stale cached instance rather than a fresh DB read, because `EntityManager.find()`/`findById` checks the L1 cache first. Confirmed by adding `repository.getEntityManager().clear()` right before the "after" assertion, which fixed it. Watch for this pattern in any test that does: ingest → re-ingest-with-something-removed → assert-it's-gone.

**Why:** both cost real debugging time (misread as an application-logic pruning bug at first, until the SQL log and an isolated `.clear()` experiment ruled that out) and neither is visible just from reading `DataIngestionService.java` — they're framework-timing details.
**How to apply:** When adding new upsert-style ingestion code in this repo (any `Panache`/`Repository`-based service), set fields before the single `persist()` call for new entities. When writing a test that checks something was deleted/pruned after an earlier read of it (directly or via a different service call) in the same test method, call `entityManager.clear()` before that assertion.
