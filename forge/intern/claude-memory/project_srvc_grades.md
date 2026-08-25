---
name: project-srvc-grades
description: Current state of the srvc-grades app build-out and ingestion testing on branch 44-srvc-grades-new-app
metadata:
  node_type: memory
  type: project
  originSessionId: 10b2b0f7-23c6-4096-b45e-6a024b8057ae
  modified: 2026-08-25T12:55:00.234Z
---

New Quarkus app `srvc-grades` (apps/srvc-grades) was scaffolded in commit 6681e4374 (2026-07-02): a JPA data model (GradeReport, GradingNode, GradingScheme, GroupMember, Job, SubmissionDefinition, Submission, TestResult, NodeReference), matching repositories, a Flyway init migration, and a subscriber (SubmissionSubscriber) that ingests `ActivityAggregate`/`SubmissionAggregate` payloads via DataIngestionService into the DB.

As of 2026-08-25, the ingestion-testing work is **done** (user's own words) — status:

- Test setup follows the repo convention: `TestService` interface (`ingestActivity`/`ingestSubmission`) calls `DataIngestionService` directly with JSON fixtures under `src/test/resources/{activity_aggregate,submission_aggregate}/`, bypassing Kafka entirely — matches srvc-git/repo-submission's pattern.
- Three test classes, 11/11 passing: `DataIngestionServiceTest` (original happy-path), `ActivityIngestionTest` (nested subgroups, pruning + group-membership replacement, historical-submission survival, empty/null group membership, no-root-group no-op), `SubmissionIngestionTest` (basic upsert, job status filtering, re-ingest-updates-in-place, missing jobs field, unknown-definition error).
- Getting tests running locally required a machine-level Docker/Testcontainers fix — see [[project_testcontainers_docker_api_version]]. Not an srvc-grades-specific issue; affected every app's tests on this machine (confirmed via srvc-git).
- Real bugs found via this test-writing effort, now fixed on the branch:
  - Flyway migration was at `src/main/resources/V1__Init.sql` instead of `src/main/resources/db/migration/V1__Init.sql` — Flyway silently found zero migrations and created no tables.
  - `onSubmissionAggregate`/`ingestJob` called `persist()` before setting required (`NOT NULL`) fields on new `SubmissionModel`/`JobModel` rows — see [[project_hibernate_persist_ordering_gotcha]] for the mechanism; this made ingesting any *new* Submission/Job throw a constraint violation. Fixed by setting fields before the single `persist()` call.
  - `SubmissionModel.submissionDefinition` / `JobModel.submission` now carry `@NotFound(action = NotFoundAction.IGNORE)` — historical Submissions/Jobs are intentionally kept when their SubmissionDefinition is later pruned by activity re-ingestion, so the FK can dangle; this makes lazy-loading it resolve to `null` instead of throwing.
  - Added `V2__GroupMemberUniqueConstraint.sql` (unique index on `group_member(submission_definition_id, group_slug, login)`).
  - `ingestAssignmentGroup` now logs a `warn` when a group has both `assignments` and `subgroups` populated (docstring says "not expected" but nothing enforced it — assignments still take precedence, subgroups silently unwalked).

Related: [[staging_db_access]] for reaching the staging DB this service talks to, [[feedback_confirm_edits]] for the edit-confirmation rule that applies to this repo, [[project_testcontainers_docker_api_version]] and [[project_hibernate_persist_ordering_gotcha]] for the two technical gotchas hit along the way.

**Why:** tracks the current feature branch so future sessions don't need a re-briefing on what srvc-grades is or what's mid-flight.
**How to apply:** When work resumes on branch 44-srvc-grades-new-app or apps/srvc-grades, start from this instead of re-reading the whole diff/history. The user is continuing with "test discovery" work next, in a separate chat session — that follow-up is not yet reflected here. Update this memory as the feature progresses, and remove/archive it once the branch merges to main.
