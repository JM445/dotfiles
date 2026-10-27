# Grading System: Data Model & Design Decisions

## Overview

`repo-grades` (`apps/repo-grades`, package `fr.epita.forge.repo.grades`) is the source of truth for grading schemes
and grade reports. Its Kafka messages live in `exchange` under `fr.epita.forge.grades`.

* All communication goes through Kafka and is asynchronous. `repo-grades` exposes no REST endpoint: the endpoints live
  in `srvc-activity-operator`, which sends commands and consumes the aggregates published here (see
  `Kafka Communication`).
* `srvc-activity-operator` builds the grading tree and owns test discovery. `repo-grades` keeps no test catalog: a test
  node references its test by a URI built from the trace's names.
* Nodes are identified by the URI of what they grade.
* `repo-grades` ingests `SubmissionAggregate` and keeps, for each job, the S3 address of its trace. Traces are parsed
  **at computation time and never stored**.
* No history: neither schemes nor reports keep past versions, and consumers keep only the last aggregate they received.

## Scope

Exams and Projects only for now. Workshop grading is out of scope, but the model should not make it impossible to add
later.

* **Exam**: several independent assignments or assignment groups, aggregated recursively.
  AssignmentGroup → Assignment → SubmissionDefinition → TestCategory → TestCase
* **Project**: a single assignment defines the final grade.
  Assignment → SubmissionDefinition → TestCategory → TestCase

## Core Entities

### GradingScheme

Configuration of an activity's grading. An activity has **exactly one** scheme (unique on `activityUri`), edited in
place: every modification bumps `version` on the same row. Edits arrive as a whole tree (`PutGradingSchemeCommand`),
which replaces the stored one.

Reports record the `schemeVersion` they were computed against, so a report whose version differs from the scheme's is
stale by construction - nothing has to be updated on edit. The cost: a stale report's `nodeResults` may reference
nodes that have since changed or been deleted. Snapshotting the tree into the report would fix this; deferred.

Several schemes per activity may be allowed later (e.g. a teacher trying alternatives). Anything keyed on the scheme
rather than on the activity will survive that change.

```
GradingScheme
  id:          UUID
  version:     int
  activityUri: String
  finalMax:    double       // total grade scale (e.g. 20.0 for a grade out of 20)
  createdAt:   Instant
  updatedAt:   Instant
  root:        GradingNode  // synthetic root node at activity level, stored as jsonb
```

**Storage.** The tree is a single `jsonb` column on the scheme (`@Type(JsonType.class)`), like
`GradeReport.nodeResults` and `repo-submission`'s `Activity.activityGraph`. Since edits replace the whole tree, this is
one column write with no node-by-node diffing. `GradingNode` is a plain nested object, not an entity, and has no
`parent` back-pointer. Flat queries over a scheme's nodes walk the tree in Java, which is fine at this size.

### GradingNode

A node in the grading tree. The tree always follows this hierarchy:

```
Activity root
  L---- AssignmentGroup   (optional)
        L---- Assignment
              L---- SubmissionDefinition
                    L---- TestCategory
                          L---- TestCase
```

The `SubmissionDefinition` level exists because an assignment may declare several definitions running tests that
share names but not meaning (e.g. a "practice" definition students run during the project, and a "final" one with
different values). Each needs its own subtree to be weighted, ignored or flagged independently.

`srvc-activity-operator` generates the initial tree from the activity structure and the tests it discovered, and
sends it whole. Every later edit is also a whole tree. `repo-grades` never builds nodes itself.

A node is identified by the URI of the entity it grades (see `NodeReference`). Ids stay stable without the operator
having to remember them: a tree regenerated from scratch gives the same test the same id, so `nodeResults` and
overrides keep pointing at the same node. Ids only need to be unique within one scheme.

