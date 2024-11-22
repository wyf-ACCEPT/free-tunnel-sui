const { Keypair } = require("@mysten/sui/cryptography");

const keypair = Ed25519Keypair.deriveKeypair(TEST_MNEMONIC, `m/44'/784'/0'/0'/0'`);
const address = keypair.getPublicKey().toSuiAddress();
console.log(address);