import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';
import 'chain.dart';
import 'chat_service.dart';
import 'theme.dart';

const _scan = 'https://sepolia.etherscan.io';
Future<void> _open(String url) => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);

class SecurityPage extends StatefulWidget {
  final ChatService svc;
  final String peer;
  const SecurityPage({super.key, required this.svc, required this.peer});
  @override
  State<SecurityPage> createState() => _SecurityPageState();
}

class _SecurityPageState extends State<SecurityPage> {
  KeyCheck? check;
  String err = '';

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() {
      check = null;
      err = '';
    });
    try {
      final c = await widget.svc.checkKey(widget.peer);
      if (mounted) setState(() => check = c);
    } catch (e) {
      if (mounted) setState(() => err = 'Could not reach Sepolia or the server: $e');
    }
  }

  Widget _card(String title, List<Widget> kids) => Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              const SizedBox(height: 8),
              ...kids,
            ])),
      );

  Widget _mono(String s) =>
      SelectableText(s, style: const TextStyle(fontFamily: 'monospace', fontSize: 12));

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final c = check;
    final msgs = widget.svc.chats[widget.peer] ?? [];
    final received = msgs.where((b) => !b.mine).toList();
    final verified = received.where((b) => b.ok).length;
    final bad = received.length - verified;
    return Scaffold(
      appBar: AppBar(title: Text('Security · ${widget.peer}'), actions: [
        IconButton(icon: const Icon(Icons.refresh), tooltip: 'Check again', onPressed: _run),
      ]),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        if (err.isNotEmpty) Text(err, style: TextStyle(color: cs.error)),
        if (c == null && err.isEmpty) const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator())),
        if (c != null) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
                color: c.match ? cs.primaryContainer : cs.errorContainer,
                borderRadius: BorderRadius.circular(14)),
            child: Row(children: [
              Icon(c.match ? Icons.verified_user : Icons.gpp_bad, size: 32, color: c.match ? kCyan : cs.error),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(
                      c.match
                          ? 'Identity verified. The key the server gives for ${widget.peer} matches the one registered on Sepolia.'
                          : c.problem.isNotEmpty
                              ? c.problem
                              : 'KEY MISMATCH. The server is giving a different key than the one registered on Sepolia. Do not trust this contact until it is resolved.',
                      style: const TextStyle(fontWeight: FontWeight.w600))),
            ]),
          ),
          const SizedBox(height: 12),
          _card('Key fingerprint', [
            const Text('Registered on Sepolia', style: TextStyle(color: Colors.white60, fontSize: 12)),
            _mono(c.onChain),
            const SizedBox(height: 8),
            const Text('Held by the server', style: TextStyle(color: Colors.white60, fontSize: 12)),
            _mono(c.serverHash.isEmpty ? '(no key)' : c.serverHash),
          ]),
          if (c.safety.isNotEmpty)
            _card('Safety number', [
              Text(c.safety, style: const TextStyle(fontFamily: 'monospace', fontSize: 20, fontWeight: FontWeight.w700, color: kCyan)),
              const SizedBox(height: 8),
              const Text('Both of you should see exactly the same number. Compare it in person or on a call. It protects against a server that lies about keys when an account is first created.',
                  style: TextStyle(color: Colors.white70, fontSize: 12)),
            ]),
        ],
        _card('Messages', [
          Text('${received.length} received · $verified verified${bad > 0 ? ' · $bad failed verification' : ''}'),
          const SizedBox(height: 4),
          if (msgs.isEmpty) const Text('No messages yet.', style: TextStyle(color: Colors.white60)),
          for (final b in msgs.reversed.take(20))
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(b.ok ? Icons.verified_outlined : Icons.warning_amber_rounded,
                  color: b.ok ? kCyan : cs.error),
              title: Text(b.mine ? 'You: ${b.text}' : b.text, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: Text(b.status),
              trailing: b.tx == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.open_in_new, size: 18),
                      tooltip: 'View transaction on Etherscan',
                      onPressed: () => _open('$_scan/tx/${b.tx}')),
            ),
        ]),
        _card('Registry contract', [
          const Text('Ethereum Sepolia testnet', style: TextStyle(color: Colors.white60, fontSize: 12)),
          _mono(kContract),
          const SizedBox(height: 8),
          OutlinedButton.icon(
              onPressed: () => _open('$_scan/address/$kContract'),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Open on Etherscan')),
        ]),
      ]),
    );
  }
}