# Contributing

Corrections and improvements are welcome — especially anything that makes the guidance **more accurate**.
This skill's value is precision, so the bar for content is high.

## The content bar

- **Verified, not vibes.** Every API name, version, and behavioral claim must match the real public
  crates (`groth16-solana 0.2`, `solana-bn254 2`, `arkworks 0.5`). If you can't machine-check a
  "matches / compatible / equivalent" claim, qualify it explicitly.
- **No invented cryptography.** Compose audited primitives; recommend the same to readers.
- **Preserve the honest caveats.** `devnet ≠ mainnet`; a deterministic-seed setup is non-production;
  serialization mistakes are silent. Don't soften these (see [`SECURITY.md`](./SECURITY.md)).
- **Stay in scope.** This skill is *only* about verifying a custom Groth16/SNARK proof on-chain. Route
  ZK-compression, confidential transfers, and formal verification to the kit's existing skills — don't
  duplicate them.
- **Token-efficient.** Keep `SKILL.md` a lean router; put detail in the focus files; let readers load
  only what they need.

## Run the checks locally

```bash
python3 -m json.tool skill-registry-entry.json > /dev/null   # registry entry is valid JSON
bash -n install.sh                                            # installer has no syntax errors
shellcheck install.sh                                         # (optional) installer lint
```

CI runs the same checks (plus a structure check) on every push and PR.

## Proposing a change

Open an issue to discuss anything substantial, or send a PR. Keep commits focused and the history clean;
the PR template lists what to confirm before review.
