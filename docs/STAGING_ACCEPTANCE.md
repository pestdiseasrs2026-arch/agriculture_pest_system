# Staging acceptance and launch

## Entry criteria

- Quality, security, Firebase Emulator, Functions, Web, and Android CI jobs pass on the same commit.
- Staging uses separate Firebase credentials, App Check providers, Storage, databases, AI endpoint, and backup destination.
- Release candidate has an immutable version tag and generated changelog.

## Acceptance suite

- Create each supported role and confirm hidden/allowed modules.
- Verify owner, cross-user, officer, laboratory, researcher, and administrator authorization.
- Run sign-in, reset-password, farm/crop, detection, expert review, soil, fertilizer, IoT, GIS, notifications, analytics, PDF, CSV, and sharing paths.
- Test airplane mode, reconnect, slow network, server timeout, permission denial, upload retry, and expired session.
- Test Android low-memory behavior and Chrome/Edge responsive layouts.
- Test keyboard traversal, TalkBack, 200% text scaling, reduced motion, and status semantics.
- Confirm Crashlytics non-fatal test, Performance traces, sanitized Analytics events, Remote Config updates, and App Check metrics.
- Request and cancel account deletion. In an isolated test account, shorten the grace period server-side and verify complete deletion.
- Restore the latest backup into a recovery project and verify representative data.

## Controlled launch

1. Obtain product, security, privacy, operations, and release-owner approval.
2. Confirm maintenance mode and feature kill switches work in staging.
3. Deploy production rules/indexes/functions before clients only when backward compatible.
4. Release to an internal cohort, then 5%, 25%, 50%, and 100% with observation windows.
5. Monitor crash-free users, latency, errors, App Check, AI, auth, uploads, FCM, and cost.
6. Pause rollout on any breached threshold. Disable the affected feature or roll back the immutable release.

## Exit criteria

- 100% rollout remains within thresholds for 24 hours.
- No unresolved high-severity security, privacy, data-loss, or accessibility defect exists.
- Backup and rollback evidence is attached to the release record.