```
GradingNode
  reference:           NodeReference        // type + uri; the uri is the node's id
  label:               String
  points:              double               // the node's own maximum, static across all students
  validationThreshold: double               // fraction [0.0 -> 1.0]; default 1.0 for test cases
  mandatory:           boolean
  ignored:             boolean
  absenceBehavior:     AbsenceBehavior
  aggregation:         AggregationRule
  adjustment:          GradeAdjustment?     // non-null marks a bonus/malus node
  pick:                Pick?                // SUBMISSION_DEF nodes only: LAST | BEST
  children:            List<GradingNode>
```

### pick

A group may have several submissions for one submission definition; `pick` says which one is graded: `LAST` (most
recent) or `BEST` (highest success percent), the same values as `ActivityAggregate`'s `Pick`. Set on `SUBMISSION_DEF`
nodes only.

It lives in the scheme so `repo-grades` doesn't have to ingest `ActivityAggregate` for one field. The operator copies
the activity's value when generating the tree, and the teacher may change it. Consequences:

* The scheme's value can drift from the activity's if the activity is edited later, like the rest of the tree.
* Pages showing students their "picked" submission follow the activity's value, so the graded submission can differ
  from the one they see as picked.
* `BEST` needs each job's success percent (`Job.successPercent`, or `overrideSuccessPercent` when set), stored at
  ingestion next to the trace address.

### points

`points` is the node's **own maximum**, declared on the scheme and identical for every student. This is the central
constraint of the model: two students must never be graded against different maxima for the same node, or their
grades cannot be compared or justified.

There is no per-student maximum. Excluded children are justified by their own `NodeResult` (`absenceStatus`), and any
coverage figure the frontend wants can be derived from them.

There is no percentage-based weight either: equal distribution is a frontend concern (a button setting all siblings to
`parentPoints / siblingCount`).

> TODO: floating point - still undecided between rounding stored values, accepting slight drift, or storing integers
> scaled up (x1000 or x10000).

### Scoring

Every node produces a **ratio** in `[0.0 -> 1.0]`, and:

```
score(node) = node.points x ratio(node)
```

The aggregation rule only decides how a node's ratio is derived from its children, so `score` is always bounded by the
node's static `points`. Leaves: ratio is `1.0` when the test passed, `0.0` when it failed.

A node is **excluded** when it is `ignored`, absent with an `IGNORE` behavior, or carries an `adjustment`. Excluded
nodes take no part in their parent's ratio. A non-leaf with no non-excluded child is itself excluded, so a ratio is
never computed over an empty set. An excluded child neither rewards nor penalises the student: the remaining children
carry the node's full `points`.

### validationThreshold

```
validated = ratio >= validationThreshold
```

Only applied to aggregating nodes (e.g. 0.5 means "at least half the points"). Test cases take `validated` straight
from the test outcome; otherwise a 0-point test case would come out validated and slip past the mandatory check. The
validator rejects a threshold other than `1.0` on a test case.

`score` and `validated` are independent: a node can score non-zero without being validated (below threshold), or
score zero and be validated (absent + `PASS`). This is why `validated` is stored in `NodeResult`.

### Flags

`mandatory` - a **global** invalidation flag: if any node carrying it is not validated, the whole report is invalid,
wherever that node sits. It never changes what a parent sums. It is evaluated in a flat pass after the tree is scored,
and the verdict goes on the root `NodeResult`: `validated = false` there, every score untouched. The computed grade
stays honest, and the flag says the report does not count.

`ignored` - this node and its subtree are excluded from computation. Takes priority over everything, including
`mandatory` (the validator rejects both on one node).

`absenceBehavior` - applies when no submission data exists for this node, at any level (e.g. a group with no trace at
all for an assignment):

* `IGNORE` : exclude from computation, like `ignored` for this group
* `PASS` : validated with full points (e.g. no cheat tests = no cheating detected)
* `FAIL` : failed with 0 points

