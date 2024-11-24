module free_tunnel_sui::utils {

    use sui::hash;
    use sui::ecdsa_k1;

    const ETOSTRING_VALUE_TOO_LARGE: u64 = 100;
    const ELOG10_VALUE_TOO_LARGE: u64 = 101;
    const EINVALID_PUBLIC_KEY: u64 = 102;

    public fun smallU64ToString(value: u64): vector<u8> {
        let mut buffer = vector::empty<u8>();
        assert!(value < 10000, ETOSTRING_VALUE_TOO_LARGE);
        if (value >= 1000) {
            let byte = (value / 1000) as u8 + 48;
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
        while (value != 0) {
            value = value / 10;
            result = result + 1;
        };
        result  // Returns 0 if given 0. Same as Solidity
    }

    #[test]
    fun testSmallU64ToString() {
        assert!(smallU64ToString(0) == b"0");
        assert!(smallU64ToString(1) == b"1");
        assert!(smallU64ToString(2) == b"2");
        assert!(smallU64ToString(9) == b"9");
        assert!(smallU64ToString(10) == b"10");
        assert!(smallU64ToString(11) == b"11");
        assert!(smallU64ToString(45) == b"45");
        assert!(smallU64ToString(60) == b"60");
        assert!(smallU64ToString(99) == b"99");
        assert!(smallU64ToString(100) == b"100");
        assert!(smallU64ToString(104) == b"104");
        assert!(smallU64ToString(110) == b"110");
        assert!(smallU64ToString(111) == b"111");
        assert!(smallU64ToString(199) == b"199");
        assert!(smallU64ToString(202) == b"202");
        assert!(smallU64ToString(500) == b"500");
        assert!(smallU64ToString(919) == b"919");
        assert!(smallU64ToString(999) == b"999");
        assert!(smallU64ToString(1000) == b"1000");
        assert!(smallU64ToString(1001) == b"1001");
        assert!(smallU64ToString(3417) == b"3417");
        assert!(smallU64ToString(9283) == b"9283");
        assert!(smallU64ToString(9999) == b"9999");
    }

    #[test]
    #[expected_failure(abort_code = ETOSTRING_VALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLarge1() {
        smallU64ToString(10000);
    }

    #[test]
    #[expected_failure(abort_code = ETOSTRING_VALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLarge2() {
        smallU64ToString(12000);
    }

    #[test]
    fun testSmallU64Log10() {
        assert!(smallU64Log10(0) == 0);
        assert!(smallU64Log10(1) == 1);
        assert!(smallU64Log10(3) == 1);
        assert!(smallU64Log10(9) == 1);
        assert!(smallU64Log10(10) == 2);
        assert!(smallU64Log10(35) == 2);
        assert!(smallU64Log10(100) == 3);
        assert!(smallU64Log10(1000) == 4);
        assert!(smallU64Log10(3162) == 4);
        assert!(smallU64Log10(9999) == 4);
    }

    #[test]
    #[expected_failure(abort_code = ELOG10_VALUE_TOO_LARGE)]
    fun testSmallU64Log10TooLarge1() {
        smallU64Log10(10000);
    }

    #[test]
    #[expected_failure(abort_code = ELOG10_VALUE_TOO_LARGE)]
    fun testSmallU64Log10TooLarge2() {
        smallU64Log10(12000);
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


}