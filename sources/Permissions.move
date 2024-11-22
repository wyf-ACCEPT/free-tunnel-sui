// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.20;

// import "@openzeppelin/contracts/utils/Strings.sol";
// import "@openzeppelin/contracts/utils/math/Math.sol";

// contract Permissions {
//     bytes26 constant ETH_SIGN_HEADER = bytes26("\x19Ethereum Signed Message:\n");

//     struct PermissionsStorage {
//         address _admin;
//         address _vault;

//         mapping(address => uint256) _proposerIndex;
//         address[] _proposerList;

//         address[][] _executorsForIndex;
//         uint256[] _exeThresholdForIndex;
//         uint256[] _exeActiveSinceForIndex;
//     }

//     // keccak256(abi.encode(uint256(keccak256("atomic-lock-mint.Permissions")) - 1)) & ~bytes32(uint256(0xff))
//     bytes32 private constant PermissionsLocation = 0xd1028ee8b04e383c5a05bb344e0e3bf65a78ced42fbbac56a26c8b6f5a4f7100;

//     function _getPermissionsStorage() private pure returns (PermissionsStorage storage $) {
//         assembly {
//             $.slot := PermissionsLocation
//         }
//     }

//     modifier onlyAdmin() {
//         require(msg.sender == getAdmin(), "Require admin");
//         _;
//     }

//     modifier onlyVaultWithAdminFallback() {
//         require(msg.sender == _getVaultWithAdminFallback(), "Require vault");
//         _;
//     }

//     modifier onlyProposer() {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         require($._proposerIndex[msg.sender] > 0, "Require a proposer");
//         _;
//     }

//     function getAdmin() public view returns (address) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._admin;
//     }

//     event AdminTransferred(address indexed prevAdmin, address indexed newAdmin);

//     function _initAdmin(address admin) internal {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         $._admin = admin;
//         emit AdminTransferred(address(0), admin);
//     }

//     function transferAdmin(address newAdmin) external onlyAdmin {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         address prevAdmin = $._admin;
//         $._admin = newAdmin;
//         emit AdminTransferred(prevAdmin, newAdmin);
//     }


//     function getVault() public view returns (address) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._vault;
//     }

//     function _getVaultWithAdminFallback() internal view returns (address) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         address vault = $._vault;
//         return vault == address(0) ? $._admin : vault;
//     }

//     event VaultTransferred(address indexed prevVault, address indexed newVault);

//     function _initVault(address vault) internal {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         $._vault = vault;
//         emit VaultTransferred(address(0), vault);
//     }

//     function transferVault(address newVault) external onlyVaultWithAdminFallback {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         address prevVault = $._vault;
//         $._vault = newVault;
//         emit VaultTransferred(prevVault, newVault);
//     }


//     function proposerIndex(address proposer) external view returns (uint256) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._proposerIndex[proposer];
//     }

//     function proposerOfIndex(uint256 index) external view returns (address) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._proposerList[index];
//     }

//     event ProposerAdded(address indexed proposer);
//     event ProposerRemoved(address indexed proposer);

//     function addProposer(address proposer) external onlyAdmin {
//         _addProposer(proposer);
//     }

//     function _addProposer(address proposer) internal {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         require($._proposerIndex[proposer] == 0, "Already a proposer");
//         $._proposerList.push(proposer);
//         $._proposerIndex[proposer] = $._proposerList.length;
//         emit ProposerAdded(proposer);
//     }

//     function removeProposer(address proposer) external onlyAdmin {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         uint256 index = $._proposerIndex[proposer];
//         require(index > 0, "Not an existing proposer");
//         delete $._proposerIndex[proposer];

//         uint256 len = $._proposerList.length;
//         if (index < len) {
//             address lastProposer = $._proposerList[len - 1];
//             $._proposerList[index - 1] = lastProposer;
//             $._proposerIndex[lastProposer] = index;
//         }
//         $._proposerList.pop();
//         emit ProposerRemoved(proposer);
//     }


//     function executorsForIndex(uint256 index) external view returns (address[] memory) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._executorsForIndex[index];
//     }

//     function exeThresholdForIndex(uint256 index) external view returns (uint256) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._exeThresholdForIndex[index];
//     }

//     function exeActiveSinceForIndex(uint256 index) external view returns (uint256) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         return $._exeActiveSinceForIndex[index];
//     }

//     function getActiveExecutors() external view returns (address[] memory executors, uint256 threshold, uint256 activeSince, uint256 exeIndex) {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         exeIndex = $._exeActiveSinceForIndex.length - 1;
//         if ($._exeActiveSinceForIndex[exeIndex] > block.timestamp) {
//             exeIndex--;
//         }
//         executors = $._executorsForIndex[exeIndex];
//         threshold = $._exeThresholdForIndex[exeIndex];
//         activeSince = $._exeActiveSinceForIndex[exeIndex];
//     }

