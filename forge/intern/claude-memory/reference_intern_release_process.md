---
name: reference-intern-release-process
description: Intern monorepo versioning/release/MR rules from the team wiki (Procédures › Workflow) — what to bump before and after an MR
metadata:
  node_type: memory
  type: reference
  originSessionId: 29840675-b6d6-430f-8e95-38392cf83797
  modified: 2026-10-27T10:00:53.633Z
---

Source: wiki Forge - Interne › Procédures › Workflow — pages "Intern: release sur main et artefacts", "Intern: versioning Maven et CI GitLab", "Workflow Git" (see [[reference-outline-wiki]]).

- Only `apps/*/pom.xml` versions matter. Never bump exchange/framework poms; `toolkit/bom` is ignored since 2026-09-01.
- When exchange or a framework changes, the CI on main redeploys it and all frameworks automatically.
- SNAPSHOT apps are auto-deployed on main. Release flow happens after the merge: drop -SNAPSHOT (`feat(<app>): release X.Y.Z`), tag `<app>-X.Y.Z`, push tag, then bump to X.Y.(Z+1)-SNAPSHOT (`feat(<app>): dev mode`).
- To test in staging before the merge: bump the app's SNAPSHOT version on the branch and push (no tag).
- MRs: conventional commits, GPG-signed + `Signed-off-by` (added automatically by a prepare-commit-msg hook that dotfiles `forge/intern/link.sh` installs; the wiki's `format.signoff` tip is wrong because it only affects format-patch; replayed rebase commits need `git rebase --signoff`), rebase not merge, fast-forward merge by GitLab, approval from someone else (#mr-review on Discord).
- Exchange gotcha (from the GPUaaS docs): Jackson rejects unknown enum values, so adding values to an existing enum requires every consumer to run the new exchange first. New classes are safe.

**How to apply:** before an MR, check the branch's commit style against these rules. Remember the user runs the git/tag commands themselves ([[reference-team-git-convention]]).
