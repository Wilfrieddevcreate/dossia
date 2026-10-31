import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../widgets/common.dart';
import 'app_lock.dart';

/// Recouvre toute l'application tant qu'elle est verrouillée. Le contenu
/// en dessous n'est ni visible, ni accessible, ni lu par les lecteurs
/// d'écran.
class AppLockGate extends ConsumerWidget {
  const AppLockGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockProvider);
    return Stack(
      children: [
        ExcludeSemantics(excluding: locked, child: child),
        Positioned.fill(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: locked
                ? const LockScreen(key: ValueKey('lock'))
                : const SizedBox.shrink(key: ValueKey('open')),
          ),
        ),
      ],
    );
  }
}

class LockScreen extends ConsumerStatefulWidget {
  const LockScreen({super.key});

  @override
  ConsumerState<LockScreen> createState() => _LockScreenState();
}

class _LockScreenState extends ConsumerState<LockScreen> {
  String? _message;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    // L'invite s'ouvre d'elle-même dès que l'écran apparaît.
    WidgetsBinding.instance.addPostFrameCallback((_) => _unlock());
  }

  Future<void> _unlock() async {
    if (_busy || !mounted) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final outcome = await ref.read(appLockProvider.notifier).unlock();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _message = switch (outcome) {
        AuthOutcome.success || AuthOutcome.cancelled => null,
        AuthOutcome.unavailable => null,
        AuthOutcome.lockedOut =>
          'Trop de tentatives. Réessayez dans quelques instants.',
        AuthOutcome.failed => 'Déverrouillage impossible. Réessayez.',
      };
    });
    if (outcome == AuthOutcome.success) {
      HapticFeedback.lightImpact();
    } else if (outcome == AuthOutcome.unavailable) {
      showMessage(
        context,
        'Verrouillage désactivé : aucun code n’est configuré sur ce '
        'téléphone.',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: theme.scaffoldBackgroundColor,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  borderRadius: BorderRadius.circular(22),
                ),
                child: Icon(
                  Icons.lock_outline_rounded,
                  color: scheme.onPrimary,
                  size: 34,
                ),
              ),
              const SizedBox(height: 24),
              Semantics(
                header: true,
                child: Text(
                  'Dossia est verrouillé',
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Utilisez votre empreinte, votre visage ou le code du '
                'téléphone.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child: _message == null
                    ? const SizedBox(width: double.infinity)
                    : Text(
                        _message!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: scheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _busy ? null : _unlock,
                  icon: const Icon(Icons.fingerprint_rounded),
                  label: const Text('Déverrouiller'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