//     function _initExecutors(address[] memory executors, uint256 threshold) internal {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         require($._exeThresholdForIndex.length == 0, "Executors already initialized");
//         require(threshold > 0, "Threshold must be greater than 0");
//         $._executorsForIndex.push(executors);
//         $._exeThresholdForIndex.push(threshold);
//         $._exeActiveSinceForIndex.push(1);
//     }

//     // All history executors will be recorded and indexed in chronological order. 
//     // When a new set of `executors` is updated, the index will increase by 1. 
//     // When updating `executors`, an `activeSince` timestamp must be provided, 
//     // indicating the time from which this set of `executors` will become effective. 
//     // The `activeSince` must be between 1.5 and 5 days after the current time, and also 
//     // at least 1 day after the `activeSince` of the previous set of `executors`. 
//     // Note that when the new set of `executors` becomes effective, the previous 
//     // set of `executors` will become invalid.
//     function updateExecutors(
//         address[] calldata newExecutors,
//         uint256 threshold,
//         uint256 activeSince,
//         bytes32[] calldata r, bytes32[] calldata yParityAndS, address[] calldata executors, uint256 exeIndex
//     ) external {
//         require(threshold > 0, "Threshold must be greater than 0");
//         require(activeSince > block.timestamp + 36 hours, "The activeSince should be after 1.5 days from now");
//         require(activeSince < block.timestamp + 5 days, "The activeSince should be within 5 days from now");

//         bytes32 digest = keccak256(abi.encodePacked(
//             ETH_SIGN_HEADER, Strings.toString(29 + 43 * newExecutors.length + 11 + Math.log10(threshold) + 1),
//             "Sign to update executors to:\n",
//             __joinAddressList(newExecutors),
//             "Threshold: ", Strings.toString(threshold)
//         ));
//         _checkMultiSignatures(digest, r, yParityAndS, executors, exeIndex);

//         PermissionsStorage storage $ = _getPermissionsStorage();
//         uint256 newIndex = exeIndex + 1;
//         if (newIndex == $._exeActiveSinceForIndex.length) {
//             $._executorsForIndex.push(newExecutors);
//             $._exeThresholdForIndex.push(threshold);
//             $._exeActiveSinceForIndex.push(activeSince);
//         } else {
//             require(activeSince >= $._exeActiveSinceForIndex[newIndex], "Failed to overwrite existing executors");
//             require(threshold >= $._exeThresholdForIndex[newIndex], "Failed to overwrite existing executors");
//             require(__cmpAddrList(newExecutors, $._executorsForIndex[newIndex]), "Failed to overwrite existing executors");
//             $._executorsForIndex[newIndex] = newExecutors;
//             $._exeThresholdForIndex[newIndex] = threshold;
//             $._exeActiveSinceForIndex[newIndex] = activeSince;
//         }
//     }

//     function __joinAddressList(address[] memory addrs) private pure returns (string memory) {
//         string memory result = "";

//         for (uint256 i = 0; i < addrs.length; i++) {
//             string memory addrStr = Strings.toHexString(addrs[i]);
//             if (i == 0) {
//                 result = string(abi.encodePacked(addrStr, "\n"));
//             } else {
//                 result = string(abi.encodePacked(result, addrStr, "\n"));
//             }
//         }

//         return result;
//     }

//     function __cmpAddrList(address[] memory list1, address[] memory list2) private pure returns (bool) {
//         if (list1.length > list2.length) {
//             return true;
//         } else if (list1.length < list2.length) {
//             return false;
//         }
//         for (uint256 i = 0; i < list1.length; i++) {
//             if (list1[i] > list2[i]) {
//                 return true;
//             } else if (list1[i] < list2[i]) {
//                 return false;
//             }
//         }
//         return false;
//     }

//     function _checkMultiSignatures(
//         bytes32 digest,
//         bytes32[] memory r,
//         bytes32[] memory yParityAndS,
//         address[] memory executors,
//         uint256 exeIndex
//     ) internal view {
//         require(r.length == yParityAndS.length, "Array length should equal");
//         require(r.length == executors.length, "Array length should equal");

//         __checkExecutorsForIndex(executors, exeIndex);

//         for (uint256 i = 0; i < executors.length; i++) {
//             address executor = executors[i];
//             __checkSignature(digest, r[i], yParityAndS[i], executor);
//         }
//     }

