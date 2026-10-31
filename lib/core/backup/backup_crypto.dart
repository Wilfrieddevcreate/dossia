/// Chiffrement des sauvegardes par mot de passe.
///
/// ## Conteneur chiffré, format 1
///
/// En-tête (67 octets), authentifié :
///
/// | Octets  | Contenu                                                    |
/// | ------- | ---------------------------------------------------------- |
/// | 0–8     | « DOSSIAENC » (ASCII)                                      |
/// | 9       | version du format (1)                                      |
/// | 10      | dérivation de clé (1 = PBKDF2-HMAC-SHA256)                 |
/// | 11–14   | nombre d'itérations (uint32 gros-boutiste)                 |
/// | 15–30   | sel aléatoire (16 octets, `Random.secure`)                 |
/// | 31–34   | taille des blocs en clair (uint32, 1 Mio)                  |
/// | 35–66   | empreinte de contrôle du mot de passe (HMAC-SHA256)        |
///
/// Viennent ensuite les blocs : chaque bloc de clair (1 Mio au plus) est
/// chiffré en AES-256-GCM et stocké sous la forme texte chiffré ‖ étiquette
/// de 16 octets. Les nonces suivent la construction STREAM (comme le format
/// age) : compteur de bloc sur 11 octets gros-boutiste ‖ 1 octet valant 1
/// pour le dernier bloc, 0 sinon. L'en-tête complet sert de données
/// associées (AAD) à chaque bloc. Un contenu vide produit un unique bloc
/// final vide.
///
/// La clé maîtresse (32 octets) est dérivée du mot de passe (UTF-8) par
/// PBKDF2-HMAC-SHA256 avec le sel (implémentation optimisée ci-dessous) ; deux sous-clés en sont tirées par
/// HMAC-SHA256 : la clé de chiffrement et la clé de contrôle. L'empreinte de
/// contrôle (HMAC des 35 premiers octets de l'en-tête) permet de distinguer
/// un mot de passe erroné d'un fichier endommagé, sans rien révéler de plus
/// que l'étiquette GCM du premier bloc.
///
/// Le sel étant aléatoire, la clé est unique pour chaque fichier : le
/// compteur de bloc suffit comme nonce. Toute modification, suppression,
/// permutation ou troncature de blocs, ou tout ajout de données, est détecté.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:cryptography/cryptography.dart';
import 'package:cryptography/dart.dart';

/// Marque de début des sauvegardes chiffrées.
final encryptedBackupMagic = ascii.encode('DOSSIAENC');

const encryptedBackupFormatVersion = 1;
const _kdfPbkdf2HmacSha256 = 1;

/// Itérations PBKDF2 par défaut (recommandation OWASP pour SHA-256).
const defaultKdfIterations = 600000;

/// Bornes acceptées à la lecture : en dessous, la protection serait trop
/// faible ; au-dessus, l'ouverture pourrait bloquer l'appareil.
const minKdfIterations = 100000;
const maxKdfIterations = 10000000;

/// Taille des blocs de clair.
const encryptedChunkSize = 1 << 20;
const _minChunkSize = 1 << 10;
const _maxChunkSize = 1 << 24;

const _saltLength = 16;
const _tagLength = 16;
const _nonceLength = 12;
const _checkLength = 32;
const _baseHeaderLength = 9 + 1 + 1 + 4 + _saltLength + 4;

/// Longueur totale de l'en-tête.
const encryptedHeaderLength = _baseHeaderLength + _checkLength;

/// Longueur minimale d'un mot de passe de sauvegarde (en caractères).
const minBackupPasswordLength = 8;

enum BackupCryptoErrorKind {
  /// Le mot de passe ne correspond pas.
  wrongPassword,

  /// Fichier tronqué, modifié ou mal formé.
  damaged,

  /// Version du format ou dérivation de clé inconnue.
  unsupported,
}

class BackupCryptoException implements Exception {
  const BackupCryptoException(this.kind);

  final BackupCryptoErrorKind kind;

  @override
  String toString() => 'BackupCryptoException(${kind.name})';
}

/// Indique si [file] commence par la marque des sauvegardes chiffrées.
Future<bool> isEncryptedContainer(File file) async {
  if (!await file.exists()) return false;
  final raf = await file.open();
  try {
    final head = await raf.read(encryptedBackupMagic.length);
    if (head.length != encryptedBackupMagic.length) return false;
    for (var i = 0; i < head.length; i++) {
      if (head[i] != encryptedBackupMagic[i]) return false;
    }
    return true;
  } finally {
    await raf.close();
  }
}

