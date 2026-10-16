---
name: reference-frontend-backend-comm
description: How ../frontends (operator/discord SPAs) talk to backend services; operator SPA uses srvc-activity-operator as its only backend; port-frontend is not involved
metadata:
  node_type: memory
  type: reference
  originSessionId: d90b8b78-da98-4827-b667-befe63e98674
  modified: 2026-10-13T13:06:29.572Z
---

Checked 2026-10-13 against origin/main (frontends repo cloned at ~/Documents/Forge/frontends).

- Browser SPAs call services **directly over REST** with `Authorization: Bearer <CRI OIDC JWT>`. `port-frontend` is the legacy server-rendered (Qute) student intranet and the SPAs never call it.
- The **operator SPA has a single backend**: `VITE_OPERATOR_URL` (`https://operator.forge.epita.fr/api/`) → srvc-activity-operator. On main it serves `/api/activities`, `/api/traces`, `/api/events`, `/api/achievements`, `/api/users/.../achievements`, `/api/ldap`, `/api/submission/export` and the analysis endpoints.
- srvc-activity-operator acts as a BFF. Example: achievements reads come from `achievement-aggregate` and `user-achievements-aggregate`, which it consumes into its own DB. Writes are sent as Kafka commands (`put-achievement-command`, `give-user-achievement-command`, …) to repo-achievement, which has no REST at all.
- The discord SPA is the exception: it calls two services directly (`VITE_PORT_DISCORD_URL`, `VITE_SRVC_NOTIFICATION_URL` → `<svc>.api.forge.epita.fr`). That is the precedent for an SPA calling a service other than its BFF.
- Kafka is service↔service only (docs/docs/development/archi-style.md).
- Gotcha: branch 44-srvc-grades-new-app was 213 commits behind origin/main on 2026-10-13. Grep origin/main (`git grep ... origin/main`) before concluding that some code doesn't exist.

Related: [[project_srvc_grades]], [[reference_intranet_permission_pattern]]
