import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'chain.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'chat_page.dart';
import 'chat_service.dart';
import 'crypto_service.dart';
import 'theme.dart';
import 'vault.dart';

/// First screen: unlock if an account exists on this device, otherwise welcome.
class AppGate extends StatelessWidget {
  const AppGate({super.key});
  @override
  Widget build(BuildContext context) => FutureBuilder<String?>(
        future: Vault.savedName(),
        builder: (_, s) {
          if (s.connectionState != ConnectionState.done) {
            return const Scaffold(body: Center(child: CircularProgressIndicator()));
          }
          return s.data == null ? const WelcomePage() : UnlockPage(name: s.data!);
        },
      );
}

class BrandMark extends StatelessWidget {
  final double size;
  const BrandMark({super.key, this.size = 88});
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
            gradient: kBrandGradient, borderRadius: BorderRadius.circular(size * 0.28)),
        child: Icon(Icons.lock_outline, size: size * 0.5, color: kNavy),
      );
}

Future<void> _registerWithServer(String base, String user, KeyPair kp) async {
  final r = await http.post(Uri.parse('$base/register'),
      headers: {'content-type': 'application/json'},
      body: jsonEncode({'user': user, 'publicKey': await CryptoService.exportPublic(kp)}));
  if (r.statusCode != 200) throw jsonDecode(r.body)['error'];
}

void _openHome(BuildContext context, String base, String me, KeyPair kp) {
  final svc = ChatService(base, me, kp)..start();
  Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomePage(svc: svc)), (_) => false);
}

class WelcomePage extends StatefulWidget {
  const WelcomePage({super.key});
  @override
  State<WelcomePage> createState() => _WelcomePageState();
}

class _WelcomePageState extends State<WelcomePage> {
  final pc = PageController();
  int page = 0;
  static const slides = [
    (Icons.lock_outline, 'Private by design',
        'Messages are encrypted on your device. The server only sees scrambled data.'),
    (Icons.link, 'Anchored on Ethereum',
        'A fingerprint of every key and message is recorded on the Sepolia blockchain.'),
    (Icons.verified_user_outlined, 'Tamper detection',
        'Your app checks each message against the blockchain and warns you if anything changed.'),
  ];

  @override
  Widget build(BuildContext context) => Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(children: [
              const SizedBox(height: 24),
              const BrandMark(),
              const SizedBox(height: 16),
              const Text('SealedChat', style: TextStyle(fontSize: 30, fontWeight: FontWeight.w800)),
              const Text('Private. Secure. End-to-End.', style: TextStyle(color: kCyan)),
              Expanded(
                child: PageView(
                  controller: pc,
                  onPageChanged: (i) => setState(() => page = i),
                  children: [
                    for (final s in slides)
                      Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                        Icon(s.$1, size: 56, color: kCyan),
                        const SizedBox(height: 16),
                        Text(s.$2, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 8),
                        Text(s.$3, textAlign: TextAlign.center),
                      ]),
                  ],
                ),
              ),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                for (var i = 0; i < slides.length; i++)
                  Container(
                      margin: const EdgeInsets.all(4),
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                          shape: BoxShape.circle, color: i == page ? kCyan : Colors.white24)),
              ]),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => page < slides.length - 1
                    ? pc.nextPage(duration: const Duration(milliseconds: 250), curve: Curves.easeOut)
                    : Navigator.of(context).push(
                        MaterialPageRoute(builder: (_) => const CreateAccountPage())),
                child: Text(page < slides.length - 1 ? 'Next' : 'Get started'),
              ),
            ]),
          ),
        ),
      );
}

class CreateAccountPage extends StatefulWidget {
  const CreateAccountPage({super.key});
  @override
  State<CreateAccountPage> createState() => _CreateAccountPageState();
}

class _CreateAccountPageState extends State<CreateAccountPage> {
  final server = TextEditingController(text: 'http://localhost:3000');
  final name = TextEditingController();
  final pin1 = TextEditingController();
  final pin2 = TextEditingController();
  String error = '';
  bool busy = false;