//     function __checkExecutorsForIndex(address[] memory executors, uint256 exeIndex) private view {
//         PermissionsStorage storage $ = _getPermissionsStorage();
//         require(executors.length >= $._exeThresholdForIndex[exeIndex], "Does not meet threshold");

//         uint256 blockTime = block.timestamp;
//         uint256 activeSince = $._exeActiveSinceForIndex[exeIndex];
//         require(activeSince < blockTime, "Executors not yet active");

//         if ($._exeActiveSinceForIndex.length > exeIndex + 1) {
//             uint256 nextActiveSince = $._exeActiveSinceForIndex[exeIndex + 1];
//             require(nextActiveSince > blockTime, "Executors of next index is active");
//         }

//         address[] memory currentExecutors = $._executorsForIndex[exeIndex];
//         for (uint256 i = 0; i < executors.length; i++) {
//             address executor = executors[i];
//             for (uint256 j = 0; j < i; j++) {
//                 require(executors[j] != executor, "Duplicated executors");
//             }

//             bool isExecutor = false;
//             for (uint256 j = 0; j < currentExecutors.length; j++) {
//                 if (executor == currentExecutors[j]) {
//                     isExecutor = true;
//                     break;
//                 }
//             }
//             require(isExecutor, "Non-executor");
//         }
//     }

//     function __checkSignature(bytes32 digest, bytes32 r, bytes32 yParityAndS, address signer) internal pure {
//         require(signer != address(0), "Signer cannot be empty address");
//         bytes32 s = yParityAndS & bytes32(0x7fffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff);
//         uint8 v = uint8((uint256(yParityAndS) >> 255) + 27);
//         require(uint256(s) <= 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0, "Invalid signature");

//         require(signer == ecrecover(digest, v, r, s), "Invalid signature");
//     }
// }


/** Below is the Sui-Move code for the Permission contract above. */

module free_tunnel_sui::permissions {

    use sui::address;
    use sui::bcs;
    use sui::hex;
    use sui::table;
    use sui::ecdsa_k1;
    use sui::clock::{Self, Clock};

    const ETH_SIGN_HEADER: vector<u8> = b"\x19Ethereum Signed Message:\n";


    const ENOT_ADMIN: u64 = 0;
    const ENOT_PROPOSER: u64 = 1;
    const EALREADY_PROPOSER: u64 = 2;
    const ENOT_EXISTING_PROPOSER: u64 = 3;
    const EEXECUTORS_ALREADY_INITIALIZED: u64 = 4;
    const ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO: u64 = 5;
    const EARRAY_LENGTH_NOT_EQUAL: u64 = 6;
    const ENOT_MEET_THRESHOLD: u64 = 7;
    const EEXECUTORS_NOT_YET_ACTIVE: u64 = 8;
    const EEXECUTORS_OF_NEXT_INDEX_IS_ACTIVE: u64 = 9;
    const EDUPLICATED_EXECUTORS: u64 = 10;
    const ENON_EXECUTOR: u64 = 11;
    const ESIGNER_CANNOT_BE_EMPTY_ADDRESS: u64 = 12;
    const EINVALID_LENGTH: u64 = 13;



    public struct PermissionsStorage has key, store {
        id: UID,
        // tokens: table::Table<u8, TypeName>,
        _admin: address,
        
        _proposerIndex: table::Table<address, u64>,
        _proposerList: vector<address>,

        _executorsForIndex: vector<vector<address>>,
        _exeThresholdForIndex: vector<u64>,
        _exeActiveSinceForIndex: vector<u64>,
    }


    fun assertOnlyAdmin(store: &PermissionsStorage, ctx: &TxContext) {
        assert!(ctx.sender() == store._admin, ENOT_ADMIN);
    }

    fun assertOnlyProposer(store: &PermissionsStorage, ctx: &TxContext) {
        assert!(table::contains(&store._proposerIndex, ctx.sender()), ENOT_PROPOSER);
    }


    public(package) fun initAdminInternal(admin: address, store: &mut PermissionsStorage) {
        store._admin = admin;
    }

    public entry fun transferAdmin(newAdmin: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        store._admin = newAdmin;
    }

    public(package) fun addProposerInternal(proposer: address, store: &mut PermissionsStorage) {
        assert!(!table::contains(&store._proposerIndex, proposer), EALREADY_PROPOSER);
        store._proposerList.push_back(proposer);
        table::add(&mut store._proposerIndex, proposer, store._proposerList.length());
    }

    public entry fun addProposer(proposer: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        addProposerInternal(proposer, store);
    }