Priority when several apply: `ignored` > `absenceBehavior` > `mandatory` > normal scoring. A node left out of the
computation cannot invalidate the report.

### AggregationRule

How a node derives its ratio over its non-excluded children:

| Rule | ratio |
|----|----|
| `SUM` | `sum(child.score) / sum(child.points)` - children weighted by their points |
| `AVERAGE` | mean of the children ratios, every child counting equally regardless of its points |
| `MIN_CHILD` | `min(child ratio)` |
| `MAX_CHILD` | `max(child ratio)` |

A points-weighted average of ratios would be identical to `SUM`, so `AVERAGE` is deliberately unweighted.

`MIN_CHILD`/`MAX_CHILD` compare **ratios**, never raw scores: a 10-point child scoring 3 must not beat a 2-point child
scoring 2. Intended for several tests checking the same thing, where the worst (or best) attempt decides.

### Adjustments (bonus / malus)

A node with a non-null `adjustment` is a bonus/malus node. It is **excluded from its parent's ratio** and evaluated
separately.

```
GradeAdjustment
  kind:  BONUS | MALUS
  ratio: double            // fraction [0.0 -> 1.0] of the scale it is applied to
```

A `MALUS` fires when its test **fails**, a `BONUS` when it **passes**. An absent test never fires an adjustment: a
student with no trash files has no trash-file test in their trace, so no malus fires.

Adjustments are a **ratio**, not absolute points, so they keep a well-defined scale at any level. Entering points is a
frontend concern: convert against `finalMax` before saving.

**For now every adjustment applies to the final grade**, wherever its node sits. Position in the tree is purely
organisational (a malus sits where its test sits, under its own test category). Keeping adjustments as tree nodes means
applying them at an arbitrary level later only changes *where the deduction lands*, not the model.

### NodeReference

Links a node to what it grades, and doubles as its id:

```
NodeReference
  type: ROOT | ASSIGNMENT_GROUP | ASSIGNMENT | SUBMISSION_DEF | TEST_CATEGORY | TEST_CASE
  uri:  String
```

`type` is needed because a URI alone does not say what it points at: an assignment group and an assignment are both
`<parentUri>/<slug>`.

**Structural levels** (`ROOT`, `ASSIGNMENT_GROUP`, `ASSIGNMENT`, `SUBMISSION_DEF`) copy their entity's intranet URI
as-is; the root uses the activity's URI. Intranet URIs are parent URI + `/` + slug, so a URI already holds its whole
path and nested assignment groups need no special handling. Always URIs, never slugs.

**Test levels** are not intranet entities, so their URI is built from the trace's
`<testcase classname="..." name="...">` attributes:

```
TEST_CATEGORY  <submissionDefUri>/<enc(classname)>
TEST_CASE      <submissionDefUri>/<enc(classname)>/<enc(testName)>
```

`enc` is UTF-8 percent-encoding of the whole segment, `/` included, so a `/` in a test name never reads as a
separator. Categories hang off the submission definition: the same classname under two definitions gives two nodes.

The computation never parses a URI back: it builds the URI of every `<testcase>` in the trace and looks nodes up by
it. The operator (building the tree) and `repo-grades` (computing) must build test URIs identically, through one shared
function in `framework-trace` next to the shared trace parser.

A node may reference a test that no trace contains yet; it is handled at computation time like any absent test.

Consequences of the reference being the id:

* **Pointing a node at another entity makes it a different node.** Its results and overrides do not follow, which is
  intended.
* **An entity appears at most once in a scheme.** The same test cannot be both a scored node and an adjustment node.
* **Every node grades something.** There are no free grouping nodes (e.g. a "Penalties" node), since they would have no
  URI.
* **Ids are longer than UUIDs**, which weighs on report size.

