# Step-by-Step: Creating `srvc-grades`

This guide is based on how every existing app in this monorepo is built. All file paths, conventions, and code patterns are taken directly from working apps like `srvc-auth` and `repo-activity`.

---

## Step 1 — Create the directory and `pom.xml`

Create `apps/srvc-grades/` and write its `pom.xml`. Use `parent-repo` (not `parent-application`) because your service has a database.

```xml
<!-- apps/srvc-grades/pom.xml -->
<?xml version="1.0" encoding="UTF-8"?>
<project xmlns="http://maven.apache.org/POM/4.0.0"
         xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
         xsi:schemaLocation="http://maven.apache.org/POM/4.0.0 https://maven.apache.org/xsd/maven-4.0.0.xsd">
    <modelVersion>4.0.0</modelVersion>
    <parent>
        <groupId>fr.epita.forge.toolkit</groupId>
        <artifactId>parent-repo</artifactId>
        <version>413</version>
        <relativePath>../../toolkit/maven/parent-repo/pom.xml</relativePath>
    </parent>

    <groupId>fr.epita.intranet</groupId>
    <artifactId>srvc-grades</artifactId>
    <version>1.0.0-SNAPSHOT</version>

    <dependencies>
        <dependency>
            <groupId>org.projectlombok</groupId>
            <artifactId>lombok</artifactId>
        </dependency>
        <dependency>
            <groupId>fr.epita.forge.toolkit</groupId>
            <artifactId>framework-messaging</artifactId>
        </dependency>
        <dependency>
            <groupId>fr.epita.forge.toolkit</groupId>
            <artifactId>framework-auth</artifactId>
        </dependency>
        <dependency>
            <groupId>io.quarkus</groupId>
            <artifactId>quarkus-smallrye-openapi</artifactId>
        </dependency>
        <dependency>
            <groupId>io.hypersistence</groupId>
            <artifactId>hypersistence-utils-hibernate-63</artifactId>
        </dependency>
        <dependency>
            <groupId>fr.epita.forge</groupId>
            <artifactId>exchange</artifactId>
        </dependency>
        <dependency>
            <groupId>io.quarkus</groupId>
            <artifactId>quarkus-junit5</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.rest-assured</groupId>
            <artifactId>rest-assured</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.quarkus</groupId>
            <artifactId>quarkus-test-security</artifactId>
            <scope>test</scope>
        </dependency>
        <dependency>
            <groupId>io.quarkus</groupId>
            <artifactId>quarkus-test-kafka-companion</artifactId>
            <scope>test</scope>
        </dependency>
    </dependencies>

    <build>
        <plugins>
            <plugin>
                <groupId>io.quarkus</groupId>
                <artifactId>quarkus-maven-plugin</artifactId>
            </plugin>
        </plugins>
    </build>
</project>
```

**Why `parent-repo`?** It automatically pulls in `framework-persistence` and `quarkus-flyway`, which you need for PostgreSQL + Flyway migrations. `parent-application` is for services without a database.

---

## Step 2 — Register in the root `pom.xml`

Open `pom.xml` at the repository root and add your module. Order matters for Maven's build graph — put it after `repo-submission` (since you'll consume submission data) and before any future consumers of your aggregates:

```xml
<!-- pom.xml, in the <modules> section -->
<module>apps/repo-submission</module>
<module>apps/srvc-grades</module>   <!-- add this line -->
<module>apps/repo-maas</module>
```

---

## Step 3 — `lombok.config`

Copy the same file used by other apps:

```
# apps/srvc-grades/lombok.config
lombok.noArgsConstructor.extraPrivate=true
```

---

## Step 4 — Java package structure

All apps follow a strict three-layer layout. Create these empty packages:

