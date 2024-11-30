module free_tunnel_sui::utils {

    use sui::hash;
    use sui::bag;
    use sui::pay;
    use sui::ecdsa_k1;
    use sui::coin::{Self, Coin};

    const ETOSTRING_VALUE_TOO_LARGE: u64 = 100;
    const ELOG10_VALUE_TOO_LARGE: u64 = 101;
    const EINVALID_PUBLIC_KEY: u64 = 102;
    const EINVALID_ETH_ADDRESS: u64 = 103;


    public fun smallU64ToString(value: u64): vector<u8> {
        let mut buffer = vector::empty<u8>();
        assert!(value < 10000000000, ETOSTRING_VALUE_TOO_LARGE);
        if (value >= 1000000000) {
            let byte = (value / 1000000000) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 100000000) {
            let byte = ((value / 100000000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 10000000) {
            let byte = ((value / 10000000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 1000000) {
            let byte = ((value / 1000000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 100000) {
            let byte = ((value / 100000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 10000) {
            let byte = ((value / 10000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 1000) {
            let byte = ((value / 1000) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 100) {
            let byte = ((value / 100) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        if (value >= 10) {
            let byte = ((value / 10) % 10) as u8 + 48;
            vector::push_back(&mut buffer, byte);
        };
        let byte = (value % 10) as u8 + 48;
        vector::push_back(&mut buffer, byte);
        buffer
    }

    public fun smallU64Log10(mut value: u64): u64 {
        assert!(value < 10000, ELOG10_VALUE_TOO_LARGE);
        let mut result = 0;
        value = value / 10;
        while (value != 0) {
            value = value / 10;
            result = result + 1;
        };
        result  // Returns 0 if given 0. Same as Solidity
    }

    public fun ethAddressFromPubkey(pk: vector<u8>): vector<u8> {
        // Public key `pk` should be uncompressed. Note that ETH pubkey has an extra 0x04 prefix (uncompressed)
        assert!(vector::length(&pk) == 64, EINVALID_PUBLIC_KEY);
        let hashValue = hash::keccak256(&pk);
        let mut ethAddr = vector::empty<u8>();
        let mut i = 12;
        while (i < 32) {
            vector::push_back(&mut ethAddr, hashValue[i]);
            i = i + 1;
        };
        ethAddr
    }

    public fun recoverEthAddress(msg: vector<u8>, r: vector<u8>, yParityAndS: vector<u8>): vector<u8> {
        let mut s = yParityAndS;
        let v = yParityAndS[0] >> 7;
        *vector::borrow_mut(&mut s, 0) = s[0] & 0x7f;

        let signature65 = vector::flatten(vector[r, s, vector::singleton(v)]);
        let compressedPk = ecdsa_k1::secp256k1_ecrecover(&signature65, &msg, 0);
        let mut pk = ecdsa_k1::decompress_pubkey(&compressedPk);
        vector::remove(&mut pk, 0);     // drop '04' prefix
        ethAddressFromPubkey(pk)
    }

    fun assertEthAddress(addr: vector<u8>) {
        assert!(addr.length() == 20, EINVALID_ETH_ADDRESS);
    }

    public fun assertEthAddressList(addrs: vector<vector<u8>>) {
        let mut i = 0;
        while (i < addrs.length()) {
            assertEthAddress(addrs[i]);
            i = i + 1;
        };
    }

    public(package) fun BRIDGE_CHANNEL(): vector<u8> {
        b"BounceBit Token Bridge"
    }

    #[allow(lint(self_transfer))]
    public(package) fun joinCoins<CoinType>(
        coinList: vector<Coin<CoinType>>,
        amount: u64,
        coinsBag: &mut bag::Bag,
        tokenIndex: u8,
        ctx: &mut TxContext,
    ) {
        let mut mergedCoins = coin::zero<CoinType>(ctx);
        pay::join_vec(&mut mergedCoins, coinList);
        let coinsToStore = coin::split(&mut mergedCoins, amount, ctx);
        transfer::public_transfer(mergedCoins, ctx.sender());   // refund

        if (coinsBag.contains(tokenIndex)) {
            let currentCoins = coinsBag.borrow_mut(tokenIndex);
            coin::join(currentCoins, coinsToStore);
        } else {
            coinsBag.add(tokenIndex, coinsToStore);
        };
    }

    #[test]
    fun testSmallU64ToString() {
        assert!(smallU64ToString(0) == b"0");
        assert!(smallU64ToString(1) == b"1");
        assert!(smallU64ToString(9) == b"9");
        assert!(smallU64ToString(10) == b"10");
        assert!(smallU64ToString(11) == b"11");
        assert!(smallU64ToString(60) == b"60");
        assert!(smallU64ToString(99) == b"99");
        assert!(smallU64ToString(100) == b"100");
        assert!(smallU64ToString(104) == b"104");
        assert!(smallU64ToString(110) == b"110");
        assert!(smallU64ToString(500) == b"500");
        assert!(smallU64ToString(919) == b"919");
        assert!(smallU64ToString(999) == b"999");
        assert!(smallU64ToString(1000) == b"1000");
        assert!(smallU64ToString(1001) == b"1001");
        assert!(smallU64ToString(3417) == b"3417");
        assert!(smallU64ToString(9283) == b"9283");
        assert!(smallU64ToString(9999) == b"9999");
        assert!(smallU64ToString(10000) == b"10000");
        assert!(smallU64ToString(10001) == b"10001");
        assert!(smallU64ToString(99999) == b"99999");
        assert!(smallU64ToString(100000) == b"100000");
        assert!(smallU64ToString(100001) == b"100001");
        assert!(smallU64ToString(999999) == b"999999");
        assert!(smallU64ToString(1000000) == b"1000000");
        assert!(smallU64ToString(9999999) == b"9999999");
        assert!(smallU64ToString(10000000) == b"10000000");
        assert!(smallU64ToString(99999999) == b"99999999");
        assert!(smallU64ToString(100000000) == b"100000000");
        assert!(smallU64ToString(999999999) == b"999999999");
        assert!(smallU64ToString(1000000000) == b"1000000000");
        assert!(smallU64ToString(1732709334) == b"1732709334");     // Timestamp of `2024-11-27 12:08:54`
        assert!(smallU64ToString(9999999999) == b"9999999999");
    }

    #[test]
    #[expected_failure(abort_code = ETOSTRING_VALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLargeFailure1() {
        smallU64ToString(10000000000);
    }

    #[test]
    #[expected_failure(abort_code = ETOSTRING_VALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLargeFailure2() {
        smallU64ToString(12000000000);
    }

    #[test]
    fun testSmallU64Log10() {
        assert!(smallU64Log10(0) == 0);
        assert!(smallU64Log10(1) == 0);
        assert!(smallU64Log10(3) == 0);
        assert!(smallU64Log10(9) == 0);
        assert!(smallU64Log10(10) == 1);
        assert!(smallU64Log10(35) == 1);
        assert!(smallU64Log10(100) == 2);
        assert!(smallU64Log10(1000) == 3);
        assert!(smallU64Log10(3162) == 3);
        assert!(smallU64Log10(9999) == 3);
    }

    #[test]
    #[expected_failure(abort_code = ELOG10_VALUE_TOO_LARGE)]
    fun testSmallU64Log10TooLargeFailure1() {
        smallU64Log10(10000);
    }

    #[test]
    #[expected_failure(abort_code = ELOG10_VALUE_TOO_LARGE)]
    fun testSmallU64Log10TooLargeFailure2() {
        smallU64Log10(12000);
    }

    #[test]
    fun testEthAddressFromPubkey() {
        let pk = x"5139c6f948e38d3ffa36df836016aea08f37a940a91323f2a785d17be4353e382b488d0c543c505ec40046afbb2543ba6bb56ca4e26dc6abee13e9add6b7e189";
        let ethAddr = ethAddressFromPubkey(pk);
        assert!(ethAddr == x"052c7707093534035fc2ed60de35e11bebb6486b", 1);
    }

    #[test]
    fun testRecoverEthAddress() {
        let message = b"stupid";
        let r = x"6fd862958c41d532022e404a809e92ec699bd0739f8d782ca752b07ff978f341";
        let yParityAndS = x"f43065a96dc53a21b4eb4ce96a84a7c4103e3485b0c87d868df545fcce0f3983";
        let ethAddr = recoverEthAddress(message, r, yParityAndS);
        assert!(ethAddr == x"2eF8a51F8fF129DBb874A0efB021702F59C1b211", 1);
    }

    #[test]
    fun testAssertEthAddressList() {
        let addrs = vector[
            x"052c7707093534035fc2ed60de35e11bebb6486b",
            x"052c7707093534035fc2ed60de35e11bebb6486b",
            x"052c7707093534035fc2ed60de35e11bebb6486b",
        ];
        assertEthAddressList(addrs);
    }

    #[test]
    #[expected_failure(abort_code = EINVALID_ETH_ADDRESS)]
    fun testAssertEthAddressListFailure() {
        let addrs = vector[
            x"052c7707093534035fc2ed60de35e11bebb648",
        ];
        assertEthAddressList(addrs);
    }
}