# Grading System: Scheme Validator

## Why this document exists

A `GradingScheme` is authored by teachers through the frontend, and most of the grade computation assumes the tree it
walks is well-formed. Rather than scattering defensive checks through `GradeCalculator`, the intent is a single
validation pass that a scheme must clear before it can be stored, and so before it can be used to compute anything.

*(2026-10-23)* The validator is **implemented** in repo-grades as `GradingSchemeValidator`; see "Implementation" at
the end of this file for how the rules below map to it. Every rule below came out of an actual design decision - the
rationale is kept so that a rule is never dropped just because its reason was forgotten.

Companion to `grading-system-data-model-design-decisions.md`, which defines the model these rules constrain.

## When it should run

**Team decision (2026-10-23):** validation runs **twice**: in `srvc-activity-operator` before it sends a
`PutGradingSchemeCommand`, so the teacher gets the errors, and again in `repo-grades` on reception, to catch what
changed in between (commands are asynchronous). A scheme failing validation is **rejected**, not saved as a draft:
`repo-grades` throws `INVALID_SCHEME` listing every violation, nothing is stored or published, and the subscriber logs
it.

`repo-grades` no longer holds the activity structure or a test catalog, so it can only check what the tree says about
itself. Whether references point at entities that still exist can only be checked by the operator, which owns both.

## Rules

### Tree structure

| Rule | Rationale |
|----|----|
*(2026-10-23)* The tree is now one nested `jsonb` value, so the earlier rules guarding the relational layout (single
root index, `root_node_id` pointing inside its scheme, parent in the same scheme, no `parent_id` cycle) hold by
construction and were removed.

| Rule | Rationale |
|----|----|
| The root node has type `ROOT`, and no other node does | The root stands for the activity; a `ROOT` deeper in the tree is meaningless |
| The root's URI equals the scheme's `activityUri` | The root uses the activity's URI, and the scheme is looked up by it |
| The root has at least one non-excluded child | A scheme whose children are all ignored or all adjustments has every child excluded, so the root is excluded too and no grade can be produced |
| Node reference types follow the hierarchy: `ROOT` > `ASSIGNMENT_GROUP` (any depth, optional) > `ASSIGNMENT` > `SUBMISSION_DEF` > `TEST_CATEGORY` > `TEST_CASE` | The model assumes this ordering; a `TEST_CASE` with children, or an `ASSIGNMENT` under a `TEST_CASE`, is meaningless |

### References (rewritten 2026-10-23)

A node's reference is `type + uri`, and the URI is the node's id (see `NodeReference` in the data-model doc). The
`DiscoveredTest` rules are gone with the catalog.

| Rule | Rationale |
|----|----|
| Every node has a non-blank `type` and `uri` | The URI is the node's id: `nodeResults` and overrides are keyed by it |
| No two nodes of a scheme share a URI | Two nodes would share one `NodeResult` and one override. It also means an entity appears at most once, e.g. a test cannot be both a scored node and an adjustment node |
| Every non-root node's URI starts with its parent's URI + `/` | Intranet URIs nest (parent URI + `/` + slug) and test URIs extend their submission definition's. This replaces the earlier "a test's `submissionDefUri` matches its `SUBMISSION_DEF` ancestor" rule: a test placed under the wrong definition would be looked up in the wrong trace and silently graded absent |
| A `TEST_CATEGORY` URI adds exactly one segment to its parent's, a `TEST_CASE` URI exactly one to its category's | Test names are percent-encoded so they hold no `/`; an extra segment means the URI was not built by the shared `testCaseUri` function and will never match a trace |
| A referenced intranet entity exists (assignment group, assignment, submission definition) | Only checkable by the operator, which knows the activity structure. A node pointing at a deleted entity is graded absent |

### Flags and fields

| Rule | Rationale |
|----|----|
| `mandatory` and `ignored` are never both set | An ignored node takes no part in computation, so it can never invalidate anything. The combination expresses two contradictory intents |
| `points >= 0` | Negative points break every ratio formula and can make a denominator zero or negative |
| `validationThreshold` within `[0.0, 1.0]` | It is compared against a ratio |
| `validationThreshold == 1.0` on a `TEST_CASE` node | Test cases take `validated` from the test outcome, so any other value is silently ignored. Better rejected than quietly dropped |
| `aggregation` is unused on leaf nodes | Same reasoning: silently ignored today |

