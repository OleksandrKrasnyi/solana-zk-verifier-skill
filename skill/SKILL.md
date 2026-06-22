---
name: solana-zk-verifier
description: Verify a custom zero-knowledge (Groth16/SNARK) proof ON-CHAIN inside a Solana program — the groth16-solana / alt_bn128 path. Use when serializing an arkworks or snarkjs proof for the chain, embedding a verifying key, ordering public inputs, isolating multiple circuits, fitting the compute budget, or deciding what an honest trusted setup means. Also routes ZK-compression → Light, confidential transfers → Token-2022, and formal verification → qedgen so you land in the right place.
user-invocable: true
---

# Verifying custom ZK proofs on-chain on Solana

This skill is about ONE thing the rest of the kit does not cover: taking a **custom Groth16 proof
you generated off-chain** (arkworks or snarkjs/circom) and **verifying it inside your own Solana
program** via the `alt_bn128` pairing syscalls (using the audited [`groth16-solana`] crate).

It is built from a real verifier deployed and verified on **Solana devnet** (program
`EYxAVesH3Fwwemg2FXHcajsVuuQ3VW1xVEvevRsysZx8`), where the same patterns verify 11 distinct
selective-disclosure circuits at **86k–121k compute units** each. Every gotcha below is one that
silently broke a real verifier first.

## First: are you in the right place? (ZK-on-Solana router)

"ZK on Solana" means several unrelated things. Pick the row that matches your goal — **read only
what you need**:

| Your goal | Use | Not this skill |
|---|---|---|
| Compress accounts / mint compressed tokens (state compression, validity proofs handled for you) | **Light Protocol / ZK Compression** → `ext/sendai` (`light-protocol`) | ✗ |
| Hide token **balances/amounts** (encrypted SPL balances, transfers) | **Token-2022 confidential transfers** → `token-2022.md` | ✗ |
| **Formally prove** your program logic is correct (Lean / specs / Kani) | **qedgen** → `ext/qedgen` | ✗ |
| **Verify a custom Groth16/SNARK proof** in your program — membership, range, selective disclosure, validity of an off-chain computation, a zkVM proof (SP1/Risc0 wrapped in Groth16) | **→ THIS skill** | |

> The first three already exist in the kit and use ZK *for you*. This skill is for when **you wrote
> the circuit** and must verify its proof on-chain yourself. If you only need one of the first three,
> stop here and go there — don't hand-roll a verifier.

## The end-to-end flow (and which focus file covers each step)

```
off-chain (host)                                          on-chain (your Solana program)
─────────────────                                         ──────────────────────────────
1. circuit + trusted setup  ── pk, vk ──┐
   trusted-setup.md                     │
2. prove(pk, witness)  ── proof, public_inputs ──┐       4. embed vk as a const           verifying-key.md
                                                  │       5. Groth16Verifier::<N>::verify   groth16-on-solana.md
3. serialize proof+vk+inputs → groth16-solana bytes       6. fits in <200K CU?              limits-and-gotchas.md
   proof-serialization.md  ───────────────────────────►  (proof_a/b/c + public_inputs in the instruction)
```

Read in this order for a first integration:

1. **`groth16-on-solana.md`** — the crate, the `alt_bn128` syscalls, the const-generic
   `Groth16Verifier<N>`, the verify call, and the trick that lets you test the *real* verifier on the
   host (no validator) in `cargo test`.
2. **`proof-serialization.md`** — the byte layer where soundness silently dies: **negate `A` only**,
   serialize coordinates **uncompressed**, the **G2 c0/c1 swap**, big-endian everything, and the exact
   **public-input order**. Most "valid proof rejected" / "wrong proof accepted" bugs live here.
3. **`verifying-key.md`** — embedding the VK as committed bytes, pinning it with a **VK-KAT** test, and
   isolating **multiple circuits** by VK + arity (no `circuit_id` field needed) with a thin per-`N` handler.
4. **`limits-and-gotchas.md`** — the **compute-budget reality** (measured CU), the **>10.7M-CU finding**
   when you try to do elliptic-curve ops *natively* on a non-syscall curve (and the Groth16-wrap fix),
   subgroup-check footguns, and measuring CU with `litesvm`.
5. **`trusted-setup.md`** — the part everyone fakes: a **deterministic seed is NOT production** (the
   toxic waste is in your source). What a Powers-of-Tau ceremony actually is, how to ingest/verify a
   `.ptau`, and why "Phase-2 over arkworks BN254" has no turnkey tool today.

## The 60-second mental model

Groth16 verification is one pairing equation. `groth16-solana` checks
`e(A,B) · e(α,β)⁻¹ · e(Σ inputᵢ·ICᵢ, γ)⁻¹ · e(C,δ)⁻¹ == 1` using three `alt_bn128` syscalls
(`*_addition`, `*_multiplication`, `*_pairing`). Your job is three things, and that's it:

1. **Get the bytes exactly right** (the crate's format ≠ arkworks' default format). → `proof-serialization.md`
2. **Hand it the right verifying key** for the right number of public inputs. → `verifying-key.md`
3. **Authenticate the public inputs** — the proof says "I know a witness for *some* root"; only your
   program knows whether *that root* is one you trust. A verifier that skips this verifies math, not
   trust. → `verifying-key.md` (root/registry binding)

## Honesty (this skill's audience is ZK/Solana builders — claims are precise)

- This skill **composes audited primitives** (`groth16-solana`, `solana-bn254`, `arkworks`). It does
  **not** invent cryptography, and you should not either.
- **devnet ≠ mainnet.** A deterministic-seed setup is fine for dev and is **not safe for mainnet** —
  see `trusted-setup.md`. The skill says so loudly rather than hiding it.
- Groth16 needs a **circuit-specific trusted setup**. If that scares you (it should, a little), read
  `trusted-setup.md` before you ship value.

## References (pin versions in your `Cargo.toml`)

- [`groth16-solana`] (Light Protocol) — the on-chain verifier. `alt_bn128` syscalls; audit lineage
  from the Light Protocol v3 audits. Note the public field is misspelled `vk_gamme_g2`.
- `solana-bn254` — the syscall wrappers + `convert_endianness`; ships a **native** altbn254 impl under
  `cfg(not(target_os = "solana"))` so the verifier runs on the host.
- `arkworks` (`ark-groth16`, `ark-bn254`, `ark-r1cs-std`) — circuits, proving, the off-chain VK.

[`groth16-solana`]: https://github.com/Lightprotocol/groth16-solana
