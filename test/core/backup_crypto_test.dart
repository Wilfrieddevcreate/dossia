import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';
import 'package:dossia/core/backup/backup_crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Itérations réduites pour garder les tests rapides.
const _testIterations = 1000;

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('dossia_crypto_');
  });

  tearDown(() async {
    if (await dir.exists()) await dir.delete(recursive: true);
  });

  Uint8List bytesOf(int length) {
    // Contenu déterministe, non périodique sur un bloc.
    final out = Uint8List(length);
    var x = 2463534242;
    for (var i = 0; i < length; i++) {
      x ^= (x << 13) & 0xffffffff;
      x ^= x >> 17;
      x ^= (x << 5) & 0xffffffff;
      out[i] = x & 0xff;
    }
    return out;
  }

  Future<File> encrypt(
    List<int> clear, {
    String password = 'motdepasse',
  }) async {
    final source = File(p.join(dir.path, 'clair.zip'));
    await source.writeAsBytes(clear);
    final target = File(p.join(dir.path, 'sauvegarde.dossia'));
    await encryptBackupFile(
      sourcePath: source.path,
      targetPath: target.path,
      password: password,
      iterations: _testIterations,
    );
    await source.delete();
    return target;
  }

  Future<Uint8List> decrypt(File file, {String password = 'motdepasse'}) async {
    final target = File(p.join(dir.path, 'dechiffre.zip'));
    await decryptBackupFile(
      sourcePath: file.path,
      targetPath: target.path,
      password: password,
      minIterations: _testIterations,
    );
    final bytes = await target.readAsBytes();
    await target.delete();
    return bytes;
  }

  Matcher failsWith(BackupCryptoErrorKind kind) =>
      throwsA(isA<BackupCryptoException>().having((e) => e.kind, 'kind', kind));

  Future<void> expectNoPlaintextLeft() async {
    expect(await File(p.join(dir.path, 'dechiffre.zip')).exists(), isFalse);
  }

  group('PBKDF2-HMAC-SHA256', () {
    String hex(List<int> b) =>
        b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

    // Valeurs de référence : RFC 7914 § 11 et hashlib.pbkdf2_hmac (Python).
    for (final (password, salt, iterations, expected) in [
      (
        ascii.encode('passwd'),
        ascii.encode('salt'),
        1,
        '55ac046e56e3089fec1691c22544b605f94185216dde0465e68b9d57c20dacbc',
      ),
      (
        ascii.encode('Password'),
        ascii.encode('NaCl'),
        80000,
        '4ddcd8f60b98be21830cee5ef22701f9641a4418d04c0414aeff08876b34ab56',
      ),
      (
        ascii.encode('p' * 100), // clé plus longue qu'un bloc
        ascii.encode('sel-tres-long' * 3),
        1000,
        '3074b047651fafb6732562e4942af8066991b76fd7c91e4e8c6689fac3dcdd1a',
      ),
      (
        utf8.encode('mot de passe éèà'),
        List.generate(16, (i) => i),
        4096,
        '3749516b119bc9bdf02ebe0c91c6f47ef89a3ac6341aa9a653f2bee20f3a140b',
      ),
      (
        <int>[],
        ascii.encode('salt'),
        3,
        '5ddf839afa2d5fb4be56e1a0f48917617559bef61ec122bfca1c7f75ac8f401d',
      ),
    ]) {
      test('vecteur $iterations itérations', () {
        expect(hex(pbkdf2HmacSha256(password, salt, iterations)), expected);
      });
    }

    test('identique à DartPbkdf2 sur des entrées aléatoires', () async {
      final random = Random(42);
      for (var n = 0; n < 20; n++) {
        final password = List.generate(
          random.nextInt(90),
          (_) => random.nextInt(256),
        );
        final salt = List.generate(
          random.nextInt(40),
          (_) => random.nextInt(256),
        );
        final iterations = 1 + random.nextInt(300);
        final reference = await DartPbkdf2(
          macAlgorithm: DartHmac(const DartSha256()),
          iterations: iterations,
          bits: 256,
        ).deriveKey(secretKey: SecretKeyData(password), nonce: salt);
        expect(
          pbkdf2HmacSha256(password, salt, iterations),
          await reference.extractBytes(),
        );
      }
    });
  });

  group('aller-retour', () {
    for (final (label, size) in [
      ('vide', 0),
      ('1 octet', 1),
      ('exactement 1 Mio', encryptedChunkSize),
      ('1 Mio + 1', encryptedChunkSize + 1),
      ('3,5 Mio', encryptedChunkSize * 3 + encryptedChunkSize ~/ 2),
    ]) {
      test(label, () async {
        final clear = bytesOf(size);
        final file = await encrypt(clear);
        expect(await isEncryptedContainer(file), isTrue);
        // En-tête + au moins une étiquette, et le clair n'apparaît pas.
        final blocks = size == 0
            ? 1
            : (size + encryptedChunkSize - 1) ~/ encryptedChunkSize;
        expect(await file.length(), encryptedHeaderLength + size + blocks * 16);
        expect(await decrypt(file), clear);
      });
    }

    test(
      'deux chiffrements du même contenu diffèrent (sel aléatoire)',
      () async {
        final clear = bytesOf(1000);
        final a = await (await encrypt(clear)).readAsBytes();
        final b = await (await encrypt(clear)).readAsBytes();
        expect(a, isNot(equals(b)));
      },
    );
  });

  group('erreurs', () {
    test('mauvais mot de passe', () async {
      final file = await encrypt(bytesOf(5000));
      await expectLater(
        decrypt(file, password: 'autre-mot-de-passe'),
        failsWith(BackupCryptoErrorKind.wrongPassword),
      );
      await expectNoPlaintextLeft();
    });

    test(
      'octet du sel modifié : indiscernable d’un mauvais mot de passe',
      () async {
        final file = await encrypt(bytesOf(5000));
        final bytes = await file.readAsBytes();
        bytes[20] ^= 0x01;
        await file.writeAsBytes(bytes);
        await expectLater(
          decrypt(file),
          failsWith(BackupCryptoErrorKind.wrongPassword),
        );
      },
    );

    test('marque modifiée', () async {
      final file = await encrypt(bytesOf(10));
      final bytes = await file.readAsBytes();
      bytes[0] = 0x58;
      await file.writeAsBytes(bytes);
      expect(await isEncryptedContainer(file), isFalse);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
    });

    test('version de format inconnue', () async {
      final file = await encrypt(bytesOf(10));
      final bytes = await file.readAsBytes();
      bytes[9] = 2;
      await file.writeAsBytes(bytes);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.unsupported),
      );
    });

    test('taille de bloc modifiée dans l’en-tête', () async {
      final file = await encrypt(bytesOf(10));
      final bytes = await file.readAsBytes();
      bytes[33] ^= 0x01; // reste dans les bornes : l'empreinte échoue.
      await file.writeAsBytes(bytes);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.wrongPassword),
      );
    });

    test('texte chiffré modifié dans un bloc du milieu', () async {
      final file = await encrypt(bytesOf(encryptedChunkSize * 3));
      final bytes = await file.readAsBytes();
      bytes[encryptedHeaderLength + encryptedChunkSize + 16 + 500] ^= 0x80;
      await file.writeAsBytes(bytes);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
      await expectNoPlaintextLeft();
    });

    test('dernier bloc supprimé (troncature)', () async {
      final file = await encrypt(bytesOf(encryptedChunkSize * 2 + 100));
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(
        bytes.sublist(0, encryptedHeaderLength + 2 * (encryptedChunkSize + 16)),
      );
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
    });

    test('troncature au milieu d’un bloc', () async {
      final file = await encrypt(bytesOf(encryptedChunkSize + 100));
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(bytes.sublist(0, bytes.length - 40));
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
    });

    test('fichier réduit à l’en-tête', () async {
      final file = await encrypt(bytesOf(100));
      final bytes = await file.readAsBytes();
      await file.writeAsBytes(bytes.sublist(0, encryptedHeaderLength));
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
    });

    test('données ajoutées après le dernier bloc', () async {
      for (final extra in [5, 16, 200]) {
        final file = await encrypt(bytesOf(3000));
        await file.writeAsBytes([
          ...await file.readAsBytes(),
          ...List.filled(extra, 7),
        ]);
        await expectLater(
          decrypt(file),
          failsWith(BackupCryptoErrorKind.damaged),
          reason: '$extra octets ajoutés',
        );
      }
    });

    test('blocs permutés', () async {
      final file = await encrypt(bytesOf(encryptedChunkSize * 3));
      final bytes = await file.readAsBytes();
      const block = encryptedChunkSize + 16;
      final first = bytes.sublist(
        encryptedHeaderLength,
        encryptedHeaderLength + block,
      );
      final second = bytes.sublist(
        encryptedHeaderLength + block,
        encryptedHeaderLength + 2 * block,
      );
      bytes.setRange(
        encryptedHeaderLength,
        encryptedHeaderLength + block,
        second,
      );
      bytes.setRange(
        encryptedHeaderLength + block,
        encryptedHeaderLength + 2 * block,
        first,
      );
      await file.writeAsBytes(bytes);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
    });

    test('itérations hors bornes à la lecture', () async {
      final file = await encrypt(bytesOf(10));
      // Le fichier de test (1000 itérations) est refusé avec le plancher réel.
      await expectLater(
        decryptBackupFile(
          sourcePath: file.path,
          targetPath: p.join(dir.path, 'dechiffre.zip'),
          password: 'motdepasse',
        ),
        failsWith(BackupCryptoErrorKind.damaged),
      );
      // Et une valeur démesurée est refusée avant tout calcul.
      final bytes = await file.readAsBytes();
      bytes.setRange(11, 15, [0xff, 0xff, 0xff, 0xff]);
      await file.writeAsBytes(bytes);
      await expectLater(
        decrypt(file),
        failsWith(BackupCryptoErrorKind.damaged),
      );
      expect(
        () => encryptBackupFile(
          sourcePath: file.path,
          targetPath: p.join(dir.path, 'x.dossia'),
          password: 'motdepasse',
          iterations: maxKdfIterations + 1,
        ),
        throwsArgumentError,
      );
    });

    test('fichier non chiffré', () async {
      final zip = File(p.join(dir.path, 'ordinaire.zip'));
      await zip.writeAsBytes([0x50, 0x4b, 0x03, 0x04, 1, 2, 3]);
      expect(await isEncryptedContainer(zip), isFalse);
      expect(
        await isEncryptedContainer(File(p.join(dir.path, 'absent'))),
        isFalse,
      );
    });
  });

  test('coût de la dérivation par défaut (informatif)', () async {
    final source = File(p.join(dir.path, 'clair.zip'));
    await source.writeAsBytes(bytesOf(encryptedChunkSize * 8));
    final watch = Stopwatch()..start();
    await encryptBackupFile(
      sourcePath: source.path,
      targetPath: p.join(dir.path, 'grand.dossia'),
      password: 'motdepasse',
    );
    // ignore: avoid_print
    print('600 000 itérations + 8 Mio : ${watch.elapsedMilliseconds} ms');
  }, tags: ['lent']);
}
