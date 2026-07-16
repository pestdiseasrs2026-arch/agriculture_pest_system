import 'package:agriculture_pest_system/core/providers/repository_providers.dart';
import 'package:agriculture_pest_system/features/auth_security/domain/auth_security.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class AccountSecurityScreen extends ConsumerStatefulWidget {
  const AccountSecurityScreen({super.key});

  @override
  ConsumerState<AccountSecurityScreen> createState() => _AccountSecurityScreenState();
}

class _AccountSecurityScreenState extends ConsumerState<AccountSecurityScreen> {
  final currentPassword = TextEditingController();
  final newPassword = TextEditingController();
  final confirmation = TextEditingController();
  bool busy = false;

  @override
  void dispose() {
    currentPassword.dispose();
    newPassword.dispose();
    confirmation.dispose();
    super.dispose();
  }

  Future<void> _changePassword() async {
    final policyError = PasswordPolicy.validate(newPassword.text);
    if (policyError != null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(policyError)));
      return;
    }
    if (newPassword.text != confirmation.text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('New passwords do not match.')),
      );
      return;
    }
    setState(() => busy = true);
    final repository = ref.read(authProfileRepositoryProvider);
    try {
      await repository.reauthenticateWithPassword(currentPassword.text);
      await repository.changePassword(newPassword.text);
      await repository.recordSecurityEvent('password_changed');
      currentPassword.clear(); newPassword.clear(); confirmation.clear();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password changed successfully.')),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(accessibleAuthMessage(error))),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final passwordAccount = user?.providerData.any((provider) => provider.providerId == 'password') ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Account security')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Card(
            child: ListTile(
              leading: Icon(user?.emailVerified == true ? Icons.verified_user : Icons.mark_email_unread_outlined),
              title: Text(user?.emailVerified == true ? 'Email verified' : 'Email verification required'),
              subtitle: Text(user?.email ?? 'No email address'),
              trailing: user != null && !user.emailVerified
                  ? TextButton(
                      onPressed: busy ? null : () async {
                        await ref.read(authProfileRepositoryProvider).sendVerification();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(content: Text('Verification email sent.')),
                          );
                        }
                      },
                      child: const Text('Resend'),
                    )
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          if (passwordAccount)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('Change password', style: Theme.of(context).textTheme.titleLarge),
                    const SizedBox(height: 8),
                    const Text('Changing your password requires your current password and a recent sign-in.'),
                    const SizedBox(height: 16),
                    TextField(controller: currentPassword, obscureText: true, decoration: const InputDecoration(labelText: 'Current password')),
                    const SizedBox(height: 12),
                    TextField(controller: newPassword, obscureText: true, decoration: const InputDecoration(labelText: 'New password', helperText: '12+ characters with uppercase, lowercase, number, and symbol')),
                    const SizedBox(height: 12),
                    TextField(controller: confirmation, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm new password')),
                    const SizedBox(height: 16),
                    FilledButton.icon(onPressed: busy ? null : _changePassword, icon: const Icon(Icons.password), label: const Text('Change password')),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 16),
          const Card(
            child: Column(
              children: [
                ListTile(leading: Icon(Icons.devices_outlined), title: Text('Current session'), subtitle: Text('Firebase securely refreshes this signed-in device. Use logout to end this session.')),
                Divider(height: 1),
                ListTile(leading: Icon(Icons.phonelink_lock_outlined), title: Text('Multi-factor authentication readiness'), subtitle: Text('MFA enrollment requires Firebase Identity Platform and supported second-factor configuration. It is not yet enforced.')),
                Divider(height: 1),
                ListTile(leading: Icon(Icons.security_outlined), title: Text('Abuse protection'), subtitle: Text('App Check and Firebase Authentication quotas protect backend requests. Distributed rate limits must be configured server-side.')),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

