---
name: reference_intranet_permission_pattern
description: How per-activity authorization is done in this monorepo (srvc-activity-operator AccessService) — the auth lib only gives global roles
metadata:
  node_type: memory
  type: reference
  originSessionId: e9e2a0d3-30ec-4520-9182-8c9617a26824
  modified: 2026-10-05T15:11:46.024Z
---

Two layers, found 2026-10-05 while scoping `GET /scheme/` filtering for srvc-grades:

1. **Global roles** from the `epita.auth` lib, configured as `epita.auth.permissions."/admin/grades".users=...` in `application.properties`, checked with `@RolesAllowed(...)` / `securityIdentity.hasRole(...)`. All-or-nothing, not per resource.
2. **Per-resource access is computed by each service from aggregates it stores itself.** Reference implementation: `apps/srvc-activity-operator/.../domain/service/AccessService.java`:
   - `TenantMemberModel(login, tenantSlug, permission)` rebuilt from `TenantAggregate.permissions` (enum `TenantPermission` in `exchange/.../aggregate/tenant/v001/`: INTRA_TRACE_READ/RETRY/PUBLISH, INTRA_NODE_READ, ...).
   - `ManagerModel(login, resourceUri, scope)` from the `managers` lists on `ActivityAggregate` (activity, assignment group, assignment, submission levels). `ActivityAggregate.tenantSlug` gives the owning tenant.
   - Rule: full-scope role OR tenant permission OR manager of the resource; otherwise throw a *not found* error (not 403).

For srvc-grades this would mean storing activity `tenantSlug` + managers, subscribing to `tenant-aggregate`, and filtering schemes in the query. Open: no tenant permission fits "can grade" (adding one changes the shared `exchange` enum), and whether assignment-level managers count. Assistant did not read the `epita.auth` lib internals — a per-resource helper there is unlikely but not ruled out.

Related: [[project_srvc_grades]]
