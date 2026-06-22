# Embedding the verifying key & supporting many circuits

The verifying key (VK) is public, so you **embed it in the program** as a committed constant. Two things
must be true and stay true: (1) the embedded VK is exactly the one your prover's proving key came from,
and (2) when you have several circuits, a proof for one cannot pass as another.

## Embed the VK as committed bytes — generated, never hand-edited

Write a tiny `gen_vk` example that runs your circuit's setup under a **fixed seed**, serializes the VK
(`vk_to_solana`, see `proof-serialization.md`), and prints Rust source. Commit the output. It is a
generated artifact — regenerate it, don't edit it.

```rust
// examples/gen_vk.rs  →  cargo run --example gen_vk > src/vk.rs && cargo fmt
let mut rng = StdRng::seed_from_u64(VK_SETUP_SEED);   // ⚠ deterministic = NON-PRODUCTION (see below)
let (_pk, vk) = Groth16::<Bn254>::circuit_specific_setup(MyCircuit::setup_instance(), &mut rng)?;
let svk = vk_to_solana(&vk);
// print: pub const VK_ALPHA_G1: [u8; 64] = [..]; ... VK_IC: [[u8; 64]; N+1] = [..];
```

```rust
// src/vk.rs  (GENERATED — do not edit by hand)
pub const VK_NR_PUBINPUTS: usize = 5;            // cosmetic in 0.2 (verify reads vk_ic.len()); keep for clarity
pub const VK_ALPHA_G1: [u8; 64]  = [/* … */];
pub const VK_BETA_G2:  [u8; 128] = [/* … */];
pub const VK_GAMME_G2: [u8; 128] = [/* … */];    // sic: "gamme"
pub const VK_DELTA_G2: [u8; 128] = [/* … */];
pub const VK_IC: [[u8; 64]; 6]  = [/* ic[0] const term, then one per public input */];
```

### The borrow-vs-own lifetime detail

`Groth16Verifyingkey<'a>` does **not** own `vk_ic` — it holds `&'a [[u8; 64]]`. So the byte owner must
outlive the verifier. With embedded `const` bytes this is free: `&VK_IC` is `'static`.

```rust
fn my_vk() -> Groth16Verifyingkey<'static> {
    Groth16Verifyingkey {
        nr_pubinputs: vk::VK_NR_PUBINPUTS,
        vk_alpha_g1:  vk::VK_ALPHA_G1,
        vk_beta_g2:   vk::VK_BETA_G2,
        vk_gamme_g2:  vk::VK_GAMME_G2,   // sic
        vk_delta_g2:  vk::VK_DELTA_G2,
        vk_ic:        &vk::VK_IC,         // const → 'static borrow
    }
}
```

(If you ever build the VK at runtime from a `Vec`, keep the owner alive in the same scope — the borrow
checker will tell you, but the failure mode reads as a confusing lifetime error, not a crypto bug.)

## Pin the VK with a KAT test (catch drift before SBF)

The one invariant that makes the embedded bytes trustworthy: they equal what the canonical setup
produces. A regenerated circuit, a bumped dependency, or a fat-fingered edit all change the VK — and an
honest proof from the *new* setup would silently fail against the *old* committed VK. Pin it:

```rust
#[test]
fn vk_kat_matches_canonical_setup() {
    let mut rng = StdRng::seed_from_u64(VK_SETUP_SEED);
    let (_pk, vk) = Groth16::<Bn254>::circuit_specific_setup(MyCircuit::setup_instance(), &mut rng).unwrap();
    let svk = vk_to_solana(&vk);
    assert_eq!(svk.vk_alpha_g1, vk::VK_ALPHA_G1);
    assert_eq!(svk.vk_beta_g2,  vk::VK_BETA_G2);
    assert_eq!(svk.vk_gamme_g2, vk::VK_GAMME_G2);
    assert_eq!(svk.vk_delta_g2, vk::VK_DELTA_G2);
    assert_eq!(svk.vk_ic.as_slice(), vk::VK_IC.as_slice());
}
```

## ⚠ A deterministic seed is NOT a production trusted setup

