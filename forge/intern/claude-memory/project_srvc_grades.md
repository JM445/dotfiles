---
name: project-srvc-grades
description: "State of repo-grades (ex srvc-grades, now apps/repo-grades) on branch 44-srvc-grades-new-app; rework done 2026-10-23, operator side next"
metadata:
  node_type: memory
  type: project
  originSessionId: fae214b5-629f-418f-8d3b-014f1f385228
  modified: 2026-10-23T15:58:46.860Z
---

**Read `LocalDocs/grading-system-data-model-design-decisions.md` and `LocalDocs/grading-system-scheme-validator.md`
FIRST** before proposing any grading design decision: they are the source of truth (kept up to date through
2026-10-23), don't duplicate them here. Guessing at semantics already answered there has cost real back-and-forth.
LocalDocs/ is a symlink, see [[reference_localdocs_symlink]]; it is personal and NOT tracked by the repo.

**State on 2026-10-23 (end of day):** the 7-step rework of srvc-grades into **repo-grades** is complete and committed
by the user step by step (user commits and pushes; commits are GPG-signed with a YubiKey, so rebases/remote git
commands are run by the user, see [[reference_team_git_convention]]). 109 tests green.
- `apps/repo-grades`, groupId `fr.epita.forge`, package `fr.epita.forge.repo.grades`, db/consumer group `repo_grades`.
  Kafka-only, no REST, follows the repo-achievement pattern.
- Messages in `exchange` under `fr.epita.forge.grades.{aggregate,command}` (unversioned, like achievements):
  GradingSchemeAggregate, GradeReportAggregate, PutGradingSchemeCommand, GradeComputationCommand, PutGradeOverrideCommand.
- framework-trace gained `TestUris` (test URIs, percent-encoded segments) and `Trace.testCasesByUri` (throws
  DUPLICATE_TEST_CASE), see [[reference_framework_trace]].
- Key decisions made today, all in the docs: node id = URI of what it grades (no free grouping nodes); traces parsed
  live at computation, never stored; one report per (scheme, group); absence descends to an absent node's
  descendants; overrides re-run the calculator on stored results (`TestOutcomes.ofResults`) and are lost on
  recomputation; scheme validation runs in the repo on reception AND in the operator before sending (team decision).

**Next piece of work: the srvc-activity-operator side** - build the initial tree, test discovery (with TestUris /
testCasesByUri), REST endpoints (`LocalDocs/Endpoints.md` is now the operator endpoint spec, written before the pivot),
consume the two aggregates, run the scheme validation before sending. Open question for the team first: move
`GradingSchemeValidator` (depends only on exchange types) to a module both apps use.

**User finds this design area hard to hold in their head** and has said so. When picking it back up, lead with a short
global view (the one formula `score = points x ratio`, what lives where) before any detail.

Related: [[feedback_comment_style]], [[feedback_confirm_edits]], [[feedback_spec_driven_tests]],
[[reference_framework_kafka_transactions]], [[project_hibernate_persist_ordering_gotcha]],
[[project_testcontainers_docker_api_version]], [[project_maven_build_cache_gotcha]],
[[project_stale_target_resources]], [[reference_intranet_uri_convention]], [[reference_frontend_backend_comm]].

**Why:** a future session on this branch or the operator follow-up needs the current state without re-reading history.
**How to apply:** start from this and the two LocalDocs design docs; update it as the operator work progresses, and
archive it once the branch merges to main.
