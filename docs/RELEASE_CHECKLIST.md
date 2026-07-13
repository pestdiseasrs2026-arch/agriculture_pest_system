# Production release checklist

## Required quality gates

- [ ] `flutter analyze --no-pub` reports no issues.
- [ ] All unit and widget tests pass.
- [ ] Firebase Emulator rules tests pass.
- [ ] Release Web build completes.
- [ ] Android APK/AAB build completes under JDK 21.
- [ ] Generated artifacts are smoke-tested on a low-resource Android device and supported browsers.

## Security and data

- [ ] Production documents use an ownership field recognized by the rules.
- [ ] Custom role claims are assigned only by a trusted server.
- [ ] Farmer, officer, laboratory, researcher, and administrator access is tested.
- [ ] Firestore indexes finish building before the application release.
- [ ] Database and Storage backups are available.
- [ ] AI API tokens and service-account credentials are stored outside source control.

## Functional smoke tests

- [ ] Sign in, sign out, password reset, and profile update.
- [ ] Farm and crop create/read/update flows.
- [ ] Detection upload, progress, prediction, retry, expert review, and report sharing.
- [ ] Soil submission and fertilizer stock transaction integrity.
- [ ] IoT live readings, offline detection, thresholds, battery, and signal status.
- [ ] GIS layers, filters, marker details, permission denial, and failed-map recovery.
- [ ] Analytics filters and live calculations.
- [ ] Notification filtering, preferences, deletion, foreground FCM, and deep links.
- [ ] PDF and CSV report generation, upload metadata, and sharing.

## Accessibility and resilience

- [ ] Keyboard-only navigation follows reading order with visible focus.
- [ ] TalkBack/VoiceOver announces controls, status, errors, and recovery actions.
- [ ] Layout remains usable at 200% text scaling.
- [ ] Reduced-motion OS preference removes nonessential animation.
- [ ] Offline, reconnect, empty, loading, error, retry, and timeout states are exercised.
- [ ] Status is never communicated by color alone.

## Deployment order

1. Deploy indexes and wait until they are ready.
2. Deploy and verify rules in staging.
3. Deploy the application to staging and run smoke tests.
4. Tag the approved source revision.
5. Deploy production rules and application artifacts from that same revision.
6. Monitor authentication, errors, notification delivery, Storage, and database usage.

Never deploy Firebase rules or publish artifacts from a workstation when the corresponding CI gate is failing or unavailable.

## GitHub environment safeguards

Create separate `staging` and `production` GitHub Environments. Each must define `FIREBASE_PROJECT_ID`, `AI_API_URL`, and the `FIREBASE_SERVICE_ACCOUNT` secret. Use different Firebase projects and service accounts. Require designated reviewers for production, prevent self-review, restrict production deployment to protected `main`, and retain deployment logs. The production job stays pending until an authorized reviewer approves it.

Rollback requires a known-good immutable commit SHA or release tag and the exact `ROLLBACK` confirmation. It uses the selected environment's approval and credentials; never use a branch name as the rollback ref.
