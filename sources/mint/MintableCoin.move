module free_tunnel_sui::mintable_coin {

    use sui::coin::{Self, Coin};

    const DECIMALS: u8 = 9;
    const NAME: vector<u8> = b"Mintable Coin";
    const SYMBOL: vector<u8> = b"MTC";

    public struct MINTABLE_COIN has drop {}

    public struct TreasuryCapBox<phantom CoinType> has key, store {
        id: UID,
        treasuryCap: coin::TreasuryCap<CoinType>,
    }

    /**
     * @dev Can't pass more parameters to the init function. 
     *      See https://docs.sui.io/concepts/sui-move-concepts/init.
     */
    fun init(witness: MINTABLE_COIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness, DECIMALS, SYMBOL, NAME, b"", option::none(), ctx,
        );
        let treasuryBox = TreasuryCapBox {
            id: object::new(ctx),
            treasuryCap: treasury,
        };
        transfer::public_share_object(treasuryBox);
        transfer::public_freeze_object(metadata);
    }

    public(package) fun mintWithTreasuryBox<CoinType>(
        amount: u64,
        recipient: address,
        treasuryCapBox: &mut TreasuryCapBox<CoinType>,
        ctx: &mut TxContext,
    ) {
        coin::mint_and_transfer(&mut treasuryCapBox.treasuryCap, amount, recipient, ctx);
    }

    public(package) fun burnWithTreasuryBox<CoinType>(
        coin: Coin<CoinType>,
        treasuryCapBox: &mut TreasuryCapBox<CoinType>,
    ) {
        coin::burn(&mut treasuryCapBox.treasuryCap, coin);
    }
}
