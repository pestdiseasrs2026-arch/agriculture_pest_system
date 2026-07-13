# Production operations runbook

## Monitoring and alert ownership

The production on-call owner must review Firebase Crashlytics, Performance Monitoring, Authentication, Firestore, Realtime Database, Storage, Functions, App Check, FCM delivery, and Hosting. Alerts must route to a monitored team channel and a named primary/secondary responder.

Minimum alert thresholds:

- Crash-free users below 99.5% over 30 minutes: high severity.
- Fatal crash regression after release: page the release owner.
- Function error rate above 2% for 10 minutes: high severity.
- Function p95 latency above 10 seconds for 15 minutes: warning.
- Firestore denied requests increasing unexpectedly: security review.
- App Check invalid requests above 5%: investigate before enforcement.
- AI API p95 above 30 seconds or errors above 5%: disable `ai_detection_enabled`.
- Storage upload errors above 5%: disable `uploads_enabled`.
- Authentication failure spike above twice the seven-day baseline: investigate abuse/outage.

Diagnostics must contain event category, outcome, timestamp, counts, durations, and exception types only. Never add user IDs, emails, names, tokens, coordinates, free-form user text, or image data.

## Incident response

1. Acknowledge and assign an incident commander.
2. Record UTC start time, affected platforms, release version, and symptoms.
3. Contain using Remote Config: enable maintenance mode or disable AI/uploads.
4. Preserve privacy-safe logs and identify the last known-good release.
5. Roll back using the guarded workflow and immutable release tag.
6. Validate authentication, Firebase reads/writes, detection, notifications, and reports.
7. Communicate status without exposing customer or security details.
8. Close only after metrics remain healthy for 30 minutes.
9. Complete a blameless review with owners and deadlines.

## App Check rollout

1. Register Play Integrity, App Attest/DeviceCheck, and Web reCAPTCHA providers.
2. Deploy the client with enforcement off.
3. Register debug tokens only in non-production Firebase projects.
4. Observe valid/invalid/unknown request metrics for at least seven days.
5. Fix unsupported clients and confirm current releases receive valid tokens.
6. Enable enforcement one Firebase product at a time in staging.
7. Run the staging acceptance suite after each product.
8. Enable production enforcement gradually. Roll back enforcement immediately if legitimate traffic is rejected.

## Backup and recovery

Daily Firestore exports write to the production backup bucket. Enable bucket versioning, retention lock appropriate to policy, lifecycle transitions, and cross-region replication. The backup service account needs export permissions but no application-user privileges.

Quarterly restore drill:

1. Select an immutable backup URI.
2. Restore into an isolated recovery project, never directly over production.
3. Verify document counts, representative records, indexes, rules, and application reads.
4. Record recovery point objective and recovery time objective results.
5. Delete recovery data according to policy.

The production restore workflow requires a protected environment and `RESTORE_PRODUCTION`; use it only after incident-command approval and a tested recovery-project restore.

