---
name: reference-framework-kafka-transactions
description: "PublisherService needs a Kafka tx, only opened around @Transactional methods, not QuarkusTransaction blocks"
metadata:
  node_type: memory
  type: reference
  originSessionId: fae214b5-629f-418f-8d3b-014f1f385228
  modified: 2026-10-23T15:58:54.421Z
---

`PublisherService.aggregate/command/...` are `@KafkaTransactional(MANDATORY)`. framework-deployment's
`FrameworkMessagingProcessor` adds `@KafkaTransactional` to every `@Transactional` method at build time, so a Kafka
transaction exists inside `@Transactional` methods only. Programmatic `QuarkusTransaction.requiringNew()` blocks open
a JTA transaction but NO Kafka one: publishing inside them fails with "MANDATORY TxType encountered without active
transaction".

Also: a call to a `@Transactional` method from within the same bean skips the interceptor. When work must run in
separate transactions (e.g. a computation, then a FAILED marker after its rollback), put the transactional methods in
another bean (repo-grades: `GradeReportService`, called by `GradingComputationService`).

Tests: services can be called directly, and published aggregates read back with KafkaCompanion
(`@QuarkusTestResource(KafkaCompanionResource.class)`, topic from `Message.buildTopic(type, class)`, record value =
`RawMessage` JSON). Topics keep messages across tests: filter on an id or command id. See [[project-srvc-grades]].
