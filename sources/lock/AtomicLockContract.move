module free_tunnel_sui::atomic_lock {

    // =========================== Packages ===========================
    use sui::event;
    use sui::table;
    use sui::balance::Balance;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use free_tunnel_sui::req_helpers::{Self, ReqHelpersStorage};
    use free_tunnel_sui::permissions::{Self, PermissionsStorage};


    // =========================== Constants ==========================
    const DEAD_ADDRESS: address = @0xdead;
    const EXPIRE_PERIOD: u64 = 259200;          // 72 hours
    const EXPIRE_EXTRA_PERIOD: u64 = 345600;    // 96 hours

    const ENOT_LOCK_MINT: u64 = 70;
    const EINVALID_REQ_ID: u64 = 71;
    const EINVALID_PROPOSER: u64 = 72;
    const EMISMATCH_COIN_AMOUNT: u64 = 73;
    const EWAIT_UNTIL_EXPIRED: u64 = 74;
    const ENOT_BURN_UNLOCK: u64 = 75;
    const EINVALID_RECIPIENT: u64 = 76;


    // ============================ Storage ===========================
    public struct AtomicLockStorage has key, store {
        id: UID,
        proposedLock: table::Table<vector<u8>, address>,
        proposedUnlock: table::Table<vector<u8>, address>,
        lockedBalanceOf: table::Table<u8, u64>,
    }

    public struct PendingBalanceBox<phantom CoinType> has key, store {
        id: UID,
        balance: Balance<CoinType>,
    }

    public struct TokenLockProposed has copy, drop {
        reqId: vector<u8>,
        proposer: address,
    }

    public struct TokenLockExecuted has copy, drop {
        reqId: vector<u8>,
        proposer: address,
    }

    public struct TokenLockCancelled has copy, drop {
        reqId: vector<u8>,
        proposer: address,
    }

    public struct TokenUnlockProposed has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    public struct TokenUnlockExecuted has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    public struct TokenUnlockCancelled has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    /**
     * @dev Cannot pass more parameters here, so you need to transfer admin, update proposers
     *          and update executors manually later.
     */
    fun init(ctx: &mut TxContext) {
        let permissionStorage = permissions::initPermissionsStorage(ctx);
        transfer::public_share_object(permissionStorage);

        let reqHelpersStorage = req_helpers::initReqHelpersStorage(ctx);
        transfer::public_share_object(reqHelpersStorage);

        let atomicLockStorage = AtomicLockStorage {
            id: object::new(ctx),
            proposedLock: table::new(ctx),
            proposedUnlock: table::new(ctx),
            lockedBalanceOf: table::new(ctx),
        };
        transfer::public_share_object(atomicLockStorage);
    }


    // =========================== Functions ===========================
    public entry fun addToken<CoinType>(
        tokenIndex: u8,
        decimals: u8,
        storeP: &mut PermissionsStorage, 
        storeR: &mut ReqHelpersStorage, 
        ctx: &mut TxContext,
    ) {
        permissions::assertOnlyAdmin(storeP, ctx);
        req_helpers::addTokenInternal<CoinType>(tokenIndex, decimals, storeR);
    }

    public entry fun removeToken(
        tokenIndex: u8,
        storeP: &mut PermissionsStorage, 
        storeR: &mut ReqHelpersStorage, 
        ctx: &mut TxContext,
    ) {
        permissions::assertOnlyAdmin(storeP, ctx);
        req_helpers::removeTokenInternal(tokenIndex, storeR);
    }

    public entry fun proposeLock<CoinType>(
        reqId: vector<u8>, 
        coinObject: Coin<CoinType>,
        storeA: &mut AtomicLockStorage, 
        storeR: &mut ReqHelpersStorage, 
        clockObject: &Clock, 
        ctx: &mut TxContext,
    ) {
        req_helpers::assertFromChainOnly(reqId);
        req_helpers::createdTimeFromCheck(reqId, clockObject);
        let action = req_helpers::actionFrom(reqId);
        assert!(action & 0x0f == 1, ENOT_LOCK_MINT);
        assert!(!storeA.proposedLock.contains(reqId), EINVALID_REQ_ID);

        let proposer = ctx.sender();
        assert!(proposer != DEAD_ADDRESS, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        storeA.proposedLock.add(reqId, proposer);

        req_helpers::tokenIndexMatchCoinType<CoinType>(tokenIndex, storeR);
        assert!(coinObject.value() == amount, EMISMATCH_COIN_AMOUNT);

        // No vault here, so just transfer from proposer to this contract
        let pendingBalanceBox = PendingBalanceBox<CoinType> {
            id: object::new(ctx),
            balance: coinObject.into_balance(),
        };
        transfer::public_share_object(pendingBalanceBox);
        event::emit(TokenLockProposed{ reqId, proposer });
    }

    public entry fun executeLock(
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        storeA: &mut AtomicLockStorage,
        storeP: &mut PermissionsStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
    ) {
        let proposer = storeA.proposedLock[reqId];
        assert!(proposer != DEAD_ADDRESS, EINVALID_REQ_ID);

        let message = req_helpers::messageFromReqSigningMessage(reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, clockObject, storeP,
        );

        *storeA.proposedLock.borrow_mut(reqId) = DEAD_ADDRESS;

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        if (storeA.lockedBalanceOf.contains(tokenIndex)) {
            let originalAmount = storeA.lockedBalanceOf[tokenIndex];
            *storeA.lockedBalanceOf.borrow_mut(tokenIndex) = originalAmount + amount;
        } else {
            storeA.lockedBalanceOf.add(tokenIndex, amount);
        };
        event::emit(TokenLockExecuted{ reqId, proposer });
    }

    public entry fun cancelLock<CoinType>(
        reqId: vector<u8>,
        pendingBalanceBox: PendingBalanceBox<CoinType>,
        storeA: &mut AtomicLockStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        let proposer = storeA.proposedLock[reqId];
        assert!(proposer != DEAD_ADDRESS, EINVALID_REQ_ID);
        assert!(
            clock::timestamp_ms(clockObject) / 1000 > req_helpers::createdTimeFrom(reqId) 
            + EXPIRE_PERIOD, EWAIT_UNTIL_EXPIRED
        );

        storeA.proposedLock.remove(reqId);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        req_helpers::tokenIndexMatchCoinType<CoinType>(tokenIndex, storeR);
        
        // No vault here, so just transfer from this contract to proposer
        let PendingBalanceBox { id, balance } = pendingBalanceBox;
        object::delete(id);
        let coinObject = coin::from_balance(balance, ctx);
        assert!(coinObject.value() == amount, EMISMATCH_COIN_AMOUNT);

        transfer::public_transfer(coinObject, proposer);
        event::emit(TokenLockCancelled{ reqId, proposer });
    }

    public entry fun proposeUnlock(
        reqId: vector<u8>,
        recipient: address,
        storeA: &mut AtomicLockStorage,
        storeP: &mut PermissionsStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        permissions::assertOnlyProposer(storeP, ctx);
        req_helpers::assertFromChainOnly(reqId);
        req_helpers::createdTimeFromCheck(reqId, clockObject);
        assert!(req_helpers::actionFrom(reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        assert!(!storeA.proposedUnlock.contains(reqId), EINVALID_REQ_ID);
        assert!(recipient != DEAD_ADDRESS, EINVALID_RECIPIENT);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        let originalAmount = storeA.lockedBalanceOf[tokenIndex];
        *storeA.lockedBalanceOf.borrow_mut(tokenIndex) = originalAmount - amount;
        storeA.proposedUnlock.add(reqId, recipient);
        event::emit(TokenUnlockProposed{ reqId, recipient });
    }

    public entry fun executeUnlock<CoinType>(
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        pendingBalanceBox: PendingBalanceBox<CoinType>,
        storeA: &mut AtomicLockStorage,
        storeP: &mut PermissionsStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        let recipient = storeA.proposedUnlock[reqId];
        assert!(recipient != DEAD_ADDRESS, EINVALID_REQ_ID);

        let message = req_helpers::messageFromReqSigningMessage(reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, clockObject, storeP,
        );

        *storeA.proposedUnlock.borrow_mut(reqId) = DEAD_ADDRESS;

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        req_helpers::tokenIndexMatchCoinType<CoinType>(tokenIndex, storeR);

        let PendingBalanceBox { id, balance } = pendingBalanceBox;
        object::delete(id);
        let coinObject = coin::from_balance(balance, ctx);
        assert!(coinObject.value() == amount, EMISMATCH_COIN_AMOUNT);

        transfer::public_transfer(coinObject, recipient);
        event::emit(TokenUnlockExecuted{ reqId, recipient });
    }

    public entry fun cancelUnlock(
        reqId: vector<u8>,
        storeA: &mut AtomicLockStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
    ) {
        let recipient = storeA.proposedUnlock[reqId];
        assert!(recipient != DEAD_ADDRESS, EINVALID_REQ_ID);
        assert!(
            clock::timestamp_ms(clockObject) / 1000 > req_helpers::createdTimeFrom(reqId) 
            + EXPIRE_EXTRA_PERIOD, EWAIT_UNTIL_EXPIRED
        );

        storeA.proposedUnlock.remove(reqId);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFromCheck(reqId, storeR);
        let originalAmount = storeA.lockedBalanceOf[tokenIndex];
        *storeA.lockedBalanceOf.borrow_mut(tokenIndex) = originalAmount + amount;
        event::emit(TokenUnlockCancelled{ reqId, recipient });
    }

}