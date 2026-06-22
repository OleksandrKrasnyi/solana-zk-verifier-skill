# /verify-zk-proof — integrate an on-chain Groth16 verify end-to-end

Guided walkthrough for wiring a custom zero-knowledge proof verification into a Solana program. Use this
when the user wants to verify a Groth16/SNARK proof they generated off-chain (arkworks or snarkjs) inside
their own program. Load the `solana-zk-verifier` skill's focus files as you go — read only what each step
needs.

## Step 0 — Confirm this is the right tool

Ask what the user actually needs. If it's compressed accounts/tokens → Light Protocol; hidden token
balances → Token-2022; proving program logic correct → qedgen. Only continue if they have (or will
write) **their own circuit** and must verify **its** proof on-chain. (Router: `skill/SKILL.md`.)

## Step 1 — Dependencies & the verify core

Add `groth16-solana = "0.2.0"` and `solana-bn254 = "2"`; dev-deps `ark-bn254`/`ark-groth16`/`ark-serialize`
at `0.5`. Write the single no-panic `verify_groth16::<N>` core and the `map_groth16_err` mapper. Confirm
`N` (the public-input count) for the circuit. → `skill/groth16-on-solana.md`.

## Step 2 — Serialize correctly (do this with a test, not by hope)

Implement `proof_to_solana` / `vk_to_solana` / `public_inputs_to_solana`. Enforce: **negate `A` only**;
serialize coordinates **uncompressed**; G2 uses `convert_endianness::<64,128>` (the **c0/c1 swap** — chunk
size 64, not 32); public inputs big-endian, in the circuit's exact order with `public_inputs[0]` = the
commitment root. → `skill/proof-serialization.md`. Then write the **keystone test**: an honest proof
through the bridge passes the *real* `groth16-solana` verifier on the host, and its decision matches the
arkworks verifier on accept *and* reject. Add the adversarial cases (un-negated A, flipped bytes, swapped
input, zero `proof_a`) — each must `Err`, none may panic.

## Step 3 — Embed & pin the verifying key

Generate the VK under a fixed seed, commit it as `const` bytes, assemble it with the `vk_gamme_g2` (sic)
field, and add the **VK-KAT test** that re-derives it from the seed and asserts byte-equality. For
multiple circuits, isolate by **VK + arity** (a separate VK + a thin per-`N` handler) — do **not** add a
`circuit_id`. → `skill/verifying-key.md`.

## Step 4 — Authenticate the public inputs

The proof proves knowledge for *some* statement; your program must decide the statement is one it trusts.
Bind `public_inputs[0]` (the root) to a registered, non-revoked record (`require_root_active`), called
**first** in every handler. → `skill/verifying-key.md`.

## Step 5 — Measure the compute budget

Run the program in `litesvm`, read `compute_units_consumed`, assert `< 200_000`, and keep that assert in
CI. A real selective-disclosure verify lands at 86k–121k CU. If you find yourself wanting to do
elliptic-curve ops on a non-BN254 curve in-program, stop — that's the >10.7M-CU trap; wrap the statement
in Groth16 instead. → `skill/limits-and-gotchas.md`.

## Step 6 — Be honest about the trusted setup

If a deterministic seed is in use, tell the user it is **dev/devnet-only** and document it in
`SECURITY.md`. Before mainnet, plan a Powers-of-Tau ceremony (or use circom + snarkjs Phase-2). →
`skill/trusted-setup.md`.

## Done

The user should now have: a tested off-chain bridge, an embedded KAT-pinned VK, a thin per-`N` handler
that authenticates the root and calls the shared verify core, a CU regression test, and a clear note on
the setup's production status.
