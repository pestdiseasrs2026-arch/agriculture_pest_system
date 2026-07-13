# Phase 11: Continuous improvement and scale readiness

Phase 11 defines migration contracts and staging evidence. It does not authorize live region, billing, identity, DNS, or datastore mutations. Production changes require an architecture decision record, cost estimate, rollback plan, data migration rehearsal, and protected-environment approval.

## Multi-region and disaster recovery

Use a primary Firebase project and an isolated recovery project in a different failure domain. Firestore location is effectively irreversible; changing it requires export/import into a new project and controlled client cutover. Document supported Firebase products by location, Recovery Point Objective, Recovery Time Objective, DNS/Hosting cutover, Storage replication, Functions deployment regions, secrets, App Check, Remote Config, AI endpoint failover, and queued-write reconciliation.

Do not active/active write across independent Firestore projects without conflict ownership and idempotency. Prefer primary-write/recovery-readiness. Run the `regional-chaos-tabletop` staging workflow quarterly; it intentionally changes no infrastructure.

## Tenant isolation

The current owner-field rules are not sufficient for cooperatives or institutions. Introduce immutable `tenantId` claims and document paths before enabling multi-tenancy:

```text
tenants/{tenantId}
tenants/{tenantId}/members/{uid}
tenants/{tenantId}/farms/{farmId}
tenants/{tenantId}/detections/{detectionId}
```

Authorization must require both membership and role; never trust a client-supplied tenant alone. Custom claims select eligible tenants, while server membership records remain authoritative. Cross-tenant administration requires a time-limited support grant, reason, ticket, approver, and immutable audit event. Add Emulator tests proving every role is denied across tenants before migrating production data.

## Firestore and high-volume testing

Partition high-write data by tenant and stable hash/time bucket. Avoid sequential document IDs, unbounded listeners, offset pagination, large arrays, and hot singleton counters. Use cursor pagination, collection-group indexes only for measured queries, distributed counters, TTL policies, and aggregation pipelines. Record index storage/write amplification and query explain evidence.

The staging `read-load` workflow is capped at 100 virtual users, read-only, and requires explicit confirmation. Configure `APP_BASE_URL`, `LOAD_TEST_VUS`, and `LOAD_TEST_DURATION` in the protected `staging-scale-test` environment. Establish baselines before increasing load. Separate authenticated API/Firestore load tools must use synthetic tenants and least-privileged test identities.

## IoT ingestion and backpressure

Replace direct device-to-database bulk ingestion with an authenticated gateway and durable queue (for example Pub/Sub), then validate schema, tenant/device ownership, timestamp skew, payload size, and sequence/idempotency key. Consumers must cap concurrency, batch writes, retry transient failures with jitter, dead-letter poison messages, expose queue age, and reject overload predictably. Devices buffer locally with a bounded queue and report dropped/late readings. Never let dashboards subscribe to unbounded raw histories; publish downsampled/latest-state documents.

Initial SLOs: accepted-ingest p95 under 2 seconds, durable-processing p95 under 30 seconds, duplicate rate below 0.1%, dead-letter rate below 0.5%, and queue age below 60 seconds. Tune these from staging evidence.

## AI registry, promotion, drift, and expert review

Every model record needs immutable artifact digest, semantic version, training/evaluation dataset versions, supported crops/regions, preprocessing contract, safety limits, owner, approval evidence, and status: `candidate`, `shadow`, `canary`, `active`, `retired`, or `blocked`. Promotion is candidate → offline evaluation → shadow → canary → active. Remote Config selects the active version; retain the prior version for immediate rollback.

Monitor expert-labelled precision, recall, safety-critical false-negative rate, calibration, confidence distribution, crop/region slices, input-quality drift, latency, disagreement, and cost. Require minimum sample sizes. Alert on statistically meaningful regression, not individual predictions. Never use protected traits or exact location in operational logs.

Expert reviews need priority, assignment, due time, disposition, model version, and audit timestamps. Suggested targets: critical treatment/safety cases within 4 hours, high severity within 1 business day, routine cases within 3 business days. Escalate breaches; do not auto-approve chemical treatment from AI output.

## Localization and accessibility

Move user-facing strings to Flutter localization resources, use locale-aware dates/numbers/units, and separate translation from agronomic validation. Maintain region-specific crop, disease, pesticide-regulation, emergency, unit, and seasonal content with an agricultural reviewer and effective dates. Test long translations, right-to-left layouts, pluralization, offline fallback, 200% text scaling, screen readers, and low-literacy language. Never machine-translate safety instructions without expert approval.

## Billing, entitlements, and limits

Billing providers issue signed server webhooks; clients never grant entitlements. Store immutable ledger events and derive current entitlement state idempotently. Define plan limits for tenants, members, farms, storage, IoT devices/messages, AI inferences, reports, and expert reviews. Enforce limits server-side with warning, grace, and hard-limit states. Preserve read/export/delete access after cancellation where policy requires it. Reconcile provider events daily and audit refunds, disputes, and administrator adjustments.

## Support access and impersonation

Prefer read-only diagnostic views. Impersonation must require support role, ticket, reason, tenant approval where required, second approval for sensitive actions, short expiry, prominent banner, no credential visibility, and append-only audit events. Prohibit billing, role, deletion, export, and security-setting changes while impersonating unless a separately approved break-glass process exists.

## Privacy-safe analytics warehouse

Export only approved events into a separate analytics project with least privilege, regional alignment, partitioning, clustering, retention, deletion propagation, and cost controls. Replace direct identifiers with rotating pseudonyms and suppress small cohorts. Do not export images, free text, precise coordinates, tokens, or raw support content. Maintain metric definitions, lineage, data-quality tests, access logs, and subject-deletion propagation.

## Public API contract

Expose versioned HTTPS endpoints such as `/v1/`; authenticate with scoped identities; authorize tenant membership server-side. Require request IDs and idempotency keys for mutations. Use bounded page sizes and opaque cursors. Return stable problem details without stack traces. Publish OpenAPI, deprecation dates, changelog, examples, quotas, and SDK compatibility.

Rate limit by tenant, identity, IP risk, and expensive operation; return `429` with `Retry-After`. Use separate limits for uploads, inference, exports, and IoT ingestion. Validate payload/content type/size, scan uploads, and protect against replay. Contract, authorization, abuse, and backward-compatibility tests are release gates.

## Infrastructure as code

Use Terraform in a dedicated infrastructure repository/state boundary for projects, APIs, IAM, service accounts, budgets, alert policies, Pub/Sub, Scheduler, Storage, BigQuery, and supported Firebase/GCP resources. Use workload identity federation instead of static keys. Pin providers, lock state remotely, require plan review, prevent production destroy, detect drift, and separate staging/production service accounts. Firebase rules, indexes, Remote Config, and Functions remain versioned here until their IaC migration is proven.

