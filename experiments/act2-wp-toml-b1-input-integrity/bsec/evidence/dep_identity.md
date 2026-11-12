# Dependency identity: commit/blob hash, never the version string

Experiment: `act2-wp-toml-b1-input-integrity/bsec` · Date: 2026-10-11

## The problem

`arnetheduck/nph` declares `requires "toml_serialization >= 0.2.18 & < 0.3.0"`
and has **no `nimble.lock`**. Any statement of the form "nph uses
toml_serialization **0.2.18**" is **not an identity statement**: seventeen
different upstream commits all declare that same version.

## Git log proof (local subject clone, full history)

`b5b387e6fb2a7cc75d54a269b07cc6218361bd46` ("v0.2.18(#99)", 2025-09-25) is
the 17th commit before HEAD `4aa8e2223649fc0837c490a4acfca7b8b1e756f9`
(2026-09-11). `git show <rev>:toml_serialization.nimble | grep ^version` for
every commit in `b5b387e6..4aa8e22`:

```
4aa8e2223649fc0837c490a4acfca7b8b1e756f9  version       = "0.2.18"
96eb1b25497d4b3cb50de272293988fe529f7b61  version       = "0.2.18"
73529768ced17720f78fb5b57191e863f8d8a9c1  version       = "0.2.18"  (Rename Toml_v100_Flags to Toml_v110_Flags (#118))
096659b77909e92be9f0a8961adc4414a3ea106b  version       = "0.2.18"
62dcb2ce764fa1aaaca2ab60e687e48e84d2a745  version       = "0.2.18"
9f35d5d7e05c3a656d0ea505dfe0099161def0d6  version       = "0.2.18"
7b700ce644b0b0848caf46ac37a7f42f992691a7  version       = "0.2.18"
a519b3471bbfbe947b1da176ab37f25e2b147b83  version       = "0.2.18"
09b92c609a562f6e85311aad66a0fb4711f1ab85  version       = "0.2.18"
58c40e65b23a8f5bc394224623112c889ef6149c  version       = "0.2.18"
d019566f97077830e16d2eca0a8239948d0564a4  version       = "0.2.18"
4eed91e339e04697463dfb158b837f36b47c7049  version       = "0.2.18"
c838ca01e71d1cb6d0ff182cbc571ab4ea3ee16f  version       = "0.2.18"  (Add flavor (#107))
9e42585d8dd1afd614220ede2cb81f0d64f860c7  version       = "0.2.18"
71ed1393853a1fa5d8c47d12fbf9400e15a7970c  version       = "0.2.18"
8a0c1bd7f2cc964f01c3140d0bc724482d44ed63  version       = "0.2.18"
4f1e8b73a31ce12de5fbe79db496f4655955a028  version       = "0.2.18"
```

(17/17 report `"0.2.18"`.) Two of these commits are exactly the
security-relevant divergence: `c838ca0` introduced the flavor mechanism
(`createTomlFlavor`) and `7352976` bound `Toml_v110_Flags` — both AFTER
`b5b387e6`. Concretely for B-SEC-03 (`scanHexEscape`'s raw-byte `\xHH`
insert, gated on `TomlHexEscape`):

| | `b5b387e6` (tag v0.2.18) | `4aa8e22` (HEAD, also "0.2.18") |
|---|---|---|
| `format.nim` | **does not exist** | exists |
| runtime flags at decode | none; `TomlReader.init` default `{}` | `Toml_v110_Flags` (incl. `TomlHexEscape`) **force-merged** in `reader.nim:62-64` |
| `\xHH` in a document with no user flags | **rejected** (`invalid hex escape, not supported by standard`) | **accepted**, raw byte inserted (e.g. `\x80` → `0x80`, invalid UTF-8) |

Same version string, opposite B-SEC-03 reachability.

## What a real install actually resolves to (empirical, this run)

Nimble (v0.22.2) resolves git-package versions **by tags**, not by the
nimble-file version at HEAD, and not by branch heads:

- Upstream tags (`git ls-remote --tags`): `v0.2.14` → `fea85b27…`,
  `v0.2.16` → `c8dc4527…`, `v0.2.18` → **`b5b387e6…`**. No tag exists after
  `v0.2.18`; HEAD `4aa8e22` is untagged and **unreachable to nimble**.
- Sandbox experiment (isolated `NIMBLE_DIR`, global state untouched):
  - `nimble install toml_serialization@"0.2.18"` → installs
    `toml_serialization-0.2.18-76ae1c2a…`, `nimblemeta.json` `vcsRevision:
    b5b387e6…`
  - `nimble install toml_serialization` (bare, highest match) → identical
    result, `vcsRevision: b5b387e6fb2a7cc75d54a269b07cc6218361bd46`.

Therefore the un-pinned nph requirement `>= 0.2.18 & < 0.3.0` resolves —
today, reproducibly — to **`b5b387e6`**, the same commit ImThemes'
`nimble.lock` pins (`vcsRevision b5b387e6…`, content checksum sha1
`76ae1c2af5dd092849b41750ff29217980dc9ca3`), and the same commit found,
byte-verified, in nph's `nimbledeps` snapshot (11/11 files identical to the
git blobs at `b5b387e6`). There is no ambiguity about the resolution
mechanism or its outcome; the ambiguity exists only if one uses the version
string as identity.

## The rule

> **Dependency identity = commit SHA / per-file blob hashes — never the
> version string.**
>
> A version string is a *declaration* made by the packaging metadata at one
> commit; multiple commits share it, and (as shown above) they can differ in
> security-relevant behavior. Any reachability/behavior verdict must name the
> resolved commit and pin the per-file blob hashes of the load-bearing files.

Practical corollaries, both recorded in `callsite.md`/`callsite.json`:

1. **Locked consumers** (ImThemes): identity is stable by construction —
   record the lock's `vcsRevision` + content checksum and verify the
   files against the subject repo's git objects at that commit.
2. **Unlocked consumers** (nph): identity is a snapshot in time. Record the
   installed snapshot's `vcsRevision`, byte-verify it, re-run a fresh
   resolution to confirm today's outcome, and state the re-evaluation
   trigger (a new in-range tag appearing upstream).

## Related prior finding (same class of defect in an earlier analysis)

`env/dependency_sources.md` §1.3 already corrected an earlier
mis-attribution where `serialization-0.2.6` (installed-but-unused) was
assumed to be the consumed version; the correction was made by replacing
"declared/installed version" with "the sources the compiler actually opened"
(strace). The present rule generalizes that correction to version strings
themselves.
