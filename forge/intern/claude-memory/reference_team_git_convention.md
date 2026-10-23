---
name: reference-team-git-convention
description: Team convention for updating feature branches from main - rebase, not merge
metadata:
  type: reference
---

The team's convention is to **rebase** feature branches on `main` rather than merge `main` into them (user, 2026-10-23). A rebase of a pushed branch needs a force-push: leave the push (`git push --force-with-lease`) to the user. In this sandbox `git fetch origin` fails with "Permission denied (publickey)", so ask the user to run `! git fetch origin` themselves.

The user's commits are GPG-signed with a YubiKey (`commit.gpgsign=true`), so any git command that writes commits (rebase, commit) or talks to the remote must be run by the user; Claude cannot sign. Force-pushes are fine on feature branches in this repo (user, 2026-10-23).
