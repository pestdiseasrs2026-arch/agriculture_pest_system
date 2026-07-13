# Phase 10: Post-launch hardening

Phase 10 starts only after the Android, Flutter, Firebase Emulator, Functions, dependency, and secret checks pass and the approved production revision is deployed. Every check below needs a timestamp, owner, result, and evidence link. Never place tokens, user identifiers, images, farm coordinates, or request bodies in evidence.

## Production verification

Run **Post-launch verification** with the deployed 40-character commit SHA and `VERIFY_PRODUCTION`. Protect the `production-observability` GitHub Environment with reviewers. Configure `APP_BASE_URL`, optional `AI_HEALTH_URL`, and optional `AI_HEALTH_TOKEN`. The AI health endpoint must not perform a billable inference or accept user data.

Manually verify sign-in, one test farm/crop, one consented synthetic detection, notification preferences, report export, account-deletion request/cancel, and logout. Delete synthetic records afterward. Record the release SHA and Firebase Hosting release ID.

## Reliability baselines and alerts

Capture seven-day and thirty-day baselines by platform and release:

| Signal | Initial threshold | Action |
|---|---:|---|
| Crash-free users | below 99.5% | stop rollout; inspect top regressions |
| Fatal crashes | any release-correlated spike | page primary responder |
| App start p95 | above 5 s | investigate startup traces |
| Network request p95 | above 30 s | disable affected feature if sustained |
| App Check invalid traffic | above 5% | investigate clients before enforcing |
| AI error rate | above 5% for 15 min | disable `ai_detection_enabled` |
| AI p95 latency | above 30 s for 15 min | degrade or disable AI |
| Firestore/Storage quota | above 80% | warn owner and review usage |
| Daily cost | above 80% of budget | warn; at 100% page owner |

Route warnings to the monitored operations channel and critical alerts to a named primary and secondary responder. Run a quarterly alert drill: acknowledge, assign incident commander, activate a harmless staging kill switch, restore it, and retain timestamps/screenshots.

App Check must progress metrics-only → partial enforcement → full enforcement. Hold each stage for at least 48 hours. Roll back enforcement if legitimate-client rejection exceeds 1% or authentication/detection success degrades.

## AI quality and cost

Log only privacy-safe aggregates: model version, coarse crop category, latency bucket, HTTP outcome, confidence bucket, review outcome, and estimated inference cost. Never log images, tokens, exact coordinates, free text, or account identifiers.

Review weekly:

- Precision/recall and false-negative rate against an expert-labelled, consented evaluation set.
- Accuracy slices by crop, disease, device, image quality, and model version.
- p50/p95 latency, timeout rate, retry rate, and provider error rate.
- Cost per successful inference and daily/monthly spend.
- Expert-review disagreement and treatment-safety escalations.

Use minimum sample sizes and confidence intervals; do not promote a model solely on overall accuracy. Roll back a model when safety-critical false negatives regress or the release exceeds its approved latency/cost envelope.

## Recovery and privacy drills

Quarterly, restore the newest immutable Firestore export into an isolated recovery project. Verify record counts, representative references, security rules, and application reads; then destroy the recovery data. Record recovery point objective, recovery time objective, backup URI, operators, start/end times, and discrepancies. Never test restoration directly against production.

Monthly, use a synthetic account to request deletion, verify the seven-day grace state, cancel once, request again, and execute deletion in an isolated environment with an accelerated clock. Confirm Authentication, profile, owned Firestore records, Storage objects, notifications, reports, and deletion request are removed. Preserve only anonymous audit evidence allowed by the retention policy.

## Store and web launch

For Google Play, keep upload/app-signing keys outside the repository, enable Play App Signing, complete Data safety and privacy-policy declarations, provide account-deletion instructions, and validate content rating and target API requirements. Release internal → closed → open/production in controlled percentages. Stop promotion on crash, ANR, authentication, App Check, or critical-path regression.

For Web, verify the custom domain, DNS ownership, certificate renewal, HTTPS redirect, HSTS, content type, immutable asset caching, safe HTML caching, service-worker update behavior, 404/SPA rewrites, supported browsers, keyboard navigation, 200% text scaling, reduced motion, contrast, and screen-reader landmarks.

## Rollback rehearsal

Before broad rollout, deploy a harmless staging change, capture its immutable SHA, run smoke tests, execute the protected rollback workflow to the prior known-good SHA, and rerun smoke tests. Record detection time, decision time, rollback duration, data compatibility, and owner. Production rollback requires incident approval and must never use a mutable branch name.

