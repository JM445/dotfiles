---
name: reference-framework-trace
description: Where JUnit-XML trace parsing lives in the monorepo (toolkit/framework/framework-trace) and how to fetch+parse a trace from S3
metadata:
  node_type: memory
  type: reference
  originSessionId: 10b2b0f7-23c6-4096-b45e-6a024b8057ae
  modified: 2026-08-26T15:09:15.324Z
---

JUnit-XML trace parsing already exists in the monorepo — no need to write an XML parser for `<testsuites><testsuite><testcase>` traces produced by MaaS workers. It lives in `toolkit/framework/framework-trace` (Jackson `XmlMapper`-based):

- `Trace` (root: `testCases`, `disabled/errors/failures/tests/skipped`, plus grading-adjacent `labels`/`successOverride`/`successPercentOverride`/`feedback`/`restrictedMessage`) — `isSuccess()`, `successPercent()`, `isValid()`, `testcase(name)`.
- `TestCase` (`name`, `className`, `time`, `errorList`/`failureList`) — `isPassed()`/`isFailed()`/`hasErrors()`/`hasFailures()`/`getErrorMessage()`.
- `Failure`/`Error` — body text + `message`/`type`/`restrictedMessage`.
- `TraceAsTree.fromTrace(trace)` — turns the flat `classname`-dotted test list into a category tree (splits on `.`); has `isValidated()`, `failedTestsOnly()`, pass/total rollups.

**Entrypoint** (not on `Trace` itself — it's the generic `Xml` util in `framework-core`, `fr.epita.framework.core.utils.Xml`):
```java
Trace trace = Xml.deserialize(xmlString, Trace.class);   // from a String
Trace trace = Xml.fromFile(path, Trace.class);            // from a file path
TraceAsTree tree = TraceAsTree.fromTrace(trace);
```

**Fetching from S3**: `Job.traceUrl` (wherever it appears — `SubmissionAggregate.Job`, `srvc-grades.JobModel`, etc.) is a **raw S3 object key**, not a URL, despite the name. Use it as-is:
```java
byte[] xmlBytes = s3ObjectService.getObject(ForgeConfig.S3BucketType.TRACES, job.traceUrl);
Trace trace = Xml.deserialize(new String(xmlBytes, StandardCharsets.UTF_8), Trace.class);
```
Confirmed by tracing the value end-to-end: `srvc-packager/ResultsUploadService` calls `s3Service.putObject(TRACES, uploadUrl, traceContent, ...)` and returns that same `uploadUrl` as `JobResultsUploadedEvent.traceUrl`, which `repo-submission/JobTransitionService` copies verbatim into `Job.traceUrl` — no reformatting at any hop.

**Existing consumers to reference for real usage patterns**: `port-frontend/ActivityService.java` (fetch+parse for display), `srvc-packager/ResultsUploadService.java`/`ResultsUploadV2Service.java` (parse right after upload, gate on `trace.isValid()` before accepting a trace at all — so anything already at a `traceUrl` is guaranteed valid downstream).

**Testing S3-dependent code**: nobody in this repo testcontainers-izes MinIO. The pattern is `@QuarkusTest` + `@InjectMock S3ObjectService`, stubbing `getObject(...)` — see `srvc-packager/ResultUploadServiceTest.java`.

**Why:** this is reusable knowledge for any service that needs to read/parse trace results, not specific to srvc-grades — worth surfacing immediately instead of re-discovering via grep next time.
**How to apply:** Before writing any new JUnit-XML parsing or S3-trace-fetching code in this monorepo, check this first. See [[project_srvc_grades]] for the concrete ingestion mechanism built on top of this in srvc-grades.
