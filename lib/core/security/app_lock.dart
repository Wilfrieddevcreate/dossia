import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:local_auth/local_auth.dart';
import 'package:local_auth_android/local_auth_android.dart';

import '../../features/settings/data/settings_repository.dart';

/// Durée passée hors de l'application au-delà de laquelle elle se verrouille.
const appLockGracePeriod = Duration(seconds: 30);

enum AuthOutcome {
  success,

  /// L'utilisateur a fermé l'invite.
  cancelled,

  /// Aucun verrouillage (code, schéma, empreinte) n'est configuré sur le
  /// téléphone.
  unavailable,

  /// Trop de tentatives : le téléphone bloque temporairement.
  lockedOut,
  failed,
}

/// Authentification du téléphone (empreinte, visage, code ou schéma).
/// Remplacée par une fausse implémentation dans les tests.
class DeviceAuth {
  DeviceAuth([LocalAuthentication? auth])
    : _auth = auth ?? LocalAuthentication();

  final LocalAuthentication _auth;

  Future<bool> isAvailable() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return false;
    try {
      return await _auth.isDeviceSupported();
    } catch (_) {
      return false;
    }
  }

  Future<AuthOutcome> authenticate(String reason) async {
    try {
      final ok = await _auth.authenticate(
        localizedReason: reason,
        // Le code du téléphone reste toujours possible en secours.
        biometricOnly: false,
        persistAcrossBackgrounding: true,
        authMessages: const [
          AndroidAuthMessages(
            signInTitle: 'Déverrouiller Dossia',
            cancelButton: 'Annuler',
          ),
        ],
      );
      return ok ? AuthOutcome.success : AuthOutcome.failed;
    } on LocalAuthException catch (e) {
      return switch (e.code) {
        LocalAuthExceptionCode.userCanceled ||
        LocalAuthExceptionCode.systemCanceled ||
        LocalAuthExceptionCode.timeout ||
        LocalAuthExceptionCode.userRequestedFallback ||
        LocalAuthExceptionCode.authInProgress => AuthOutcome.cancelled,
        LocalAuthExceptionCode.noCredentialsSet => AuthOutcome.unavailable,
        LocalAuthExceptionCode.temporaryLockout ||
        LocalAuthExceptionCode.biometricLockout => AuthOutcome.lockedOut,
        _ => AuthOutcome.failed,
      };
    } on PlatformException {
      return AuthOutcome.failed;
    }
  }
}

final deviceAuthProvider = Provider<DeviceAuth>((ref) => DeviceAuth());

/// État de verrouillage au démarrage, fixé avant le premier affichage pour
/// qu'aucun contenu n'apparaisse avant le déverrouillage.
final initialAppLockProvider = Provider<bool>((ref) => false);

/// Horloge, remplaçable dans les tests.
final appLockClockProvider = Provider<DateTime Function()>(
  (ref) => DateTime.now,
);

/// Retour depuis une activité ouverte par Dossia (appareil photo, sélecteur
/// de fichiers, partage) : ce retour ne doit pas verrouiller l'application.
abstract final class ExternalActivity {
  static DateTime? _until;

  /// À appeler juste avant d'ouvrir une activité Android externe.
  static void expect() =>
      _until = DateTime.now().add(const Duration(minutes: 5));

  static bool _consume() {
    final until = _until;
    _until = null;
    return until != null && DateTime.now().isBefore(until);
  }
}

/// `true` lorsque l'application est verrouillée.
class AppLockController extends Notifier<bool> {
  DateTime? _backgroundedAt;
  bool _authenticating = false;

  @override
  bool build() => ref.read(initialAppLockProvider);

  bool get _enabled => ref.read(settingsProvider).value?.appLockEnabled ?? false;

  DateTime _now() => ref.read(appLockClockProvider)();

  void onBackground() {
    if (_authenticating) return;
    _backgroundedAt ??= _now();
  }

  void onForeground() {
    final since = _backgroundedAt;
    _backgroundedAt = null;
    if (_authenticating || since == null) return;
    if (ExternalActivity._consume()) return;
    if (_enabled && _now().difference(since) >= appLockGracePeriod) {
      state = true;
    }
  }

  /// Demande l'authentification et déverrouille en cas de succès. Si le
  /// téléphone n'a plus aucun verrouillage configuré, le verrouillage de
  /// Dossia est désactivé pour ne jamais bloquer l'accès aux données.
  Future<AuthOutcome> unlock() async {
    if (_authenticating) return AuthOutcome.cancelled;
    _authenticating = true;
    try {
      final auth = ref.read(deviceAuthProvider);
      final outcome = await auth.isAvailable()
          ? await auth.authenticate('Accédez à vos documents et dossiers.')
          : AuthOutcome.unavailable;
      if (outcome == AuthOutcome.unavailable) {
        await ref
            .read(settingsRepositoryProvider)
            .setBool(SettingKeys.appLockEnabled, false);
      }
      if (outcome == AuthOutcome.success ||
          outcome == AuthOutcome.unavailable) {
        state = false;
      }
      return outcome;
    } finally {
      _authenticating = false;
      _backgroundedAt = null;
    }
  }

  /// Active ou désactive le verrouillage, après authentification.
  Future<AuthOutcome> setEnabled(bool enable) async {
    if (_authenticating) return AuthOutcome.cancelled;
    _authenticating = true;
    try {
      final auth = ref.read(deviceAuthProvider);
      if (!await auth.isAvailable()) return AuthOutcome.unavailable;
      final outcome = await auth.authenticate(
        enable
            ? 'Confirmez pour activer le verrouillage.'
            : 'Confirmez pour désactiver le verrouillage.',
      );
      if (outcome == AuthOutcome.success) {
        await ref
            .read(settingsRepositoryProvider)
            .setBool(SettingKeys.appLockEnabled, enable);
      }
      return outcome;
    } finally {
      _authenticating = false;
      _backgroundedAt = null;
    }
  }
}

final appLockProvider = NotifierProvider<AppLockController, bool>(
  AppLockController.new,
);