  Future<void> _create() async {
    final user = name.text.trim(), pin = pin1.text;
    String? bad;
    if (!RegExp(r'^[A-Za-z0-9_]{2,20}$').hasMatch(user)) {
      bad = 'Use 2-20 letters, digits or underscores for the username.';
    } else if (!RegExp(r'^\d{6}$').hasMatch(pin)) {
      bad = 'The PIN must be exactly 6 digits.';
    } else if (pin != pin2.text) {
      bad = 'The two PINs do not match.';
    }
    if (bad != null) return setState(() => error = bad!);
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final base = server.text.trim();
      final kp = await CryptoService.newKeyPair();
      await _registerWithServer(base, user, kp); // about 15 seconds: written to Sepolia
      await Vault.create(name: user, pin: pin, kp: kp, server: base);
      if (mounted) _openHome(context, base, user, kp);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Create your account')),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: [
              TextField(controller: server, decoration: const InputDecoration(labelText: 'Server address')),
              const SizedBox(height: 12),
              TextField(controller: name, decoration: const InputDecoration(labelText: 'Username')),
              const SizedBox(height: 12),
              TextField(
                  controller: pin1,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: '6-digit PIN')),
              const SizedBox(height: 12),
              TextField(
                  controller: pin2,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Repeat PIN')),
              const SizedBox(height: 16),
              FilledButton(
                  onPressed: busy ? null : _create,
                  child: Text(busy ? 'Registering on Sepolia (about 15 seconds)…' : 'Create account')),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text('Your PIN encrypts your private key on this device. If you forget it, the account cannot be recovered.',
                      style: TextStyle(color: Colors.white60, fontSize: 12))),
            ]),
          ),
        ),
      );
}

class UnlockPage extends StatefulWidget {
  final String name;
  const UnlockPage({super.key, required this.name});
  @override
  State<UnlockPage> createState() => _UnlockPageState();
}

class _UnlockPageState extends State<UnlockPage> {
  final pin = TextEditingController();
  String error = '';
  bool busy = false;

  Future<void> _unlock() async {
    setState(() {
      busy = true;
      error = '';
    });
    try {
      final kp = await Vault.unlock(pin.text);
      if (kp == null) throw 'Wrong PIN.';
      final base = await Vault.savedServer();
      await _registerWithServer(base, widget.name, kp); // quick for a returning user
      if (mounted) _openHome(context, base, widget.name, kp);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _forget() async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
              title: const Text('Forget this account?'),
              content: const Text('The saved keys are deleted from this device and cannot be recovered. The username stays taken on Sepolia.'),
              actions: [
                TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Forget')),
              ],
            ));
    if (ok == true) {
      await Vault.wipe();
      if (mounted) {
        Navigator.of(context).pushReplacement(MaterialPageRoute(builder: (_) => const WelcomePage()));
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(24), children: [
              const Center(child: BrandMark(size: 72)),
              const SizedBox(height: 16),
              Center(child: Text('Welcome back, ${widget.name}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))),
              const SizedBox(height: 24),
              TextField(
                  controller: pin,
                  obscureText: true,
                  keyboardType: TextInputType.number,
                  onSubmitted: (_) => _unlock(),
                  decoration: const InputDecoration(labelText: 'PIN')),
              const SizedBox(height: 16),
              FilledButton(onPressed: busy ? null : _unlock, child: const Text('Unlock')),
              if (error.isNotEmpty)
                Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              TextButton(onPressed: busy ? null : _forget, child: const Text('Forget this account')),
            ]),
          ),
        ),
      );
}

/// WhatsApp-style home screen: contacts sorted by last message, with unread counts.
class HomePage extends StatefulWidget {
  final ChatService svc;
  const HomePage({super.key, required this.svc});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  List<String> contacts = [];
  ChatService get svc => widget.svc;

  @override
  void initState() {
    super.initState();
    svc.addListener(_changed);
    _load();
  }

  @override
  void dispose() {
    svc.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    for (final k in svc.chats.keys) { // a new sender becomes a contact
      if (!contacts.contains(k)) {
        contacts.add(k);
        _save();
      }
    }
    if (mounted) setState(() {});
  }

