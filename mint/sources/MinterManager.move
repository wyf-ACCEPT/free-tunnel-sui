module mint::minter_manager {

    use sui::table;
    use sui::pay;
    use sui::coin::{Self, Coin, TreasuryCap};

    const DECIMALS: u8 = 18;
    const NAME: vector<u8> = b"Coin Name";
    const SYMBOL: vector<u8> = b"SYMBOL";

    const ENOT_SUPER_ADMIN: u64 = 1;
    const ETREASURY_CAP_MANAGER_DESTROYED: u64 = 2;
    const EMINTER_REVOKED: u64 = 3;


    public struct MINTER_MANAGER has drop {}

    public struct TreasuryCapManager<phantom CoinType> has key, store {
        id: UID,
        superAdmin: address,
        treasuryCap: TreasuryCap<CoinType>,
        revokedMinters: table::Table<ID, bool>,
    }

    public struct MinterCap<phantom CoinType> has key, store {
        id: UID,
        managerId: ID,
    }


    fun init(witness: MINTER_MANAGER, ctx: &mut TxContext) {
        let (treasuryCap, metadata) = coin::create_currency(
            witness, DECIMALS, SYMBOL, NAME, b"", option::none(), ctx,
        );
        transfer::public_freeze_object(metadata);

        setupTreasuryCapManager(ctx.sender(), treasuryCap, ctx);
    }


    // ===================== Treasury Cap Management =====================
    public entry fun setupTreasuryCapManager<CoinType>(
        superAdmin: address,
        treasuryCap: TreasuryCap<CoinType>,
        ctx: &mut TxContext,
    ) {
        let treasuryCapManager = TreasuryCapManager<CoinType> {
            id: object::new(ctx),
            superAdmin,
            treasuryCap,
            revokedMinters: table::new(ctx),
        };
        transfer::public_share_object(treasuryCapManager);
    }

    public entry fun destroyTreasuryCapManager<CoinType>(
        treasuryCapManager: TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
        let TreasuryCapManager<CoinType> {
            id, superAdmin: _, treasuryCap, revokedMinters,
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
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
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
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
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
