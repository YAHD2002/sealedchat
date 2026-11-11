require('dotenv').config();
const express = require('express');
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const { JsonRpcProvider, Wallet, Contract, ZeroHash, formatEther } = require('ethers');

const { RELAYER_KEY, SEPOLIA_RPC, CONTRACT } = process.env;
if (!RELAYER_KEY || !SEPOLIA_RPC || !CONTRACT) {
  console.error('Missing RELAYER_KEY, SEPOLIA_RPC or CONTRACT in .env');
  process.exit(1);
}
const provider = new JsonRpcProvider(SEPOLIA_RPC, 11155111, { staticNetwork: true });
const wallet = new Wallet(RELAYER_KEY, provider);
const registry = new Contract(CONTRACT, [
  'function registerKey(bytes32 userId, bytes32 h)',
  'function anchorMessage(uint256 id, bytes32 fromId, bytes32 toId, bytes32 h)',
  'function keyOf(bytes32) view returns (bytes32)'
], wallet);

const sha = s => crypto.createHash('sha256').update(s).digest('hex');
const b32 = s => '0x' + sha(s); // bytes32 = SHA-256 of the text

// One transaction at a time, so nonces never clash.
let chainQueue = Promise.resolve();
function onChain(fn) {
  const run = chainQueue.then(fn);
  chainQueue = run.catch(() => {});
  return run;
}
const errText = e => e.shortMessage || e.message;

const app = express();
app.use(express.json());
app.use((req, res, next) => {
  res.set('Access-Control-Allow-Origin', '*');
  res.set('Access-Control-Allow-Headers', 'content-type');
  if (req.method === 'OPTIONS') return res.sendStatus(204);
  next();
});

const users = {};     // name -> { publicKey, ready }
const messages = {};  // id -> message
const queue = {};     // name -> [ids] waiting for delivery
const online = {};    // name -> websocket
let tamperNext = false;

app.post('/register', async (req, res) => {
  const { user, publicKey } = req.body || {};
  if (!/^[A-Za-z0-9_]{2,20}$/.test(user || '') || !publicKey)
    return res.status(400).json({ error: 'Use a name of 2-20 letters, digits or underscores.' });

  const cur = users[user];
  if (cur) { // same person coming back during this server session
    if (cur.ready && cur.publicKey === publicKey) return res.json({ tx: null, returning: true });
    return res.status(409).json({ error: 'That name is taken.' });
  }
  users[user] = { publicKey, ready: false }; // reserve while checking the chain
  try {
    const existing = await registry.keyOf(b32(user));
    if (existing !== ZeroHash) {
      // Already on Sepolia: accept only if it is the SAME key (a returning user).
      if (existing.toLowerCase() === b32(publicKey).toLowerCase()) {
        users[user].ready = true;
        return res.json({ tx: null, returning: true });
      }
      throw new Error('That name is already registered to a different key. Use another name.');
    }
    const tx = await onChain(async () => {
      const t = await registry.registerKey(b32(user), b32(publicKey));
      await t.wait();
      return t.hash;
    });
    users[user].ready = true;
    res.json({ tx });
  } catch (e) {
    delete users[user];
    console.error('register failed:', errText(e));
    res.status(409).json({ error: errText(e) });
  }
});

let fakeKeyFor = null; // demo only
const fakeKey = () => crypto.generateKeyPairSync('x25519').publicKey
  .export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');

app.get('/keys/:user', (req, res) => {
  const u = users[req.params.user];
  if (!(u && u.ready)) return res.status(404).json({ error: 'Unknown user.' });
  res.json({ publicKey: fakeKeyFor === req.params.user ? fakeKey() : u.publicKey });
});

// Demo only: the next relayed message is altered AFTER its hash is anchored on-chain.
app.post('/demo/tamper-next', (_, res) => { tamperNext = true; res.json({ armed: true }); });

// Demo only: make the server lie about one user's key.
app.post('/demo/fake-key/:user', (req, res) => { fakeKeyFor = req.params.user; res.json({ armed: fakeKeyFor }); });
app.post('/demo/fake-key-off', (_, res) => { fakeKeyFor = null; res.json({ armed: null }); });

const server = http.createServer(app);
const wss = new WebSocketServer({ server, path: '/ws' });

wss.on('connection', (ws, req) => {
  const user = new URL(req.url, 'http://x').searchParams.get('user');
  if (!users[user] || !users[user].ready) return ws.close(4001, 'unknown user');
  online[user] = ws;
  (queue[user] || []).splice(0).forEach(id => ws.send(JSON.stringify({ type: 'msg', ...messages[id] })));

  ws.on('message', async raw => {
    let m;
    try { m = JSON.parse(raw); } catch { return; }
    if (m.type !== 'send' || typeof m.payload !== 'string') return;
    if (!users[m.to] || !users[m.to].ready)
      return ws.send(JSON.stringify({ type: 'error', ref: m.ref, error: 'Recipient is not registered.' }));
    const id = BigInt('0x' + crypto.randomBytes(8).toString('hex')).toString();
    try {
      const tx = await onChain(async () => {
        const t = await registry.anchorMessage(id, b32(user), b32(m.to), b32(m.payload));
        await t.wait();
        return t.hash;
      });
      let payload = m.payload;
      if (tamperNext) { // simulate a malicious server
        const i = payload.length - 3;
        payload = payload.slice(0, i) + (payload[i] === 'A' ? 'B' : 'A') + payload.slice(i + 1);
        tamperNext = false;
      }
      messages[id] = { id, from: user, to: m.to, payload, tx };
      ws.send(JSON.stringify({ type: 'ack', ref: m.ref, id, tx }));
      const t = online[m.to];
      if (t && t.readyState === 1) t.send(JSON.stringify({ type: 'msg', ...messages[id] }));
      else (queue[m.to] = queue[m.to] || []).push(id);
    } catch (e) {
      console.error('anchor failed:', errText(e));
      ws.send(JSON.stringify({ type: 'error', ref: m.ref, error: errText(e) }));
    }
  });
  ws.on('close', () => { if (online[user] === ws) delete online[user]; });
});

const port = process.env.PORT || 3000;
server.listen(port, async () => {
  console.log('SealedChat server on port ' + port);
  console.log('Relayer', wallet.address, 'balance', formatEther(await provider.getBalance(wallet.address)), 'ETH');
});