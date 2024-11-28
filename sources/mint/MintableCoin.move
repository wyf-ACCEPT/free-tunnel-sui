module free_tunnel_sui::mintable_coin {

    use sui::table;
    use sui::pay;
    use sui::coin::{Self, Coin, TreasuryCap};

    const DECIMALS: u8 = 9;
    const NAME: vector<u8> = b"Mintable Coin";
    const SYMBOL: vector<u8> = b"MTC";

    const ENOT_SUPER_ADMIN: u64 = 150;
    const ESUBCAP_MISMATCH: u64 = 151;
    const EMINTER_REVOKED: u64 = 152;


    public struct MINTABLE_COIN has drop {}

    public struct TreasuryCapManager<phantom CoinType> has key, store {
        id: UID,
        superAdmin: address,
        treasuryCap: TreasuryCap<CoinType>,
        revokedCapList: table::Table<ID, bool>,
    }

    public struct SubTreasuryCap<phantom CoinType> has key, store { 
        id: UID,
        parentId: ID,
    }

    /**
     * @dev Can't pass more parameters to the init function. 
     *      See https://docs.sui.io/concepts/sui-move-concepts/init.
     */
    fun init(witness: MINTABLE_COIN, ctx: &mut TxContext) {
        let (treasuryCap, metadata) = coin::create_currency(
            witness, DECIMALS, SYMBOL, NAME, b"", option::none(), ctx,
        );
        transfer::public_transfer(treasuryCap, ctx.sender());
        transfer::public_freeze_object(metadata);
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
            revokedCapList: table::new(ctx),
        };
        transfer::public_share_object(treasuryCapManager);
    }

    public entry fun destroyTreasuryCapManager<CoinType>(
        treasuryCapManager: TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
        let TreasuryCapManager<CoinType> {
            id, superAdmin: _, treasuryCap, revokedCapList,
        } = treasuryCapManager;

        object::delete(id);
        table::drop(revokedCapList);
        transfer::public_transfer(treasuryCap, ctx.sender());
    }

    public entry fun grantSubTreasuryCap<CoinType>(
        minter: address,
        treasuryCapManager: &TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
        let subTreasuryCap = SubTreasuryCap<CoinType> {
            id: object::new(ctx),
            parentId: object::uid_to_inner(&treasuryCapManager.id),
        };
        transfer::public_transfer(subTreasuryCap, minter);
    }

    public entry fun revokeSubTreasuryCap<CoinType>(
        subTreasuryCap: &SubTreasuryCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(ctx.sender() == treasuryCapManager.superAdmin, ENOT_SUPER_ADMIN);
        treasuryCapManager.revokedCapList.add(object::uid_to_inner(&subTreasuryCap.id), true);
    }

    public entry fun mint<CoinType>(
        amount: u64,
        recipient: address,
        subTreasuryCap: &mut SubTreasuryCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(
            !treasuryCapManager.revokedCapList.contains(object::uid_to_inner(&subTreasuryCap.id)),
            EMINTER_REVOKED,
        );
        assert!(
            subTreasuryCap.parentId == object::uid_to_inner(&treasuryCapManager.id),
            ESUBCAP_MISMATCH,
        );
        coin::mint_and_transfer(&mut treasuryCapManager.treasuryCap, amount, recipient, ctx);
    }

    public entry fun burn<CoinType>(
        amount: u64,
        coinList: vector<Coin<CoinType>>,
        subTreasuryCap: &mut SubTreasuryCap<CoinType>,
        treasuryCapManager: &mut TreasuryCapManager<CoinType>,
        ctx: &mut TxContext,
    ) {
        assert!(
            !treasuryCapManager.revokedCapList.contains(object::uid_to_inner(&subTreasuryCap.id)),
            EMINTER_REVOKED,
        );
        assert!(
            subTreasuryCap.parentId == object::uid_to_inner(&treasuryCapManager.id),
            ESUBCAP_MISMATCH,
        );
        let mut coinMerged = coin::zero<CoinType>(ctx);
        pay::join_vec(&mut coinMerged, coinList);
        let coinObject = coin::split(&mut coinMerged, amount, ctx);
        transfer::public_transfer(coinMerged, ctx.sender());
        coin::burn(&mut treasuryCapManager.treasuryCap, coinObject);
    }

}
