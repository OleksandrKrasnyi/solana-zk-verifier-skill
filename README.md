# solana-zk-verifier-skill

[![checks](https://github.com/OleksandrKrasnyi/solana-zk-verifier-skill/actions/workflows/ci.yml/badge.svg)](https://github.com/OleksandrKrasnyi/solana-zk-verifier-skill/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](./LICENSE)

A [Claude Code](https://claude.com/claude-code) skill for the
[Solana AI Kit](https://github.com/solanabr/solana-ai-kit): **verify a custom zero-knowledge
(Groth16/SNARK) proof on-chain inside your own Solana program** — the `groth16-solana` / `alt_bn128`
path. Production-grade gotchas distilled from a verifier that is **deployed and verified on Solana
devnet**, not generic AI filler.

## The gap this fills

"ZK on Solana" already has good coverage in the kit — for things the libraries do *for* you:

- **ZK-compression** (compressed accounts/tokens) → Light Protocol (`ext/sendai`)
- **Confidential transfers** (hidden token balances) → Token-2022 (`token-2022.md`)
- **Formal verification** (proving your program logic correct) → qedgen (`ext/qedgen`)

None of them cover the case where **you wrote the circuit** and need to **verify its proof on-chain
yourself**: serializing an arkworks/snarkjs proof into the exact bytes the verifier wants, embedding a
verifying key, ordering public inputs, isolating multiple circuits, and fitting the compute budget.
That path — `groth16-solana` over the `alt_bn128` pairing syscalls — is what this skill teaches, and it
is genuinely absent from the kit today. The skill's `SKILL.md` also **routes** you to the three options
above when one of *them* is what you actually need, so you never build a verifier you didn't have to.

## Install

This is a documentation skill (Markdown — `SKILL.md` + focus files + one command). Add it to a project
that already uses the Solana AI Kit.

**As a git submodule** (recommended — tracks upstream):

```bash
git submodule add https://github.com/OleksandrKrasnyi/solana-zk-verifier-skill \
  .claude/skills/ext/solana-zk-verifier
```

**Or copy it in** with the bundled helper (no network, no sudo, no executables — it only copies files):

```bash
./install.sh /path/to/your/project   # defaults to the current directory
```

Then add the entry from `skill-registry-entry.json` to your kit's `.claude/skills/skill-registry.json`.
Claude Code picks up the new skill on the next session.

## What's inside

| File | Covers |
|---|---|
| `skill/SKILL.md` | The router + decision tree + the 60-second mental model. Start here. |
| `skill/groth16-on-solana.md` | The crate, the `alt_bn128` syscalls, the const-generic `Groth16Verifier<N>`, the no-panic verify core, and how to test the *real* verifier on the host. |
| `skill/proof-serialization.md` | The byte layer where soundness silently dies: negate `A` only, uncompressed coords, the G2 c0/c1 swap, big-endian, public-input order. |
| `skill/verifying-key.md` | Embedding the VK as committed bytes, a VK-KAT test, isolating many circuits by VK+arity (no `circuit_id`), the thin per-`N` handler, and authenticating public inputs. |
| `skill/limits-and-gotchas.md` | Measured CU (86k–121k), the >10.7M-CU non-syscall-curve finding (and the Groth16-wrap fix), subgroup-check footguns, measuring CU with `litesvm`, CI linker OOM. |
| `skill/trusted-setup.md` | Why a deterministic seed is **not production**, what a Powers-of-Tau ceremony is, ingesting/verifying a `.ptau`, and the arkworks-BN254 Phase-2 gap. |
| `commands/verify-zk-proof.md` | A guided walkthrough command for integrating an on-chain verify end-to-end. |

## Provenance & proof-points (verifiable, no private code)

The patterns are distilled from a real selective-disclosure verifier on **Solana devnet**, program
[`EYxAVesH3Fwwemg2FXHcajsVuuQ3VW1xVEvevRsysZx8`](https://explorer.solana.com/address/EYxAVesH3Fwwemg2FXHcajsVuuQ3VW1xVEvevRsysZx8?cluster=devnet),
which verifies **11 distinct Groth16 circuits** (arities `N = 2…8`) at **86k–121k CU** each. The
measured numbers, the negation/endianness rules, the `>10.7M CU` non-syscall-curve result, and the
subgroup-check finding all come from that work — the skill ships the **generalized patterns**, not that
project's source.

## Honesty & scope

- **Composed, not invented.** This skill builds on audited primitives — `groth16-solana` (Light
  Protocol), `solana-bn254`, `arkworks`. It does not roll new cryptography, and tells you not to either.
- **devnet ≠ mainnet.** A deterministic-seed trusted setup is fine for dev and **unsafe for mainnet**;
  `trusted-setup.md` says so loudly and explains the ceremony path.
- **Precise claims.** The kit *does* have ZK (compression, confidential transfers, formal verification).
  The narrow, true claim is only about **custom on-chain proof verification**.

## Versions

`groth16-solana 0.2` · `solana-bn254 2` · `arkworks 0.5` (`ark-groth16`/`ark-bn254`/`ark-r1cs-std`).
Pin exact versions in your `Cargo.toml` — a verifier is security-critical.

## Contributing & project docs

- [`CONTRIBUTING.md`](./CONTRIBUTING.md) — how to propose changes; the precision/honesty bar for content.
- [`SECURITY.md`](./SECURITY.md) — security guidance, honest caveats (devnet ≠ mainnet, non-production setup), and how to report an issue.
- [`AI-USAGE.md`](./AI-USAGE.md) — how this skill was authored (Claude Code) and how its content was verified.
- [`CHANGELOG.md`](./CHANGELOG.md) — version history.

## License

[MIT](./LICENSE).
