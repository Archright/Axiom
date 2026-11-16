# Third-Party Notices

This file identifies the third-party materials included in or distributed with this repository and the licenses that continue to govern them.

The **Axiom Source-Available License 1.0** (`LicenseRef-Axiom-SAL-1.0`) applies to the original portions of the Covered Work. It does not relicense, and does not apply to, the third-party materials listed below; each such material remains governed by its own license as stated here and as reproduced under `LICENSES/`.

Where a dual license "Apache License 2.0 OR MIT" is indicated, you may use, reproduce, and distribute the material under either the Apache License 2.0 or the MIT license, at your option.

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

## 3. nim-stew — verbatim pinned subject (Apache-2.0 OR MIT)

- Files:
  - `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim` — verbatim copy of `stew/base36.nim` from nim-stew **v0.5.2 (byte-identical to v0.5.0 and @1853f20b)** (byte-identical `diff` 0), with its original license header.
  - `tests/golden/base32_subject/stew/base32.nim` — verbatim `decodedLength` excerpt (`stew/base32.nim:55-60`) from nim-stew **v0.5.2**.
  - `tests/unit/test_sidecar_binding.nim`, `tests/unit/test_base36_cout_binding.nim`, `tests/unit/test_bug_verdict_projection.nim`, `tests/cli/test_base36_composite_golden.nim` — Axiom-authored tests embedding the `stew/base36.nim:52-60` sizing functions (nim-stew **v0.5.2**) verbatim as string constants (`GoldenSubject` / `GoldenSubjectProj` / `GoldenSubjectComposite`; `MutantSubjectProj` is a one-token mutant of the same excerpt for the BUG_FOUND S6 fixture); each transcription replaces the stew license header with an Axiom description comment.
  - `experiments/act2-wp4d-symbol-identity/wp4d-definition-inventory-nim-stew-RAW.txt` — extracted definition signatures from nim-stew.
- Upstream: <https://github.com/status-im/nim-stew> — Copyright (c) 2025 Status Research & Development GmbH
- License: **Apache-2.0 OR MIT** — header text preserved in `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim:1-7`; full texts in `LICENSES/Apache-2.0.txt` (<https://www.apache.org/licenses/LICENSE-2.0.txt>) and `LICENSES/MIT.txt` (<https://opensource.org/license/mit>).

## 4. nim-libp2p — embedded bytesview copy (Apache-2.0 OR MIT)

- File: `tests/unit/test_libp2p_bytesview_binding.nim` (the `BvSubjectModuleBytes` constant embeds the complete 22-line `libp2p/utils/bytesview.nim`, byte-identical, sha256-verified)
- Upstream: <https://github.com/status-im/nim-libp2p> at commit `a130a7f32219909bdcda14b7f1e64d0804fc832c` (pin: `config/spec/nim_libp2p_bytesview_slice.json`)
- License: **Apache-2.0 OR MIT** — Copyright (c) Status Research & Development GmbH — full texts in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.

## 5. Vendored build dependencies archive (Apache-2.0 OR MIT)

- File: `experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz`
- Contents: complete sources of three Status ecosystem packages — `faststreams` 0.5.2, `serialization` 0.5.4, `stew` 0.5.0 — renamed to `.nim.vendored`; each package directory in the archive carries `LICENSE-APACHE` and `LICENSE-MIT`.
- Upstream: <https://github.com/status-im/faststreams>, <https://github.com/status-im/nim-serialization> (<https://github.com/status-im/serialization>), <https://github.com/status-im/nim-stew> — Copyright (c) 2018-2024 Status Research & Development GmbH
- License: **Apache-2.0 OR MIT** — the repackaged archive ships `LICENSE-APACHE` and `LICENSE-MIT` inside each package directory in the archive; full texts are also reproduced in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.
- Naming note: the inserted Apache-2.0 text is named `LICENSE-APACHE` (resolving the in-file header references), while the upstream repositories name this file `LICENSE-APACHEv2`; the contents are byte-identical to the pinned upstream commits.

## 6. serde_json — Rust verification slice fixtures and lockfiles (Apache-2.0 OR MIT)

- Files:
  - `experiments/serde-json-escape-slice-2026-11/` (`inputs/Cargo.lock`, `ACCEPTANCE.md`, and run artifacts for `serde_json::read::is_escape`)
- Upstream: <https://github.com/serde-rs/json> — Copyright (c) Erick Tryzelaar, David Tolnay, and serde-rs contributors
- License: **Apache-2.0 OR MIT** — full texts in `LICENSES/Apache-2.0.txt` and `LICENSES/MIT.txt`.

## 7. Build-time dependencies — nimcrypto, malebolgia, checksums, fusion (MIT)

- Packages: `malebolgia` 1.3.2 (<https://github.com/Araq/malebolgia>) — MIT Copyright (c) 2023 Andreas Rumpf; `checksums` 0.2.2 (<https://github.com/nim-lang/checksums>) — MIT Copyright (c) 2023 Nim Contributors; `fusion` 1.2 (<https://github.com/nim-lang/fusion>) — MIT; `nimcrypto` 0.7.3 (<https://github.com/cheatfate/nimcrypto>) — MIT Copyright (c) 2018 Eugene Kabanov.
- License: **MIT** — text in `LICENSES/MIT.txt`
- Distribution note: resolved and fetched by the Nim package manager at build time (pinned), not vendored in this repository.

## 8. Springer open-access volume PDF — SVF-SVC (CC-BY 4.0)

- File: `docs/spec/SVF-SVC_Software_Verification_Using_SVF.pdf`
- Source: **Gurfinkel & Heule (eds.), "Software Verification Using SVF (SVF-SVC)", TACAS 2025 Part III, LNCS 15698**, Springer, 2025 — <https://doi.org/10.1007/978-3-031-90660-2> (open access); SVF upstream <https://github.com/SVF-tools/SVF>.
- Relevant chapter: McGowan, Richards, Sui (UNSW), "Software Verification Using SVF", pp. 254–259 — <https://doi.org/10.1007/978-3-031-90660-2_21>.
- License: **Creative Commons Attribution 4.0 International (CC-BY-4.0)** — text in `LICENSES/CC-BY-4.0.txt` (<https://creativecommons.org/licenses/by/4.0/legalcode>)
- Changes: none — unmodified copy of the open-access volume PDF.

---

Correction and update policy: the authoritative classification of third-party materials is `compliance/provenance/source-origin.yml` together with the audited inventory (`docs/evidence/sal10_publication/B1_third_party_inventory.md`). This notices file is kept in 1:1 correspondence with `compliance/provenance/source-origin.yml`.
