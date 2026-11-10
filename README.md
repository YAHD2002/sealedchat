# SealedChat

End-to-end encrypted messaging where **key fingerprints and message hashes are anchored on the Ethereum Sepolia testnet**, so tampering and fake identities can be detected by the clients themselves.

## How it works

```
Flutter app (Alice) ──WebSocket──> Node.js relay server ──WebSocket──> Flutter app (Bob)
      │                                   │                                  │
      │ encrypt (X25519 + AES-256-GCM)    │ writes hashes                    │ reads hashes
      │                                   ▼                                  │ and verifies
      └──────────────────────────> Ethereum Sepolia  <───────────────────────┘
                                  SealedChatRegistry contract
```

1. Each user creates an X25519 key pair on the device. The server registers `SHA-256(public key)` on-chain under the user's name. A name can only be registered once.
2. To send a message, the app encrypts it with a shared secret (X25519 key exchange, AES-256-GCM). The server only ever sees ciphertext.
3. The server anchors `SHA-256(ciphertext)` on-chain, then relays the message.
4. The receiving app reads the contract **directly from Sepolia** (not from the server). It checks that the ciphertext hash matches the anchored one and that the sender's key matches the registered fingerprint. Only then does it decrypt.

A malicious server cannot overwrite a registered key or silently change a message: the clients would detect the mismatch.

## Contracts (Sepolia)

| Contract | Address | Notes |
| --- | --- | --- |
| SealedChatRegistry | `0xBdb2A76727B96dD9d5fa01Cc75BdCFE9E07A4137` | Used by the app. Only the relayer wallet can write. Keys and anchors are write-once. |
| SecureMessageRegistry | `0x69830446F9aDe0ecAB17761a731E7A0395F4D7dd` | First version (per-wallet). Superseded. |

View on Etherscan: https://sepolia.etherscan.io/address/0xBdb2A76727B96dD9d5fa01Cc75BdCFE9E07A4137

## Project layout

```
contracts/   Solidity contracts
server/      Node.js (Express + ws + ethers) relay server
sealedchat/  Flutter app (Android, iOS, Windows, web)
```

## Run it

You need Node.js, Flutter, and a little Sepolia test ETH for the relayer wallet.

**Server**
```
cd server
npm install
node makeWallet.js        # creates a relayer wallet and saves its key in .env
```
Fund the printed relayer address with Sepolia ETH from a faucet. Then copy `.env.example` values into `.env` (keep `RELAYER_KEY`), and run:
```
npm start
```

**App**
```
cd sealedchat
flutter pub get
flutter run -d chrome     # and flutter run -d windows for the second user
```
Log in with two different names, each naming the other as the chat partner. Names are permanent on-chain, so use a new name for each test.

**Tamper test:** `POST http://localhost:3000/demo/tamper-next`, then send a message. The receiver shows it as tampered.

## Limitations (planned work)

- Keys are created fresh at each app start (no device storage yet), so names cannot be reused.
- No user authentication yet.
- No multi-device support.
- The relayer can withhold messages, and could register a name nobody has taken yet.
- Testnet only. Not audited.

## Screenshots

Add images to `docs/` and they will show here:

![Verified chat](docs/verified-chat.png)
![Tamper detected](docs/tamper-detected.png)
![Contract on Etherscan](docs/etherscan-contract.png)
