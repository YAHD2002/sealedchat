   const { Wallet } = require('ethers');
   const fs = require('fs');
   const w = Wallet.createRandom();
   fs.appendFileSync('.env', `RELAYER_KEY=${w.privateKey}\n`);
   console.log('Relayer address:', w.address);