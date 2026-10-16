---
name: reference_intranet_permission_pattern
description: How per-tenant/per-activity authorization works in this monorepo — framework-auth already carries tenant permissions; only activity managers are hand-rolled
metadata:
  node_type: memory
  type: reference
  originSessionId: 0fd7d4dc-d060-489d-b154-803293eea21b
  modified: 2026-10-09T12:32:52.445Z
---

Corrected 2026-10-09 from the team's Outline doc "Auth: workflow et mécanismes" (user had a copy in /tmp). Earlier version of this memory said services ingest TenantAggregate themselves — **wrong as a general rule**.

1. **Global permissions**: `@RolesAllowed(Permissions.X)` / `securityIdentity.hasRole(...)`. Source: srvc-auth DB, broadcast as `PermissionAggregate` on Kafka, cached in memory by every service embedding `framework-auth` (its own `AuthSubscriber`, nothing to write).
2. **Tenant permissions** (`TenantPermission` enum in exchange `TenantAggregate`): repo-tenant -> TenantAggregate -> srvc-auth translates to `/tenant/<slug>/<perm lowercased, _ -> />` -> PermissionAggregate -> framework-auth cache. Check programmatically: `@Authenticated` on the endpoint + `AuthService.currentUserHasTenantPermission(slug, perm)` (framework-auth, since 2023; used by port-frontend `PermissionService`/`ContextService`). Child tenants inherit parents' permissions (done in repo-tenant).
3. **Activity managers** (`ActivityAggregate.managers`, + `tenantSlug`) are NOT in the permission system: still stored and checked by each service. `srvc-activity-operator`'s `AccessService` also keeps its own tenant-member table — an outlier, not the pattern to copy.

Gaps: framework-auth only answers yes/no per tenant slug, no "list tenants where I have X" — for list endpoints, loop over the (few) known tenant slugs. `currentUserHasPermission` doesn't consult `epita.auth.enable=false` bypass, so with auth disabled tenant checks likely return false (not verified at runtime).

Related: [[project_srvc_grades]]
