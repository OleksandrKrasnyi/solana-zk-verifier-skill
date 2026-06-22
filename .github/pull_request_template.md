## What & why

<!-- What does this change, and why? -->

## Checklist

- [ ] Claims are **verified** against the real crate APIs (`groth16-solana 0.2`, `solana-bn254 2`,
      `arkworks 0.5`); any "matches/compatible" claim is machine-checked or explicitly qualified.
- [ ] No invented cryptography; audited primitives only.
- [ ] Honest caveats preserved (devnet ≠ mainnet; deterministic seed = non-production; silent
      serialization failures).
- [ ] In scope (custom on-chain proof verification) — does not duplicate Light / Token-2022 / qedgen.
- [ ] Local checks pass: `python3 -m json.tool skill-registry-entry.json`, `bash -n install.sh`.