```
apps/srvc-grades/src/main/java/fr/epita/intranet/grades/
├── presentation/
│   ├── rest/
│   │   ├── GradingSchemeResource.java     # REST endpoints (Step 8)
│   │   ├── GradeReportResource.java
│   │   └── Permissions.java               # Permission path constants (Step 7)
│   └── subscriber/
│       └── SubmissionSubscriber.java      # Kafka consumer (Step 9)
├── domain/
│   └── service/
│       ├── GradingSchemeService.java      # Business logic (Step 8)
│       └── GradeComputationService.java
├── data/
│   ├── model/
│   │   ├── GradingSchemeModel.java        # JPA entities (Step 6)
│   │   ├── GradingNodeModel.java
│   │   ├── DiscoveredTestModel.java
│   │   └── GradeReportModel.java
│   └── repository/
│       ├── GradingSchemeRepository.java   # Panache repos (Step 6)
│       ├── GradingNodeRepository.java
│       ├── DiscoveredTestRepository.java
│       └── GradeReportRepository.java
└── ErrorCodes.java                        # Error catalog (Step 7)
```

---

## Step 5 — `application.properties`

```properties
# apps/srvc-grades/src/main/resources/application.properties

forge.app-name=srvc-grades
forge.persistence.db-name=srvc_grades

# DEV
%dev.quarkus.http.port=8089
%dev.epita.auth.enable=true

# TEST
%test.epita.auth.enable=true
%test.quarkus.oidc.enabled=false
%test.forge.http-port=0
%test.forge.deployment.random-http-port-for-test=true
%test.quarkus.http.port=0

quarkus.flyway.migrate-at-start=true
quarkus.flyway.baseline-on-migrate=true

# LOGS
quarkus.log.category."org.apache.kafka".level=WARN

# MISC
quarkus.arc.remove-unused-beans=false
quarkus.swagger-ui.always-include=true
quarkus.swagger-ui.theme=material
hibernate.types.print.banner=false
quarkus.micrometer.enabled=false

# OIDC
quarkus.oidc.credentials.secret=${OIDC_SECRET_KEY:f6ff8d394e6185d41834b19210979b897852680cf34700ae4ecb24ea}
quarkus.oidc.authentication.scopes=openid,profile,picture,epita

# Kafka consumers
epita.group.id=srvc_grades-1
epita.random=

epita.auth.permissions."/admin/grades".users=${ADMIN_GRADES_PERMISSION:}
```

Pick a port not already used. Confirm `8089` is free by checking all `%dev.quarkus.http.port` values in existing `application.properties` files.

---

## Step 6 — Flyway migration `V1__Init.sql`

Create `apps/srvc-grades/src/main/resources/db/migration/V1__Init.sql`.

Key design decisions from the data model:
- `GradingNode` is a self-referencing tree (parent FK to itself)
- `NodeReference` is a sealed type → store as discriminator column + typed columns
- `GradeReport.nodeResults` is a `Map<UUID, NodeResult>` → store as JSONB (backed by `@Type(JsonBinaryType.class)` from `hypersistence-utils`), same approach as `traceStats` in `SubmissionAggregate.Job`

