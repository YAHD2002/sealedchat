import 'dart:convert';
import 'package:http/http.dart' as http;
import 'crypto_service.dart';

const kRpc = 'https://ethereum-sepolia-rpc.publicnode.com';
const kContract = '0xBdb2A76727B96dD9d5fa01Cc75BdCFE9E07A4137';

// First 4 bytes of keccak256("keyOf(bytes32)") and keccak256("anchors(uint256)").
const _selKeyOf = 'df78bce2';
const _selAnchors = '368b733e';

class Chain {
  static Future<String> _call(String data) async {
    final r = await http.post(Uri.parse(kRpc),
        headers: {'content-type': 'application/json'},
        body: jsonEncode({
          'jsonrpc': '2.0',
          'id': 1,
          'method': 'eth_call',
          'params': [{'to': kContract, 'data': data}, 'latest']
        }));
    final j = jsonDecode(r.body);
    if (j['error'] != null) throw j['error']['message'];
    return (j['result'] as String).toLowerCase();
  }

  /// Key fingerprint registered for a username ('0x000…' if none).
  static Future<String> keyHashOf(String user) async =>
      _call('0x$_selKeyOf${await CryptoService.sha256Hex(user)}');

  /// Ciphertext hash anchored for a message id ('0x000…' if none).
  static Future<String> anchorOf(String id) =>
      _call('0x$_selAnchors${BigInt.parse(id).toRadixString(16).padLeft(64, '0')}');
}