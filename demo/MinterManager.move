module minter_manager::minter_manager {

    use sui::event;
    use sui::table;
    use sui::pay;
    use sui::coin::{Self, Coin, TreasuryCap};

    const ENOT_ADMIN: u64 = 1;
    const ETREASURY_CAP_MANAGER_DESTROYED: u64 = 2;
    const EMINTER_REVOKED: u64 = 3;

    // Data structures
    public struct TreasuryCapManager<phantom CoinType> has key, store {
        id: UID,
        admin: address,
        treasuryCap: TreasuryCap<CoinType>,
        revokedMinters: table::Table<ID, bool>,
    }

    public struct MinterCap<phantom CoinType> has key, store {
        id: UID,
        managerId: ID,
    }

    // Structs for events
    public struct AdminTransferred has copy, drop {
        prevAdmin: address,
        newAdmin: address,
    }

    public struct TreasuryCapManagerSetup has copy, drop {
        admin: address,
        treasuryCapManagerId: ID,
    }

    public struct TreasuryCapManagerDestroyed has copy, drop {
        treasuryCapManagerId: ID,
    }

    public struct MinterCapIssued has copy, drop {
        recipient: address,
        minterCapId: ID,
    }

    public struct MinterCapRevoked has copy, drop {
        minterCapId: ID,
    }

    public struct MinterCapDestroyed has copy, drop {
        minterCapId: ID,
    }


    // Entry functions
    public entry fun transferAdmin<CoinType>(
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        newAdmin: address,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_ADMIN);
        treasuryCapManager.admin = newAdmin;
        event::emit(AdminTransferred { prevAdmin: ctx.sender(), newAdmin });
    }

    public entry fun setupTreasuryCapManager<CoinType>(
        admin: address,
        treasuryCap: TreasuryCap<CoinType>,
        ctx: &mut TxContext,
    ) {
        let treasuryCapManager = TreasuryCapManager<CoinType> {
            id: object::new(ctx),
            admin,
            treasuryCap,
            revokedMinters: table::new(ctx),
        };
        let treasuryCapManagerId = object::uid_to_inner(&treasuryCapManager.id);
        transfer::public_share_object(treasuryCapManager);
        event::emit(TreasuryCapManagerSetup { admin, treasuryCapManagerId });
    }

    public entry fun destroyTreasuryCapManager<CoinType>(
        treasuryCapManager: TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_ADMIN);
        let TreasuryCapManager<CoinType> {
            id, admin: _, treasuryCap, revokedMinters,
        } = treasuryCapManager;

        let treasuryCapManagerId = object::uid_to_inner(&id);
        object::delete(id);
        table::drop(revokedMinters);
        transfer::public_transfer(treasuryCap, ctx.sender());
        event::emit(TreasuryCapManagerDestroyed { treasuryCapManagerId });
    }

    public entry fun issueMinterCap<CoinType>(
        recipient: address,
        treasuryCapManager: &TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_ADMIN);
        let minterCap = MinterCap<CoinType> {
            id: object::new(ctx),
            managerId: object::uid_to_inner(&treasuryCapManager.id),
        };
        let minterCapId = object::uid_to_inner(&minterCap.id);
        transfer::public_transfer(minterCap, recipient);
        event::emit(MinterCapIssued { recipient, minterCapId });
    }

    public entry fun revokeMinterCap<CoinType>(
        minterCapId: ID,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_ADMIN);
        treasuryCapManager.revokedMinters.add(minterCapId, true);
        event::emit(MinterCapRevoked { minterCapId });
    }

    public entry fun destroyMinterCap<CoinType>(
        minterCap: MinterCap<CoinType>,
    ) {
        let MinterCap<CoinType> { id, managerId: _ } = minterCap;
        let minterCapId = object::uid_to_inner(&id);
        object::delete(id);
        event::emit(MinterCapDestroyed { minterCapId });
    }

    public entry fun mint<CoinType>(
        amount: u64,
        recipient: address,
        minterCap: &mut MinterCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(
            !treasuryCapManager.revokedMinters.contains(object::uid_to_inner(&minterCap.id)),
            EMINTER_REVOKED,
        );
        assert!(
            minterCap.managerId == object::uid_to_inner(&treasuryCapManager.id),
            ETREASURY_CAP_MANAGER_DESTROYED,
        );
        coin::mint_and_transfer(&mut treasuryCapManager.treasuryCap, amount, recipient, ctx);
    }

    public entry fun burn<CoinType>(
        amount: u64,
        coinList: vector<Coin<CoinType>>,
        minterCap: &mut MinterCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(
            !treasuryCapManager.revokedMinters.contains(object::uid_to_inner(&minterCap.id)),
            EMINTER_REVOKED,
        );
        assert!(
            minterCap.managerId == object::uid_to_inner(&treasuryCapManager.id),
            ETREASURY_CAP_MANAGER_DESTROYED,
        );
        let mut mergedCoins = coin::zero<CoinType>(ctx);
        pay::join_vec(&mut mergedCoins, coinList);
        let burningCoins = coin::split(&mut mergedCoins, amount, ctx);
        transfer::public_transfer(mergedCoins, ctx.sender());
        coin::burn(&mut treasuryCapManager.treasuryCap, burningCoins);
    }
}
