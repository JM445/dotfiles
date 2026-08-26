# Grading System: Data Model & Design Decisions

## Scope

Exams and Projects only for now. Workshop grading is out of scope for the initial implementation, but the model should not make it impossible to add later.

## Activity Types

### Exam

* Multiple independent assignments or assignment groups
* Tree structure with aggregation rules applied recursively
* Granularity: AssignmentGroup → Assignment → TestCategory → TestCase

### Project

* Single assignment defines the final grade
* Granularity: Assignment → TestCategory → TestCase

## Core Entities

### GradingScheme

Configuration template for an activity's grading. Every modification increments the version rather than overwriting - existing reports keep a reference to the version they were computed against and are never silently invalidated. When a scheme changes, associated reports are marked `STALE` instead of deleted.

```
GradingScheme
  id:          UUID
  version:     int
  activityUri: String
  finalMax:    double       // total grade scale (e.g. 20.0 for a grade out of 20)
  createdAt:   Instant
  updatedAt:   Instant
  root:        GradingNode  // synthetic root node at activity level
```

### GradingNode

A node in the grading tree. The tree always follows this hierarchy:

```
Activity root
  L---- AssignmentGroup   (optional)
        L---- Assignment
              L---- TestCategory
                    L---- TestCase
```

```
GradingNode
  id:                  UUID
  label:               String
  reference:           NodeReference
  points:              double               // contribution to parent's effective max
  validationThreshold: double               // fraction [0.0 -> 1.0]; default 1.0 for test cases
  mandatory:           boolean
  ignored:             boolean
  absenceBehavior:     AbsenceBehavior
  aggregation:         AggregationRule
  children:            List<GradingNode>
```

### points

Each node has a `points` value representing its contribution to the parent's effective max. There is no percentage-based weight type - equal distribution is a frontend concern (a button that sets all siblings to `parentEffectiveMax / siblingCount`).

The parent's effective max is always derived from its children:

```
effectiveMax(node) = sum of points for all non-ignored, non-absent-IGNORE children
```

It is never stored on the parent node, which avoids any inconsistency between a declared max and what the children actually sum to.

> TODO: floating point - still undecided between rounding stored values, accepting slight drift, or storing integers scaled up (x1000 or x10000).

### validationThreshold

```
validated = (score / effectiveMax) >= validationThreshold
```

Defaults to `1.0` for test cases (JUnit tests are binary). Configurable for higher levels (e.g. 0.5 means "at least half the points").

Note that `score` and `validated` are separate things - a node can score non-zero but not be validated (below threshold), or score zero but be validated (absent + `PASS`). This is why `validated` is stored explicitly in `NodeResult` rather than derived from score alone.

### Flags

`mandatory` - if this node is not validated, the parent's score is forced to 0 regardless of other children. Evaluated after all children are scored.

`ignored` - this node and its entire subtree are excluded from computation. Takes priority over everything else, including `mandatory` (a node cannot be both). The scheme validator should reject that combination.

`absenceBehavior` - applies when no submission data exists for this node. Absence can happen at any level, not just test cases (e.g. a student with no trace at all for a given assignment).

* `IGNORE` : exclude from computation, same effect as `ignored` for this submission
* `PASS` : consider the node validated with full points (e.g. no cheat tests = no cheating detected)
* `FAIL` : consider the node failed with 0 points

Priority order when multiple flags apply: `ignored` > `absenceBehavior` > `mandatory` > normal scoring.


### AggregationRule

| Rule | Behavior |
|----|----|
| `SUM` | Sum all children scores directly |
| `WEIGHTED_AVERAGE` | Weighted average of children scores (weight = points), scaled to effectiveMax |
| `MIN_CHILD` | Score equals the lowest child score (normalized) |
| `MAX_CHILD` | Score equals the highest child score (normalized) |


### NodeReference

Typed discriminant linking a node to its intranet entity:

```
NodeReference (sealed)
  AssignmentGroupRef  { assignmentGroupSlug: String }
  AssignmentRef       { assignmentSlug: String }
  TestCategoryRef     { assignmentSlug: String, classname: String }
  TestCaseRef         { discoveredTestId: UUID }
```

`TestCaseRef` references a `DiscoveredTest` by UUID to avoid dealing with the full composite key everywhere.

### DiscoveredTest

Tests are not predefined - they are discovered from JUnit XML results produced by MaaS workers. Discovery happens synchronously at `SubmissionAggregate` ingestion: for each `Job` with status `RESULT_UPLOADED`, the trace at `traceUrl` is fetched and parsed, and one `DiscoveredTest` is upserted per distinct `(classname, testKey)` found. Re-ingestion of a retried job (same `Job.id`, new `traceUrl`) naturally re-triggers parsing, so no separate retry-detection mechanism is needed.

