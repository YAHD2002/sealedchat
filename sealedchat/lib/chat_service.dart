import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chain.dart';
import 'crypto_service.dart';

class Bubble {
  final String text;
  String status;
  bool ok;
  final bool mine;
  final int ts;
  Bubble(this.text, this.status, this.ok, this.mine, [int? ts])
      : ts = ts ?? DateTime.now().millisecondsSinceEpoch;
  Map<String, dynamic> toJson() => {'t': text, 's': status, 'o': ok, 'm': mine, 'ts': ts};
  factory Bubble.fromJson(Map<String, dynamic> j) =>
      Bubble(j['t'], j['s'], j['o'], j['m'], j['ts']);
}

String short(String t) => t.length > 12 ? '${t.substring(0, 10)}…' : t;

/// Keeps one WebSocket open, verifies every incoming message against Sepolia,
/// and stores each chat's history encrypted on the device.
class ChatService extends ChangeNotifier {
  final String base, me;
  final KeyPair keyPair;
  ChatService(this.base, this.me, this.keyPair);

  final chats = <String, List<Bubble>>{};
  final unread = <String, int>{};
  final _pinned = <String, String>{};
  final _refs = <int, (String, Bubble)>{};
  WebSocketChannel? _ch;
  SecretKey? _storeKey;
  String? openPeer;
  String connection = 'Connecting…';
  int _counter = 0;
  bool _closed = false;

  void start() {
    final u = Uri.parse(base);
    _ch = WebSocketChannel.connect(u.replace(
        scheme: u.scheme == 'https' ? 'wss' : 'ws', path: '/ws', queryParameters: {'user': me}));
    connection = 'Connected';
    _ch!.stream.listen(_onWs, onDone: _lost, onError: (_) => _lost());
  }

  void _lost() {
    if (_closed) return;
    connection = 'Disconnected from server';
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _ch?.sink.close();
    super.dispose();
  }

  // ---------- encrypted history ----------
  Future<SecretKey> _key() async => _storeKey ??= await Hkdf(hmac: Hmac.sha256(), outputLength: 32)
      .deriveKey(
          secretKey: SecretKey(base64Decode(await CryptoService.exportPrivate(keyPair))),
          nonce: utf8.encode('sealedchat'),
          info: utf8.encode('history'));

  String _pk(String peer) => 'h_${me}_$peer';

  Future<List<Bubble>> load(String peer) async {
    if (chats.containsKey(peer)) return chats[peer]!;
    final list = <Bubble>[];
    try {
      final raw = (await SharedPreferences.getInstance()).getString(_pk(peer));
      if (raw != null) {
        final box = SecretBox.fromConcatenation(base64Decode(raw), nonceLength: 12, macLength: 16);
        final json = utf8.decode(await AesGcm.with256bits().decrypt(box, secretKey: await _key()));
        for (final j in jsonDecode(json) as List) {
          final b = Bubble.fromJson(j as Map<String, dynamic>);
          if (b.status.startsWith('Anchoring')) b.status = 'Sent (confirmation lost)';
          list.add(b);
        }
      }
    } catch (_) {}
    return chats[peer] = list;
  }

  Future<void> _save(String peer) async {
    final data = utf8.encode(jsonEncode(chats[peer]!.map((b) => b.toJson()).toList()));
    final box = await AesGcm.with256bits().encrypt(data, secretKey: await _key());
    (await SharedPreferences.getInstance()).setString(_pk(peer), base64Encode(box.concatenation()));
  }

  Future<void> forget(String peer) async {
    chats.remove(peer);
    unread.remove(peer);
    (await SharedPreferences.getInstance()).remove(_pk(peer));
    notifyListeners();
  }

  Future<void> _add(String peer, Bubble b) async {
    (await load(peer)).add(b);
    if (openPeer != peer && !b.mine) unread[peer] = (unread[peer] ?? 0) + 1;
    notifyListeners();
    await _save(peer);
  }

  void markRead(String peer) {
    if (unread.remove(peer) != null) notifyListeners();
  }

  // ---------- verification ----------
  Future<String?> _peerKey(String user) async {
    if (_pinned.containsKey(user)) return _pinned[user];
    final r = await http.get(Uri.parse('$base/keys/$user'));
    if (r.statusCode != 200) return null;
    final pub = jsonDecode(r.body)['publicKey'] as String;
    final onChain = await Chain.keyHashOf(user);
    if (onChain != '0x${await CryptoService.sha256Hex(pub)}') return null;
    return _pinned[user] = pub;
  }

  Future<void> _onWs(dynamic raw) async {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    if (m['type'] == 'ack' || m['type'] == 'error') {
      final r = _refs[m['ref']];
      if (r == null) return;
      if (m['type'] == 'ack') {
        r.$2.status = 'Sent, anchored on Sepolia (tx ${short(m['tx'])})';
      } else {
        r.$2.status = 'Failed: ${m['error']}';
        r.$2.ok = false;
      }
      notifyListeners();
      await _save(r.$1);
    } else if (m['type'] == 'msg') {
      await _receive(m);
    }
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    final from = m['from'] as String;
    try {
      final anchored = await Chain.anchorOf(m['id'] as String);
      final want = '0x${await CryptoService.sha256Hex(m['payload'])}';
      if (anchored != want) {
        return _add(from, Bubble('Message hidden',
            'Tampered or not anchored: ciphertext does not match the Sepolia record', false, false));
      }
      final k = await _peerKey(from);
      if (k == null) {
        return _add(from,
            Bubble('Message hidden', 'Sender’s key does not match the Sepolia record', false, false));
      }
      final shared = await CryptoService.sharedKey(keyPair, k);
      final t = await CryptoService.decrypt(m['payload'], shared);
      await _add(from, Bubble(t, 'Verified on Sepolia', true, false));
    } catch (e) {
      await _add(from, Bubble('Message hidden', 'Could not verify: $e', false, false));
    }
  }

  /// Returns an error message, or null if the message was handed to the server.
  Future<String?> send(String peer, String text) async {
    try {
      final k = await _peerKey(peer);
      if (k == null) {
        return '$peer is not registered yet (they may need to unlock their app), or their key does not match the Sepolia record.';
      }
      final shared = await CryptoService.sharedKey(keyPair, k);
      final payload = await CryptoService.encrypt(text, shared);
      final ref = ++_counter;
      final b = Bubble(text, 'Anchoring on Sepolia… (about 15 seconds)', true, true);
      _refs[ref] = (peer, b);
      _ch!.sink.add(jsonEncode({'type': 'send', 'to': peer, 'payload': payload, 'ref': ref}));
      await _add(peer, b);
      return null;
    } catch (e) {
      return 'Could not send: $e';
    }
  }
}