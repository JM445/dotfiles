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

`root` is a stored FK (`grading_scheme.root_node_id`). Nodes keep their own `scheme` reference as well, so that
scheme-wide flat queries (validation, listing every node of a scheme) don't have to walk the tree. That makes the
two FKs circular, which is fine as long as `root_node_id` is nullable: Hibernate inserts the scheme, cascades the
tree, then updates the pointer. A partial unique index on `grading_node (scheme_id) WHERE parent_id IS NULL`
guarantees a scheme has exactly one parentless node.

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
  scheme:              GradingScheme        // owning scheme, kept on every node for flat queries
  label:               String
  reference:           NodeReference
  points:              double               // the node's own maximum, static across all students
  validationThreshold: double               // fraction [0.0 -> 1.0]; default 1.0 for test cases
  mandatory:           boolean
  ignored:             boolean
  absenceBehavior:     AbsenceBehavior
  aggregation:         AggregationRule
  adjustment:          GradeAdjustment?     // non-null marks a bonus/malus node
  children:            List<GradingNode>
```

### points

`points` is the node's **own maximum**, and it is static: it is declared on the scheme and is the same for every
student. This is the central constraint of the whole model - two students must never be graded against different
maxima for the same node, or their grades cannot be compared or justified when one of them objects.

There is no percentage-based weight type - equal distribution is a frontend concern (a button that sets all siblings
to `parentPoints / siblingCount`).

> TODO: floating point - still undecided between rounding stored values, accepting slight drift, or storing integers scaled up (x1000 or x10000).

### Scoring

Every node produces a **ratio** in `[0.0 -> 1.0]`, and:

```
score(node) = node.points x ratio(node)
```

The aggregation rule only decides how a node's ratio is derived from its children. Scale enters in exactly one place,
and `score` is always bounded by the node's static `points`.

Leaves are the base case: ratio is `1.0` when the test passed, `0.0` when it failed.

A node is **excluded** when it is `ignored`, when it is absent with an `IGNORE` behavior, or when it carries an
`adjustment` (see below). Excluded nodes take no part in their parent's ratio. A non-leaf with no non-excluded child
is itself excluded - which is what keeps a ratio from ever being computed over an empty set.

Because each node's ratio is computed only over the children that were actually assessable, an excluded child neither
rewards nor penalises the student: the remaining children simply carry the node's full `points`.

### validationThreshold

```
validated = ratio >= validationThreshold
```

Only applied to aggregating nodes. Test cases are binary and take `validated` straight from the test outcome: running
the fraction on them would make a test case worth 0 point come out validated, which would let it slip past the
mandatory check below. The scheme validator should reject a `validationThreshold` other than `1.0` on a test case,
since it is silently unused there.

Configurable for higher levels (e.g. 0.5 means "at least half the points").

### effectiveMax

```
effectiveMax(node) = node.points x (sum of points of non-excluded children / sum of points of all children)
```

`effectiveMax` is **audit data only**. It drives nothing - not the score, not `validated` - and exists to answer a
single question: "how much of this node was actually assessable for this student?" A student who sees a score out of
ten with four of the ten test cases ignored needs that recorded somewhere, or the grade cannot be justified.

It is deliberately kept out of score computation because it is **dynamic**: it shrinks per student as things are
ignored or absent. Letting it into the score would break the static-maximum rule above.

At a leaf it is `points`, or `0` when the leaf is excluded.

Note that `score` and `validated` are separate things - a node can score non-zero but not be validated (below threshold), or score zero but be validated (absent + `PASS`). This is why `validated` is stored explicitly in `NodeResult` rather than derived from score alone.

### Flags

`mandatory` - a **global** invalidation flag: if any node carrying it is not validated, the whole report is invalid,
wherever that node sits in the tree. It is deliberately decoupled from score aggregation - `validated` stays a purely
local information and a mandatory failure never changes what a parent sums. Evaluated in a flat pass after the whole
tree has been scored.

This replaces an earlier per-parent propagation design (a mandatory child dragging down its direct parent). That
version conflated two different features and made "how far up does the failure travel" ambiguous at every level; a
single global check has no such ambiguity.

The report carries the verdict on its root `NodeResult`: a global mandatory failure sets `validated = false` there and
leaves every score untouched, so the computed grade stays honest and the flag is what says the report does not count.

`ignored` - this node and its entire subtree are excluded from computation. Takes priority over everything else, including `mandatory` (a node cannot be both). The scheme validator should reject that combination.

`absenceBehavior` - applies when no submission data exists for this node. Absence can happen at any level, not just test cases (e.g. a student with no trace at all for a given assignment).

* `IGNORE` : exclude from computation, same effect as `ignored` for this submission
* `PASS` : consider the node validated with full points (e.g. no cheat tests = no cheating detected)
* `FAIL` : consider the node failed with 0 points

Priority order when multiple flags apply: `ignored` > `absenceBehavior` > `mandatory` > normal scoring. A node left
out of the computation cannot invalidate the report, whether it was excluded by its own `ignored` flag or because it
was absent with an `IGNORE` behavior.


### AggregationRule

How a node derives its ratio, over its non-excluded children:

| Rule | ratio |
|----|----|
| `SUM` | `sum(child.score) / sum(child.points)` - children weighted by their own points |
| `AVERAGE` | mean of the children ratios, every child counting equally regardless of its points |
| `MIN_CHILD` | `min(child ratio)` |
| `MAX_CHILD` | `max(child ratio)` |

`AVERAGE` replaces an earlier `WEIGHTED_AVERAGE` rule. A points-weighted average of the children ratios is
`sum(child.ratio x child.points) / sum(child.points)`, which is exactly `sum(child.score) / sum(child.points)` - the
same expression as `SUM`. The two rules were provably identical, so the useful distinction is the other one: `SUM`
weights children by their points, `AVERAGE` gives every child the same weight no matter how many tests it contains.

`MIN_CHILD`/`MAX_CHILD` compare **ratios**, never raw scores: a child worth 10 points scoring 3 must not count as
better than a child worth 2 points scoring 2. Their intended use is several tests checking the same thing, where the
teacher wants the worst (or best) attempt to decide.


### Adjustments (bonus / malus)

A node carrying a non-null `adjustment` is a bonus/malus node. It is **excluded from its parent's ratio** exactly like
an ignored node, and is evaluated separately.

```
GradeAdjustment
  kind:  BONUS | MALUS
  ratio: double            // fraction [0.0 -> 1.0] of the scale it is applied to
