module free_tunnel_sui::req_helpers {

    use std::type_name::{Self, TypeName};

    use sui::table;
    use sui::hash;
    use sui::hex;


    const CHAIN: u8 = 0x40;     // TODO: Which id should be used?

    const BRIDGE_CHANNEL: vector<u8> = b"Merlin ERC20 Bridge";      // TODO: Change name?

    const PROPOSE_PERIOD: u64 = 172800;         // 48 hours
    const EXPIRE_PERIOD: u64 = 259200;          // 72 hours
    const EXPIRE_EXTRA_PERIOD: u64 = 345600;    // 96 hours

    const ETH_SIGN_HEADER: vector<u8> = b"\x19Ethereum Signed Message:\n";


    const ETOKEN_INDEX_OCCUPIED: u64 = 0;
    const ETOKEN_INDEX_CANNOT_BE_ZERO: u64 = 1;
    const ETOKEN_INDEX_NONEXISTENT: u64 = 2;
    const EINVALID_REQ_ID_LENGTH: u64 = 3;
    const ENOT_FROM_CURRENT_CHAIN: u64 = 4;
    const ENOT_TO_CURRENT_CHAIN: u64 = 5;

    const EVALUE_TOO_LARGE: u64 = 10;


    public struct ReqHelpersStorage has key, store {
        id: UID,
        tokens: table::Table<u8, TypeName>,
    }

    public(package) fun addToken<CoinType>(store: &mut ReqHelpersStorage, tokenIndex: u8) {
        assert!(!table::contains(&store.tokens, tokenIndex), ETOKEN_INDEX_OCCUPIED);
        assert!(tokenIndex > 0, ETOKEN_INDEX_CANNOT_BE_ZERO);
        table::add(&mut store.tokens, tokenIndex, type_name::get<CoinType>());

        // TODO: Consider decimals?
    }

    public(package) fun removeToken(store: &mut ReqHelpersStorage, tokenIndex: u8) {
        assert!(table::contains(&store.tokens, tokenIndex), ETOKEN_INDEX_NONEXISTENT);
        assert!(tokenIndex > 0, ETOKEN_INDEX_CANNOT_BE_ZERO);
        table::remove(&mut store.tokens, tokenIndex);
    }

    /// `reqId` in format of `version:uint8|createdTime:uint40|action:uint8|tokenIndex:uint8|amount:uint64|from:uint8|to:uint8|(TBD):uint112`
    public(package) fun versionFrom(reqId: vector<u8>): u8 {
        *vector::borrow(&reqId, 0)
    }

    public(package) fun createdTimeFrom(reqId: vector<u8>): u64 {
        let mut time = (*vector::borrow(&reqId, 1) as u64);
        let mut i = 2;
        while (i < 6) {
            let byte = *vector::borrow(&reqId, i);
            time = (time << 8) + (byte as u64);
            i = i + 1;
        };
        time
    }

    public(package) fun actionFrom(reqId: vector<u8>): u8 {
        *vector::borrow(&reqId, 6)
    }

    public(package) fun tokenIndexFrom(reqId: vector<u8>): u8 {
        *vector::borrow(&reqId, 7)
    }

    public(package) fun amountFrom(reqId: vector<u8>): u64 {
        let mut amount = (*vector::borrow(&reqId, 8) as u64);
        let mut i = 9;
        while (i < 16) {
            let byte = *vector::borrow(&reqId, i);
            amount = (amount << 8) + (byte as u64);
            i = i + 1;
        };
        amount
    }


    fun smallU64ToString(value: u64): vector<u8> {
        let mut buffer = vector::empty<u8>();
        assert!(value < 1000, EVALUE_TOO_LARGE);
        if (value >= 100) {
            let byte = (value / 100) as u8 + 48;
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


    #[allow(implicit_const_copy)]
    public(package) fun digestFromReqSigningMessage(reqId: vector<u8>): vector<u8> {
        assert!(vector::length(&reqId) == 32, EINVALID_REQ_ID_LENGTH);
        let specificAction = actionFrom(reqId) & 0x0f;

        let mut message = vector::empty<u8>();

        if (specificAction == 1) {
            message = vector::flatten(vector[
                ETH_SIGN_HEADER, 
                smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 29 + 66),
                b"[", BRIDGE_CHANNEL, b"]\n",
                b"Sign to execute a lock-mint:\n",
                b"0x",
                hex::encode(reqId),
            ]);
        } else if (specificAction == 2) {
            message = vector::flatten(vector[
                ETH_SIGN_HEADER, 
                smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 31 + 66),
                b"[", BRIDGE_CHANNEL, b"]\n",
                b"Sign to execute a burn-unlock:\n",
                b"0x",
                hex::encode(reqId),
            ]);
        } else if (specificAction == 3) {
            message = vector::flatten(vector[
                ETH_SIGN_HEADER, 
                smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 29 + 66),
                b"[", BRIDGE_CHANNEL, b"]\n",
                b"Sign to execute a burn-mint:\n",
                b"0x",
                hex::encode(reqId),
            ]);
        } else {
            return vector::empty<u8>()
        };
        hash::keccak256(&message)
    }

    public(package) fun assertFromChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == *vector::borrow(&reqId, 16), ENOT_FROM_CURRENT_CHAIN);
    }

    public(package) fun assertToChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == *vector::borrow(&reqId, 17), ENOT_TO_CURRENT_CHAIN);
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
    }

    #[test]
    #[expected_failure(abort_code = EVALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLarge1() {
        smallU64ToString(1000);
    }

    #[test]
    #[expected_failure(abort_code = EVALUE_TOO_LARGE)]
    fun testSmallU64ToStringTooLarge2() {
        smallU64ToString(1200);
    }

    #[test]
    fun testHexEncode() {
        let value = vector[0x33, 0x45];
        assert!(hex::encode(value) == b"3345");
    }

    


}