### Adjustment nodes

| Rule | Rationale |
|----|----|
| An adjustment node has no children | It resolves a single test outcome; children would never be visited |
| `mandatory` is not set on an adjustment node | An adjustment node is excluded from scoring and has no meaningful `validated` |
| `validationThreshold` and `absenceBehavior` are unused on an adjustment node | Not consulted during evaluation |
| `adjustment.ratio` within `[0.0, 1.0]` | It is a fraction of the scale it applies to |

### Data assumptions

| Rule | Rationale |
|----|----|
| No two tests under the same submission definition share a name | A deliberate design assumption (see the Assumptions section of the data-model doc) rather than something the model enforces. Whether this belongs in the scheme validator or at trace-ingestion time is **not decided** - ingestion is where the duplicate would first be observable, but the scheme is where it does damage |

## Idea: a trace validator

**Status: an idea, nothing decided.** The scheme validator above checks that a *scheme* is well-formed. The mirror
problem is that a scheme can be perfectly valid and still produce nonsense grades because the *traces* it grades
against are not usable. A trace validator would be a pass over the traces produced for a submission, answering "can
the grading system actually work with this?"

This would be a big change and interacts awkwardly with how ingestion works today (see below), so it is written down
as a direction rather than a plan.

### What could be checked on a trace

**Structural - the trace is parseable at all**

* The object at `traceUrl` parses as JUnit XML (`Xml.deserialize(raw, Trace.class)` does not throw). Today a
  malformed trace surfaces as an exception in the middle of `ingestTrace`, inside the ingestion transaction.
* Every `<testcase>` carries a non-empty `classname` and `name`. Both go into the test's URI, so an empty one gives a
  URI no scheme can meaningfully reference.
* The trace is non-empty when the job reported `RESULT_UPLOADED`. A job that claims to have results but produced no
  test case is a worker problem, and every node pointing at it silently falls into `absenceBehavior`.

**Identity - the assumptions the grading model relies on**

* No two `<testcase>` entries in one trace share the same `(classname, name)`. This is the enforcement point for the
  test-name uniqueness assumption the data model adopted: a trace is the only place a duplicate is actually
  observable, and `DiscoveredTest` silently collapses duplicates into one row today.
* Depending on how strictly the assumption is read, also: no two entries share the same `name` across different
  classnames within the same submission definition.
* `classname` has the dotted shape the category level of the tree expects.

**Coverage - the trace fits the scheme and the cohort**

* Every test the scheme references via a `TEST_CASE` node appears in the trace. If it does not, every student silently
  falls through to `absenceBehavior`, which is exactly the kind of failure that looks like a grading bug rather than
  a data problem.
* Tests present in the catalog for this submission definition but absent from this student's trace, and the reverse. This is
  **not** an error - cheat-detection and compilation tests legitimately appear only sometimes - but it is a useful
  signal: "this trace is missing the 30 tests every other student produced" is almost always a compilation failure
  worth surfacing to a teacher rather than silently grading as a pile of absences.
* A retry producing dramatically fewer tests than the previous job for the same submission.

### Where this collides with the current ingestion model

> *(2026-10-23)* Outdated by the repo-grades rework: `repo-grades` no longer ingests traces or keeps
> `DiscoveredTest`/`TestResult`, it parses traces at computation time, and test discovery moved to the operator. The
> ordering problem below mostly disappears; what is left is deciding which app (operator at discovery, `repo-grades`
> at computation) runs which trace check. Kept for the record.

`DataIngestionService.ingestTrace` parses the trace and upserts `DiscoveredTest` and `TestResult` rows as it goes,
inside the ingestion transaction. There is no point at which a whole trace has been examined but nothing written.

That makes the ordering a real design question rather than a detail:

* **Validate before ingesting** means either parsing twice, or restructuring `ingestTrace` into a parse step, a
  validation step, and a write step. The cleanest, and the most invasive.
