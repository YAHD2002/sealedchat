import 'package:flutter/material.dart';
import 'chain.dart';
import 'chat_service.dart';

class ChatPage extends StatefulWidget {
  final ChatService svc;
  final String peer;
  const ChatPage({super.key, required this.svc, required this.peer});
  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final input = TextEditingController();
  String notice = '';

  @override
  void initState() {
    super.initState();
    widget.svc.openPeer = widget.peer;
    widget.svc.addListener(_changed);
    widget.svc.load(widget.peer).then((_) {
      widget.svc.markRead(widget.peer);
      _changed();
    });
  }

  @override
  void dispose() {
    widget.svc.openPeer = null;
    widget.svc.removeListener(_changed);
    input.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _send() async {
    final text = input.text.trim();
    if (text.isEmpty) return;
    input.clear();
    final err = await widget.svc.send(widget.peer, text);
    if (mounted) setState(() => notice = err ?? '');
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
    final bubbles = widget.svc.chats[widget.peer] ?? [];
    return Scaffold(
      appBar: AppBar(
        title: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(widget.peer),
          Text(widget.svc.connection, style: const TextStyle(fontSize: 12, color: Colors.white60)),
        ]),
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
          child: ListView(reverse: true, padding: const EdgeInsets.all(12), children: [
            for (final b in bubbles.reversed)
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
                      decoration: InputDecoration(hintText: 'Message to ${widget.peer}'))),
              const SizedBox(width: 8),
              IconButton.filled(onPressed: _send, icon: const Icon(Icons.send)),
            ]),
          ),
        ),
      ]),
    );
  }
}