```

The node resolves a test outcome like any other leaf. A `MALUS` fires when that test **fails**, a `BONUS` when it
**passes**. An absent test never fires an adjustment, bonus or malus - which is exactly what makes the motivating case
work with no extra machinery: a student with no trash files has no `TestResult` row for the trash-file test, so no
malus fires.

Adjustments are stored as a **ratio**, not as absolute points. Absolute points would only be meaningful at the root
("-1 out of 20"), and applying the same adjustment at an interior node later would have no well-defined scale. A
ratio generalises to any level. Entering a fixed point value is a frontend concern: it converts to a ratio against
`finalMax` before saving, and may later offer a toggle between the two.

**For now every adjustment applies to the final grade**, wherever its node sits in the tree. Node position is purely
organisational - a trash-file malus can live under the assignment it belongs to - but has no effect on where the
adjustment lands. Keeping them as tree nodes rather than a flat list on the scheme is what makes applying them at an
arbitrary level a later change to *where the deduction lands* rather than a re-model.

Because adjustment nodes are excluded, a node whose children are *all* adjustments has no non-excluded child and is
therefore itself excluded, by the general rule. A "Penalties" grouping node holding only maluses is a natural way to
author this and needs no special case.

### NodeReference

Typed discriminant linking a node to its intranet entity:

```
NodeReference (sealed)
  AssignmentGroupRef  { assignmentGroupUri: String }
  AssignmentRef       { assignmentUri: String }
  TestCategoryRef     { assignmentUri: String, classname: String }
  TestCaseRef         { submissionDefUri: String, discoveredTestId: UUID }
