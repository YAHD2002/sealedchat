import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// X25519 key exchange + AES-256-GCM encryption + SHA-256 hashing.
class CryptoService {
  static final _kx = X25519();
  static final _aes = AesGcm.with256bits();
  static final _sha = Sha256();

  static Future<KeyPair> newKeyPair() => _kx.newKeyPair();

  /// Public key as base64.
  static Future<String> exportPublic(KeyPair kp) async {
    final pk = await kp.extractPublicKey() as SimplePublicKey;
    return base64Encode(pk.bytes);
  }

  static SimplePublicKey _importPublic(String b64) =>
      SimplePublicKey(base64Decode(b64), type: KeyPairType.x25519);

  static Future<SecretKey> sharedKey(KeyPair mine, String theirPublicB64) =>
      _kx.sharedSecretKey(keyPair: mine, remotePublicKey: _importPublic(theirPublicB64));

  /// Returns base64(nonce || ciphertext || mac).
  static Future<String> encrypt(String text, SecretKey key) async {
    final box = await _aes.encrypt(utf8.encode(text), secretKey: key);
    return base64Encode(box.concatenation());
  }

  static Future<String> decrypt(String payload, SecretKey key) async {
    final box = SecretBox.fromConcatenation(base64Decode(payload),
        nonceLength: 12, macLength: 16);
    return utf8.decode(await _aes.decrypt(box, secretKey: key));
  }

  static Future<String> sha256Hex(String s) async {
    final h = await _sha.hash(utf8.encode(s));
    return h.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}