```sql
-- V1__Init.sql

CREATE TABLE grading_scheme (
    id              UUID             NOT NULL PRIMARY KEY,
    version         INTEGER          NOT NULL DEFAULT 1,
    activity_uri    TEXT             NOT NULL,
    final_max       DOUBLE PRECISION NOT NULL,
    created_at      TIMESTAMP        NOT NULL,
    updated_at      TIMESTAMP        NOT NULL
);

CREATE UNIQUE INDEX idx_grading_scheme_activity_version
    ON grading_scheme (activity_uri, version);

CREATE TABLE grading_node (
    id                    UUID             NOT NULL PRIMARY KEY,
    scheme_id             UUID             NOT NULL
        CONSTRAINT grading_node_fk_scheme REFERENCES grading_scheme (id),
    parent_id             UUID
        CONSTRAINT grading_node_fk_parent REFERENCES grading_node (id),
    label                 TEXT             NOT NULL,
    points                DOUBLE PRECISION NOT NULL,
    validation_threshold  DOUBLE PRECISION NOT NULL DEFAULT 1.0,
    mandatory             BOOLEAN          NOT NULL DEFAULT FALSE,
    ignored               BOOLEAN          NOT NULL DEFAULT FALSE,
    absence_behavior      TEXT             NOT NULL,  -- IGNORE | PASS | FAIL
    aggregation           TEXT             NOT NULL,  -- SUM | WEIGHTED_AVERAGE | MIN_CHILD | MAX_CHILD
    -- NodeReference discriminator
    ref_type                  TEXT,  -- ACTIVITY_ROOT | ASSIGNMENT_GROUP | ASSIGNMENT | TEST_CATEGORY | TEST_CASE
    ref_assignment_group_slug TEXT,
    ref_assignment_slug       TEXT,
    ref_classname             TEXT,
    ref_discovered_test_id    UUID
);

CREATE TABLE discovered_test (
    id               UUID      NOT NULL PRIMARY KEY,
    activity_uri     TEXT      NOT NULL,
    assignment_slug  TEXT      NOT NULL,
    classname        TEXT      NOT NULL,
    test_key         TEXT      NOT NULL,
    first_seen_at    TIMESTAMP NOT NULL,
    last_seen_at     TIMESTAMP NOT NULL,
    occurrence_count INTEGER   NOT NULL DEFAULT 1,
    UNIQUE (activity_uri, assignment_slug, classname, test_key)
);

CREATE TABLE grade_report (
    id             UUID             NOT NULL PRIMARY KEY,
    scheme_id      UUID             NOT NULL
        CONSTRAINT grade_report_fk_scheme REFERENCES grading_scheme (id),
    scheme_version INTEGER          NOT NULL,
    student_id     TEXT             NOT NULL,
    activity_uri   TEXT             NOT NULL,
    computed_at    TIMESTAMP        NOT NULL,
    final_grade    DOUBLE PRECISION NOT NULL,
    final_max      DOUBLE PRECISION NOT NULL,
    status         TEXT             NOT NULL,  -- FRESH | STALE | COMPUTING | FAILED
    node_results   JSONB            NOT NULL   -- Map<UUID, NodeResult>
);

CREATE INDEX idx_grade_report_activity_student
    ON grade_report (activity_uri, student_id);
```

---

## Step 7 — `Permissions.java` and `ErrorCodes.java`

```java
// presentation/rest/Permissions.java
package fr.epita.intranet.grades.presentation.rest;

public interface Permissions {
    String BASE = "/intranet/grades/";

    String SCHEME_BASE    = BASE + "scheme/";
    String SCHEME_READ    = SCHEME_BASE + "read";
    String SCHEME_WRITE   = SCHEME_BASE + "write";

    String REPORT_BASE    = BASE + "report/";
    String REPORT_READ    = REPORT_BASE + "read";
    String REPORT_COMPUTE = REPORT_BASE + "compute";
}
```

```java
// ErrorCodes.java
package fr.epita.intranet.grades;

import fr.epita.framework.core.error.ErrorCode;
import lombok.Getter;

public enum ErrorCodes implements ErrorCode {
    SCHEME_NOT_FOUND(404, "No grading scheme for activity %s"),
    SCHEME_VERSION_CONFLICT(409, "Scheme version mismatch for activity %s (expected %d, got %d)"),
    NODE_REFERENCES_UNKNOWN_TEST(400, "Node references unknown discovered test %s"),
    NODE_IGNORED_AND_MANDATORY(400, "Node %s cannot be both ignored and mandatory"),
    REPORT_NOT_FOUND(404, "No grade report with id %s"),
    COMPUTATION_FAILED(500, "Grade computation failed for student %s on activity %s: %s"),
    ;

    public final String message;
    public @Getter final int httpCode;

    ErrorCodes(int httpCode, String message) {
        this.message = message;
        this.httpCode = httpCode;
    }

    @Override
    public String getMessage(Object... parameters) {
        return String.format(message, parameters);
    }
}
```

---

## Step 8 — JPA Models and Repositories

Pattern: `@Entity` + `@Table`, all fields `public`, Lombok `@AllArgsConstructor @NoArgsConstructor @With`. No getters/setters — Panache reads public fields directly.

```java
// data/model/GradingSchemeModel.java
package fr.epita.intranet.grades.data.model;

import jakarta.persistence.*;
import lombok.*;
import java.time.Instant;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "grading_scheme")
@AllArgsConstructor @NoArgsConstructor @With
public class GradingSchemeModel {
    public @Id UUID id;
    public int version;
    public String activityUri;
    public double finalMax;
    public Instant createdAt;
    public Instant updatedAt;

    @OneToMany(mappedBy = "scheme", cascade = CascadeType.ALL, orphanRemoval = true)
    public List<GradingNodeModel> nodes;
}
```

