# Authentication security readiness

Implemented controls include email verification gating for password accounts, strong password validation, recent-login reauthentication for password changes and deletion, accessible authentication errors, reset-password UI, bounded client cooldown, privacy-safe security events, user security notifications, and Firebase Auth Emulator coverage.

## Console and server controls required before production

- Enable Email/Password and configure verification/reset templates in Firebase Authentication.
- Add the production and staging Web domains to Authorized domains. Verify Android SHA-256 configuration and application links.
- Configure the reset and verification action URLs to an HTTPS page owned by the project. Test expired, malformed, already-used, reset-password, and verify-email `oobCode` links on Android and Web. Never log action codes.
- Upgrade/configure Firebase Identity Platform before claiming MFA. Select supported factors, recovery policy, enrollment UX, privileged-role requirements, and Emulator/staging tests.
- Enforce distributed login throttling using Firebase/Identity Platform quotas, App Check, monitoring, and edge/API rate limits. Client cooldown is usability protection, not a security boundary.
- Implement cross-device session revocation through a protected server endpoint using Firebase Admin `revokeRefreshTokens`. Require recent login, record an audit event, and sign out the current device afterward.
- Alert on credential stuffing, reset spikes, verification abuse, disabled users, MFA changes, password changes, account deletion, and session revocation without including email addresses, tokens, IP addresses, or action codes in application logs.

Production acceptance requires Auth Emulator tests, staging action-link tests on Android/Web, role authorization tests, and manual verification that reset and verification links return to the intended application origin.

