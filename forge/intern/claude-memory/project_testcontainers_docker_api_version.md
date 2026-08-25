---
name: project-testcontainers-docker-api-version
description: How to fix Testcontainers/Docker-devservices failures in this repo's Quarkus tests on this machine
metadata:
  node_type: memory
  type: project
  originSessionId: 18425905-8bc2-493e-a7e8-3de44290e15b
  modified: 2026-08-25T12:55:17.238Z
---

Any `@QuarkusTest` in the Forge monorepo (`/home/jm445/Documents/Forge/intern`) that relies on Kafka/Postgres devservices fails locally on this machine with `IllegalStateException: Previous attempts to find a Docker environment failed`, root cause `BadRequestException (Status 400: "client version 1.32 is too old. Minimum supported API version is 1.40...")`. Confirmed repo-wide (not app-specific): reproduced identically in both `srvc-grades` and `srvc-git`.

**Root cause:** Testcontainers 1.20.6 (bundled transitively via this repo's pinned Quarkus version) ships its own *shaded* internal copy of docker-java. When its `DockerClientProviderStrategy.getClientForConfig()` can't resolve an API version, it hardcodes a fallback to `RemoteApiVersion.VERSION_1_32` — confirmed directly in the bytecode (`getstatic RemoteApiVersion.VERSION_1_32` right after a check for `UNKNOWN_VERSION`). This machine's Docker daemon (29.6.2, `MinAPIVersion: 1.40`) rejects that outright. This is a version-negotiation bug in that Testcontainers release, not a real "Docker unavailable" problem — `docker ps`/`docker info` work fine.

**Fix:** set the Java system property `api.version` (e.g. `1.41`) — this is a docker-java system property (NOT an env var; this docker-java build doesn't read `DOCKER_API_VERSION` at all, only recognizes `DOCKER_HOST`/`DOCKER_CONTEXT`/`DOCKER_TLS_VERIFY`/`DOCKER_CONFIG`/`DOCKER_CERT_PATH` plus the `api.version` system property). Once set, the fallback branch never triggers and devservices start real Testcontainers-managed Kafka/Postgres containers normally.

**Critical detail on how to set it:** `MAVEN_OPTS="-Dapi.version=1.41"` does NOT work, even though it correctly sets the property in Maven's own JVM — because `@QuarkusTest` augmentation (where the Docker calls actually happen) runs inside a Surefire-*forked* JVM, and Surefire only auto-forwards `-D` properties that were passed on the Maven command line, not ones baked into the parent JVM via `MAVEN_OPTS`. Must use `JDK_JAVA_OPTIONS="-Dapi.version=1.41"` instead — a standard env var every `java` launch honors (including the forked one), bypassing Maven's forwarding rules entirely.

Applied as a **personal, untracked** fix in the user's own dev-shell flake (`~/Documents/Github/dotfiles/forge/intern/flake.nix`, not part of this repo): `export JDK_JAVA_OPTIONS="-Dapi.version=1.41"` in the `shellHook`. Deliberately kept out of the repo/CI config — a teammate or CI runner with an *older* Docker daemon (max API version below 1.41) would break the same way in reverse ("client version too new").

**Why:** this eats significant debugging time every time it resurfaces (already did, twice, across two sessions) since the error message ("Previous attempts to find a Docker environment failed... check configuration") gives no hint toward the real cause.
**How to apply:** When any `@QuarkusTest` run on this machine fails with that Docker/Testcontainers error, check first whether the fix is present in the current shell (`echo $JDK_JAVA_OPTIONS`) before re-diagnosing from scratch. If missing/not reloaded, `direnv reload` (or exit/re-`cd`) after confirming the flake has it.