```java
// data/model/GradingNodeModel.java
package fr.epita.intranet.grades.data.model;

import jakarta.persistence.*;
import lombok.*;
import java.util.List;
import java.util.UUID;

@Entity
@Table(name = "grading_node")
@AllArgsConstructor @NoArgsConstructor @With
public class GradingNodeModel {
    public @Id UUID id;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "scheme_id")
    public GradingSchemeModel scheme;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "parent_id")
    public GradingNodeModel parent;

    @OneToMany(mappedBy = "parent", cascade = CascadeType.ALL, orphanRemoval = true)
    public List<GradingNodeModel> children;

    public String label;
    public double points;
    public double validationThreshold;
    public boolean mandatory;
    public boolean ignored;

    @Enumerated(EnumType.STRING)
    public AbsenceBehavior absenceBehavior;

    @Enumerated(EnumType.STRING)
    public AggregationRule aggregation;

    // NodeReference fields
    public String refType;
    public String refAssignmentGroupSlug;
    public String refAssignmentSlug;
    public String refClassname;
    public UUID refDiscoveredTestId;

    public enum AbsenceBehavior { IGNORE, PASS, FAIL }
    public enum AggregationRule  { SUM, WEIGHTED_AVERAGE, MIN_CHILD, MAX_CHILD }
}
```

```java
// data/repository/GradingSchemeRepository.java
package fr.epita.intranet.grades.data.repository;

import fr.epita.framework.core.Logged;
import fr.epita.framework.persistence.repository.Repository;
import fr.epita.intranet.grades.data.model.GradingSchemeModel;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.persistence.EntityManager;
import jakarta.transaction.Transactional;
import lombok.AllArgsConstructor;
import java.util.Optional;
import java.util.UUID;

@ApplicationScoped
@AllArgsConstructor(onConstructor = @__(@Inject))
public class GradingSchemeRepository implements Repository<GradingSchemeModel, UUID>, Logged {
    private EntityManager entityManager;

    public Optional<GradingSchemeModel> findLatestByActivity(String activityUri) {
        return entityManager
                .createQuery(
                    "FROM GradingSchemeModel s WHERE s.activityUri = :uri ORDER BY s.version DESC",
                    GradingSchemeModel.class)
                .setParameter("uri", activityUri)
                .setMaxResults(1)
                .getResultStream()
                .findFirst();
    }

    @Transactional
    public GradingSchemeModel persistTransactional(GradingSchemeModel model) {
        persist(model);
        return model;
    }
}
```

Repeat the same `@ApplicationScoped` + `Repository<Model, ID>` pattern for `GradingNodeRepository`, `DiscoveredTestRepository`, and `GradeReportRepository`.

---

## Step 9 — Kafka Subscriber

Your service listens to `submission-aggregate` to discover new tests from `Job.traceStats` and to trigger recomputation. Follow the exact pattern from `PermissionSubscriber` in `srvc-auth`:

```java
// presentation/subscriber/SubmissionSubscriber.java
package fr.epita.intranet.grades.presentation.subscriber;

import fr.epita.framework.core.Logged;
import fr.epita.framework.core.message.Message;
import fr.epita.framework.core.message.RawMessage;
import fr.epita.framework.messaging.domain.entity.ConsumerConfig;
import fr.epita.framework.messaging.domain.service.MessageService;
import fr.epita.intranet.aggregate.submission.v001.SubmissionAggregate;
import fr.epita.intranet.grades.domain.service.GradeComputationService;
import io.smallrye.common.annotation.Blocking;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.validation.constraints.NotNull;
import org.eclipse.microprofile.reactive.messaging.Incoming;

@ApplicationScoped
public class SubmissionSubscriber implements Logged {

    @Inject MessageService messageService;
    @Inject GradeComputationService gradeComputationService;

    @Incoming("submission-aggregate")
    @Blocking
    @ConsumerConfig(
            groupId = "${epita.group.id}",
            type = Message.Type.AGGREGATE,
            payloadClass = SubmissionAggregate.class)
    public void onSubmissionAggregate(@NotNull RawMessage rawMessage) {
        messageService.<SubmissionAggregate>unpackRawMessage(rawMessage, message -> {
            gradeComputationService.onSubmissionAggregate(message.payload);
        });
    }
}
```