* **Validate after ingesting** means rows for a trace later judged invalid are already in the catalog - and
  `DiscoveredTest` is deliberately never pruned, so those entries stay resolvable forever. A teacher authoring a
  scheme would see them in the picker.
* **Quarantine** - ingest, but flag the job so grading skips it - keeps ingestion untouched but needs somewhere to
  record the verdict (a job status, or a new table) and a decision about what grading does with a quarantined job:
  treat it as absence, or refuse to compute.

Two further things to settle before any of this:

* `srvc-packager` already calls `trace.isValid()` before uploading, which is why `repo-grades` does not re-validate
  on read. A second validation pass means deciding which side owns which check, rather than duplicating.
* Trace validation is naturally **per job**, while the uniqueness assumption is **per submission definition**. Some
  of the checks above cannot be answered from a single trace at all.

## Open questions

* Should `GradingSchemeValidator` move to a module both `repo-grades` and `srvc-activity-operator` use, so that the
  two validations run the same rules? To be decided with the team.

Settled on 2026-10-23:

* Reject or save as a draft: **reject** (see "When it should run").
* Which app checks what: both run the tree rules (team decision); only the operator can check that referenced
  entities exist. A rejection reaches the teacher through the operator's own validation, before the command is sent;
  a rejection in `repo-grades` is only logged, and its sender sees that the scheme's `lastCommandId` did not move.
* Test-name uniqueness: on both sides, `DUPLICATE_URI` in the scheme and `DUPLICATE_TEST_CASE` when a trace is read
  (see "Implementation").
* Error shape: a collected list of `(nodeUri, Rule)` violations, which `repo-grades` reports as one `INVALID_SCHEME`
  error (a `GradesErrorCodes` entry) listing them all.

## Implementation (2026-10-23)

`GradingSchemeValidator.validate(PutGradingSchemeCommand)` returns every violation, as `(nodeUri, Rule)` pairs (a null
`nodeUri` for scheme-level rules), rather than stopping at the first, so that the operator can show them all. It
depends on nothing but the exchange messages, so it can move to a module the operator also uses, which would make the
two validations one set of rules called from two places. Whether to do so is for the team to decide.

How the rules above map to `Rule`, and how they changed while implementing:

* Kept as written: `ROOT_NOT_AT_TOP`, `ROOT_BELOW_TOP`, `ROOT_URI_NOT_ACTIVITY`, `WRONG_HIERARCHY`,
  `MISSING_REFERENCE`, `DUPLICATE_URI`, `URI_NOT_UNDER_PARENT`, `TEST_URI_NOT_ONE_SEGMENT`, `MANDATORY_AND_IGNORED`,
  `NEGATIVE_POINTS`, `THRESHOLD_OUT_OF_RANGE`, `TEST_CASE_THRESHOLD_NOT_ONE`, `MANDATORY_ADJUSTMENT`,
  `ADJUSTMENT_RATIO_OUT_OF_RANGE`.
* `NOTHING_TO_GRADE` checks the root's **direct** children only (at least one neither ignored nor an adjustment). A
  tree with no test node at all is accepted: the operator may build it before the first submission, when no test is
  known yet.
* Added: `FINAL_MAX_NOT_POSITIVE`, `MISSING_ABSENCE_BEHAVIOR` and `MISSING_AGGREGATION` (the computation dereferences
  both), `MISSING_ADJUSTMENT_KIND`, `ADJUSTMENT_NOT_ON_TEST_CASE` (which, with the hierarchy, also covers "an
  adjustment node has no children"), and `PICK_OUTSIDE_SUBMISSION_DEF`.
* Dropped: "`aggregation` is unused on leaf nodes" and "`validationThreshold` and `absenceBehavior` are unused on an
  adjustment node". These fields always hold a value in the messages, so "unused" cannot be told from "set"; the
  computation ignores them there.
* Not checkable here, left to the operator: "a referenced intranet entity exists".
* Covered by `DUPLICATE_URI`: "no two tests under the same submission definition share a name", on the scheme's side.
  Its trace side is `DUPLICATE_TEST_CASE`, raised when a trace is read.
