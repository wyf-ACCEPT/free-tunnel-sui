module mint_manager::minter_manager {

    use sui::table;
    use sui::pay;
    use sui::coin::{Self, Coin, TreasuryCap};

    const ENOT_SUPER_ADMIN: u64 = 1;
    const ETREASURY_CAP_MANAGER_DESTROYED: u64 = 2;
    const EMINTER_REVOKED: u64 = 3;


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


    public entry fun transferAdmin<CoinType>(
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        newAdmin: address,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_SUPER_ADMIN);
        treasuryCapManager.admin = newAdmin;
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
        transfer::public_share_object(treasuryCapManager);
    }

    public entry fun destroyTreasuryCapManager<CoinType>(
        treasuryCapManager: TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_SUPER_ADMIN);
        let TreasuryCapManager<CoinType> {
            id, admin: _, treasuryCap, revokedMinters,
        } = treasuryCapManager;

        object::delete(id);
        table::drop(revokedMinters);
        transfer::public_transfer(treasuryCap, ctx.sender());
    }

    public entry fun issueMinterCap<CoinType>(
        recipient: address,
        treasuryCapManager: &TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_SUPER_ADMIN);
        let minterCap = MinterCap<CoinType> {
            id: object::new(ctx),
            managerId: object::uid_to_inner(&treasuryCapManager.id),
        };
        transfer::public_transfer(minterCap, recipient);
    }

    public entry fun revokeMinterCap<CoinType>(
        minterCap: &MinterCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.admin, ENOT_SUPER_ADMIN);
        treasuryCapManager.revokedMinters.add(object::uid_to_inner(&minterCap.id), true);
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
