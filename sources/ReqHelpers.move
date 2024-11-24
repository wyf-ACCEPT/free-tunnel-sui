module free_tunnel_sui::req_helpers {

    // =========================== Packages ===========================
    use std::type_name::{Self, TypeName};
    use sui::table;
    use sui::hash;
    use sui::hex;
    use sui::clock::{Self, Clock};
    use free_tunnel_sui::utils::smallU64ToString;


    // =========================== Constants ==========================
    const CHAIN: u8 = 0x40;     // TODO: Which id should be used?
    const BRIDGE_CHANNEL: vector<u8> = b"Merlin ERC20 Bridge";      // TODO: Change name?
    const PROPOSE_PERIOD: u64 = 172800;         // 48 hours
    const ETH_SIGN_HEADER: vector<u8> = b"\x19Ethereum Signed Message:\n";

    const ETOKEN_INDEX_OCCUPIED: u64 = 0;
    const ETOKEN_INDEX_CANNOT_BE_ZERO: u64 = 1;
    const ETOKEN_INDEX_NONEXISTENT: u64 = 2;
    const EINVALID_REQ_ID_LENGTH: u64 = 3;
    const ENOT_FROM_CURRENT_CHAIN: u64 = 4;
    const ENOT_TO_CURRENT_CHAIN: u64 = 5;
    const ECREATED_TIME_TOO_EARLY: u64 = 6;
    const ECREATED_TIME_TOO_LATE: u64 = 7;
    const EAMOUNT_CANNOT_BE_ZERO: u64 = 8;
    

    // ============================ Storage ===========================
    public struct ReqHelpersStorage has key, store {
        id: UID,
        tokens: table::Table<u8, TypeName>,
        tokenDecimals: table::Table<u8, u8>,
    }

    public(package) fun initReqHelpersStorage(ctx: &mut TxContext): ReqHelpersStorage {
        ReqHelpersStorage {
            id: object::new(ctx),
            tokens: table::new(ctx),
            tokenDecimals: table::new(ctx),
        }
    }


    // =========================== Functions ===========================
    public(package) fun addTokenInternal<CoinType>(tokenIndex: u8, store: &mut ReqHelpersStorage) {
        assert!(!store.tokens.contains(tokenIndex), ETOKEN_INDEX_OCCUPIED);
        assert!(tokenIndex > 0, ETOKEN_INDEX_CANNOT_BE_ZERO);
        store.tokens.add(tokenIndex, type_name::get<CoinType>());

        // TODO: Consider decimals?
    }

    public(package) fun removeTokenInternal(tokenIndex: u8, store: &mut ReqHelpersStorage) {
        assert!(store.tokens.contains(tokenIndex), ETOKEN_INDEX_NONEXISTENT);
        assert!(tokenIndex > 0, ETOKEN_INDEX_CANNOT_BE_ZERO);
        store.tokens.remove(tokenIndex);
    }

    /// `reqId` in format of `version:uint8|createdTime:uint40|action:uint8|tokenIndex:uint8|amount:uint64|from:uint8|to:uint8|(TBD):uint112`
    public(package) fun versionFrom(reqId: vector<u8>): u8 {
        reqId[0]
    }

    public(package) fun createdTimeFrom(reqId: vector<u8>): u64 {
        let mut time = reqId[1] as u64;
        let mut i = 2;
        while (i < 6) {
            time = (time << 8) + (reqId[i] as u64);
            i = i + 1;
        };
        time
    }

    public(package) fun createdTimeFromCheck(reqId: vector<u8>, clockObject: &Clock): u64 {
        let time = createdTimeFrom(reqId);
        assert!(time > clock::timestamp_ms(clockObject) / 1000 - PROPOSE_PERIOD, ECREATED_TIME_TOO_EARLY);
        assert!(time < clock::timestamp_ms(clockObject) / 1000 + 60, ECREATED_TIME_TOO_LATE);
        time
    }

    public(package) fun actionFrom(reqId: vector<u8>): u8 {
        reqId[6]
    }

    public(package) fun tokenIndexFrom(reqId: vector<u8>): u8 {
        reqId[7]
    }

    public(package) fun tokenIndexFromCheck(reqId: vector<u8>, store: &ReqHelpersStorage): u8 {
        let tokenIndex = tokenIndexFrom(reqId);
        assert!(store.tokens.contains(tokenIndex), ETOKEN_INDEX_NONEXISTENT);
        tokenIndex
    }

    public(package) fun tokenIndexMatchCoinType<CoinType>(tokenIndex: u8, store: &ReqHelpersStorage): bool {
        let typeNameExpected = store.tokens[tokenIndex];
        let typeNameActual = type_name::get<CoinType>();
        typeNameExpected == typeNameActual
    }

    public(package) fun amountFrom(reqId: vector<u8>): u64 {
        let mut amount = reqId[8] as u64;
        let mut i = 9;
        while (i < 16) {
            amount = (amount << 8) + (reqId[i] as u64);
            i = i + 1;
        };
        assert!(amount > 0, EAMOUNT_CANNOT_BE_ZERO);
        amount
    }

    #[allow(implicit_const_copy)]
    public(package) fun messageFromReqSigningMessage(reqId: vector<u8>): vector<u8> {
        assert!(reqId.length() == 32, EINVALID_REQ_ID_LENGTH);
        let specificAction = actionFrom(reqId) & 0x0f;

        match (specificAction) {
            1 => {
                (vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + BRIDGE_CHANNEL.length() + 29 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a lock-mint:\n",
                    b"0x", hex::encode(reqId),
                ]).flatten()
            },
            2 => {
                (vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + BRIDGE_CHANNEL.length() + 31 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a burn-unlock:\n",
                    b"0x", hex::encode(reqId),
                ]).flatten()
            },
            3 => {
                (vector[
                    ETH_SIGN_HEADER, 
                    smallU64ToString(3 + BRIDGE_CHANNEL.length() + 29 + 66),
                    b"[", BRIDGE_CHANNEL, b"]\n",
                    b"Sign to execute a burn-mint:\n",
                    b"0x", hex::encode(reqId),
                ]).flatten()
            },
            _ => {
                vector::empty<u8>()
            }
        }
    }

    public(package) fun digestFromReqSigningMessage(reqId: vector<u8>): vector<u8> {
        hash::keccak256(&messageFromReqSigningMessage(reqId))
    }

    public(package) fun assertFromChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == reqId[16], ENOT_FROM_CURRENT_CHAIN);
    }

    public(package) fun assertToChainOnly(reqId: vector<u8>) {
        assert!(CHAIN == reqId[17], ENOT_TO_CURRENT_CHAIN);
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
        assert!(digestFromReqSigningMessage(reqId) == hash::keccak256(&vector::empty<u8>()));
    }

}