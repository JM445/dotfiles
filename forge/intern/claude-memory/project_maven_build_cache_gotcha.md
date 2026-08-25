---
name: project-maven-build-cache-gotcha
description: Maven build-cache extension causes "no file assigned to artifact" install errors and "no tests to run" after a cache hit in this repo
metadata:
  node_type: memory
  type: project
  originSessionId: 10b2b0f7-23c6-4096-b45e-6a024b8057ae
  modified: 2026-08-25T13:10:00.000Z
---

The Forge monorepo (`/home/jm445/Documents/Forge/intern`) uses the Maven build-cache extension, configured at `.mvn/maven-build-cache-config.xml`. Two symptoms observed in the same debugging session, both root-caused to the same defect, first hit on `apps/srvc-grades` (branch 44-srvc-grades-new-app) after editing `pom.xml` (removing then re-adding an `assertj-core` dependency):

1. `../../mvnw clean install -DskipTests` failing with:
   ```
   [ERROR] Failed to execute goal org.apache.maven.plugins:maven-install-plugin:3.1.4:install (default-install) on project X:
   The packaging plugin for project X did not assign a file to the build artifact
   ```
2. After working around that, `../../mvnw test` reporting `No tests to run` even though test classes exist in `src/test/java`.

**Root cause:** `.mvn/maven-build-cache-config.xml` explicitly excludes `pom.xml` from the cache checksum (`<exclude>pom.xml</exclude>` under `<input><global><excludes>`), relying on Maven's own dependency-change detection instead of the cache's own hash — this doesn't reliably invalidate a stale cache entry after certain pom edits. On a cache hit, the extension marks mojos like `compiler:compile`/`compiler:testCompile` as "Skipping plugin execution (cached)" but does **not** actually re-extract the compiled `.class` files onto disk — confirmed directly: running `test-compile` alone with a cache hit leaves `target/classes` and `target/test-classes` absent entirely (only `target/generated-sources` exists). Only the final packaged artifact (the jar) gets restored, and only when a goal at/after `package`/`install` runs — which is why `install` looked "further along" than `test-compile` but still failed (the packaging plugin's artifact-file reference didn't get set correctly during that partial cache restore either).

**Fix:** append `-Dmaven.build.cache.skipCache=true` to the Maven command to force everything to actually execute instead of trusting the cache:
```
../../mvnw clean install -DskipTests -Dmaven.build.cache.skipCache=true
../../mvnw test -Dmaven.build.cache.skipCache=true
```
This is a local, non-invasive workaround — did not touch `.mvn/maven-build-cache-config.xml` itself, since that's a shared repo-level config affecting every app; changing it wasn't warranted for a single-session local cache staleness issue.

**Why:** cost real confusion time — the install error message ("did not assign a file to the build artifact") and the "No tests to run" message both look like real build/config problems, give no hint that a stale local build-cache entry is the actual cause. Not specific to `srvc-grades` — the cache config is repo-wide, so any app could hit this after a pom.xml edit.
**How to apply:** When a Maven command in this repo fails with either of those two symptoms right after editing a `pom.xml` (especially adding/removing dependencies), try `-Dmaven.build.cache.skipCache=true` before digging into the pom or the code — check `~/.m2/build-cache` staleness first, not the dependency change itself. Related: [[project_srvc_grades]] for the session this was discovered in, [[project_testcontainers_docker_api_version]] for another local-machine-only build quirk in this repo, [[project_claude_memory_flake_link]] for how this repo's own Claude Code memory storage is wired up (relevant context for where this file itself lives).