The invariants between references (unique URIs, each nested under its parent's, types following the hierarchy) are
enforced by the validator, see `grading-system-scheme-validator.md`.

### Ingested data

`repo-grades` ingests `SubmissionAggregate` and keeps only what computation needs: for each submission, its group and
submission definition, and for its current job, the trace's S3 address (`Job.traceUrl`, a raw S3 key) and the success
percent `BEST` needs. A retried job (same `Job.id`, new `traceUrl`) updates the stored address. Groups are known only
through the submissions they made.

**Test results are parsed at computation time and never stored.** For each `SUBMISSION_DEF` node, the computation
picks the group's submission, fetches and parses its trace, and looks test nodes up by URI. Accepted costs:

* Recomputing depends on the trace still being in S3 (nothing is purged).
* Each computation fetches one trace per submission definition of the group.

Many tests only appear in some traces (a trash-file test only when a trash file is found; no runtime suite when
compilation fails). This is normal, and is what `absenceBehavior` handles.

### GradeReport

Computed grade for one **group** on one scheme: every member gets the same grade. There is a single report per
`(scheme, groupSlug)`, overwritten on recomputation. `activityUri` is copied from the scheme so reports can be fetched
by activity.

> Open question: groups are per submission definition, and a scheme spans several, so a student could be in different
> groups for different definitions (e.g. solo practice, pair final). One report per group assumes this never happens
> within one scheme.

`repo-grades` cannot tell an unknown group from a registered one that never submitted. Such a report is still
computed: every `SUBMISSION_DEF` node is absent and its `absenceBehavior` decides, which is correct as long as
submission definitions default to `FAIL`. Mapping groups to members is the operator's job.

```
GradeReport
  id:              UUID
  schemeId:        UUID
  schemeVersion:   int
  groupSlug:       String
  activityUri:     String
  computedAt:      Instant
  finalGrade:      double     // pure tree computation, adjustments NOT included
  finalMax:        double     // copied from scheme at computation time
  adjustmentTotal: double     // signed sum of every adjustment that fired
  status:          ReportStatus
  nodeResults:     Map<String, NodeResult> // keyed by the node's URI
```

`finalGrade` never includes adjustments. They are combined only when exported for teachers:

```
exportedGrade = clamp(finalGrade + adjustmentTotal, 0, finalMax)
```

This keeps grades transparent: a student at 17/20 can see it was 19 minus 2 for trash files. The clamp is applied at
export only.

```
enum ReportStatus { FRESH | STALE | FAILED }
```

Recomputation is asynchronous and frontend-triggered. Until then, the last grade stays visible but flagged. A report is
outdated when:

- **The scheme changed**: `report.schemeVersion != scheme.version`. Derived, never written, so it cannot drift.
- **The group's data changed**: a new submission or job arrived after the computation. Ingestion marks the report
  `STALE` and publishes it.

**`FAILED`.** A failed computation still publishes a report, otherwise the operator never learns about it. Throwing in
a Kafka consumer aborts the transaction and its outgoing messages, so the handler catches the failure, marks the report
`FAILED` with an `errorCode` and publishes it without rethrowing. The report keeps the results of its last successful
computation.

### NodeResult

```
NodeResult
  nodeUri:       String     // the node's reference.uri
  score:         double
  validated:     boolean
  absenceStatus: AbsenceStatus
  override:      GradeOverride?

enum AbsenceStatus { PRESENT | ABSENT_PASS | ABSENT_FAIL | ABSENT_IGNORE | IGNORED | NO_ASSESSABLE_CHILD }

GradeOverride
  score:    double
  reason:   String
  by:       String
  at:       Instant
```

For an adjustment node, `score` is the signed amount that fired (negative for a malus, zero if it did not fire).

`NO_ASSESSABLE_CHILD` marks an aggregating node excluded because none of its children was left to score.

**Overrides.** Set by `PutGradeOverrideCommand`; stored in the report, which is then republished. Overrides live in the
report only, so **a recomputation discards them**. The operator sees them in the last report and can warn or refuse
before requesting a computation.

* The grade is recomputed **from the stored results, not the traces**, so the override is the only thing that changes;
  newer submissions are not pulled in.
* An overridden node **keeps its computed result**; the override replaces it for the parent only. Removing it gives the
  computed result back.
* Any node can be overridden, interior ones included: descendants keep their results for the breakdown but no longer
  count. An excluded node (absent, `NO_ASSESSABLE_CHILD`) counts again once overridden.
* Rejected: an **ignored** node (un-ignore it in the scheme), a node **under an absent node** (override the absent
  node), a **FAILED** report, a report on an **older scheme version** (recompute first), a score outside
  `[0, points]` (for an adjustment: between 0 and `±ratio x finalMax`), and a missing reason.
* An overridden node is `validated` when score / points >= threshold (full points for a test case); the mandatory check
  uses this.
* The report keeps its status and `computedAt`; `lastCommandId` becomes the override command's. A null score removes
  the override. Author and date come from the message context.

## Grade Computation Algorithm

Bottom-up. Every node produces a ratio, and `score = node.points x ratio`:

1. If `ignored`, the node and its subtree are excluded. Stop.
2. If the node carries an `adjustment`, it is excluded from its parent and evaluated separately. Stop.
3. If no data exists for this node, apply `absenceBehavior` (`IGNORE` excludes it). Descendants are not scored but take
   the same absence status (`ABSENT_FAIL`: 0, not validated; `ABSENT_PASS`: full points, validated; `ABSENT_IGNORE`:
   excluded), except ignored subtrees, which record nothing, and adjustments, which never fire. Stop. This way a
   mandatory node under an absent `FAIL` node invalidates the report, and every node has a result. Data can be missing
   for a `SUBMISSION_DEF` (no graded trace) or a `TEST_CASE` (not in the trace).
4. Leaf: find the node's test by URI in the parsed trace of the group's picked submission for its `SUBMISSION_DEF`
   ancestor. ratio is `1.0` on success, `0.0` on failure.
5. Non-leaf: derive the ratio from non-excluded children with the `aggregation` rule. No non-excluded child: excluded.
6. `score = node.points x ratio`.
7. `validated = ratio >= validationThreshold` for aggregating nodes, the test outcome for test cases.

Then, once the whole tree is scored:

1. **Mandatory pass**: if any non-excluded `mandatory` node is not validated, set `validated = false` on the root's
   `NodeResult`. Scores are not rewritten.
2. `finalGrade = root.ratio x finalMax`.
3. `adjustmentTotal` = signed sum of every adjustment that fired, each `±(adjustment.ratio x finalMax)`.

## Kafka Communication

`repo-grades` publishes its data as aggregates and accepts commands from other apps to change it. Messages live in
`exchange/`: aggregates under `aggregate/<domain>/v001` with `@Version(1)`, commands under `command/` implementing
`Command`. The Kafka topic is built from the class's fully qualified name and version, so renaming or moving a class
changes its topic.

Each command carries a sender-generated `commandId`, and each aggregate echoes the last one it applied as
`lastCommandId`. Commands get no reply, so this is how the operator knows a command was applied. Rejections are not
reported yet; how command errors reach the teacher is still open.

Commands are sent with a random Kafka key, so two commands on the same scheme have no ordering guarantee. Aggregates
are keyed by `getId()`, so all versions of one aggregate arrive in order.

### Aggregates

Each aggregate is a full snapshot of its entity, republished whole on every change.

**GradingSchemeAggregate**: `Aggregate<UUID>`, keyed by the scheme id:

```
GradingSchemeAggregate:
  id:            UUID
  activityUri:   String
  version:       int             // bumped on every accepted PutGradingSchemeCommand
  finalMax:      double
  root:          Node
  createdAt:     ZonedDateTime
  updatedAt:     ZonedDateTime
  updatedBy:     String          // login of the last editor, from the command's InboundContext
  lastCommandId: UUID

Node                             // nested class, reused by PutGradingSchemeCommand
  reference:           Reference // its uri is the node's id
  label:               String
  points:              double
  validationThreshold: double
  mandatory:           boolean
  ignored:             boolean
  absenceBehavior:     IGNORE | PASS | FAIL
  aggregation:         SUM | AVERAGE | MIN_CHILD | MAX_CHILD
  adjustment:          { kind: BONUS | MALUS, ratio: double }?
  pick:                LAST | BEST?   // SUBMISSION_DEF only
  children:            List<Node>

Reference                        // see NodeReference
  type: ROOT | ASSIGNMENT_GROUP | ASSIGNMENT | SUBMISSION_DEF | TEST_CATEGORY | TEST_CASE
  uri:  String
```

**GradeReportAggregate**: `Aggregate<UUID>`, keyed by the report id, one per `(scheme, groupSlug)`, updated in place:

```
GradeReportAggregate:
  id:              UUID
  schemeId:        UUID
  schemeVersion:   int
  activityUri:     String
  groupSlug:       String
  status:          FRESH | STALE | FAILED
  errorCode:       String?        // set when FAILED
  computedAt:      ZonedDateTime  // last successful computation
  finalMax:        double
  finalGrade:      double         // adjustments not included
  adjustmentTotal: double
  nodeResults:     List<NodeResult>   // { nodeUri, score, validated, absenceStatus, override? }
  lastCommandId:   UUID
```

An exam tree down to its test cases can hold thousands of nodes, and a report carries one result per node, so both
messages can get large. `repo-events` already raises `max.partition.fetch.bytes` to consume `ActivityAggregate`; the
operator's consumers will likely need the same.

### Commands

**PutGradingSchemeCommand** creates or replaces a grading scheme:

```
PutGradingSchemeCommand:
  commandId:       UUID
  schemeId:        UUID      // generated by the sender on creation
  activityUri:     String
  expectedVersion: Integer?  // null = create; otherwise rejected if it differs from the current version
  finalMax:        double
  root:            Node      // the whole tree, replaces the stored one
```

`expectedVersion` protects against concurrent edits and the lack of ordering between commands. The author comes from
the message's `InboundContext`.

**GradeComputationCommand** computes the grade of a group on a scheme, against the scheme's current version.
Computing a whole activity is one command per group, sent by the operator:

```
GradeComputationCommand:
  commandId: UUID
  schemeId:  UUID
  groupSlug: String
```

**PutGradeOverrideCommand** sets or removes an override on a report (author and date from the message context):

```
PutGradeOverrideCommand:
  commandId: UUID
  reportId:  UUID
  nodeUri:   String
  score:     double?   // null removes the override
  reason:    String
```

## Out of Scope (for now)

* Workshop grading (last-reached strategy, notion-based scoring)
* YAML-defined grading schemes
* Student-facing grade visibility (teacher-only for now, Auriga integration possible later)
* Automatic recomputation on scheme change
* Applying a bonus/malus at an arbitrary level of the tree rather than to the final grade
* Several distinct tests sharing one name inside a submission definition (see Assumptions)
* History of schemes and reports
* Deleting a scheme or a report (when needed: soft delete with a `deletedAt` field)
* Keeping overrides across a recomputation
* Reorganising the tree freely, independently from the intranet structure, with nodes grading no intranet entity (they
  would need synthetic ids)

## Assumptions

**Test names are unique within a submission definition.** Teachers must ensure no two tests under the same submission
definition share a name. Anything that would naturally produce one test per occurrence (one per trash file, one per
compilation warning) must be a single test listing the occurrences in its failure message. A malus is therefore the
same for one trash file or ten. Counting a variable number of failing tests, discovered per student, would need
machinery nothing else in the model requires.

## Related documents

* `grading-system-scheme-validator.md` - the rules a grading scheme must satisfy before it can be used.
