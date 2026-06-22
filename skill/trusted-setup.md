# Trusted setup: the honest version

Groth16 is succinct and cheap to verify (that's why it's great on Solana), but it has a price the other
files gloss over: a **circuit-specific trusted setup**. Setup produces a proving key and a verifying
key from secret randomness ("toxic waste", `τ, α, β, …`). **Anyone who knows that secret can forge a
proof for any statement.** Soundness depends entirely on the secret being destroyed.

## Deterministic seed = the secret is in your repo

The convenient dev pattern —

```rust
let mut rng = StdRng::seed_from_u64(VK_SETUP_SEED);
let (pk, vk) = Groth16::<Bn254>::circuit_specific_setup(MyCircuit::setup_instance(), &mut rng)?;
```

— means the toxic waste is **recoverable from the seed in your source**. This is:

- ✅ fine for **dev, devnet, CI, KAT vectors, and demos** (reproducible, reviewable, no ceremony needed);
- ❌ **not safe for mainnet value** — a deterministic seed is a public backdoor.

Say this plainly in `SECURITY.md`. The VK-KAT test (`verifying-key.md`) pins the VK against *drift*; it
does **not** make a seeded setup production-safe. Don't let a green test suite imply otherwise.

## What "production" means: a ceremony

The fix is a **multi-party computation (MPC) ceremony**: many participants each contribute randomness;
the setup is secure as long as **at least one** participant honestly destroys their share. It comes in
two phases:

- **Phase 1 — Powers of Tau (universal).** Curve-specific, circuit-independent. You can **reuse an
  existing public ceremony** instead of running your own — the PSE / Hermez "Perpetual Powers of Tau"
  for BN254 is the standard one (snarkjs `.ptau` files, many independent contributors).
- **Phase 2 — circuit-specific.** Specializes Phase-1 output to *your* circuit's constraint system.
  This one you (or a service) must run for each circuit.

## Ingesting & checking a Phase-1 `.ptau` (and the Montgomery shortcut)

You can parse a snarkjs `.ptau` directly into arkworks types. The non-obvious part is the coordinate
encoding, and it happens to be a gift:

> snarkjs stores each `Fq` coordinate as **32 bytes, little-endian, in Montgomery form** (`a·R mod q`,
> `R = 2²⁵⁶`). arkworks' BN254 `Fq` stores its internal `BigInt` in the **same** `R = 2²⁵⁶` Montgomery
> form. So those bytes *are* arkworks' internal limbs — `Fq::new_unchecked(BigInt(limbs))` adopts them
> with **no conversion**. Range-check `< q` first (untrusted input), then adopt.

```rust
fn read_fq(buf: &[u8; 32]) -> Result<Fq, PtauError> {
    let mut limbs = [0u64; 4];
    for (i, l) in limbs.iter_mut().enumerate() {
        *l = u64::from_le_bytes(buf[i*8..i*8+8].try_into().unwrap());
    }
    let bi = BigInt::<4>::new(limbs);
    if bi >= Fq::MODULUS { return Err(PtauError::CoordNotReduced); } // canonical residue only
    Ok(Fq::new_unchecked(bi))
}
```

**This is fail-safe by construction:** the reader does no cryptographic trust on its own; every point it
produces is re-checked (on-curve, prime-order subgroup) by a structural `verify()`. A decoding bug
yields off-curve points that `verify()` **rejects** — it can never silently mint a usable-but-wrong SRS.

What a structural `verify()` checks (pairing equations): the `τ`-ladders are consistent
(`e(τⁱ⁺¹·G1, G2) == e(τⁱ·G1, τ·G2)`), G1 and G2 agree on `τ`, the `α/β` ladders are consistent, and —
**load-bearing** — every G2 point is in the prime-order subgroup (G2 has a non-trivial cofactor). It
validated end-to-end against a real `powersOfTau28_hez_final_08.ptau`.

> **Honesty:** `verify()` proves the transcript is **structurally well-formed**, NOT that any participant
> was honest / actually destroyed their secret. Multi-party honesty comes from the ceremony's social
> process (public participation, attestations), not from your parser.

## The Phase-2 gap (read before you plan a mainnet launch)

There is, as of mid-2026, **no turnkey arkworks-native BN254 Phase-2 tool**:

- `ark-groth16 0.5`'s parameter generator **samples `τ` in the clear** — it has no hook to consume
  external Powers-of-Tau, so you can't just "feed it" a Phase-1 transcript.
- snarkjs's mature Phase-2 is **circom-format** (R1CS from circom), not an arkworks
  `ConstraintSynthesizer`.
- Celo's `snark-setup` is on the `zexe` fork (BLS12-377/381/BW6-761 — **no BN254**); aleo-setup targets
  Aleo curves.

So "consume Phase-1 into an arkworks circuit" is **novel, security-critical MPC code** — not something
to hand-roll for mainnet without expert review and audit. Two honest paths:

1. **Express the circuit in circom**, use snarkjs's Phase-2 over a public Powers-of-Tau ceremony, and
   verify the resulting proof with `groth16-solana` (it is circom/snarkjs-compatible). Most mature route
   to a credible mainnet setup today.
2. **Commission or run an audited arkworks Phase-2** if you must stay in arkworks. Treat it as a
   crypto-engineering project, not a config change.

For dev and devnet, the deterministic seed plus a loud caveat is the right amount of effort. Escalate to
a ceremony **before** the verifier guards anything of value — and tell your users which regime you're in.
