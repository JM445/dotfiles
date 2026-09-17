# Grading System: Scheme Validator

## Why this document exists

A `GradingScheme` is authored by teachers through the frontend, and most of the grade computation assumes the tree it
walks is well-formed. Rather than scattering defensive checks through `GradingService`, the intent is a single
validation pass that a scheme must clear before it can be used to compute anything.

That validator is **not implemented yet**. This file collects the rules as they surface during design and
implementation, so none of them are lost by the time it gets written. Every rule below came out of an actual design
decision - the rationale is kept so that a rule is never dropped just because its reason was forgotten.

Companion to `grading-system-data-model-design-decisions.md`, which defines the model these rules constrain.

## When it should run

At minimum before a scheme is saved, and again before a computation runs against it - a scheme can become invalid
without being edited (a referenced `DiscoveredTest` could be pruned, a submission definition could disappear from the
activity aggregate).

Open question: whether a scheme that fails validation is rejected outright at save time, or saved as a draft and only
blocked from computing. Not decided.

## Rules

### Tree structure

| Rule | Rationale |
|----|----|
| A scheme has exactly one root: the only node with no parent | Already enforced in the DB by the partial unique index `grading_node (scheme_id) WHERE parent_id IS NULL` |
| `scheme.root_node_id` points at a node that is parentless **and** belongs to that same scheme | The FK alone allows it to point at a mid-tree node, or at a node from another scheme |
| A node's parent belongs to the same scheme as the node | Nothing in the schema ties `child.scheme_id` to `parent.scheme_id` |
| No cycles: a node is never its own ancestor | `parent_id` is a self-FK with nothing preventing a loop; the recursive walk would not terminate |
| The root has at least one non-excluded child | A scheme whose only child is, say, a "Penalties" grouping node has every child excluded, so the root is excluded too and no grade can be produced |
| Node reference types follow the hierarchy: `ASSIGNMENT_GROUP` > `ASSIGNMENT` > `TEST_CATEGORY` > `TEST_CASE` | The model assumes this ordering; a `TEST_CASE` with children, or an `ASSIGNMENT` under a `TEST_CASE`, is meaningless |

### References

| Rule | Rationale |
|----|----|
| A `TEST_CASE` node has a non-null `ref_discovered_test_id` | The column is nullable because the whole `NodeReference` is a flattened embeddable, so the DB cannot require it per ref type. A null reaches `findByIdOptional(null)` at compute time |
| `discoveredTestId` points at an existing `DiscoveredTest` | Already enforced by the FK. Kept here because the validator should give a readable error rather than surfacing a constraint violation |
| A `TEST_CASE` node's `submissionDefUri` refers to an existing submission definition | Resolved at compute time, where a miss currently throws |
| The referenced `DiscoveredTest` belongs to the assignment of the referenced submission definition | Nothing structurally prevents pairing a test from one assignment with a submission definition from another; the resulting grade would be silently wrong rather than failing |

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
* Every `<testcase>` carries a non-empty `classname` and `name`. Both are part of the `DiscoveredTest` natural key,
  so an empty one produces a catalog entry no scheme can meaningfully reference.
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

* Every test the scheme references via a `TestCaseRef` appears in the trace. If it does not, every student silently
  falls through to `absenceBehavior`, which is exactly the kind of failure that looks like a grading bug rather than
  a data problem.
* Tests present in the catalog for this assignment but absent from this student's trace, and the reverse. This is
  **not** an error - cheat-detection and compilation tests legitimately appear only sometimes - but it is a useful
  signal: "this trace is missing the 30 tests every other student produced" is almost always a compilation failure
  worth surfacing to a teacher rather than silently grading as a pile of absences.
* A retry producing dramatically fewer tests than the previous job for the same submission.

### Where this collides with the current ingestion model

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

* `srvc-packager` already calls `trace.isValid()` before uploading, which is why `srvc-grades` does not re-validate
  on read. A second validation pass means deciding which side owns which check, rather than duplicating.
* Trace validation is naturally **per job**, while the uniqueness assumption is **per submission definition**. Some
  of the checks above cannot be answered from a single trace at all.

## Open questions

* Reject on save, or save as draft and block computation? See "When it should run".
* Where does the test-name uniqueness check live - scheme validation or trace ingestion?
* Should validation failures reuse `GradesErrorCodes`, or return a collected list of problems so the frontend can show
  every issue at once rather than one at a time? The error-handling approach for the grading service as a whole is
  still undecided and should be settled first.
