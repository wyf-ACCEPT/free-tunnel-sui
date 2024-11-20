module free_tunnel_sui::mintable_coin {
    use sui::coin;

    const DECIMALS: u8 = 9;
    const NAME: vector<u8> = b"Mintable Coin";
    const SYMBOL: vector<u8> = b"MTC";

    public struct MINTABLE_COIN has drop {}

    /**
     * @dev Can't pass more parameters to the init function. 
     *      See https://docs.sui.io/concepts/sui-move-concepts/init.
     */
    fun init(witness: MINTABLE_COIN, ctx: &mut TxContext) {
        let (treasury, metadata) = coin::create_currency(
            witness, DECIMALS, SYMBOL, NAME, b"", option::none(), ctx,
        );
        transfer::public_transfer(treasury, ctx.sender());
        transfer::public_freeze_object(metadata);
    }
}
