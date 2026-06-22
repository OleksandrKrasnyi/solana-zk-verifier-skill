# Security

This repository is a **documentation skill** — Markdown guidance plus a copy-only `install.sh`. It ships
no runtime, no binaries, and no network calls. But it teaches you to build something
**security-critical** (an on-chain proof verifier), so the honest caveats below are part of the product.

## Honest caveats (read before shipping value)

- **A deterministic-seed trusted setup is NON-PRODUCTION.** `StdRng::seed_from_u64(...)` puts the
  setup's toxic waste in your source — anyone with the seed can forge proofs. Fine for dev / devnet /
  CI; **never** for mainnet value. Escalate to a Powers-of-Tau ceremony first. See
  [`skill/trusted-setup.md`](./skill/trusted-setup.md).
- **devnet ≠ mainnet.** The measured CU numbers and patterns come from a devnet deployment. Re-measure
  and re-review for your own program.
- **Audit lineage, not a blanket audit.** `groth16-solana`'s verifier was audited during the Light
  Protocol v3 audit (release `0.0.1`). Pin the exact version you use, record its checksum, and diff the
  verifier source against the audited revision before mainnet.
- **Serialization mistakes break soundness silently.** Negate `A` only, get the G2 `c0/c1` order right,
  keep everything big-endian, and keep the public-input order. Test with adversarial cases **and** a
  decision cross-check against an independent verifier (see [`skill/proof-serialization.md`](./skill/proof-serialization.md)).
- **Subgroup-check footgun.** Validate prime-order subgroup membership of any untrusted curve point on a
  cofactor > 1 curve before use (see [`skill/limits-and-gotchas.md`](./skill/limits-and-gotchas.md)).
- **Composed, not invented.** This skill builds on audited primitives (`groth16-solana`, `solana-bn254`,
  `arkworks`) and invents no cryptography. Neither should you.

## Reporting a problem

- **Content errors** (a wrong API, an incorrect claim, an unsafe recommendation): please
  [open an issue](https://github.com/OleksandrKrasnyi/solana-zk-verifier-skill/issues). Accuracy is the
  whole point of this skill — corrections are very welcome.
- **Sensitive reports:** use GitHub's
  [private security advisories](https://github.com/OleksandrKrasnyi/solana-zk-verifier-skill/security/advisories/new)
  rather than a public issue.

Because this is documentation, "a vulnerability" usually means **a recommendation that could lead a
reader to an unsound verifier**. Those are treated as high priority.