/// Chiffre [sourcePath] vers [targetPath], hors du fil principal. En cas
/// d'échec, le fichier cible partiel est supprimé.
Future<void> encryptBackupFile({
  required String sourcePath,
  required String targetPath,
  required String password,
  int iterations = defaultKdfIterations,
}) {
  if (iterations < 1 || iterations > maxKdfIterations) {
    throw ArgumentError.value(iterations, 'iterations');
  }
  return Isolate.run(
    () => _encrypt(sourcePath, targetPath, password, iterations),
  );
}

/// Déchiffre [sourcePath] vers [targetPath], hors du fil principal. Lève une
/// [BackupCryptoException] ; le fichier cible partiel est alors supprimé.
///
/// [minIterations] ne doit être abaissé que dans les tests.
Future<void> decryptBackupFile({
  required String sourcePath,
  required String targetPath,
  required String password,
  int minIterations = minKdfIterations,
}) {
  return Isolate.run(
    () => _decrypt(sourcePath, targetPath, password, minIterations),
  );
}

// -----------------------------------------------------------------------------
// Implémentation (exécutée dans un isolate)

class _Keys {
  _Keys(this.encryption, this.check);

  final Uint8List encryption;
  final Uint8List check;

  void wipe() {
    encryption.fillRange(0, encryption.length, 0);
    check.fillRange(0, check.length, 0);
  }
}

Future<_Keys> _deriveKeys(
  String password,
  List<int> salt,
  int iterations,
) async {
  final passwordBytes = Uint8List.fromList(utf8.encode(password));
  final master = pbkdf2HmacSha256(passwordBytes, salt, iterations);
  passwordBytes.fillRange(0, passwordBytes.length, 0);
  try {
    final hmac = crypto.Hmac(crypto.sha256, master);
    return _Keys(
      Uint8List.fromList(hmac.convert(utf8.encode('dossia/chiffrement')).bytes),
      Uint8List.fromList(hmac.convert(utf8.encode('dossia/controle')).bytes),
    );
  } finally {
    master.fillRange(0, master.length, 0);
  }
}

// -----------------------------------------------------------------------------
// PBKDF2-HMAC-SHA256 (RFC 8018), clé de 32 octets.
//
// Implémentation dédiée : les états HMAC « ipad » et « opad » sont calculés
// une seule fois, chaque itération ne coûte donc que deux compressions
// SHA-256, sans allocation. C'est 2 à 4 fois plus rapide que l'implémentation
// générique, ce qui compte sur les téléphones d'entrée de gamme. Vérifiée par
// les vecteurs de la RFC 7914 et par comparaison avec `DartPbkdf2`.

/// Dérive une clé de 32 octets (exposé pour les tests).
Uint8List pbkdf2HmacSha256(List<int> password, List<int> salt, int iterations) {
  if (iterations < 1) throw ArgumentError.value(iterations, 'iterations');
  final key = Uint8List(64)
    ..setAll(
      0,
      password.length > 64 ? crypto.sha256.convert(password).bytes : password,
    );
  final pad = Uint32List(16);
  final inner = Uint32List.fromList(_sha256Iv);
  final outer = Uint32List.fromList(_sha256Iv);
  for (var i = 0; i < 16; i++) {
    pad[i] = _word(key, i * 4) ^ 0x36363636;
  }
  _compress(inner, pad);
  for (var i = 0; i < 16; i++) {
    pad[i] = _word(key, i * 4) ^ 0x5c5c5c5c;
  }
  _compress(outer, pad);
  key.fillRange(0, key.length, 0);
  pad.fillRange(0, pad.length, 0);

  // U1 = HMAC(P, S ‖ INT(1)).
  final first = crypto.Hmac(
    crypto.sha256,
    password,
  ).convert([...salt, 0, 0, 0, 1]).bytes;
  final u = Uint32List(8);
  for (var i = 0; i < 8; i++) {
    u[i] = _word(first, i * 4);
  }
  final t = Uint32List.fromList(u);

  // Message de 32 octets après un bloc de clé : longueur totale 96 octets.
  final message = Uint32List(16)
    ..[8] = 0x80000000
    ..[15] = 96 * 8;
  final state = Uint32List(8);
  for (var j = 1; j < iterations; j++) {
    message.setRange(0, 8, u);
    state.setAll(0, inner);
    _compress(state, message);
    message.setRange(0, 8, state);
    state.setAll(0, outer);
    _compress(state, message);
    for (var i = 0; i < 8; i++) {
      u[i] = state[i];
      t[i] ^= state[i];
    }
  }

  final out = Uint8List(32);
  for (var i = 0; i < 8; i++) {
    out[i * 4] = t[i] >> 24;
    out[i * 4 + 1] = (t[i] >> 16) & 0xff;
    out[i * 4 + 2] = (t[i] >> 8) & 0xff;
    out[i * 4 + 3] = t[i] & 0xff;
  }
  for (final list in [inner, outer, u, t, message, state]) {
    list.fillRange(0, list.length, 0);
  }
  return out;
}

