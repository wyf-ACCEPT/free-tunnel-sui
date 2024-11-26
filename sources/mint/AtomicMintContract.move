module free_tunnel_sui::atomic_mint {

    // =========================== Packages ===========================
    use sui::bag;
    use sui::event;
    use sui::table;
    use sui::pay;
    use sui::coin::{Self, Coin};
    use sui::clock::{Self, Clock};
    use free_tunnel_sui::req_helpers::{Self, ReqHelpersStorage};
    use free_tunnel_sui::permissions::{Self, PermissionsStorage};
    use free_tunnel_sui::mintable_coin::{Self, TreasuryCapBox};


    // =========================== Constants ==========================
    const DEAD_ADDRESS: address = @0xdead;
    const EXPIRE_PERIOD: u64 = 259200;          // 72 hours
    const EXPIRE_EXTRA_PERIOD: u64 = 345600;    // 96 hours

    const EINVALID_REQ_ID: u64 = 50;
    const EINVALID_RECIPIENT: u64 = 51;
    const ENOT_LOCK_MINT: u64 = 52;
    const ENOT_BURN_MINT: u64 = 53;
    const EWAIT_UNTIL_EXPIRED: u64 = 54;
    const EINVALID_PROPOSER: u64 = 55;
    const ENOT_BURN_UNLOCK: u64 = 56;


    // ============================ Storage ===========================
    public struct AtomicMintStorage has key, store {
        id: UID,
        proposedMint: table::Table<vector<u8>, address>,
        proposedBurn: table::Table<vector<u8>, address>,
        coinsPendingBurn: bag::Bag,
    }

    public struct TokenMintProposed has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    public struct TokenMintExecuted has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    public struct TokenMintCancelled has copy, drop {
        reqId: vector<u8>,
        recipient: address,
    }

    public struct TokenBurnProposed has copy, drop {
        reqId: vector<u8>,
        proposer: address,
    }

    public struct TokenBurnExecuted has copy, drop {
        reqId: vector<u8>,
        proposer: address,
    }

    public struct TokenBurnCancelled has copy, drop {
        reqId: vector<u8>,
        proposer: address,
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

        let atomicMintStorage = AtomicMintStorage {
            id: object::new(ctx),
            proposedMint: table::new(ctx),
            proposedBurn: table::new(ctx),
            coinsPendingBurn: bag::new(ctx),
        };
        transfer::public_share_object(atomicMintStorage);
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

    public entry fun proposeMint<CoinType>(
        reqId: vector<u8>,
        recipient: address,
        storeA: &mut AtomicMintStorage,
        storeP: &mut PermissionsStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        permissions::assertOnlyProposer(storeP, ctx);
        req_helpers::assertToChainOnly(reqId);
        assert!(req_helpers::actionFrom(reqId) & 0x0f == 1, ENOT_LOCK_MINT);
        proposeMintInternal<CoinType>(reqId, recipient, storeA, storeR, clockObject);
    }

    public entry fun proposeMintFromBurn<CoinType>(
        reqId: vector<u8>,
        recipient: address,
        storeA: &mut AtomicMintStorage,
        storeP: &mut PermissionsStorage,
        storeR: &mut ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        permissions::assertOnlyProposer(storeP, ctx);
        req_helpers::assertToChainOnly(reqId);
        assert!(req_helpers::actionFrom(reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeMintInternal<CoinType>(reqId, recipient, storeA, storeR, clockObject);
    }

    fun proposeMintInternal<CoinType>(
        reqId: vector<u8>,
        recipient: address,
        storeA: &mut AtomicMintStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
    ) {
        req_helpers::checkCreatedTimeFrom(reqId, clockObject);
        assert!(!storeA.proposedMint.contains(reqId), EINVALID_REQ_ID);
        assert!(recipient != DEAD_ADDRESS, EINVALID_RECIPIENT);

        req_helpers::amountFrom(reqId, storeR);
        req_helpers::tokenIndexFrom<CoinType>(reqId, storeR);
        storeA.proposedMint.add(reqId, recipient);

        event::emit(TokenMintProposed{ reqId, recipient });
    }

    public entry fun executeMint<CoinType>(
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        treasuryCapBox: &mut TreasuryCapBox<CoinType>,
        storeA: &mut AtomicMintStorage,
        storeP: &mut PermissionsStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        let recipient = storeA.proposedMint[reqId];
        assert!(recipient != DEAD_ADDRESS, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, clockObject, storeP,
        );

        *storeA.proposedMint.borrow_mut(reqId) = DEAD_ADDRESS;

        let amount = req_helpers::amountFrom(reqId, storeR);
        req_helpers::tokenIndexFrom<CoinType>(reqId, storeR);

        mintable_coin::mintWithTreasuryBox(amount, recipient, treasuryCapBox, ctx);
        event::emit(TokenMintExecuted{ reqId, recipient });
    }

    public entry fun cancelMint(
        reqId: vector<u8>,
        storeA: &mut AtomicMintStorage,
        clockObject: &Clock,
    ) {
        let recipient = storeA.proposedMint[reqId];
        assert!(recipient != DEAD_ADDRESS, EINVALID_REQ_ID);
        assert!(
            clock::timestamp_ms(clockObject) / 1000 > req_helpers::createdTimeFrom(reqId)
            + EXPIRE_EXTRA_PERIOD, EWAIT_UNTIL_EXPIRED
        );

        storeA.proposedMint.remove(reqId);
        event::emit(TokenMintCancelled{ reqId, recipient });
    }


    public entry fun proposeBurn<CoinType>(
        reqId: vector<u8>,
        coinList: vector<Coin<CoinType>>,
        storeA: &mut AtomicMintStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        req_helpers::assertToChainOnly(reqId);
        assert!(req_helpers::actionFrom(reqId) & 0x0f == 2, ENOT_BURN_UNLOCK);
        proposeBurnInternal<CoinType>(
            reqId, coinList, storeA, storeR, clockObject, ctx,
        );
    }

    public entry fun proposeBurnForMint<CoinType>(
        reqId: vector<u8>,
        coinList: vector<Coin<CoinType>>,
        storeA: &mut AtomicMintStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        req_helpers::assertFromChainOnly(reqId);
        assert!(req_helpers::actionFrom(reqId) & 0x0f == 3, ENOT_BURN_MINT);
        proposeBurnInternal<CoinType>(
            reqId, coinList, storeA, storeR, clockObject, ctx,
        );
    }

    #[allow(lint(self_transfer))]
    fun proposeBurnInternal<CoinType>(
        reqId: vector<u8>,
        coinList: vector<Coin<CoinType>>,
        storeA: &mut AtomicMintStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        req_helpers::checkCreatedTimeFrom(reqId, clockObject);
        assert!(!storeA.proposedBurn.contains(reqId), EINVALID_REQ_ID);

        let proposer = ctx.sender();
        assert!(proposer != DEAD_ADDRESS, EINVALID_PROPOSER);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(reqId, storeR);
        storeA.proposedBurn.add(reqId, proposer);

        let mut coinMerged = coin::zero<CoinType>(ctx);
        pay::join_vec(&mut coinMerged, coinList);
        let coinObject = coin::split(&mut coinMerged, amount, ctx);
        transfer::public_transfer(coinMerged, ctx.sender());

        if (storeA.coinsPendingBurn.contains(tokenIndex)) {
            let coinInside = storeA.coinsPendingBurn.borrow_mut(tokenIndex);
            coin::join(coinInside, coinObject);
        } else {
            storeA.coinsPendingBurn.add(tokenIndex, coinObject);
        };
        event::emit(TokenBurnProposed{ reqId, proposer });
    }

    public entry fun executeBurn<CoinType>(
        reqId: vector<u8>,
        r: vector<vector<u8>>,
        yParityAndS: vector<vector<u8>>,
        executors: vector<vector<u8>>,
        exeIndex: u64,
        treasuryCapBox: &mut TreasuryCapBox<CoinType>,
        storeA: &mut AtomicMintStorage,
        storeP: &mut PermissionsStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        let proposer = storeA.proposedBurn[reqId];
        assert!(proposer != DEAD_ADDRESS, EINVALID_REQ_ID);

        let message = req_helpers::msgFromReqSigningMessage(reqId);
        permissions::checkMultiSignatures(
            message, r, yParityAndS, executors, exeIndex, clockObject, storeP,
        );

        *storeA.proposedBurn.borrow_mut(reqId) = DEAD_ADDRESS;

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(reqId, storeR);

        let coinInside = storeA.coinsPendingBurn.borrow_mut(tokenIndex);
        let coinObject = coin::split(coinInside, amount, ctx);

        mintable_coin::burnWithTreasuryBox(coinObject, treasuryCapBox);
        event::emit(TokenBurnExecuted{ reqId, proposer });
    }

    public entry fun cancelBurn<CoinType>(
        reqId: vector<u8>,
        storeA: &mut AtomicMintStorage,
        storeR: &ReqHelpersStorage,
        clockObject: &Clock,
        ctx: &mut TxContext,
    ) {
        let proposer = storeA.proposedBurn[reqId];
        assert!(proposer != DEAD_ADDRESS, EINVALID_REQ_ID);
        assert!(
            clock::timestamp_ms(clockObject) / 1000 > req_helpers::createdTimeFrom(reqId)
            + EXPIRE_PERIOD, EWAIT_UNTIL_EXPIRED
        );

        storeA.proposedBurn.remove(reqId);

        let amount = req_helpers::amountFrom(reqId, storeR);
        let tokenIndex = req_helpers::tokenIndexFrom<CoinType>(reqId, storeR);

        let coinInside = storeA.coinsPendingBurn.borrow_mut(tokenIndex);
        let coinObject: Coin<CoinType> = coin::split(coinInside, amount, ctx);

        transfer::public_transfer(coinObject, proposer);
        event::emit(TokenBurnCancelled{ reqId, proposer });
    }

}