  Future<void> _load() async {
    final list = (await SharedPreferences.getInstance()).getStringList('contacts') ?? [];
    for (final c in list) {
      await svc.load(c);
    }
    if (mounted) setState(() => contacts = list);
  }

  Future<void> _save() async =>
      (await SharedPreferences.getInstance()).setStringList('contacts', contacts);

  int _last(String c) {
    final l = svc.chats[c];
    return l == null || l.isEmpty ? 0 : l.last.ts;
  }

  Future<void> _add() async {
    final name = TextEditingController();
    String error = '';
    bool busy = false;
    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: const Text('Add contact'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            TextField(
                controller: name,
                autofocus: true,
                decoration: const InputDecoration(labelText: 'Username')),
            if (error.isNotEmpty)
              Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(error, style: TextStyle(color: Theme.of(ctx).colorScheme.error))),
          ]),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: busy
                  ? null
                  : () async {
                      final u = name.text.trim();
                      if (u.isEmpty) return;
                      if (u == svc.me) {
                        setD(() => error = 'That is you.');
                        return;
                      }
                      if (contacts.contains(u)) {
                        setD(() => error = 'Already in your contacts.');
                        return;
                      }
                      setD(() {
                        busy = true;
                        error = '';
                      });
                      try {
                        final h = await Chain.keyHashOf(u);
                        if (h == '0x${'0' * 64}') {
                          setD(() {
                            busy = false;
                            error = '$u is not registered on Sepolia.';
                          });
                          return;
                        }
                        setState(() => contacts.add(u));
                        await _save();
                        if (ctx.mounted) Navigator.pop(ctx);
                      } catch (e) {
                        setD(() {
                          busy = false;
                          error = 'Could not check Sepolia: $e';
                        });
                      }
                    },
              child: Text(busy ? 'Checking Sepolia…' : 'Add'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sorted = [...contacts]..sort((a, b) => _last(b).compareTo(_last(a)));
    return Scaffold(
      appBar: AppBar(
        title: Row(children: [
          const BrandMark(size: 30),
          const SizedBox(width: 10),
          Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('SealedChat'),
            Text('${svc.me} · ${svc.connection}',
                style: const TextStyle(fontSize: 12, color: Colors.white60)),
          ]),
        ]),
        actions: [
          IconButton(
              icon: const Icon(Icons.lock_outline),
              tooltip: 'Lock',
              onPressed: () {
                final me = svc.me;
                svc.dispose();
                Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => UnlockPage(name: me)), (_) => false);
              }),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.person_add_alt_1),
          label: const Text('Add contact')),
      body: sorted.isEmpty
          ? const Center(
              child: Padding(
                  padding: EdgeInsets.all(32),
                  child: Text(
                      'No contacts yet.\nTap Add contact and enter a username registered on Sepolia.',
                      textAlign: TextAlign.center)))
          : ListView(children: [
              for (final c in sorted)
                Dismissible(
                  key: ValueKey(c),
                  direction: DismissDirection.endToStart,
                  background: Container(
                      color: cs.errorContainer,
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 20),
                      child: const Icon(Icons.delete_outline)),
                  onDismissed: (_) {
                    setState(() => contacts.remove(c));
                    _save();
                    svc.forget(c); // also deletes the saved history
                  },
                  child: ListTile(
                    leading: CircleAvatar(
                        backgroundColor: kPurple,
                        foregroundColor: Colors.white,
                        child: Text(c[0].toUpperCase())),
                    title: Text(c),
                    subtitle: Text(
                        (svc.chats[c]?.isNotEmpty ?? false)
                            ? '${svc.chats[c]!.last.mine ? 'You: ' : ''}${svc.chats[c]!.last.text}'
                            : 'Encrypted · verified on Sepolia',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                    trailing: (svc.unread[c] ?? 0) > 0 ? Badge(label: Text('${svc.unread[c]}')) : null,
                    onTap: () => Navigator.of(context)
                        .push(MaterialPageRoute(builder: (_) => ChatPage(svc: svc, peer: c))),
                  ),
                ),
            ]),
    );
  }
}