`StdRng::seed_from_u64(...)` means the setup's **toxic waste is recoverable from your source** — anyone
with the seed can forge a proof for any statement. That is acceptable for **dev / devnet / CI / KATs**
and unacceptable for **mainnet value**. State it loudly in your `SECURITY.md`; the KAT test guards
against *drift*, not against this — it does not change the security model. The real fix is a ceremony →
`trusted-setup.md`.

## Many circuits: isolate by VK + arity, NOT by a `circuit_id`

The instinct is to add a `circuit_id` field and `match` on it. **Don't.** A separate VK already isolates
circuits cryptographically, on four independent layers:

1. **Distinct VK bytes** — a proof for circuit X fails the pairing under circuit Y's VK. This alone is
   sufficient; it holds even for two circuits with the **same number of public inputs**.
2. **Distinct arity `N`** — `Groth16Verifier::<N>` and the Anchor instruction's fixed-size
   `[[u8; 32]; N]` argument are different *types*; a proof of the wrong arity can't even be passed in.
3. **Root binding** — `require!(root_record.root == public_inputs[0])` scopes each proof to a root your
   registry trusts (next section).
4. **Thin per-circuit handler** — each handler hands its *own* VK to the shared core; there is no place
   for a mix-up.

A `circuit_id` field would add trust/attack surface (who validates it? what if it lies?) and buy nothing
that the VK doesn't already give you. Test the isolation explicitly: take two **same-arity** circuits and
assert each one's proof is **rejected** by the other's handler.

> **Account-stored / parameterized VK registry?** Tempting for "any circuit at runtime", but it doesn't
> even remove the per-`N` work (the const generic still forces a `match` on `public_inputs.len()`), and
> it adds a new question — who vouches for VK bytes a user uploads? Skip it until a concrete multi-tenant
> requirement forces it. Embedded, KAT-pinned VKs are the right default.

## The thin per-`N` handler pattern

Because `N` is a const generic (`groth16-on-solana.md`), one handler cannot serve variable `N`. Embrace
it: a **shared `verify_groth16::<N>` core** (the only crypto code) + **one thin wrapper per circuit**.
Adding a circuit then costs exactly: one `vk_X.rs` (generated) + one `vk_X_kat` test + one handler.

```rust
// circuit A: N = 5
pub fn verify_a(ctx: Context<Verify>, a:[u8;64], b:[u8;128], c:[u8;64], pi:[[u8;32]; 5]) -> Result<()> {
    require_root_active(&ctx.accounts.root_record, pi[0])?;
    verify_groth16::<5>(&a_vk(), &a, &b, &c, &pi)
}
// circuit B: N = 2 — different type, different VK, same reviewed core
pub fn verify_b(ctx: Context<Verify>, a:[u8;64], b:[u8;128], c:[u8;64], pi:[[u8;32]; 2]) -> Result<()> {
    require_root_active(&ctx.accounts.root_record, pi[0])?;
    verify_groth16::<2>(&b_vk(), &a, &b, &c, &pi)
}
```

## Authenticate the public inputs — verifying math is not verifying trust

A Groth16 proof says *"I know a witness such that the circuit is satisfied for these public inputs."* It
says **nothing** about whether those public inputs are ones you should accept. If
`public_inputs[0]` is a commitment **root** (a Merkle root the issuer signed, say), the proof proves
membership against *some* root — only your program can decide if *that* root is trusted.

So bind it. Keep a registry (a PDA per trusted root) and gate every verify on it:

```rust
fn require_root_active(root_record: &RootRecord, proven_root: [u8; 32]) -> Result<()> {
    require!(root_record.root == proven_root, MyError::RootNotRegistered); // the proven root is THIS record's
    require!(!root_record.revoked, MyError::RootRevoked);                  // and not revoked
    Ok(())
}
```

Two failure modes this closes, both real:

- **Forgot the equality.** If you load a `RootRecord` PDA but never check it equals `public_inputs[0]`,
  an attacker presents a proof valid for *their* root while pointing at *your* registered PDA. The math
  passes; the trust doesn't exist. The equality is load-bearing.
- **Forgot revocation on a new handler.** Centralize the check in one function and call it first in
  *every* handler. A new circuit that silently omits it accepts proofs against revoked roots. (See
  `limits-and-gotchas.md`.)