Then enable the channel in `application.properties`:

```properties
mp.messaging.incoming.submission-aggregate.enabled=${INGEST_ENABLED:true}
```

---

## Step 10 — REST Resource skeleton

```java
// presentation/rest/GradingSchemeResource.java
package fr.epita.intranet.grades.presentation.rest;

import fr.epita.framework.core.Logged;
import fr.epita.intranet.grades.domain.service.GradingSchemeService;
import jakarta.annotation.security.RolesAllowed;
import jakarta.enterprise.context.ApplicationScoped;
import jakarta.inject.Inject;
import jakarta.ws.rs.*;
import jakarta.ws.rs.core.MediaType;
import org.eclipse.microprofile.openapi.annotations.tags.Tag;

import static fr.epita.intranet.grades.presentation.rest.Permissions.*;

@Path("/scheme")
@Tag(name = "Grading Scheme")
@ApplicationScoped
@Produces(MediaType.APPLICATION_JSON)
@Consumes(MediaType.APPLICATION_JSON)
public class GradingSchemeResource implements Logged {

    @Inject GradingSchemeService schemeService;

    @GET
    @Path("/{activityUri}")
    @RolesAllowed(SCHEME_READ)
    public Object getScheme(@PathParam("activityUri") String activityUri) {
        // TODO: implement
        return schemeService.getLatest(activityUri);
    }

    @PUT
    @Path("/{activityUri}")
    @RolesAllowed(SCHEME_WRITE)
    public Object putScheme(@PathParam("activityUri") String activityUri, Object request) {
        // TODO: implement
        return null;
    }
}
```

---

## Step 11 — Test resources

Create `apps/srvc-grades/src/test/resources/application.properties`:

```properties
%test.epita.auth.enable=true
%test.quarkus.oidc.enabled=false
%test.forge.http-port=0
%test.forge.deployment.random-http-port-for-test=true
%test.quarkus.http.port=0
quarkus.flyway.migrate-at-start=true
```

---

## Summary of files to create

| File | Purpose |
|---|---|
| `apps/srvc-grades/pom.xml` | Maven module, extends `parent-repo` |
| `apps/srvc-grades/lombok.config` | Lombok config |
| `src/main/resources/application.properties` | App config, Kafka channels, port |
| `src/main/resources/db/migration/V1__Init.sql` | DB schema |
| `src/.../ErrorCodes.java` | Error catalog |
| `src/.../presentation/rest/Permissions.java` | Permission path constants |
| `src/.../presentation/rest/GradingSchemeResource.java` | REST endpoints |
| `src/.../presentation/rest/GradeReportResource.java` | REST endpoints |
| `src/.../presentation/subscriber/SubmissionSubscriber.java` | Kafka consumer |
| `src/.../domain/service/GradingSchemeService.java` | Business logic |
| `src/.../domain/service/GradeComputationService.java` | Computation logic |
| `src/.../data/model/*.java` | JPA entities |
| `src/.../data/repository/*.java` | Panache repositories |
| `src/test/resources/application.properties` | Test config |
| Root `pom.xml` | Register `<module>apps/srvc-grades</module>` |

---

## Open questions before implementing endpoints

1. **API contract location** — Define a `GradingSchemeResourceApi` interface in the `exchange` module (so other services can call you typed), or keep the API internal for now?
2. **`node_results` storage** — JSONB (recommended above) vs. a normalized `node_result` table.
3. **Dev port** — Confirm `8089` is free: `grep -r "quarkus.http.port" apps/*/src/main/resources/application.properties`.
4. **Kafka consumer group suffix** — `srvc_grades-1` assumes a single instance. If you need partitioned consumers later, revisit.
5. **`JobResultsUploadedEvent` vs `SubmissionAggregate`** — Your data model says you listen to `JobResultUploaded` to discover tests, but `SubmissionAggregate.Job.traceStats` already carries that data. Clarify with the team which is the canonical source.
