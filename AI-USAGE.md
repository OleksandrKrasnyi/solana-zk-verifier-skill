# AI usage

This skill was authored with **Claude Code** (Anthropic) — fittingly, since the artifact *is* a Claude
Code skill. Disclosure is at the project level (here), not per-commit.

## What that means concretely

- **Human-owned and reviewed.** The author (Oleksandr Krasnyi) owns the repository, reviewed every file,
  and is responsible for its claims.
- **Grounded in real work, not generated from nothing.** The technical content is distilled from the
  author's own Groth16 selective-disclosure verifier **deployed and verified on Solana devnet** (program
  [`EYxAVesH3Fwwemg2FXHcajsVuuQ3VW1xVEvevRsysZx8`](https://explorer.solana.com/address/EYxAVesH3Fwwemg2FXHcajsVuuQ3VW1xVEvevRsysZx8?cluster=devnet)),
  which verifies 11 circuits at 86k–121k CU. The code snippets are **generalized patterns**, not a copy
  of that project's source.
- **Verified, not asserted.** Crate names, versions, and APIs were cross-checked against a real compiling
  implementation (`groth16-solana 0.2`, `solana-bn254 2`, `arkworks 0.5`); upstream claims
  (`groth16-solana` audit lineage, version, circom/snarkjs compatibility) were checked against the
  source repository; unverifiable third-party claims (specific audit-firm names) were removed rather than
  guessed.

## Why disclose

The audience is ZK / Solana builders, where precision and provenance are reputational currency. Being
explicit about how this was made — and about its honest limits (see [`SECURITY.md`](./SECURITY.md)) — is
part of doing it well.
