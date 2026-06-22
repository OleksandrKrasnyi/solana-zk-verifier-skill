# Proof & VK serialization: arkworks → `groth16-solana` bytes

This is where soundness silently dies. A wrong byte here does not crash — it makes the verifier
**reject a valid proof** or, worse, makes a tampered input *look* fine until it doesn't. Every rule
below is enforced by a test in a real verifier; treat them as load-bearing, not stylistic.

The target format is the one [`solana-bn254`]'s `alt_bn128_g1_decompress` / `alt_bn128_g2_decompress`
consume — **uncompressed, big-endian, coordinate-major**. arkworks' default is the opposite
(compressed, little-endian, with a flag byte). Four independent things differ; get any one wrong and
the pairing check fails silently.

## Rule 1 — Negate `A`, and ONLY `A`

`groth16-solana` checks a pairing **product that equals 1**, not the textbook
`e(A,B) == e(α,β)·e(Σ,γ)·e(C,δ)`. To move `e(A,B)` to the other side it expects you to submit `-A`,
because `e(-A, B) = e(A, B)⁻¹`. No verifying-key element is negated (the crate does not call
`prepare_verifying_key`); `B`, `C`, and all of α/β/γ/δ go as-is.

```rust
pub fn proof_to_solana(proof: &ark_groth16::Proof<Bn254>) -> SolanaProof {
    SolanaProof {
        proof_a: g1_be(&(-proof.a)),  // ← the negation. The ONLY one.
        proof_b: g2_be(&proof.b),     // as-is
        proof_c: g1_be(&proof.c),     // as-is
    }
}
```

> **Symptom if you get it wrong:** every honest proof is rejected, 100% of the time. Pin it with a
> direct regression test (`solana_path_rejects_unnegated_a`): feed the *un-negated* `A` and assert the
> verifier returns `Err`. It is the single likeliest mistake.

## Rule 2 — Serialize coordinates separately, UNCOMPRESSED

Do not `CanonicalSerialize` the affine point as a unit — that emits arkworks' compressed encoding with a
flag byte in the high bits, which corrupts the layout. Serialize `x` and `y` **independently** with
`Compress::No`, into fixed slices.

```rust
use ark_serialize::{CanonicalSerialize, Compress};

// G1 → 64 bytes big-endian. x → [..32], y → [32..]; reverse EACH 32-byte coordinate.
// For G1 there is no coordinate swap — x stays before y.
fn g1_be(p: &G1Affine) -> [u8; 64] {
    let mut le = [0u8; 64];
    p.x.serialize_with_mode(&mut le[..32], Compress::No).unwrap(); // exact-sized buffer
    p.y.serialize_with_mode(&mut le[32..], Compress::No).unwrap();
    convert_endianness::<32, 64>(&le) // reverse each 32-byte chunk → big-endian
}
```

## Rule 3 — The G2 `c0/c1` swap is hidden inside the chunk size

G2 coordinates are `Fq2 = c0 + c1·u`, i.e. two `Fq` (32 bytes LE each ⇒ 64 bytes per coordinate). The
alt_bn128 / EIP-197 convention stores them as **`c1‖c0`** (the conjugate order) and big-endian. You get
both at once by reversing each **64-byte half as a whole**:

```rust
use solana_bn254::compression::prelude::convert_endianness;

// G2 → 128 bytes. Reversing each 64-byte half SIMULTANEOUSLY (a) swaps c0/c1 and (b) converts to BE.
fn g2_be(p: &G2Affine) -> [u8; 128] {
    let mut le = [0u8; 128];
    p.x.serialize_with_mode(&mut le[..64],  Compress::No).unwrap();
    p.y.serialize_with_mode(&mut le[64..], Compress::No).unwrap();
    convert_endianness::<64, 128>(&le) // ← CHUNK SIZE 64, NOT 32
}
```

> **The footgun:** `convert_endianness::<32, 128>` also "looks like big-endian" and compiles fine — but
> it reverses 32-byte chunks, leaving `c0/c1` in arkworks order. The point is well-formed and on-curve;
> the proof just **silently fails to verify**. The chunk size *is* the c0/c1 swap. Pin G2 with a
> known-answer or, better, with the end-to-end honest-proof test (it exercises a real G2 `B`).

## Rule 4 — Don't hand-roll the byte reversal

