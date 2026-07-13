# Quarterly assurance review

Quarter: __________  Lead: __________  Release baseline: __________

## Security and privacy

- [ ] Tenant boundary and role-matrix Emulator tests pass, including cross-tenant denial.
- [ ] IAM, service accounts, support grants, secrets, dependencies, and audit logs reviewed.
- [ ] App Check metrics/enforcement and abuse/rate-limit evidence reviewed.
- [ ] Retention, deletion propagation, warehouse exports, and privacy requests sampled.
- [ ] Threat model, data inventory, subprocessors, and incident lessons updated.

## Reliability and scale

- [ ] Read-load results meet approved error/latency thresholds without quota or cost surprise.
- [ ] IoT queue age, dead letters, duplicates, late events, and backpressure tested.
- [ ] Backup restore and non-mutating regional chaos tabletop completed with RTO/RPO.
- [ ] Firestore hot spots, indexes, listener counts, pagination, storage, and spend reviewed.
- [ ] Rollback of app, Remote Config, Functions, rules, and AI model rehearsed in staging.

## AI and human review

- [ ] Active model digest/version matches the approved registry record.
- [ ] Crop/region accuracy, calibration, drift, safety false negatives, latency, and cost reviewed.
- [ ] Canary promotion and automated/manual rollback evidence retained.
- [ ] Expert-review SLA breaches and treatment-safety escalations have corrective actions.

## Accessibility, localization, and support

- [ ] Supported locales reviewed by language and agricultural-domain reviewers.
- [ ] Keyboard, screen reader, contrast, reduced motion, RTL, and 200% scaling checks pass.
- [ ] Support access and impersonation samples contain approvals, expiry, reason, and audit evidence.
- [ ] Public API documentation, compatibility, quotas, and deprecations are current.

## Architecture decision

- [ ] Architecture diagrams, data flows, SLOs, capacity forecast, and cost forecast updated.
- [ ] IaC plan/drift review completed; production destroy protection verified.
- [ ] Accepted risks have owner, deadline, compensating control, and approver.

Decision: **approved / conditionally approved / remediation required**

Approvers: __________  Evidence bundle: __________  Next review: __________