```
DiscoveredTest
  id:              UUID
  activityUri:     String
  assignmentUri:   String
  classname:       String    // <testcase classname="...">
  testKey:         String    // <testcase name="...">
  firstSeenAt:     Instant
  lastSeenAt:      Instant
  occurrenceCount: int
```

Natural (unique) key: `(assignmentUri, classname, testKey)` — `activityUri` is deliberately excluded from it, since URIs on this intranet are globally unique strings built by concatenating parent URIs (`assignmentUri` already embeds its owning `activityUri`), so including `activityUri` in the key would add no actual uniqueness guarantee. It's kept as a plain, non-key column purely for activity-wide queries (an `Exam` spans multiple assignments under one `activityUri`; without this column, listing every discovered test across the whole exam would require first enumerating all of its assignment URIs). Both URI fields are stored verbatim (no parsing) — they're already available as-is on the loaded `SubmissionDefinitionModel` at ingestion time.

A teacher can only reference a test in a scheme after at least one submission has produced it. The scheme validator rejects `TestCaseRef` pointing to an unknown `discoveredTestId`.

Many tests only appear in some submissions (cheat detection, compilation errors/warnings, etc.) - this is expected. The `absenceBehavior` on the node handles the semantic for each case.

`DiscoveredTest` is a dimension/catalog table, not a duplicate of `TestResult` below: it answers "does this test conceptually exist for this activity", independent of any one submission's outcome, and it is what `GradingNode.reference` (`TestCaseRef`) points to. Keeping it separate (rather than deriving the set of known tests live from `TestResult`) matters for two reasons: it stays resolvable even if older `TestResult` rows are later archived/pruned for space, and `firstSeenAt`/`lastSeenAt`/`occurrenceCount` are cheap reads for the scheme-authoring UI instead of a live aggregate over a potentially huge result table.

### TestResult

The actual per-submission outcome for one discovered test - persisted at ingestion time (see above), not re-derived from S3 traces at grade-computation time. One row per `(Job, DiscoveredTest)`.

```
TestResult
  id:             UUID
  discoveredTest: DiscoveredTest   // FK - test identity lives here, not duplicated as classname/testKey strings
  jobId:          UUID
  submissionId:   UUID
  success:        boolean
  failMessage:    String?
```

Storing all results at ingestion time (rather than re-parsing traces on every grade computation/recomputation) trades DB storage growth for: fast, repeatable grade computation that doesn't depend on S3 trace objects still existing or being reachable at compute time, and no repeated S3 load when a teacher recomputes a scheme multiple times while iterating on it.

### GradeReport

Computed grade for one student on one activity. A new report is created on each recomputation rather than overwriting the previous one.

```
GradeReport
  id:            UUID
  schemeId:      UUID
  schemeVersion: int
  studentId:     String
  activityUri:   String
  computedAt:    Instant
  finalGrade:    double
  finalMax:      double     // copied from scheme at computation time
  status:        ReportStatus
  nodeResults:   Map<UUID, NodeResult>   // keyed by GradingNode.id
```

```
enum ReportStatus { FRESH | STALE | COMPUTING | FAILED }
```

Recomputation is asynchronous and frontend-triggered. When a scheme is modified, associated reports move to `STALE` - the last known grade stays visible but flagged as outdated until the frontend requests a recomputation.

A student may have multiple submissions for the same assignment. The grading service always picks the canonical one using the activity's existing `pickStrategy`.

### NodeResult

```
NodeResult
  nodeId:        UUID
  score:         double
  effectiveMax:  double
  validated:     boolean
  absenceStatus: AbsenceStatus
  override:      GradeOverride?

enum AbsenceStatus { PRESENT | ABSENT_PASS | ABSENT_FAIL | ABSENT_IGNORE | IGNORED }

GradeOverride
  score:    double
  reason:   String
  by:       String
  at:       Instant
```

## Grade Computation Algorithm

Bottom-up (leaves first):


1. If no data exists for this node, apply `absenceBehavior`. If `IGNORE`, exclude from parent and stop.
2. If `ignored` is set, exclude from parent and stop.
3. For leaf nodes: read the `TestResult` row for `(submission, discoveredTest)` referenced by the node's `TestCaseRef`.
4. For non-leaf nodes: apply `aggregation` rule over non-excluded children.
5. Compute `effectiveMax` as the sum of `points` of non-excluded children.
6. Compute `validated`: `score / effectiveMax >= validationThreshold`.
7. If any mandatory child is not validated, force this node's score to 0.
8. Bubble up score and points to parent.

## Out of Scope (for now)

* Workshop grading (last-reached strategy, notion-based scoring)
* YAML-defined grading schemes
* Student-facing grade visibility (teacher-only for now, Auriga integration possible later)
* Automatic recomputation on scheme change
* Bonus points / grade caps