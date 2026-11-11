import 'dart:convert';
import 'dart:math';
import 'package:cryptography/cryptography.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'crypto_service.dart';

/// Stores the private key encrypted with a key derived from the user's PIN.
class Vault {
  static final _kdf = Pbkdf2(macAlgorithm: Hmac.sha256(), iterations: 20000, bits: 256);
  static final _aes = AesGcm.with256bits();

  static Future<String?> savedName() async {
    final p = await SharedPreferences.getInstance();
    return p.getString('vault') == null ? null : p.getString('name');
  }

  static Future<String> savedServer() async =>
      (await SharedPreferences.getInstance()).getString('server') ?? 'http://localhost:3000';

  static Future<void> create(
      {required String name, required String pin, required KeyPair kp, required String server}) async {
    final salt = List<int>.generate(16, (_) => Random.secure().nextInt(256));
    final key = await _kdf.deriveKeyFromPassword(password: pin, nonce: salt);
    final priv = base64Decode(await CryptoService.exportPrivate(kp));
    final box = await _aes.encrypt(priv, secretKey: key);
    final p = await SharedPreferences.getInstance();
    await p.clear();
    await p.setString('name', name);
    await p.setString('salt', base64Encode(salt));
    await p.setString('vault', base64Encode(box.concatenation()));
    await p.setString('pub', await CryptoService.exportPublic(kp));
    await p.setString('server', server);
  }

  /// Returns the key pair, or null if the PIN is wrong.
  static Future<KeyPair?> unlock(String pin) async {
    final p = await SharedPreferences.getInstance();
    try {
      final key = await _kdf.deriveKeyFromPassword(
          password: pin, nonce: base64Decode(p.getString('salt')!));
      final box = SecretBox.fromConcatenation(base64Decode(p.getString('vault')!),
          nonceLength: 12, macLength: 16);
      final priv = await _aes.decrypt(box, secretKey: key);
      return CryptoService.importKeyPair(base64Encode(priv), p.getString('pub')!);
    } catch (_) {
      return null; // a wrong PIN fails the authentication check
    }
  }

  static Future<void> wipe() async => (await SharedPreferences.getInstance()).clear();
}