`convert_endianness` is `solana-bn254`'s own helper — the *same library* whose verifier consumes the
result. Use it. A hand-written `bytes.reverse()` is one off-by-one away from a soundness bug and gains
you nothing. Single-source the audited code path.

## Rule 5 — Public inputs: big-endian, in the circuit's exact order

Each public input is a field element serialized **big-endian**, and the **order must match your
circuit's public-input vector** (the order `gamma_abc_g1`/`vk_ic` was generated against). `vk_ic[0]` is
the constant term; `vk_ic[i+1]` is paired with public input `i`.

```rust
fn fr_be(x: &Fr) -> [u8; 32] {
    let mut le = [0u8; 32];
    x.serialize_with_mode(&mut le[..], Compress::No).unwrap(); // canonical (LE) integer
    convert_endianness::<32, 32>(&le)                          // → big-endian; verifier checks `< r`
}

// N inferred from the array → the call site is checked against Groth16Verifier::<N>.
pub fn public_inputs_to_solana<const N: usize>(inputs: &[Fr; N]) -> [[u8; 32]; N] {
    inputs.map(|fr| fr_be(&fr))
}
```

Build this array from your circuit's own `to_vec()` / public-input accessor — **never assemble it by
hand at the call site**. A swapped or reordered input means the verifier computes its linear
combination against the wrong scalars: silent corruption, not an error. Convention that pays off later:
make `public_inputs[0]` your commitment **root**, so the on-chain handler can authenticate it
(`verifying-key.md`).

**KAT to pin endianness by eye:** `Fr(20210301)` (a `YYYYMMDD` date) is `0x0134627D`, so its big-endian
32 bytes are 28 zeros followed by `01 34 62 7D`. A one-line assert that catches an endianness flip
without needing a full proof.

## Rule 6 — The arkworks 0.4 / 0.5 version boundary is fine (it's bytes)

`groth16-solana 0.2` pulls `ark-bn254 0.5`; `solana-bn254`'s host branch pulls `ark-bn254 0.4`. They
coexist in `Cargo.lock` without conflict because **the boundary between your code and the verifier is
`[u8; …]`**, and the *uncompressed* BN254 point layout (x‖y by coordinate) is identical across 0.4/0.5.
Don't fight the duplicate dep — the round-trip test confirms the bytes match empirically.

## Rule 7 — The VK serializes by the same rules (and the field is misspelled)

The verifying key uses the same `g1_be` / `g2_be`; nothing is negated. One quirk: the crate's struct
field for γ is spelled **`vk_gamme_g2`** (a typo baked into the public API). Use it verbatim.

```rust
// vk_ic = gamma_abc_g1, SAME order: ic[0] constant term, ic[i+1] ↔ public input i.
pub fn vk_to_solana(vk: &VerifyingKey<Bn254>) -> SolanaVerifyingKey {
    SolanaVerifyingKey {
        vk_alpha_g1: g1_be(&vk.alpha_g1),
        vk_beta_g2:  g2_be(&vk.beta_g2),
        vk_gamme_g2: g2_be(&vk.gamma_g2),   // ← sic: "gamme"
        vk_delta_g2: g2_be(&vk.delta_g2),
        vk_ic: vk.gamma_abc_g1.iter().map(g1_be).collect(),
    }
}
```

(How those bytes become a committed on-chain constant, and the borrow-vs-own lifetime detail of
`Groth16Verifyingkey`, are in `verifying-key.md`.)

## Test it like it's load-bearing (because it is)

One honest-proof round-trip validates **all six rules at once** (A negation, G1/G2 endianness, the
c0/c1 order, uncompressed layout, the `vk_ic` mapping, BE public inputs). Add the adversarial cases —
each must `Err`, none may panic:

- **un-negated `A`** → reject (Rule 1 regression);
- **one flipped byte** in each of `proof_a` / `proof_b` / `proof_c` → reject;
- **one flipped low byte** in each public input (stays `< r`, so it reaches the pairing) → reject;
- a **semantically swapped** revealed input (e.g. a different claimed value) → reject;
- a **zero `proof_a`** (`[0; 64]`, the point at infinity) → reject **without panic**;
- **decision cross-check**: for several (seed, witness) pairs, `Groth16::verify` (arkworks) and the
  `groth16-solana` path return the *same* accept/reject decision.

The cross-check is the one that matters most: it is the difference between "my serializer is
self-consistent" and "my serializer agrees with an independent verifier."

[`solana-bn254`]: https://docs.rs/solana-bn254
