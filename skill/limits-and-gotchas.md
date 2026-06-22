# Compute budget, limits & the gotchas that cost real CU

The unique value of this file: numbers and failures from a **real deployed verifier**, not estimates.

## The compute budget — and where Groth16 verify actually lands

Each Solana instruction starts with a **200,000 CU** budget (raisable per-transaction up to **1.4M**
via `ComputeBudgetInstruction::set_compute_unit_limit`). Heap is **32 KB** by default, raisable to
**256 KB** (the hard max) via `request_heap_frame`.

A full Groth16 selective-disclosure verify via the `alt_bn128` syscalls measures, across arities
`N = 2…8`:

| Circuit (public inputs `N`) | CU |
|---|---|
| age / equality (N=2) | ~86k |
| capture-window (N=3) | ~92k |
| employment (N=4) | ~98k |
| membership / exclusion (N=5) | ~104k |
| escrow (N=7) | ~115k |
| multi-field (N=8) | ~121k |

So a single verify fits comfortably in the default 200K — you do **not** need to raise the limit for one
proof, and you have room for your own account logic around it. CU grows mildly with `N` (more `vk_ic`
scalar-muls). Two verifies in one instruction would still fit under the raised 1.4M ceiling, but you'd
typically raise the limit explicitly and measure.

## The big one: native curve ops on a non-syscall curve are ~100× too expensive

Solana has a pairing/group-op syscall for **exactly one** curve: BN254 (`alt_bn128`). That's why
Groth16-over-BN254 is cheap. The moment you need elliptic-curve arithmetic on **any other** curve —
including an *embedded* curve like `ed_on_bn254` (a JubJub-family curve, used for in-circuit ElGamal /
Pedersen) — there is **no syscall**, so it runs as pure software in SBF.

A measured spike: verifying a single Chaum–Pedersen DLEQ (a Sigma proof, ~4 scalar multiplications on
`ed_on_bn254`) **natively in the program** consumed **>10,700,000 CU** *and* hit heap-OOM at the 256 KB
maximum — before finishing — even with the compute ceiling raised to 50M. One scalar-mul is ~3M CU in
software; fixed-base / MSM tricks shave 25–40%, nowhere near closing a 7.7× gap over even the 1.4M
per-instruction limit, and they don't address the heap wall at all.

**The fix that worked: wrap the statement in Groth16.** Express the curve relation (`pk = sk·G`,
`d = sk·c1`, …) as R1CS constraints with arkworks' `EdwardsVar` gadget, prove it off-chain, and verify
*that* Groth16 proof via the `alt_bn128` syscall path you already have. Same statement, **~106k CU**
instead of >10.7M.

> **Rule of thumb:** if an on-chain operation isn't BN254 pairing/group-ops, assume doing it *natively*
> in your program is infeasible on CU, and reach for "prove it off-chain, verify the Groth16 wrap
> on-chain" instead. The syscall is the only cheap curve in town.

## Subgroup-check footgun on cofactor > 1 curves

`groth16-solana` does its own field-size and on-curve checks on the proof/VK points (BN254). The trap is
in **your protocol's** points: if your circuit or instruction consumes an *untrusted* point on a curve
with **cofactor > 1** — `ed_on_bn254` has cofactor 8 — an attacker can submit a **small-order** point.
Pairing/encryption with it can leak `secret mod cofactor` (e.g. `sk mod 8`), one careful query at a time.

Defence: **check prime-order subgroup membership** of every externally-supplied curve point before using
it (in-circuit, or on-chain if the point is an instruction argument — but note an on-chain `ed_on_bn254`
subgroup check is itself ~3M CU, so it's usually enforced in-circuit or by trusting an admin-validated
key). This was a real full-severity review finding; it does not apply to the BN254 proof points (the
crate guards those), only to embedded-curve material you introduce.

## Measure CU with `litesvm` (no validator)

`litesvm` runs the actual SBF `.so` in-process and reports exact CU. This is your CU regression gate.

```rust
use litesvm::LiteSVM;

let mut svm = LiteSVM::new();
svm.add_program_from_file(program_id, "target/deploy/my_program.so").unwrap();
// … build the verify instruction with serialized proof bytes …
let meta = svm.send_transaction(tx).expect("verify");
let cu = meta.compute_units_consumed;
println!("verify CU = {cu}");
assert!(cu < 200_000, "must stay under the per-instruction budget, got {cu}");
```

Same SBF bytecode as on-chain ⇒ the CU number is real. Keep a `cu < 200_000` assert in CI so a circuit
change that bloats the proof can't sneak past the budget.

## Revocation gate in EVERY handler

Centralize root-auth + revocation (`require_root_active`, see `verifying-key.md`) and call it **first**
in every `verify_*` handler. The failure mode is silent: a new handler that forgets it will happily
accept proofs against a **revoked** root. One function, called everywhere, tested with a
`revoke → expect reject` case per handler.

## CI: the SBF test binary can OOM the linker

A program with a large transitive dep tree (arkworks + anchor + the verifier) produces a big test
binary; statically linking it on a small CI runner (≈7 GB / 2 cores) can **SIGBUS/OOM during link**.
Symptoms hide behind a `continue-on-error` job and look like a flake. Fixes that worked:

```bash
export CARGO_PROFILE_TEST_DEBUG=0   # drop debug info from the test binary (biggest win)
export CARGO_BUILD_JOBS=1           # serialize codegen to cap peak memory
# free disk before the SBF build step; consider mold/lld as the scalable fix
```

And keep the on-chain test job **blocking** once it's stable — a non-blocking job masks real regressions
(a linker OOM hid behind a green check for whole milestones once). Treat genuine toolchain-install
flakiness with a retry, not with `continue-on-error`.

## `local passes ≠ CI passes`

Your laptop has more RAM/disk than the runner. The verify logic is identical, but the *build* isn't —
the OOM above only ever appeared in CI. Budget for that: pin the toolchain, set the env above, and
measure CU in CI (via `litesvm`) so "it worked locally" is never the last word.
