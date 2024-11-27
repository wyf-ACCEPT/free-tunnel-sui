/** Below is the Sui-Move code for the Permission contract above. */

module free_tunnel_sui::permissions {

    // =========================== Packages ===========================
    use sui::address;
    use sui::event;
    use sui::table;
    use sui::clock::{Self, Clock};
    use free_tunnel_sui::utils::{recoverEthAddress, smallU64ToString, smallU64Log10, assertEthAddressList};


    // =========================== Constants ==========================
    const ETH_SIGN_HEADER: vector<u8> = b"\x19Ethereum Signed Message:\n";
    const ETH_ZERO_ADDRESS: vector<u8> = vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0];

    const ENOT_ADMIN: u64 = 20;
    const ENOT_PROPOSER: u64 = 21;
    const EALREADY_PROPOSER: u64 = 22;
    const ENOT_EXISTING_PROPOSER: u64 = 23;
    const EEXECUTORS_ALREADY_INITIALIZED: u64 = 24;
    const ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO: u64 = 25;
    const EARRAY_LENGTH_NOT_EQUAL: u64 = 26;
    const ENOT_MEET_THRESHOLD: u64 = 27;
    const EEXECUTORS_NOT_YET_ACTIVE: u64 = 28;
    const EEXECUTORS_OF_NEXT_INDEX_IS_ACTIVE: u64 = 29;
    const EDUPLICATED_EXECUTORS: u64 = 30;
    const ENON_EXECUTOR: u64 = 31;
    const ESIGNER_CANNOT_BE_EMPTY_ADDRESS: u64 = 32;
    const EINVALID_LENGTH: u64 = 33;
    const EINVALID_SIGNATURE: u64 = 34;
    const EACTIVE_SINCE_SHOULD_AFTER_36H: u64 = 35;
    const EACTIVE_SINCE_SHOULD_WITHIN_5D: u64 = 36;
    const EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS: u64 = 37;


    // ============================ Storage ===========================
    public struct PermissionsStorage has key, store {
        id: UID,
        _admin: address,
        
        _proposerIndex: table::Table<address, u64>,
        _proposerList: vector<address>,

        _executorsForIndex: vector<vector<vector<u8>>>,
        _exeThresholdForIndex: vector<u64>,
        _exeActiveSinceForIndex: vector<u64>,
    }

    public(package) fun initPermissionsStorage(ctx: &mut TxContext): PermissionsStorage {
        PermissionsStorage {
            id: object::new(ctx),
            _admin: ctx.sender(),
            _proposerIndex: table::new(ctx),
            _proposerList: vector::empty(),
            _executorsForIndex: vector::empty(),
            _exeThresholdForIndex: vector::empty(),
            _exeActiveSinceForIndex: vector::empty(),
        }
    }

    public struct AdminTransferred has copy, drop {
        prevAdmin: address,
        newAdmin: address,
    }

    public struct ProposerAdded has copy, drop {
        proposer: address,
    }

    public struct ProposerRemoved has copy, drop {
        proposer: address,
    }


    // =========================== Functions ===========================
    public(package) fun assertOnlyAdmin(store: &PermissionsStorage, ctx: &TxContext) {
        assert!(ctx.sender() == store._admin, ENOT_ADMIN);
    }

    public(package) fun assertOnlyProposer(store: &PermissionsStorage, ctx: &TxContext) {
        assert!(store._proposerIndex.contains(ctx.sender()), ENOT_PROPOSER);
    }

    public(package) fun initAdminInternal(admin: address, store: &mut PermissionsStorage) {
        store._admin = admin;
        event::emit(AdminTransferred { prevAdmin: @0x0, newAdmin: admin });
    }

    public entry fun transferAdmin(newAdmin: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        let prevAdmin = store._admin;
        store._admin = newAdmin;
        event::emit(AdminTransferred { prevAdmin, newAdmin });
    }

    public entry fun addProposer(proposer: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        addProposerInternal(proposer, store);
    }

    public(package) fun addProposerInternal(proposer: address, store: &mut PermissionsStorage) {
        assert!(!store._proposerIndex.contains(proposer), EALREADY_PROPOSER);
        store._proposerList.push_back(proposer);
        store._proposerIndex.add(proposer, store._proposerList.length());
        event::emit(ProposerAdded { proposer });
    }

    public entry fun removeProposer(proposer: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        assert!(store._proposerIndex.contains(proposer), ENOT_EXISTING_PROPOSER);
        let index = store._proposerIndex.remove(proposer);

        let len = store._proposerList.length();
        if (index < len) {
            let lastProposer = store._proposerList[len - 1];
            *store._proposerList.borrow_mut(index) = lastProposer;
            *store._proposerIndex.borrow_mut(lastProposer) = index;
        };
        store._proposerList.pop_back();
        event::emit(ProposerRemoved { proposer });
    }

    public(package) fun initExecutorsInternal(executors: vector<vector<u8>>, threshold: u64, store: &mut PermissionsStorage) {
        assertEthAddressList(executors);
        assert!(store._exeThresholdForIndex.length() == 0, EEXECUTORS_ALREADY_INITIALIZED);
        assert!(threshold > 0, ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO);
        store._executorsForIndex.push_back(executors);
        store._exeThresholdForIndex.push_back(threshold);
        store._exeActiveSinceForIndex.push_back(1);
    }


    public entry fun updateExecutors(
        newExecutors: vector<vector<u8>>,
        threshold: u64,
        activeSince: u64,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        clockObject: &Clock,
        store: &mut PermissionsStorage,
    ) {
        assertEthAddressList(newExecutors);
        assert!(threshold > 0, ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO);
        assert!(
            activeSince > clock::timestamp_ms(clockObject) / 1000 + 36 * 3600,  // 36 hours
            EACTIVE_SINCE_SHOULD_AFTER_36H,
        );
        assert!(
            activeSince < clock::timestamp_ms(clockObject) / 1000 + 120 * 3600,  // 5 days
            EACTIVE_SINCE_SHOULD_WITHIN_5D,
        );

        let msg = vector[
            ETH_SIGN_HEADER, 
            smallU64ToString(29 + 43 * newExecutors.length() + 11 + smallU64Log10(threshold) + 1),
            b"Sign to update executors to:\n",
            joinAddressList(newExecutors),
            b"Threshold: ", 
            smallU64ToString(threshold)
        ].flatten();

        checkMultiSignatures(msg, r, yParityAndS, executors, exeIndex, clockObject, store);

        let newIndex = exeIndex + 1;
        if (newIndex == store._exeActiveSinceForIndex.length()) {
            store._executorsForIndex.push_back(newExecutors);
            store._exeThresholdForIndex.push_back(threshold);
            store._exeActiveSinceForIndex.push_back(activeSince);
        } else {
            assert!(activeSince >= store._exeActiveSinceForIndex[newIndex], EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS);
            assert!(threshold >= store._exeThresholdForIndex[newIndex], EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS);
            assert!(cmpAddrList(newExecutors, store._executorsForIndex[newIndex]), EFAILED_TO_OVERWRITE_EXISTING_EXECUTORS);
            *store._executorsForIndex.borrow_mut(newIndex) = newExecutors;
            *store._exeThresholdForIndex.borrow_mut(newIndex) = threshold;
            *store._exeActiveSinceForIndex.borrow_mut(newIndex) = activeSince;
        }
    }


    fun joinAddressList(ethAddrs: vector<vector<u8>>): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < ethAddrs.length()) {
            let addrPadding = address::from_bytes(vector[
                ethAddrs[i], vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]
            ].flatten());
            let addrStr32 = address::to_string(addrPadding).as_bytes();   // 64 bytes
            let mut addrStr = vector::empty<u8>();
            let mut j = 0;
            while (j < 40) {
                addrStr.push_back(addrStr32[j]);
                j = j + 1;
            };

            result.append(vector[b"0x", addrStr, b"\n"].flatten());
            i = i + 1;
        };
        result
    }

    fun cmpAddrList(list1: vector<vector<u8>>, list2: vector<vector<u8>>): bool {
        if (list1.length() > list2.length()) {
            true
        } else if (list1.length() < list2.length()) {
            false
        } else {
            let mut i = 0;
            while (i < list1.length()) {
                let addr1Padding = address::from_bytes(vector[
                    vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], list1[i]
                ].flatten());
                let addr2Padding = address::from_bytes(vector[
                    vector[0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0], list2[i]
                ].flatten());
                let addr1U256 = address::to_u256(addr1Padding);
                let addr2U256 = address::to_u256(addr2Padding);
                if (addr1U256 > addr2U256) {
                    return true
                } else if (addr1U256 < addr2U256) {
                    return false
                };
                i = i + 1;
            };
            false
        }
    }

    public(package) fun checkMultiSignatures(
        msg: vector<u8>,     // Can only ecrecover from raw message in Sui
        r: vector<vector<u8>>, 
        yParityAndS: vector<vector<u8>>, 
        executors: vector<vector<u8>>, 
        exeIndex: u64,
        clockObject: &Clock,
        store: &PermissionsStorage,
    ) {
        assert!(r.length() == yParityAndS.length(), EARRAY_LENGTH_NOT_EQUAL);
        assert!(r.length() == executors.length(), EARRAY_LENGTH_NOT_EQUAL);
        checkExecutorsForIndex(executors, exeIndex, clockObject, store);
        let mut i = 0;
        while (i < executors.length()) {
            checkSignature(msg, r[i], yParityAndS[i], executors[i]);
            i = i + 1;
        };
    }

    fun checkExecutorsForIndex(executors: vector<vector<u8>>, exeIndex: u64, clockObject: &Clock, store: &PermissionsStorage) {
        assertEthAddressList(executors);
        assert!(executors.length() >= store._exeThresholdForIndex[exeIndex], ENOT_MEET_THRESHOLD);
        let blockTime = clock::timestamp_ms(clockObject) / 1000;
        let activeSince = store._exeActiveSinceForIndex[exeIndex];
        assert!(activeSince < blockTime, EEXECUTORS_NOT_YET_ACTIVE);

        if (store._exeActiveSinceForIndex.length() > exeIndex + 1) {
            let nextActiveSince = store._exeActiveSinceForIndex[exeIndex + 1];
            assert!(nextActiveSince > blockTime, EEXECUTORS_OF_NEXT_INDEX_IS_ACTIVE);
        };

        let currentExecutors = store._executorsForIndex[exeIndex];
        let mut i = 0;
        while (i < executors.length()) {
            let executor = executors[i];
            let mut j = 0;
            while (j < i) {
                assert!(executors[j] != executor, EDUPLICATED_EXECUTORS);
                j = j + 1;
            };
            let mut isExecutor = false;
            let mut j = 0;
            while (j < currentExecutors.length()) {
                if (executor == currentExecutors[j]) {
                    isExecutor = true;
                    break
                };
                j = j + 1;
            };
            assert!(isExecutor, ENON_EXECUTOR);
            i = i + 1;
        };
    }

    fun checkSignature(msg: vector<u8>, r: vector<u8>, yParityAndS: vector<u8>, ethSigner: vector<u8>) {
        assert!(ethSigner != ETH_ZERO_ADDRESS, ESIGNER_CANNOT_BE_EMPTY_ADDRESS);
        assert!(r.length() == 32, EINVALID_LENGTH);
        assert!(yParityAndS.length() == 32, EINVALID_LENGTH);
        assert!(ethSigner.length() == 20, EINVALID_LENGTH);
        let recoveredEthAddr = recoverEthAddress(msg, r, yParityAndS);
        assert!(recoveredEthAddr == ethSigner, EINVALID_SIGNATURE);
    }


    #[test]
    fun testAddressToU256() {
        let addr = @0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef;
        let addrU256 = address::to_u256(addr);
        assert!(addrU256 == 0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef);
    }

    #[test]
    fun testJoinAddressList() {
        let addrs = vector[
            x"00112233445566778899aabbccddeeff00112233",
            x"000000000000000000000000000000000000beef"
        ];
        let result = joinAddressList(addrs);
        let expected = 
        b"0x00112233445566778899aabbccddeeff00112233\n0x000000000000000000000000000000000000beef\n";
        assert!(result == expected);
        assert!(expected.length() == 43 * 2);
    }

    #[test]
    fun testVectorCompare() {
        assert!(vector[1, 2, 3] == vector[1, 2, 3]);
        assert!(vector[1, 2, 3] != vector[1, 2, 4]);
    }

    #[test]
    fun testCmpAddrList() {
        let ethAddr1 = x"00112233445566778899aabbccddeeff00112233";
        let ethAddr2 = x"00112233445566778899aabbccddeeff00112234";
        let ethAddr3 = x"0000ffffffffffffffffffffffffffffffffffff";
        assert!(cmpAddrList(vector[ethAddr1, ethAddr2], vector[ethAddr1]));
        assert!(!cmpAddrList(vector[ethAddr1], vector[ethAddr1, ethAddr2]));
        assert!(cmpAddrList(vector[ethAddr1, ethAddr2], vector[ethAddr1, ethAddr1]));
        assert!(!cmpAddrList(vector[ethAddr2, ethAddr1], vector[ethAddr2, ethAddr2]));
        assert!(!cmpAddrList(vector[ethAddr2, ethAddr3], vector[ethAddr2, ethAddr3]));
    }
}