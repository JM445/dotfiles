---
name: reference-idea-nix-jdk-paths
description: "IntelliJ \"full of errors\" on one host but Maven compiles — check ~/.config/JetBrains/<ver>/options/jdk.table.xml for SDK homePaths pointing at /nix/store paths missing on this host"
metadata:
  node_type: memory
  type: reference
  originSessionId: 45fbf3d0-48a1-4b5d-bf2f-e9129f44f5a6
  modified: 2026-10-09T09:35:51.308Z
---

IntelliJ's SDK table (`~/.config/JetBrains/IntelliJIdea<ver>/options/jdk.table.xml`, project SDK is named "21") stores absolute `/nix/store/<hash>-jetbrains-jdk-...` paths. On a host where that store path doesn't exist (other machine, or garbage-collected), the Maven import fails at startup (`idea.log`: `Cannot run program "/nix/store/.../bin/java"`) and the editor shows errors everywhere, while `./mvnw` compiles fine.

Seen 2026-10-09 working from home: IDEA 2026.1 SDK "21" pointed at missing `jetbrains-jdk-jcef-21.0.9`.

**How to apply:** check `test -e <homePath>/bin/java` for each SDK, and the IDEA log at `~/.cache/JetBrains/IntelliJIdea<ver>/log/idea.log`. Fix = repoint SDK at an existing JDK 21, then Maven → Reload. Related: [[project-claude-memory-flake-link]] (same class of stale /nix/store path problem).
