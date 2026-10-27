---
name: reference-gitlab-glab
description: "How to reach the team GitLab (gitlab.cri.epita.fr) via glab from the intern devshell, and what the user's fine-grained token can't do"
metadata:
  node_type: memory
  type: reference
  originSessionId: 29840675-b6d6-430f-8e95-38392cf83797
  modified: 2026-10-27T14:01:30.111Z
---

`glab` comes from the intern devshell (dotfiles forge/intern flake), so Bash tool shells don't have it on PATH. Run `direnv exec . glab ...` (prints the devshell banner) or call the nix store binary directly. The user is logged in with a read-only **fine-grained** token (set up 2026-10-27).

- REST works: `glab api 'projects/forge%2Fapps%2Fintern/...'`, MRs, pipelines, jobs, job traces, artifact archives.
- GraphQL returns `project: null`, and the web `/-/jobs/<id>/artifacts/download?file_type=...` routes return the login page. So security *report* artifacts (gl-dependency-scanning-report.json) can't be fetched. Only the archive is available: SBOMs and gl-sast-report.json.
- MR pipelines run allow_failure scanners: gemnasium(-maven) dependency scanning and semgrep SAST.

**How to apply:** for a security-widget question, a new app is flagged with every vulnerable dependency it uses. Compare its SBOM with the other apps' before treating findings as new (on MR !1136, all of repo-grades' deps already existed elsewhere at the same versions). Never print the token.
