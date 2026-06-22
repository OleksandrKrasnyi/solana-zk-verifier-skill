# Changelog

All notable changes to this skill are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project aims to follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.0] — 2026-06-22

Initial release.

### Added
- `skill/SKILL.md` — the ZK-on-Solana router + decision tree (routes ZK-compression → Light,
  confidential transfers → Token-2022, formal verification → qedgen; custom proof verification → here).
- Five focus files: `groth16-on-solana.md`, `proof-serialization.md`, `verifying-key.md`,
  `limits-and-gotchas.md`, `trusted-setup.md`.
- `commands/verify-zk-proof.md` — a guided end-to-end walkthrough.
- `install.sh` (copy-only installer), `skill-registry-entry.json`, `README.md`, `LICENSE` (MIT).
- Project docs: `SECURITY.md`, `CONTRIBUTING.md`, `AI-USAGE.md`, this changelog.
- CI: registry-JSON validation, installer lint, and skill-structure checks.
