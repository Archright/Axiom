# INTEGRITY — subject tree byte-identity, pre↔post (Zero-Footprint verification)

Run window: 2026-10-22 20:51:19–20:51:36 KST (d1 20:51:19–20:51:28, d2 20:51:29–20:51:36), defect legs d1+d2 (`bin/ax prove --project <subject-abs> --target "libp2p/utils/bytesview.nim::toOpenArray"`, fresh state dirs) + the unit-suite legs (own fixtures/state — never touch the clone). Subject clone: `<workspace>/nim-libp2p` (status-im/nim-libp2p; origin `iftech/nim-libp2p` fork) — **the clone's POSIX mode bits were `0775`/`0664` (owner-writable) throughout the window and no `chmod` occurred inside it** (`ctime` 2026-10-22 16:34, before the 20:51 run), so the freeze's mode-bit write-protection was NOT in force for this slice; the Zero-Footprint verdict therefore rests on the measured evidence below — no subject file carries an mtime inside the run window (the newest mtime in the tree is 2026-10-22 14:20:19; 0 files newer than 20:00), the pre/post pins are byte-identical, the porcelain is empty at both ends, and the in-run fold `replay.moduleSha256 == replay.moduleSha256AfterRun`. Recorded as a deviation in [ACTEGRITY.md](./ACCEPTANCE.md) §7. Axiom-side revision under test: `801a12be69f7f82f6792e31ccc5757cbc7a48364` (PR #1043 merge — a native 2-parent MERGE, parents `6e45b7167` + `efde23cc4`; required checks 5/5 PASS, landing observed TERMINAL_SUCCESS).

## Manifest method (frozen in FREEZE.md §7)

```
cd <subject> && find . -path ./.git -prune -o -type f -print | sort | xargs sha256sum > <pre|post>.sha256
```

641 files hashed (`.git` pruned). The frozen manifest copies (`runs/subject_tree_pre.sha256`, `runs/subject_tree_post.sha256`) were **not preserved** by the run; what the run preserved are the pins `subject_pins_pre.txt` / `subject_pins_post.txt` (HEAD, tree, module content sha256 — byte-identical, sha256 `fdbf8db3bdaf4863287ff5b59f4c22ea6c8b016d654d6a38fe4ed33fb03e95ff` at both ends). The full-tree manifest was re-derived from the unchanged tree with the frozen command: **641 entries**, manifest-file sha256 `85c39af3dd8f1c06da29ca39aab2ffce78b6dfcf685c849448da22f6f3163bd4` — the same value at both ends, because no subject file was added, removed or rewritten inside the run window (the newest mtime in the tree is 2026-10-22 14:20:19; 0 files newer than 20:00).

## Subject pin — pre / post (git object IDs + content digest)

Two **different hash kinds** are recorded here and must not be conflated (the git repo is SHA-1;
the module digest is a content SHA-256 — the overlay's `semanticCaveats` state the distinction):

| projection | pre | post | equal |
|---|---|---|---|
| `git rev-parse HEAD` | `a130a7f32219909bdcda14b7f1e64d0804fc832c` | `a130a7f32219909bdcda14b7f1e64d0804fc832c` | IDENTICAL |
| `git rev-parse HEAD^{tree}` | `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` | `ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841` | IDENTICAL |
| `git rev-parse HEAD:libp2p/utils/bytesview.nim` (blob OID) | `621e111d53fd07b4e2eeeb2410a1cd6c05719159` | `621e111d53fd07b4e2eeeb2410a1cd6c05719159` | IDENTICAL |
| `sha256sum libp2p/utils/bytesview.nim` (content digest) | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` | `b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee` | IDENTICAL — the overlay's `blobSha256` pin holds |
| `git status --porcelain` | empty | empty | IDENTICAL |
| pins file sha256 (`subject_pins_pre.txt` / `subject_pins_post.txt`) | `fdbf8db3bdaf4863287ff5b59f4c22ea6c8b016d654d6a38fe4ed33fb03e95ff` | `fdbf8db3bdaf4863287ff5b59f4c22ea6c8b016d654d6a38fe4ed33fb03e95ff` | IDENTICAL |
| full-tree manifest file sha256 (re-derived, 641 entries) | `85c39af3dd8f1c06da29ca39aab2ffce78b6dfcf685c849448da22f6f3163bd4` | `85c39af3dd8f1c06da29ca39aab2ffce78b6dfcf685c849448da22f6f3163bd4` | IDENTICAL |
| `cmp pre post` | — | — | byte-identical (`cmp` on the preserved pins reports no difference; the re-derived manifests are byte-identical) |

## In-run mechanical fold

The pipeline's own subject-integrity fold (both d1 and d2) must independently agree with the
file-level audit above: `replay.moduleSha256 == replay.moduleSha256AfterRun == b205c969…` ∧
`replay.porcelainClean=true` ∧ `replay.subjectGitRef == a130a7f32…` ∧
`replay.treeMerkle == ec4a0c7e…`.

Payload records 5–9, verbatim from the run's `counterExample` (d1 and d2 byte-identical):

```
5. replay.subjectGitRef=a130a7f32219909bdcda14b7f1e64d0804fc832c
6. replay.treeMerkle=ec4a0c7ee22ddc63338c32d3639e49fd9ab4c841
7. replay.moduleSha256=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee
8. replay.moduleSha256AfterRun=b205c969ba04f4199d8fd4a121d4b6fccdc82c426e336add0e1e9fd0e961e5ee
9. replay.porcelainClean=true
```

**Verdict: subject tree untouched — 0 of 641 files changed, pin intact, porcelain clean at both ends. No digest change ⇒ the judgment table's `digest change → FAIL` row is NOT triggered.** The Zero-Footprint claim rests on the measured pins, the empty porcelain, the mtime census of the tree and the in-run fold above — **not** on the clone's mode bits, which were owner-writable throughout the window (see the header caveat and ACCEPTANCE.md §7).
