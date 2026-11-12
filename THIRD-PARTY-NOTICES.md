# Third-Party Notices

This file identifies the third-party materials included in, referenced by, or distributed with this repository and the licenses that continue to govern them.

The **Axiom Source-Available License 1.0** (`LicenseRef-Axiom-SAL-1.0`) applies to the original portions of the Covered Work. It does not relicense, and does not apply to, the third-party materials listed below; each such material remains governed by its own license as stated here and as reproduced under `LICENSES/`.

Where a dual license "Apache License 2.0 OR MIT" is indicated, you may use, reproduce, and distribute the material under either the Apache License 2.0 or the MIT license, at your option (the choice model used by the Status and Rust ecosystems).

## 1. ed25519 — C implementation (Zlib)

- Files: `vendor/ed25519/ed25519/src/*.{c,h}`, `vendor/ed25519/ed25519/test.c`, `vendor/ed25519/ed25519/license.txt`, `vendor/ed25519/ed25519/readme.md`
- Upstream: <https://github.com/orlp/ed25519> (Orson Peters)
- License: **Zlib** — Copyright (c) 2015 Orson Peters — text in `LICENSES/Zlib.txt` (<https://opensource.org/license/zlib>)
- Embedded header: `src/sha512.c:1-8` carries a verbatim **LibTomCrypt** header (Tom St Denis, <http://libtom.org>): "The library is free for all purposes without any express guarantee it works." — a public-domain-style disclaimer covering the LibTomCrypt-derived SHA-512 implementation in that file, as distributed by the `orlp/ed25519` upstream; the remaining `src/*.{c,h}` files are Zlib Copyright (c) 2015 Orson Peters as stated above. Header preserved verbatim.
- Notice of Modification (Zlib License §2): Modified from the upstream `orlp/ed25519` distribution (`ge.c:349`, `precomp_data.h:1,46`) for `const`-qualifier alignment, compiler warning suppression, and Nim FFI integration; this copy is not the original software verbatim.

## 2. ed25519 — Nim bindings (MIT)

- Files: `vendor/ed25519/ed25519.nim`, `vendor/ed25519/README.md`, `vendor/ed25519/ed25519.nimble`
- Upstream: <https://github.com/niv/ed25519.nim> (niv)
- License: **MIT** (declared in `ed25519.nimble` as `license = "MIT"`; the upstream package does not ship a license text file) — text in `LICENSES/MIT.txt` (<https://opensource.org/license/mit>)
- Modifications: wrapper body is identical to upstream master; `ed25519.nimble` version field changed (`0.1.1` → `1.0.0`) locally.

## 3. nim-stew — verbatim files, subject fixtures, and signature corpus (Apache-2.0 OR MIT)

- Files:
  - `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim` — verbatim copy of `stew/base36.nim` from nim-stew **v0.5.0** (byte-identical `diff` 0), with its original license header.
  - `tests/golden/base36_subject/stew/base36.nim` — partial excerpt of `stew/base36.nim` from nim-stew **v0.5.2** (sizing functions, 6 lines), marked "VERBATIM transcription".
  - `tests/negative/base36_mutant_subject/stew/base36.nim` — the same excerpt with an intentional seeded mutation (test fixture).
  - `experiments/act2-wp4d-symbol-identity/wp4d-definition-inventory-nim-stew-RAW.txt` — extracted definition signatures from nim-stew.
  - `experiments/act2-r0-atom-getbitsbe/subjects/stew/` — subject verification scope reference (`stew/endians2.nim` / `getBitsBE`).
- Upstream: <https://github.com/status-im/nim-stew> — Copyright (c) 2018-2025 Status Research & Development GmbH
- License: **Apache-2.0 OR MIT** — header text preserved in `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim:1-7`; full texts in `LICENSES/Apache-2.0.txt` (<https://www.apache.org/licenses/LICENSE-2.0.txt>) and `LICENSES/MIT.txt` (<https://opensource.org/license/mit>).

## 4. nim-libp2p — embedded bytesview copy (Apache-2.0 OR MIT)

- File: `tests/unit/test_libp2p_bytesview_binding.nim` (the `BvSubjectModuleBytes` constant embeds the complete 22-line `libp2p/utils/bytesview.nim`, byte-identical, sha256-verified)
- Upstream: <https://github.com/status-im/nim-libp2p> at commit `a130a7f32219909bdcda14b7f1e64d0804fc832c` (pin: `config/spec/nim_libp2p_bytesview_slice.json`)
- License: **Apache-2.0 OR MIT** — Copyright (c) Status Research & Development GmbH — full texts in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.

## 5. Vendored build dependencies archive (Apache-2.0 OR MIT)

- File: `experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz`
- Contents: complete sources of three Status ecosystem packages, renamed to `.nim.vendored` (per-package file counts in the repackaged archive, including `nimblemeta.json` and the two license texts):
  - `faststreams` 0.5.2 (16 files, including `faststreams-0.5.2/LICENSE-APACHE` and `faststreams-0.5.2/LICENSE-MIT`)
  - `serialization` 0.5.4 (12 files, including `serialization-0.5.4/LICENSE-APACHE` and `serialization-0.5.4/LICENSE-MIT`)
  - `stew` 0.5.0 (56 files, including `stew-0.5.0/LICENSE-APACHE` and `stew-0.5.0/LICENSE-MIT`)
- Upstream: <https://github.com/status-im/faststreams>, <https://github.com/status-im/nim-serialization> (<https://github.com/status-im/serialization>), <https://github.com/status-im/nim-stew> — Copyright (c) 2018-2024 Status Research & Development GmbH
- License: **Apache-2.0 OR MIT** — the repackaged archive ships `LICENSE-APACHE` and `LICENSE-MIT` inside each package directory in the archive; full texts are also reproduced in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.
- Naming note: the inserted Apache-2.0 text is named `LICENSE-APACHE` (resolving the in-file header references), while the upstream repositories name this file `LICENSE-APACHEv2`; the contents are byte-identical to the pinned upstream commits.

## 6. serde_json — Rust verification slice fixtures and lockfiles (Apache-2.0 OR MIT)

- Files:
  - `experiments/serde-json-escape-slice-2026-11/` (`inputs/Cargo.lock`, `ACCEPTANCE.md`, and run artifacts for `serde_json::read::is_escape`)
  - `experiments/act2-r0-reanchor/subjects/serde_json/`
  - `tests/fixtures/rust/axiom_escape_probe/src/lib.rs` (bool-expression slice modeled on `serde_json::read::is_escape`)
- Upstream: <https://github.com/serde-rs/json> — Copyright (c) Erick Tryzelaar, David Tolnay, and serde-rs contributors
- License: **Apache-2.0 OR MIT** — full texts in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.

## 7. Nim standard library reference patterns and signature corpus (MIT)

- Files:
  - `experiments/act2-wpi-structural-ingress/canonical/signature_corpus.json`
  - `experiments/act2-wpi-structural-ingress/canonical/signature_corpus_run1.json`
  - `experiments/act2-wpi-structural-ingress/canonical/signature_corpus_run2.json`
- Upstream: <https://github.com/nim-lang/Nim> (`lib/pure/bitops.nim` head/tail excerpts and Nim stdlib reference patterns) — Copyright (c) 2006-2024 Andreas Rumpf and Nim Contributors; Copyright (c) 2019 Status Research & Development GmbH
- License: **MIT** — text in `LICENSES/MIT.txt`.

## 8. nimcrypto — build-time dependency (MIT)

- Package: `nimcrypto` 0.7.3 (Copyright (c) 2018 Eugene Kabanov) — <https://github.com/cheatfate/nimcrypto>
- License: **MIT** — text in `LICENSES/MIT.txt`
- Distribution note: `nimcrypto` is not vendored in this repository; it is resolved and fetched by the Nim package manager at build time (pinned in the lock file).

## 9. Springer open-access volume PDF — SVF-SVC (CC-BY 4.0)

- File: `docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`
- Source: **Gurfinkel & Heule (eds.), "Software Verification Using SVF (SVF-SVC)", TACAS 2025 Part III, LNCS 15698**, Springer, 2025 — <https://doi.org/10.1007/978-3-031-90660-2> (open access); SVF upstream <https://github.com/SVF-tools/SVF>.
- Relevant chapter: McGowan, Richards, Sui (UNSW), "Software Verification Using SVF", pp. 254–259 — <https://doi.org/10.1007/978-3-031-90660-2_21>.
- License: **Creative Commons Attribution 4.0 International (CC-BY-4.0)** — text in `LICENSES/CC-BY-4.0.txt` (<https://creativecommons.org/licenses/by/4.0/legalcode>)
- Changes: none — unmodified copy of the open-access volume PDF.

## 10. Removed third-party documents (citation references)

Other third-party papers that previously existed as PDF files under `docs/spec/` were removed from this repository for redistribution-right reasons. Bibliographic references (DOI / arXiv / official links) for those papers are recorded in `docs/spec/PDF_REFERENCES.md`. Nothing in that file is licensed under the Axiom Source-Available License; it merely cites publicly identified works.

## 11. Build-time dependencies — malebolgia, checksums, fusion (MIT)

- Packages: `malebolgia` 1.3.2 (<https://github.com/Araq/malebolgia>) — MIT Copyright (c) 2023 Andreas Rumpf; `checksums` 0.2.2 (<https://github.com/nim-lang/checksums>) — MIT Copyright (c) 2023 Nim Contributors; `fusion` 1.2 (<https://github.com/nim-lang/fusion>) — MIT.
- License: **MIT** — text in `LICENSES/MIT.txt`
- Distribution note: resolved and fetched by the Nim package manager at build time (pinned), not vendored.

## 12. External verification toolchain components (not vendored)

Axiom invokes external formal verification tools at runtime or in CI (none of these are vendored in this repository):

- **Lean 4** (<https://github.com/leanprover/lean4>) — Apache-2.0
- **Z3 Theorem Prover** (<https://github.com/Z3Prover/z3>) — MIT
- **Charon** (<https://github.com/AeneasVerif/charon>) and **Aeneas** (<https://github.com/AeneasVerif/aeneas>) — Apache-2.0

---

Correction and update policy: the authoritative classification of third-party materials is `compliance/provenance/source-origin.yml` together with the audited inventory (`docs/evidence/sal10_publication/B1_third_party_inventory.md`). This notices file is kept in 1:1 correspondence with `compliance/provenance/source-origin.yml`.
