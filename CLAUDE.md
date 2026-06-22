# Repo notes for Claude

This repository is a **Claude Code skill** for the [Solana AI Kit](https://github.com/solanabr/solana-ai-kit):
how to verify a custom Groth16/SNARK proof **on-chain** on Solana (`groth16-solana` / `alt_bn128`).

- **Canonical content** is `skill/SKILL.md` (the router) + the five focus `.md` files. `commands/` holds
  the guided walkthrough. There is no application code to build — it's documentation.
- **Editing guidance:** keep claims **precise and verifiable**. The narrow true claim is "the kit has no
  *custom on-chain proof-verification* skill"; the kit *does* have ZK-compression (Light), confidential
  transfers (Token-2022), and formal verification (qedgen) — route to them, don't overclaim.
- **No invented cryptography**; the skill composes audited primitives (`groth16-solana`, `solana-bn254`,
  `arkworks`) and says so.
- **devnet ≠ mainnet** and a deterministic-seed setup is **non-production** — preserve those caveats.
- **No private or real-case data** of any kind. Code snippets are generalized patterns, not anyone's
  proprietary source.
- License: **MIT**.
