import 'package:agriculture_pest_system/core/models/app_models.dart';
import 'package:agriculture_pest_system/core/providers/repository_providers.dart';
import 'package:agriculture_pest_system/features/auth_security/domain/auth_security.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class PrivacyAccountScreen extends ConsumerStatefulWidget {
  final UserProfile user;
  const PrivacyAccountScreen({super.key, required this.user});

  @override
  ConsumerState<PrivacyAccountScreen> createState() =>
      _PrivacyAccountScreenState();
}

class _PrivacyAccountScreenState extends ConsumerState<PrivacyAccountScreen> {
  bool busy = false;

  Future<void> _requestDeletion() async {
    final controller = TextEditingController();
    final passwordController = TextEditingController();
    final authRepository = ref.read(authProfileRepositoryProvider);
    final passwordAccount = authRepository.auth.currentUser?.providerData.any(
          (provider) => provider.providerId == 'password',
        ) ??
        false;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Request account deletion?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Your account will enter a seven-day grace period. You can cancel during that period. Afterward, your profile and owned application data are permanently removed.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              decoration: const InputDecoration(
                labelText: 'Type DELETE to confirm',
              ),
            ),
            if (passwordAccount) ...[
              const SizedBox(height: 12),
              TextField(
                controller: passwordController,
                obscureText: true,
                decoration: const InputDecoration(
                  labelText: 'Current password',
                  helperText: 'Required to verify this sensitive action',
                ),
              ),
            ],
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep account'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(context, controller.text.trim() == 'DELETE'),
            child: const Text('Request deletion'),
          ),
        ],
      ),
    );
    final password = passwordController.text;
    controller.dispose();
    passwordController.dispose();
    if (confirmed != true) return;
    setState(() => busy = true);
    try {
      if (passwordAccount) {
        await authRepository.reauthenticateWithPassword(password);
      } else {
        final lastSignIn = authRepository.auth.currentUser?.metadata.lastSignInTime;
        if (lastSignIn == null || DateTime.now().difference(lastSignIn) > const Duration(minutes: 5)) {
          throw StateError('For security, log out and sign in again before deleting your account.');
        }
      }
      await ref
          .read(dataLifecycleRepositoryProvider)
          .requestAccountDeletion(widget.user.uid);
      await authRepository.recordSecurityEvent('account_deletion_requested');
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              error is StateError
                  ? error.message
                  : accessibleAuthMessage(error),
            ),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _cancelDeletion() async {
    setState(() => busy = true);
    try {
      await ref
          .read(dataLifecycleRepositoryProvider)
          .cancelAccountDeletion(widget.user.uid);
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Cancellation failed: $error')));
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = ref.watch(deletionRequestProvider(widget.user.uid));
    final pending = request.value != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Privacy & account')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          const Card(
            child: ListTile(
              leading: Icon(Icons.privacy_tip_outlined),
              title: Text('Data lifecycle'),
              subtitle: Text(
                'Operational diagnostics are retained for 90 days and security audit logs for 365 days. Report exports remain under your control.',
              ),
            ),
          ),
          const SizedBox(height: 16),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    pending ? 'Deletion pending' : 'Delete account',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    pending
                        ? 'Your request is in its grace period. Cancel it to keep your account.'
                        : 'Request permanent deletion of your profile, owned records, reports, uploads, and authentication account.',
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: busy
                        ? null
                        : pending
                        ? _cancelDeletion
                        : _requestDeletion,
                    icon: Icon(pending ? Icons.undo : Icons.delete_outline),
                    label: Text(
                      pending ? 'Cancel deletion' : 'Request account deletion',
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
