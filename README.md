# Free Tunnel (Atomic-Lock-Mint) for Sui

## Roles

- **Project team**: Responsible for issuing and managing the token. They develop and deploy their own token management package.
- **Free team**: Operates the Free Tunnel, facilitating atomic lock and mint operations for cross-chain protocol interactions.

## Instructions

1. The Project team uses the provided `demo/MintManager.move` to develop their own package.
2. The Project team provides the Free team with their code repository. The Free team needs to add the Project team's repository as a dependency to build the `free_tunnel_sui` package.
3. The Project team deploys `mint_manager` and provides the Free team with the deployed package ID, which also needs to be included in the Free team's package.
4. The Free team builds the project and deploys `atomic_lock` or `atomic_mint`.
5. The Free team calls `addToken` to add the Project team's coin information.
6. The Project team calls `transferMinterCap` to transfer the `minterCap` to `free_tunnel_sui`.
