import 'dart:convert';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:web_socket_channel/web_socket_channel.dart';
import 'chain.dart';
import 'crypto_service.dart';

class Bubble {
  final String text;
  String status;
  bool ok;
  final bool mine;
  Bubble(this.text, this.status, this.ok, this.mine);
}

String short(String t) => t.length > 12 ? '${t.substring(0, 10)}…' : t;

class ChatPage extends StatefulWidget {
  final String base, me, peer;
  final KeyPair keyPair;
  const ChatPage(
      {super.key, required this.base, required this.me, required this.peer, required this.keyPair});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  late final WebSocketChannel ch;
  final input = TextEditingController();
  final bubbles = <Bubble>[];
  final refs = <int, Bubble>{};
  final pinned = <String, String>{};
  String notice = '';
  int counter = 0;

  @override
  void initState() {
    super.initState();
    final u = Uri.parse(widget.base);
    ch = WebSocketChannel.connect(u.replace(
        scheme: u.scheme == 'https' ? 'wss' : 'ws',
        path: '/ws',
        queryParameters: {'user': widget.me}));
    ch.stream.listen(_onWs, onDone: () {
      if (mounted) setState(() => notice = 'Disconnected from server.');
    });
  }

  @override
  void dispose() {
    ch.sink.close();
    super.dispose();
  }

  /// Fetches a user's key and trusts it only if its hash matches the Sepolia record.
  Future<String?> _peerKey(String user) async {
    if (pinned.containsKey(user)) return pinned[user];
    final r = await http.get(Uri.parse('${widget.base}/keys/$user'));
    if (r.statusCode != 200) return null;
    final pub = jsonDecode(r.body)['publicKey'] as String;
    final onChain = await Chain.keyHashOf(user);
    if (onChain != '0x${await CryptoService.sha256Hex(pub)}') return null;
    return pinned[user] = pub;
  }

  void _add(Bubble b) {
    if (mounted) setState(() => bubbles.add(b));
  }

  Future<void> _onWs(dynamic raw) async {
    final m = jsonDecode(raw as String) as Map<String, dynamic>;
    if (m['type'] == 'ack') {
      final b = refs[m['ref']];
      if (b != null && mounted) {
        setState(() => b.status = 'Sent, anchored on Sepolia (tx ${short(m['tx'])})');
      }
    } else if (m['type'] == 'error') {
      final b = refs[m['ref']];
      if (b != null && mounted) {
        setState(() {
          b.status = 'Failed: ${m['error']}';
          b.ok = false;
        });
      }
    } else if (m['type'] == 'msg') {
      await _receive(m);
    }
  }

  Future<void> _receive(Map<String, dynamic> m) async {
    try {
      final anchored = await Chain.anchorOf(m['id'] as String);
      final want = '0x${await CryptoService.sha256Hex(m['payload'])}';
      if (anchored != want) {
        _add(Bubble('Message hidden',
            'Tampered or not anchored: ciphertext does not match the Sepolia record', false, false));
        return;
      }
      final k = await _peerKey(m['from']);
      if (k == null) {
        _add(Bubble('Message hidden', 'Sender’s key does not match the Sepolia record', false, false));
        return;
      }
      final shared = await CryptoService.sharedKey(widget.keyPair, k);
      final t = await CryptoService.decrypt(m['payload'], shared);
      _add(Bubble(t, 'From ${m['from']}, verified on Sepolia', true, false));
    } catch (e) {
      _add(Bubble('Message hidden', 'Could not verify: $e', false, false));
    }
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    try {
      final k = await _peerKey(widget.peer);
      if (k == null) {
        setState(() => notice =
            'Cannot send: ${widget.peer} is not registered yet, or their key does not match the Sepolia record.');
        return;
      }
      final shared = await CryptoService.sharedKey(widget.keyPair, k);
      final payload = await CryptoService.encrypt(text, shared);
      final ref = ++counter, b = Bubble(text, 'Anchoring on Sepolia… (about 15 seconds)', true, true);
      refs[ref] = b;
      ch.sink.add(jsonEncode({'type': 'send', 'to': widget.peer, 'payload': payload, 'ref': ref}));
      input.clear();
      setState(() {
        notice = '';
        bubbles.add(b);
      });
    } catch (e) {
      setState(() => notice = 'Could not send: $e');
    }
  }

  void _info() => showDialog(
      context: context,
      builder: (_) => AlertDialog(
            title: const Text('On-chain registry'),
            content: const SelectableText(
                'Network: Ethereum Sepolia\nContract: $kContract\nhttps://sepolia.etherscan.io/address/$kContract'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close'))],
          ));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text('${widget.me} chatting with ${widget.peer}'),
        actions: [IconButton(icon: const Icon(Icons.info_outline), tooltip: 'Registry', onPressed: _info)],
      ),
      body: Column(children: [
        if (notice.isNotEmpty)
          Container(
              width: double.infinity,
              color: cs.errorContainer,
              padding: const EdgeInsets.all(10),
              child: Text(notice, style: TextStyle(color: cs.onErrorContainer))),
        Expanded(
          child: ListView(padding: const EdgeInsets.all(12), children: [
            for (final b in bubbles)
              Align(
                alignment: b.mine ? Alignment.centerRight : Alignment.centerLeft,
                child: Container(
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.all(10),
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.8),
                  decoration: BoxDecoration(
                      color: b.ok
                          ? (b.mine ? cs.primaryContainer : cs.surfaceContainerHighest)
                          : cs.errorContainer,
                      borderRadius: BorderRadius.circular(12)),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(b.text),
                    const SizedBox(height: 2),
                    Text(b.status,
                        style: TextStyle(fontSize: 12, color: b.ok ? cs.primary : cs.error)),
                  ]),
                ),
              ),
          ]),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
            child: Row(children: [
              Expanded(
                  child: TextField(
                      controller: input,
                      onSubmitted: (_) => _send(),
                      decoration: InputDecoration(
                          hintText: 'Message to ${widget.peer}',
                          border: const OutlineInputBorder()))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}