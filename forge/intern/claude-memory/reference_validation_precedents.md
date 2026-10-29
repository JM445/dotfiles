---
name: reference-validation-precedents
description: "Where existing apps validate incoming writes (activity YAML, achievement and restriction commands); no app validates on both ends"
metadata:
  node_type: memory
  type: reference
  originSessionId: 5e50c891-c0b5-4be7-809a-7bdd60744f41
  modified: 2026-10-29T10:55:22.959Z
---

Checked 2026-10-29 on main:
- **Activities**: not a Kafka command. The activity YAML is PUT synchronously over REST to repo-activity (`PUT /activity/{slug}`, auth by activity token). The only validator is `PutActivityRequestValidator` in repo-activity (collects every error with a `Collector`). It runs on put (`INVALID_ACTIVITY_REQUEST` with all errors) and is exposed as a dry-run `/activity/{slug}/validate`. The operator trusts the aggregate.
- **Achievements** (operator → `put-achievement-command` → repo-achievement): validated only in operator `AchievementService`. The repo handler trusts the command; its subscriber try/catch only logs failures, so the user never sees them.
- **Activity restrictions** (operator → `activity-restriction-command` → repo-activity): validated only in operator `ActivityRestrictionService`.
- Rule of thumb: async command → validate at the sender (the only side that can answer the user); sync REST → validate in the repo + dry-run endpoint. Grading's "validate both ends" is stricter than any precedent.

Related: [[project_srvc_grades]], [[reference_frontend_backend_comm]]
