# INTEGRITY — subject tree byte-identity, pre↔post (Zero-Footprint verification)

Run window: 2026-10-19, defect legs d1+d2 (`bin/ax prove --project /tmp/sidecar_probe/nim-stew --target "stew/base36.nim::decodedLength"`, fresh state dirs) + unit-suite leg (`nim r tests/unit/test_sidecar_binding.nim`, own fixtures/state — never touches the clone). Subject clone: `/tmp/sidecar_probe/nim-stew`, whole tree write-protected (dirs `r-xr-xr-x`, files `r--r--r--`; probe `touch` → EACCES) for the entire window.

## Manifest method (frozen in FREEZE.md §7)

```
cd /tmp/sidecar_probe/nim-stew && find . -path ./.git -prune -o -type f -print | sort | xargs sha256sum > <pre|post>.sha256
```

95 files hashed (`.git` pruned). Copies preserved: `runs/subject_tree_pre.sha256`, `runs/subject_tree_post.sha256`.

## Results

| projection | pre | post | equal |
|---|---|---|---|
| manifest file sha256 | `685717450622a8010fea8839e73d9e26c83da9c7190f6c2fcc2f86d4209ba290` | `685717450622a8010fea8839e73d9e26c83da9c7190f6c2fcc2f86d4209ba290` | **IDENTICAL** |
| `git rev-parse HEAD` | `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` | `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` | IDENTICAL |
| `git status --porcelain` | empty | empty | IDENTICAL |
| `cmp pre post` | — | — | byte-identical (`MANIFESTS BYTE-IDENTICAL`) |
| `stew/base36.nim` sha256 | `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` | same | IDENTICAL (adoption `blobSha256` pin holds) |

In-run mechanical fold (BUG_FOUND payload, both d1 and d2): `replay.moduleSha256 == replay.moduleSha256AfterRun == b8a42a6a…` ∧ `replay.porcelainClean=true` — the pipeline's own subject-integrity fold independently agrees with this file-level audit.

**Verdict: subject tree untouched — 0 of 95 files changed, pin intact, porcelain clean at both ends. No digest change ⇒ judgment table `digest change → FAIL` row is NOT triggered.**
