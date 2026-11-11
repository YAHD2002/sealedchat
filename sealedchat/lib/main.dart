import 'package:flutter/material.dart';
import 'screens.dart';
import 'theme.dart';

void main() => runApp(const SealedChatApp());

class SealedChatApp extends StatelessWidget {
  const SealedChatApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'SealedChat',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const AppGate(),
      );
}