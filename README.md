# Free Tunnel (Atomic-Lock-Mint) for Sui



## Instructions

1. The project team uses the provided `demo/MintManager.move` to develop their own package.
2. The project team provides us with their code repository. We need to add their repository as a dependency to build the `free_tunnel_sui` package.
3. The project team deploys `mint_manager` and provides us with the deployed package ID, which also needs to be included in our package.
4. We build the project and deploy `atomic_lock` or `atomic_mint`.
5. We call `addToken` to add the project team's coin information.
6. The project team calls `transferCap` to transfer the `minterCap` to `free_tunnel_sui`.