    public entry fun removeProposer(proposer: address, store: &mut PermissionsStorage, ctx: &mut TxContext) {
        assertOnlyAdmin(store, ctx);
        assert!(table::contains(&store._proposerIndex, proposer), ENOT_EXISTING_PROPOSER);
        let index = table::remove(&mut store._proposerIndex, proposer);

        let len = store._proposerList.length();
        if (index < len) {
            let lastProposer = store._proposerList[len - 1];
            *vector::borrow_mut(&mut store._proposerList, index - 1) = lastProposer;
            *table::borrow_mut(&mut store._proposerIndex, lastProposer) = index;
        };
        vector::pop_back(&mut store._proposerList);
    }

    public(package) fun initExecutorsInternal(executors: vector<address>, threshold: u64, store: &mut PermissionsStorage) {
        assert!(store._exeThresholdForIndex.length() == 0, EEXECUTORS_ALREADY_INITIALIZED);
        assert!(threshold > 0, ETHRESHOLD_MUST_BE_GREATER_THAN_ZERO);
        store._executorsForIndex.push_back(executors);
        store._exeThresholdForIndex.push_back(threshold);
        store._exeActiveSinceForIndex.push_back(1);
    }


    // public entry fun updateExecutors (TODO)


    fun joinAddressList(addrs: vector<address>): vector<u8> {
        let mut result = vector::empty<u8>();
        let mut i = 0;
        while (i < addrs.length()) {
            let addrStr = address::to_string(addrs[i]).as_bytes();
            result.append(vector::flatten(vector[b"0x", *addrStr, b"\n"]));
            i = i + 1;
        };
        result
    }

    fun cmpAddrList(list1: vector<address>, list2: vector<address>): bool {
        if (list1.length() > list2.length()) {
            true
        } else if (list1.length() < list2.length()) {
            false
        } else {
            let mut i = 0;
            while (i < list1.length()) {
                let addr1U256 = address::to_u256(list1[i]);
                let addr2U256 = address::to_u256(list2[i]);
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

    // fun checkMultiSignatures(
    //     msg: vector<u8>,     // Can only ecrecover from raw message in Sui
    //     r: vector<vector<u8>>, 
    //     yParityAndS: vector<vector<u8>>, 
    //     executors: vector<address>, 
    //     exeIndex: u64
    // ) {
    //     assert!(r.length() == yParityAndS.length(), EARRAY_LENGTH_NOT_EQUAL);
    //     assert!(r.length() == executors.length(), EARRAY_LENGTH_NOT_EQUAL);
    // }

    fun checkExecutorsForIndex(executors: vector<address>, exeIndex: u64, clock_object: &Clock, store: &PermissionsStorage) {
        assert!(executors.length() >= store._exeThresholdForIndex[exeIndex], ENOT_MEET_THRESHOLD);
        let blockTime = clock::timestamp_ms(clock_object) / 1000;
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
                    break;
                };
                j = j + 1;
            };
            assert!(isExecutor, ENON_EXECUTOR);
            i = i + 1;
        };
    }

    fun checkSignature(msg: vector<u8>, r: vector<u8>, yParityAndS: vector<u8>, pubkey: address) {
        assert!(pubkey != @0x0, ESIGNER_CANNOT_BE_EMPTY_ADDRESS);
        assert!(r.length() == 32, EINVALID_LENGTH);
        assert!(yParityAndS.length() == 32, EINVALID_LENGTH);
        let mut s = yParityAndS;
        let v = yParityAndS[0] >> 7;
        *vector::borrow_mut(&mut s, 0) = s[0] & 0x7f;

        let signature65 = vector::flatten(vector[r, s, vector::singleton(v)]);
        let compressedPubkey = ecdsa_k1::secp256k1_ecrecover(&signature65, &msg, 0);
        // let decompressedPubkey = ecdsa_k1::decompress_pubkey(compressedPubkey);
        // assert!(pubkey == decompressedPubkey, EINVALID_SIGNATURE);
    }


    use std::debug;

    #[test]
    fun testAddressToU256() {
        let addr = @0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef;
        let addrU256 = address::to_u256(addr);
        assert!(addrU256 == 0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef);
    }


    #[test]
    fun testJoinAddressList() {
        let addrs = vector[
            @0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef,
            @0x000000000000000000000000000000000000000000000000000000000000beef,
        ];
        let result = joinAddressList(addrs);
        let expected = 
        b"0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef\n0x000000000000000000000000000000000000000000000000000000000000beef\n";
        assert!(result == expected);
    }

    #[test]
    fun testSignature() {
        let addr = @0x1234567809abcdef1234567809abcdef1234567809abcdef1234567809abcdef;

    }





}