```

All levels reference their intranet entity by URI, never by slug - URIs are the globally unique identifier here (see
the `DiscoveredTest` key discussion below).

`TestCaseRef` references a `DiscoveredTest` by UUID to avoid dealing with the full composite key everywhere. It still
needs `submissionDefUri` alongside it: a `DiscoveredTest` is keyed on the *assignment*, and an assignment may declare
several submission definitions, so the test identity alone does not say which submission definition a student is
graded against - and resolving a student to a group, then to a picked submission, requires exactly that.

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
  finalGrade:    double     // pure tree computation, adjustments NOT included
  finalMax:      double     // copied from scheme at computation time
  adjustmentTotal: double   // signed sum of every adjustment that fired
  status:        ReportStatus
  nodeResults:   Map<UUID, NodeResult>   // keyed by GradingNode.id
```

`finalGrade` and `adjustmentTotal` are stored separately and `finalGrade` never includes the adjustments. They are
combined only when the report is written out for teachers:

```
exportedGrade = clamp(finalGrade + adjustmentTotal, 0, finalMax)
```

Keeping them apart is the same transparency argument as `effectiveMax`: a student looking at 17/20 has to be able to
see that it was 19 minus 2 for trash files. Note the clamp is applied at export only, so a report can legitimately
record a `finalGrade + adjustmentTotal` above `finalMax` or below zero.

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

For an adjustment node, `score` records the signed amount that fired (negative for a malus, zero if it did not fire)
and `effectiveMax` is `0`, since the node takes no part in its parent's ratio.

## Grade Computation Algorithm

Bottom-up (leaves first). Every node produces a ratio, and `score = node.points x ratio`:

1. If `ignored` is set, the node and its whole subtree are excluded. Stop.
2. If the node carries an `adjustment`, it is excluded from its parent and evaluated separately. Stop.
3. If no data exists for this node, apply `absenceBehavior`. If `IGNORE`, the node is excluded. Stop.
4. Leaf nodes: read the `TestResult` row for the `DiscoveredTest` referenced by the node's `TestCaseRef`. ratio is
   `1.0` on success, `0.0` on failure.
5. Non-leaf nodes: derive the ratio from the non-excluded children with the node's `aggregation` rule. A node left
   with no non-excluded child is itself excluded.
6. `score = node.points x ratio`.
7. `validated = ratio >= validationThreshold` for aggregating nodes, the test outcome itself for test cases.
8. Record `effectiveMax` for audit.

Then, once the whole tree is scored:

1. **Mandatory pass**: if any non-excluded node flagged `mandatory` is not validated, set `validated = false` on the
   root's `NodeResult`. Scores are not rewritten.
2. `finalGrade = root.ratio x finalMax`.
3. `adjustmentTotal` = the signed sum of every adjustment that fired, each as `±(adjustment.ratio x finalMax)`.

`finalGrade` and `adjustmentTotal` are recorded separately; they are combined and clamped only at export time.

## Out of Scope (for now)

* Workshop grading (last-reached strategy, notion-based scoring)
* YAML-defined grading schemes
* Student-facing grade visibility (teacher-only for now, Auriga integration possible later)
* Automatic recomputation on scheme change
* Applying a bonus/malus at an arbitrary level of the tree rather than to the final grade
* Several distinct tests sharing one name inside a submission definition (see Assumptions)

## Assumptions

**Test names are unique within a submission definition.** Teachers are responsible for ensuring no two tests under the
same submission definition share a name. Anything that would naturally produce one test per occurrence - one test per
trash file, one per compilation warning - must instead be a single test listing the occurrences in its failure
message, for the student's reference. The consequence is that a malus is the same for one trash file or ten.

This is a deliberate simplification: a node that had to count a variable number of failing tests, discovered per
student and unknown when the scheme is authored, needs machinery that nothing else in this model requires. It can be
revisited, but not for a first implementation.

## Related documents

* `grading-system-scheme-validator.md` - the rules a grading scheme must satisfy before it can be used.
