// module free_tunnel_sui::mintable_coin {
//     use sui::coin;

//     const INITIAL_SUPPLY: u64 = 1000_000000;
//     const NAME: vector<u8> = b"Mintable Coin";
//     const SYMBOL: vector<u8> = b"MTC";

//     public struct MINTABLE_COIN has drop {}

//     fun init(witness: MINTABLE_COIN, ctx: &mut TxContext) {
//         // Process metadata
//         let (treasury, metadata) = coin::create_currency(
//             witness, 6, SYMBOL, NAME, b"", option::none(), ctx,
//         );
//         transfer::public_freeze_object(metadata);

//         // Mint initial supply
//         let mut treasury = treasury;
//         let coin = coin::mint(&mut treasury, INITIAL_SUPPLY, ctx);
//         transfer::public_transfer(coin, ctx.sender());

//         // Transfer treasury to the owner
//         transfer::public_transfer(treasury, ctx.sender());
//     }
// }