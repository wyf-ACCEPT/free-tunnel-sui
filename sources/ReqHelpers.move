module free_tunnel_sui::req_helpers {

    use std::type_name::{Self, TypeName};
    use sui::table;
    use sui::hash;
    use sui::hex;
    use free_tunnel_sui::utils::smallU64ToString;

    const CHAIN: u8 = 0x40;     // TODO: Which id should be used?
    const BRIDGE_CHANNEL: vector<u8> = b"Merlin ERC20 Bridge";      // TODO: Change name?
    // const PROPOSE_PERIOD: u64 = 172800;         // 48 hours
    // const EXPIRE_PERIOD: u64 = 259200;          // 72 hours
    // const EXPIRE_EXTRA_PERIOD: u64 = 345600;    // 96 hours
    const ETH_SIGN_HEADER: vector<u8> = b"\x19Ethereum Signed Message:\n";

    const ETOKEN_INDEX_OCCUPIED: u64 = 0;
    const ETOKEN_INDEX_CANNOT_BE_ZERO: u64 = 1;
    const ETOKEN_INDEX_NONEXISTENT: u64 = 2;
    const EINVALID_REQ_ID_LENGTH: u64 = 3;
    const ENOT_FROM_CURRENT_CHAIN: u64 = 4;
    const ENOT_TO_CURRENT_CHAIN: u64 = 5;


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

    #[allow(implicit_const_copy)]
    public(package) fun digestFromReqSigningMessage(reqId: vector<u8>): vector<u8> {
        assert!(vector::length(&reqId) == 32, EINVALID_REQ_ID_LENGTH);
        let specificAction = actionFrom(reqId) & 0x0f;

        match (specificAction) {
            1 => {
                hash::keccak256(&vector::flatten(vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 29 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a lock-mint:\n",
                    b"0x", hex::encode(reqId),
                ]))
            },
            2 => {
                hash::keccak256(&vector::flatten(vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 31 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a burn-unlock:\n",
                    b"0x", hex::encode(reqId),
                ]))
            },
            3 => {
                hash::keccak256(&vector::flatten(vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + vector::length(&BRIDGE_CHANNEL) + 29 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a burn-mint:\n",
                    b"0x", hex::encode(reqId),
                ]))
            },
            _ => {
                vector::empty<u8>()
            }
        }
    }

    public(package) fun assertFromChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == *vector::borrow(&reqId, 16), ENOT_FROM_CURRENT_CHAIN);
    }

    public(package) fun assertToChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == *vector::borrow(&reqId, 17), ENOT_TO_CURRENT_CHAIN);
    }


    #[test]
    fun testHexEncode() {
        let value = vector[0x33, 0x45];
        assert!(hex::encode(value) == b"3345");
    }

    #[test]
    fun testDecodingReqid() {
        // `version:uint8|createdTime:uint40|action:uint8|tokenIndex:uint8|amount:uint64|from:uint8|to:uint8|(TBD):uint112`
        let reqId = x"112233445566778899aabbccddeeff004040ffffffffffffffffffffffffffff";
        assert!(versionFrom(reqId) == 0x11);
        assert!(createdTimeFrom(reqId) == 0x2233445566);
        assert!(actionFrom(reqId) == 0x77);
        assert!(tokenIndexFrom(reqId) == 0x88);
        assert!(amountFrom(reqId) == 0x99aabbccddeeff00);
        assertFromChainOnly(reqId);
        assertToChainOnly(reqId);
    }

    #[test]
    fun testDigestFromReqSigningMessage1() {
        // action 1: lock-mint
        let reqId = x"112233445566018899aabbccddeeff004040ffffffffffffffffffffffffffff";
        let expected = x"b2cca04d052677f9c855ed80cf6a2fff36621f9b725d2495d785aee31a702cbe";
        assert!(digestFromReqSigningMessage(reqId) == expected);
    }

    #[test]
    fun testDigestFromReqSigningMessage2() {
        // action 2: burn-unlock
        let reqId = x"112233445566028899aabbccddeeff004040ffffffffffffffffffffffffffff";
        let expected = x"1512678d7774afc7b0506d593d4a4ccb71187be5f67644b08fd2e5a996341568";
        assert!(digestFromReqSigningMessage(reqId) == expected);
    }

    #[test]
    fun testDigestFromReqSigningMessage3() {
        // action 3: burn-mint
        let reqId = x"112233445566038899aabbccddeeff004040ffffffffffffffffffffffffffff";
        let expected = x"63f63440c8969acb7576b758f1a00fe5ee916e365ac0a373d77291bcb02e59eb";
        assert!(digestFromReqSigningMessage(reqId) == expected);
    }

    #[test]
    fun testDigestFromReqSigningMessage4() {
        let reqId = x"112233445566048899aabbccddeeff004040ffffffffffffffffffffffffffff";
        assert!(digestFromReqSigningMessage(reqId) == vector::empty<u8>());
    }

}