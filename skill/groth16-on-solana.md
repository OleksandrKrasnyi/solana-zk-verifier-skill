# Verifying Groth16 on Solana with `groth16-solana`

## The crate and the syscalls

Solana exposes BN254 (alt_bn128) pairing as runtime **syscalls**:
`sol_alt_bn128_group_op` (addition, scalar multiplication) and `sol_alt_bn128_pairing`. You almost
never call these directly — you use [`groth16-solana`] (Light Protocol), which implements the Groth16
verification equation on top of them.

```toml
# Cargo.toml — pin exact versions (a verifier is security-critical; do not float).
[dependencies]
groth16-solana = "0.2.0"          # the on-chain verifier (alt_bn128)
solana-bn254  = "2"               # syscall wrappers + convert_endianness + a host impl (see "testing")

[dev-dependencies]
ark-bn254     = "0.5"             # off-chain: your circuit, proving, the source-of-truth VK
ark-groth16   = "0.5"
ark-serialize = "0.5"
```

> **Audit lineage, stated honestly.** `groth16-solana`'s verifier was audited during the **Light
> Protocol v3 audit**, which covered crate release **0.0.1** (the report is linked from the crate's
> repository). That is *lineage*, not a standalone report for the exact `0.2.0` you pin. Before
> mainnet: pin the version, record the crate checksum, and diff `groth16.rs` against the audited
> revision. (See `trusted-setup.md` — the verifier is rarely your weakest link; the setup is.)

## The verifier is const-generic over the public-input count

```rust
use groth16_solana::groth16::{Groth16Verifier, Groth16Verifyingkey};
use groth16_solana::errors::Groth16Error;

// `N` = number of public inputs. It is a CONST GENERIC: a 2-input verifier and a 5-input verifier
// are different types. `new()` enforces `public_inputs.len() + 1 == vk_ic.len()` — a VK of the wrong
// arity is rejected at construction (vk_ic = gamma_abc_g1, one IC term per input plus the constant).
let mut verifier = Groth16Verifier::<N>::new(
    &proof_a,        // &[u8; 64]  — G1, NEGATED, big-endian (see proof-serialization.md)
    &proof_b,        // &[u8; 128] — G2, big-endian, c0/c1 in alt_bn128 order
    &proof_c,        // &[u8; 64]  — G1, big-endian
    &public_inputs,  // &[[u8; 32]; N] — each a big-endian field element
    &vk,             // &Groth16Verifyingkey — borrows vk_ic (see verifying-key.md)
)?;
verifier.verify()?; // Ok(()) = accepted; Err(Groth16Error::ProofVerificationFailed) = rejected
```

This const-generic `N` is the single most load-bearing design fact for a multi-circuit program: it
**forces** a per-`N` instruction handler. See `verifying-key.md` for the thin-handler pattern.

## The one verify core you should write (no-panic, generic over `N`)

Centralize the crypto in exactly one reviewed function. Every predicate/circuit calls it; nothing else
touches `Groth16Verifier`.

```rust
use anchor_lang::prelude::*;

/// The SINGLE Groth16 verify path. An `Err` here means "proof rejected", never a program panic.
fn verify_groth16<const N: usize>(
    vk: &Groth16Verifyingkey<'_>,
    proof_a: &[u8; 64],
    proof_b: &[u8; 128],
    proof_c: &[u8; 64],
    public_inputs: &[[u8; 32]; N],
) -> Result<()> {
    let mut verifier = Groth16Verifier::<N>::new(proof_a, proof_b, proof_c, public_inputs, vk)
        .map_err(map_groth16_err)?;
    verifier.verify().map_err(map_groth16_err)?;
    Ok(())
}

/// Map the crate error to YOUR program error. A rejected proof must be an ordinary `Err`, not a panic
/// or an `unwrap()` — a verifier that can panic on a crafted input is a DoS (and worse).
fn map_groth16_err(e: Groth16Error) -> Error {
    match e {
        Groth16Error::ProofVerificationFailed => error!(MyError::ProofRejected),
        Groth16Error::PublicInputGreaterThanFieldSize => error!(MyError::PublicInputOutOfField),
        _ => error!(MyError::VerifierInputInvalid), // length/decompression — invalid input, not a failure
    }
}
```

Then a handler is three lines: authenticate the inputs, call the core. (Input authentication —
binding `public_inputs[0]` to a root your program trusts — is in `verifying-key.md`; skipping it is the
classic "I verified a proof but for a statement I never authorized" bug.)

```rust
pub fn verify_my_proof(
    ctx: Context<VerifyProof>,
    proof_a: [u8; 64], proof_b: [u8; 128], proof_c: [u8; 64],
    public_inputs: [[u8; 32]; N],   // N is a concrete number here, e.g. 5
) -> Result<()> {
    require_root_active(&ctx.accounts.root_record, public_inputs[0])?; // authenticate the statement
    verify_groth16::<N>(&my_vk(), &proof_a, &proof_b, &proof_c, &public_inputs) // then the math
}
```

## CHECK, don't reach for `unchecked`

`new()` (the checked path) validates that each public input is `< r` (the field size) and that points
decompress. There is an `*_unchecked` temptation in the BN254 ecosystem "for performance". **You do not
need it here** — the checked verify of a real selective-disclosure proof measures **86k–121k CU**
(across arities N=2…8), comfortably inside the 200K per-instruction budget (`limits-and-gotchas.md`).
Skipping field-size checks on attacker-supplied public inputs trades a soundness guard for CU you have
to spare. Don't.

## Why you can test the REAL verifier on the host (the keystone)

You do **not** need a validator, SBF build, or devnet to know your bytes are right. `solana-bn254`
ships a **native arkworks implementation** of altbn254 under `cfg(not(target_os = "solana"))`. So the
*exact same* `groth16_solana::Groth16Verifier::verify()` runs in a plain `cargo test` on your laptop —
on the host it uses arkworks pairings, on SBF it uses the syscalls, **same API, same bytes**.

This is what lets you close serialization correctness *before* touching the chain:

```rust
#[test]
fn honest_proof_verifies_through_the_real_verifier() {
    let (vk, proof, public) = setup_and_prove();          // your circuit, off-chain
    let (pa, pb, pc) = proof_to_solana(&proof);            // proof-serialization.md
    let inputs = public_inputs_to_solana(&public);         // [[u8;32]; N], big-endian
    let svk = vk_to_solana(&vk);                            // embedded-VK bytes

    let mut v = Groth16Verifier::<N>::new(&pa, &pb, &pc, &inputs, &svk.as_borrow()).unwrap();
    assert!(v.verify().is_ok(), "an honest proof must pass the real groth16-solana verifier");
}
```

Pair it with a **decision cross-check**: assert the native arkworks verifier (`Groth16::verify`) and
the `groth16-solana` path *agree* — both accept the honest proof and both reject a tampered one. A
round-trip that only checks "my bridge agrees with itself" will happily pass while being wrong; the
cross-check against an independent verifier is what catches a silent format bug. (Details and the full
adversarial battery are in `proof-serialization.md`.)

## On-chain vs host: nothing changes but the backend

When you `anchor build` / `cargo build-sbf`, the same `verify_groth16::<N>` compiles to the syscall
backend automatically (the `cfg(target_os = "solana")` branch of `solana-bn254`). You write and review
one code path; the host tests exercise the real arithmetic; SBF swaps in the syscalls. That property is
the whole reason this is pleasant to work with — lean on it.

[`groth16-solana`]: https://github.com/Lightprotocol/groth16-solana