int _word(List<int> b, int o) =>
    (b[o] << 24) | (b[o + 1] << 16) | (b[o + 2] << 8) | b[o + 3];

const _sha256Iv = <int>[
  0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
  0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
];

const _sha256K = <int>[
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, //
  0x923f82a4, 0xab1c5ed5, 0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3,
  0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174, 0xe49b69c1, 0xefbe4786,
  0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147,
  0x06ca6351, 0x14292967, 0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13,
  0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85, 0xa2bfe8a1, 0xa81a664b,
  0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a,
  0x5b9cca4f, 0x682e6ff3, 0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208,
  0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

final _schedule = Uint32List(64);

/// Compression SHA-256 d'un bloc de 16 mots dans [state].
void _compress(Uint32List state, Uint32List block) {
  final w = _schedule;
  for (var i = 0; i < 16; i++) {
    w[i] = block[i];
  }
  for (var i = 16; i < 64; i++) {
    final x = w[i - 15], y = w[i - 2];
    final s0 = _rotr(x, 7) ^ _rotr(x, 18) ^ (x >> 3);
    final s1 = _rotr(y, 17) ^ _rotr(y, 19) ^ (y >> 10);
    w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & 0xffffffff;
  }
  var a = state[0], b = state[1], c = state[2], d = state[3];
  var e = state[4], f = state[5], g = state[6], h = state[7];
  for (var i = 0; i < 64; i++) {
    final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
    final ch = (e & f) ^ (~e & g);
    final t1 = (h + s1 + ch + _sha256K[i] + w[i]) & 0xffffffff;
    final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
    final maj = (a & b) ^ (a & c) ^ (b & c);
    final t2 = (s0 + maj) & 0xffffffff;
    h = g;
    g = f;
    f = e;
    e = (d + t1) & 0xffffffff;
    d = c;
    c = b;
    b = a;
    a = (t1 + t2) & 0xffffffff;
  }
  state[0] = (state[0] + a) & 0xffffffff;
  state[1] = (state[1] + b) & 0xffffffff;
  state[2] = (state[2] + c) & 0xffffffff;
  state[3] = (state[3] + d) & 0xffffffff;
  state[4] = (state[4] + e) & 0xffffffff;
  state[5] = (state[5] + f) & 0xffffffff;
  state[6] = (state[6] + g) & 0xffffffff;
  state[7] = (state[7] + h) & 0xffffffff;
}

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & 0xffffffff;

Uint8List _u32(int value) =>
    Uint8List(4)..buffer.asByteData().setUint32(0, value, Endian.big);

int _readU32(List<int> bytes, int offset) => ByteData.sublistView(
  Uint8List.fromList(bytes.sublist(offset, offset + 4)),
).getUint32(0, Endian.big);

List<int> _nonce(int counter, bool last) {
  final nonce = Uint8List(_nonceLength);
  var c = counter;
  for (var i = _nonceLength - 2; i >= 0 && c > 0; i--) {
    nonce[i] = c & 0xff;
    c >>= 8;
  }
  nonce[_nonceLength - 1] = last ? 1 : 0;
  return nonce;
}

List<int> _check(_Keys keys, List<int> baseHeader) =>
    crypto.Hmac(crypto.sha256, keys.check).convert(baseHeader).bytes;

bool _constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

Future<void> _encrypt(
  String sourcePath,
  String targetPath,
  String password,
  int iterations,
) async {
  final random = Random.secure();
  final salt = Uint8List.fromList(
    List.generate(_saltLength, (_) => random.nextInt(256)),
  );
  final baseHeader =
      (BytesBuilder()
            ..add(encryptedBackupMagic)
            ..addByte(encryptedBackupFormatVersion)
            ..addByte(_kdfPbkdf2HmacSha256)
            ..add(_u32(iterations))
            ..add(salt)
            ..add(_u32(encryptedChunkSize)))
          .toBytes();
  final keys = await _deriveKeys(password, salt, iterations);
  final header = Uint8List.fromList([
    ...baseHeader,
    ..._check(keys, baseHeader),
  ]);

  final aes = DartAesGcm.with256bits();
  final keyData = SecretKeyData(keys.encryption);
  final input = File(sourcePath).openSync();
  final output = File(targetPath).openSync(mode: FileMode.writeOnly);
  var completed = false;
  try {
    output.writeFromSync(header);
    final length = input.lengthSync();
    final chunks = max(
      1,
      (length + encryptedChunkSize - 1) ~/ encryptedChunkSize,
    );
    for (var i = 0; i < chunks; i++) {
      final clear = input.readSync(encryptedChunkSize);
      final box = aes.encryptSync(
        clear,
        secretKeyData: keyData,
        nonce: _nonce(i, i == chunks - 1),
        aad: header,
      );
      output
        ..writeFromSync(box.cipherText)
        ..writeFromSync(box.mac.bytes);
    }
    output.flushSync();
    completed = true;
  } finally {
    keys.wipe();
    input.closeSync();
    output.closeSync();
    if (!completed) _deleteQuietly(targetPath);
  }
}

Future<void> _decrypt(
  String sourcePath,
  String targetPath,
  String password,
  int minIterations,
) async {
  const damaged = BackupCryptoException(BackupCryptoErrorKind.damaged);
  final input = File(sourcePath).openSync();
  RandomAccessFile? output;
  _Keys? keys;
  var completed = false;
  try {
    final total = input.lengthSync();
    if (total < encryptedHeaderLength) throw damaged;
    final header = input.readSync(encryptedHeaderLength);
    if (!_constantTimeEquals(
      header.sublist(0, encryptedBackupMagic.length),
      encryptedBackupMagic,
    )) {
      throw damaged;
    }
    if (header[9] != encryptedBackupFormatVersion ||
        header[10] != _kdfPbkdf2HmacSha256) {
      throw const BackupCryptoException(BackupCryptoErrorKind.unsupported);
    }
    final iterations = _readU32(header, 11);
    if (iterations < minIterations || iterations > maxKdfIterations) {
      throw damaged;
    }
    final salt = header.sublist(15, 15 + _saltLength);
    final chunkSize = _readU32(header, 15 + _saltLength);
    if (chunkSize < _minChunkSize || chunkSize > _maxChunkSize) throw damaged;

    final baseHeader = header.sublist(0, _baseHeaderLength);
    keys = await _deriveKeys(password, salt, iterations);
    if (!_constantTimeEquals(
      _check(keys, baseHeader),
      header.sublist(_baseHeaderLength),
    )) {
      throw const BackupCryptoException(BackupCryptoErrorKind.wrongPassword);
    }

    // Le mot de passe est bon : toute erreur suivante vient du fichier.
    final body = total - encryptedHeaderLength;
    if (body <= 0) throw damaged;
    final block = chunkSize + _tagLength;
    final chunks = (body + block - 1) ~/ block;
    final lastSize = body - (chunks - 1) * block;
    if (lastSize < _tagLength) throw damaged;

    final aes = DartAesGcm.with256bits();
    final keyData = SecretKeyData(keys.encryption);
    output = File(targetPath).openSync(mode: FileMode.writeOnly);
    for (var i = 0; i < chunks; i++) {
      final last = i == chunks - 1;
      final size = last ? lastSize : block;
      final data = input.readSync(size);
      if (data.length != size) throw damaged;
      final split = size - _tagLength;
      try {
        final clear = aes.decryptSync(
          SecretBox(
            Uint8List.sublistView(data, 0, split),
            nonce: _nonce(i, last),
            mac: Mac(Uint8List.sublistView(data, split)),
          ),
          secretKeyData: keyData,
          aad: header,
        );
        output.writeFromSync(clear);
      } on SecretBoxAuthenticationError {
        throw damaged;
      }
    }
    output.flushSync();
    completed = true;
  } finally {
    keys?.wipe();
    input.closeSync();
    output?.closeSync();
    if (!completed) _deleteQuietly(targetPath);
  }
}

void _deleteQuietly(String path) {
  try {
    final file = File(path);
    if (file.existsSync()) file.deleteSync();
  } on FileSystemException {
    // Nettoyage non critique.
  }
}
