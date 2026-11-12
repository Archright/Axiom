# B1 — Third-Party Materials Inventory (SAL 1.0 Publication Readiness, Gate 1-R2)

**기준**: 로컬 클론 HEAD `73e1a792e`(2026-11-04 스냅샷) + `git fetch --tags origin` 후 원격 `201ac6c54` 관측(2026-11-05). 조사는 READ-ONLY(저장소 무변경).
**방법**: 트랙된 파일 전수 `git grep`(저작권 `©|copyright`, 외부 라이선스 문구, SPDX, 외부 패키지 마커) + 후보 파일 직접 열람 + upstream 원본 diff(ed25519 2종, nim-libp2p 1종은 GitHub raw fetch 바이트 대조) + `.gitmodules`/git 이력/바이너리 확장자 스캔. PDF 권리 판정: PDF 내부 텍스트·메타데이터(`pdftotext`·`pdfinfo`·`pdffonts`·`pdfimages`) + arXiv API·Crossref REST API·OSTI API·Wayback CDX·저자 홈페이지 교차 검증.
**UNKNOWN 상태**: 판정 관련 UNKNOWN **0건**(R2a 해소 완료). 마이너 세부 UNKNOWN은 §6 참조(판정 무영향).

---

## 1. Third-party 확정 목록

### 1-A. 제품에 컴파일되는 in-tree 제3자 코드 — vendor/ed25519/ (2계층)

| 파일 | 출처 | 라이선스 | 수정 여부 |
|---|---|---|---|
| `vendor/ed25519/ed25519/src/*.{c,h}`, `test.c` (13파일) | [orlp/ed25519](https://github.com/orlp/ed25519) (Orson Peters) | **zlib** — `ed25519/license.txt:1` "Copyright (c) 2015 Orson Peters" | niv 패키지 동봉본과 바이트 동일; orlp master 대비 `ge.c:349`·`precomp_data.h:1,46` const 한정자 2곳 차이(업스트림 드리프트 추정) |
| `vendor/ed25519/ed25519.nim`, `README.md`, `ed25519.nimble` | [niv/ed25519.nim](https://github.com/niv/ed25519.nim) | **MIT** — `ed25519.nimble:4,6` "author = \"niv\"", "license = \"MIT\"" | 래퍼 본체 upstream master 동일; nimble version 0.1.1→1.0.0 로컬 변경(lock 핀과 불일치 — 부록 4) |

- 사용처(제품 바이너리에 링크): `src/core/trusted/bypass_verify.nim:19`, `src/core/trusted/ratchet_authority.nim:21`, `src/infrastructure/certificate_attestation.nim:11`.
- MIT 선언이 nimble 메타데이터뿐(MIT 전문 파일 없음 — upstream에도 없음), C 코드는 zlib 별도 적용.

### 1-B. status-im 계열 사본 — Apache-2.0 OR MIT, "Copyright (c) Status Research & Development GmbH"

| 파일 | 범위 | 원본 | 수정 |
|---|---|---|---|
| `tests/fixtures/bug_verdict_scope/base36_pinned_subject.nim` (223줄) | 파일 전체 verbatim — stew-0.5.0/stew/base36.nim과 `diff` 0 | [status-im/nim-stew](https://github.com/status-im/nim-stew) v0.5.0 | 없음 |
| `tests/golden/base36_subject/stew/base36.nim` | 부분 발췌 — base36.nim:52-60(사이징 함수 2개, 6줄), "VERBATIM transcription" 주석 명시 | nim-stew v0.5.2 | 라이선스 헤더가 Axiom 설명 주석으로 대체됨 |
| `tests/negative/base36_mutant_subject/stew/base36.nim` | 동일 발췌 + `+ 1` 제거 변이("seeded mutation" 명시) | 〃 | 의도적 변이(BUG_FOUND 픽스처) |
| `tests/unit/test_libp2p_bytesview_binding.nim:53-75` | `BvSubjectModuleBytes` 상수에 bytesview.nim 전체(22줄, 613 bytes) 임베디드 — sha256 재계산 일치, [status-im/nim-libp2p@a130a7f3](https://raw.githubusercontent.com/status-im/nim-libp2p/a130a7f32219909bdcda14b7f1e64d0804fc832c/libp2p/utils/bytesview.nim) raw fetch 바이트 동일 | nim-libp2p (핀: `config/spec/nim_libp2p_bytesview_slice.json`) | 없음(바이트 정확). 임베디드 문자열 자체가 제3자 코드 |

헤더 전문(`base36_pinned_subject.nim:1-7` 등): "Copyright (c) 2025 Status Research & Development GmbH / Licensed under either of * Apache License, version 2.0 * MIT license".
**라이선스 갭**: 헤더가 참조하는 `LICENSE-APACHE`/`LICENSE-MIT` 파일이 저장소에 존재하지 않음 → L2에서 `LICENSES/`로 해소.

### 1-C. 트랙된 아카이브 내 제3자 소스 전체

`experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz` (90 엔트리) — status-im 패키지 3종 전체 소스:
- `faststreams-0.5.2`(13 .nim), `serialization-0.5.4`(10 .nim), `stew-0.5.0`(56 .nim) — 전부 `.nim.vendored` 개명.
- 아카이브 내 `LICENSE-APACHE`/`LICENSE-MIT` 미동봉(nimblemeta.json만 동반). stew 일부는 인라인 이중 라이선스 헤더 유지, faststreams/serialization은 헤더 없음(원본이 LICENSE 파일 표기 방식).
- 라이선스: **Apache-2.0 OR MIT**. git 이력상 과거 `bsec/offline/deps/` 디렉터리 → 현재 tarball로만 존재.
- **L2 대응**: 재패키징 — 패키지별 라이선스 전문 아카이브 내부 삽입 + MANIFEST 재생성 + `bash bsec/replay.sh verify` 재실행으로 원장 폐쇄 증명.

### 1-D. 제3자 문서 — docs/spec 논문 PDF (21종 = 현행 18 + 이력 전용 3)

Per-PDF 권리 판정표(R2b, 2026-11-05 확정):

| # | 파일명 | 논문 식별 | 판정 | 근거 요약 |
|---|---|---|---|---|
| 1 | AI-driven formal mathematical reasoning.pdf | Yang 외 7인, arXiv:2412.16075 (2024) | **REMOVE** | arXiv 기본 비독점 라이선스 |
| 2 | Abstract Interpretation.pdf | **Cousot & Cousot POPL'77**(ACM pp.238–252, DOI 10.1145/512950.512973) — R2a 식별 확정 | **REMOVE** | © 1977 ACM 저작물 스캔(1999 프랑스계 Distiller) |
| 3 | Checking_Safety_Properties_…_SAT-Solver.pdf | Sheeran, Singh, Stålmarck, FMCAD 2000, LNCS 1954, DOI 10.1007/3-540-40922-X_8 | **REMOVE** | Springer 카메라레디("© Springer-Verlag") |
| 4 | DESIGN AND SYNTHESIS OF SYNCHRONIZATION SKELETONS.pdf | Clarke & Emerson (1981), LNCS 131, DOI 10.1007/BFb0025774 | **REMOVE** | Springer 디지털 스캔(PageGenie) |
| 5 | Dependent Types in Practical Programming.pdf | Hongwei Xi, CMU 박사학위논문 (1998), "© 1998 Hongwei Xi" | **REMOVE** | 저자 thesis 재배포 허용 문구 없음 |
| 6 | Formal verification of a realistic compiler.pdf | Leroy, CACM 52(7) (2009), DOI 10.1145/1538788.1538814 | **REMOVE** | ACM 정본; 저자 preprint 재배포 허가 문서 없음 |
| 7 | LeanDojo_…_Language_Models.pdf | Yang 외, NeurIPS 2023 D&B, arXiv:2306.15626v2 | **REMOVE** | arXiv 기본 비독점 |
| 8 | PROGRAMMING WITH ABSTRACT DATA TYPES.pdf | Liskov & Zilles (1974), DOI 10.1145/800233.807045 | **REMOVE** | ACM 저작물 스캔 |
| 9 | Program slicing.pdf | Weiser, ICSE-5 (1981) — IEEE 저작권 코드 포함 | **REMOVE** | IEEE 저작권 문구 포함 스캔 |
| 10 | Property Directed Reachability with Extended Resolution.pdf | **Luka & Vizel**(Technion — R2a 저자 확정), CAV 2025, LNCS 15931, DOI 10.1007/978-3-031-98668-0_13; 저장본 arXiv:2505.18998v1 | **REMOVE**(교체 시 KEEP 가능) | arXiv v1 기본 라이선스 — Springer판은 CC-BY 4.0이므로 파일 교체 시 KEEP 전환 가능 |
| 11 | SAT-Based Model Checking Without Unrollin.pdf | Bradley, VMCAI 2011, LNCS 6538, DOI 10.1007/978-3-642-18275-4_7 | **REMOVE** | Springer 정본(비OA); preprint 허가 문서 없음 |
| 12 | SMT-based Model Checking for Recursive Programs.pdf | Komuravelli, Gurfinkel, Chaki (SPACER), CAV 2014; 저장본 arXiv:1405.4028v2 | **REMOVE** | arXiv 기본 라이선스; Springer판 비OA |
| 13 | SVF-SVC_Software_Verification_Using_SVF.pdf | TACAS 2025 Part III **전체 volume**(Gurfinkel & Heule eds., LNCS 15698, 284pp) — 목적 챕터 McGowan, Richards, Sui(UNSW), pp.254–259, DOI 10.1007/978-3-031-90660-2_21 | **KEEP** | PDF 앞물자 "This book is an open access publication" + **CC-BY 4.0**(Crossref 이중 확인) |
| 14 | Subjective_logic.pdf | Jøsang draft 2013-02-18(미출판) — R2a: 저자 공식 배본(wayback 100% 텍스트 일치), 2016 철수, 라이선스 표기 0건 | **REMOVE** | 재배포 권리 미확립 |
| 15 | Temporal_Induction_by_Incremental_SAT_Solving.pdf | Eén & Sörensson, ENTCS 89(4) (2004), DOI 10.1016/S1571-0661(05)82542-3 | **REMOVE(조건부)** | 출판판 Open Archive CC-BY-NC-ND 3.0 — NC 충족 미확정, 보수 REMOVE |
| 16 | cegar.pdf | Clarke, Grumberg, Jha, Lu, Veith, CAV 2000, LNCS 1855, DOI 10.1007/10722167_15 | **REMOVE** | Springer 정본(비OA); preprint 허가 문서 없음 |
| 17 | program_synthesis.pdf | Gulwani, Polozov, Singh, FnT PL 4(1-2) (2017), DOI 10.1561/2500000010 | **REMOVE** | PDF 명시 "No part of this publication may be reproduced… without prior written permission" |
| 18 | propositions-as-types.pdf | Wadler, CACM 58(12) (2015), DOI 10.1145/2699407 — 저자 preprint V10(저자 홈페이지 판본 sha256 일치) | **REMOVE** | 저자 preprint 재배포 허용 문구 없음; ACM 정본 |
| 19 | dempster_shafer.pdf (이력 전용: `532ce56f0` 2026-06-04 추가 → 06-05 삭제) | Sentz & Ferson, SAND2002-0835, Sandia (2002), DOI 10.2172/800792 | **REMOVE**(2026-11-06 판정 확정 — agent-133 증거 종결) | 표지 "Unlimited Release…Approved for public release; further dissemination unlimited"은 배포 해제 표기일 뿐 — 전문·XMP 라이선스 문구 0건·저자(Sentz & Ferson) 비연방(권리 보유 가능)·OSTI 정책상 OSTI 열람 ≠ 퍼블릭 도메인, 재배포는 권리자 허락 필요·판본 sha256 OSTI 공개판 일치 → 재배포 권리 미확립·인용 manifest 대체(§5) |
| 20 | "LeanDojo: Theorem…Models.pdf" 콜론명 (이력 전용: `dc7ac5bc9` → `72a820625` 개명 R100) | #7과 동일 논문·**byte-identical**(sha256 일치) | **REMOVE**(=#7) | #7 근거와 동일 |
| 21 | "SVF-SVC: Software…SVF.pdf" 콜론명 (이력 전용: `dc7ac5bc9` → `72a820625` 개명 R100) | #13과 **byte-identical**(sha256 일치) | **KEEP**(=#13) | #13 근거(CC-BY 4.0)와 동일 |

**판정 요약**: KEEP 2종(#13·#21) + REMOVE 19종(#19 포함 — 2026-11-06 agent-133 증거 종결로 REMOVE 확정). KEEP 시 CC-BY 4.0 BY 의무 3요소(저자·출처·라이선스 링크·변경 여부)를 THIRD-PARTY-NOTICES에 명시.

### 1-E. 짧은 코드 인용·발췌 (Axiom 저작 문서/데이터 내 제3자 인용)

- `experiments/nim-libp2p-bytesview-slice-e2e/discovery/04_c2_fact_reverification.md:5-28` — bytesview.nim 전체(22줄) + nim-libp2p 테스트 발췌(줄번호 표기)
- `experiments/.../discovery/05_replay_forms_wiring_checklist.md:12-13` — 템플릿 2줄 인용
- `docs/spec/nim_libp2p_bytesview_slice_contract.md:18-20,55-63` — 템플릿 2줄 + noise.nim 호출부 인용
- `docs/evidence/nim_libp2p_bytesview_slice_2026-10-22.md`, `docs/evidence/bug_verdict_contract_slice_2026-10-08.md:56-58` — 코드 줄·docstring 참조 인용
- `docs/spec/base36_sizing_binding_contract.md:18-23` — stew 사이징 함수 2개 인용(라인 출처 표기)
- `experiments/act2-wpi-structural-ingress/canonical/signature_corpus{,_run1,_run2}.json` — Nim 표준 라이브러리 `lib/pure/bitops.nim`(MIT, "Nim Authors 2017 + Status Research 2019") head200/tail200 400자 발췌
- `experiments/act2-wp4d-symbol-identity/wp4d-definition-inventory-nim-stew-RAW.txt`(193KB) 외 2종 — nim-stew 정의 시그니처 1390건 추출물

→ L2에서 발췌 귀속 표기로 정리(golden/negative stew 발췌 포함).

### 1-F. 외부 빌드 의존성 (in-tree 코드 없음 — nimble.lock 핀; SAL 고지 대상)

| 패키지 | 라이선스(원문 확인) | 실제 사용 |
|---|---|---|
| nim 2.2.10 (nim-lang/Nim) | MIT | 툴체인 |
| malebolgia 1.3.2 (Araq) | MIT ©2023 Andreas Rumpf | `src/gate/*` 다수 import — 바이너리 포함 |
| checksums 0.2.2 (nim-lang) | MIT ©2023 Nim Contributors | `src/` 전역(sha2) — 바이너리 포함 |
| fusion 1.2 (Araq/nim-lang) | MIT | `src/gate/rule_patterns.nim:11` — 바이너리 포함 |
| nimcrypto 0.7.3 (cheatfate) | MIT ©2018 Eugene Kabanov | **활성 의존**(R2a 정정) — tools/ 3파일 import(`rule_proposal.nim:12`·`agent_bypass_sign.nim:22`·`agent_bypass_commit.nim:19`), 빌드시간 fetch·비-vendor |
| ed25519 0.1.1 (niv) | MIT | vendor/ 사본으로 충족 |
| Z3 4.13.3 (Z3Prover) | MIT | 외부 바이너리, hermetic 다운로드(`.github/actions/setup-axiom-toolchain/action.yml`·`tools/build_hermetic_binaries.nim`) |
| charon 0.1.281 | — | .llbc 생성 도구(출력물만 in-tree) |

---

## 2. Original 판정 근거 요약

- **src/ 전역(트랙된 Nim 소스)**: 저작권 표기 0건, 외부 라이선스 문구 0건, SPDX 0건. 유일한 "Adapted from"(`src/engine/task_dag.nim:4`)은 내부 파일 참조. 임포트는 stdlib + 1-F 의존성뿐.
- **tools/, bin/, ci/, config/**: 동일 무매치. `config/vendors.nims`는 Z3 hermetic 설정(Axiom 저작).
- **docs/(md)**: 저작권 매치 0건 — 제3자 인용은 1-E 나열분뿐.
- **tests/**: 저작권 매치 2건만(1-B). `tests/fixtures/rust/axiom_*_probe` 5크레이트는 Axiom 저작 프로브(외부 의존성 없음). `.llbc`는 charon 생성 산출물. 그 외 픽스처 전부 Axiom 제작·명명.
- **proofs/**: `lake-manifest.json` packages 0건, `Generated/SharedIRHeader.lean`은 Axiom 생성기 산출("Auto-generated by ir_def.nim — DO NOT EDIT"), 나머지 .lean은 Axiom 저작.
- **experiments/ tarball들**: 전수 확인 — Axiom 자체 프로브 TOML 입력·로그·출력뿐(유일한 제3자 예외 = 1-C deps.tar.gz).
- **Unknown 코드 0건** — §3의 5항은 문서 판본·메타데이터 미확정분이었고 전부 해소됨.

## 3. UNKNOWN 5건 해소 기록 (R2a, 2026-11-05)

1. `Abstract Interpretation.pdf` → **Cousot & Cousot POPL'77** 확정(6중 기하 정합 — 타이틀 라인 폭 4/5 ≤1.2pt·133.0pt 완전 일치; PDF 16p = 부가 타이틀 시트 1장 + 논문 본체 15장; 1999-04-22 프랑스 Distiller 스캔). '51쪽 원본' 과제 가정은 오류로 판명.
2. `SVF-SVC…pdf` → 전체 서지·저자 확정(TACAS 2025 LNCS 15698, McGowan·Richards·Sui, CC-BY 4.0).
3. nimcrypto 0.7.3 → **잔존 핀이 아닌 활성 의존으로 정정**(tools/ 3파일 import + nimble requires·lock 핀, 제거 커밋 없음, MIT).
4. PDR-ER 저자 → **Luka & Vizel 2인 확정**(로컬 표지·arXiv 메타·Springer·CAV 2025 accepted 목록 3중 교차).
5. `Subjective_logic.pdf` → 저자 공식 배포 draft 확정(wayback 2015-01-31 스냅샷과 pdftotext 전문 100% 일치, 2016 Springer 출간 후 게시 철수, 문서 내 라이선스 표기 0건) → REMOVE 근거 확보.

## 4. SAL 1.0 공개 전 정리 대상 충돌 (부록 — L2·E2 입력)

1. 루트 `LICENSE`(독점 조항)과 in-tree 제3자 코드(zlib/MIT/Apache-2.0 OR MIT)의 모순 → L1 개정 + THIRD-PARTY-NOTICES로 해소.
2. status-im 헤더가 참조하는 `LICENSE-APACHE`/`LICENSE-MIT` 파일 미포함 → `LICENSES/` 생성으로 해소.
3. `deps.tar.gz` 내 라이선스 전문 미동봉 → 재패키징(MANIFEST 재생성 + replay 검증).
4. vendor/ed25519의 MIT가 nimble 선언뿐(MIT 전문 부재), nimble version 1.0.0 ≠ lock 핀 0.1.1 → `LICENSES/MIT.txt` 동봉 + version 불일치 기록.
5. docs/spec PDF — §1-D 판정표대로 REMOVE 19종(#19 포함·인용 manifest 대체) / KEEP 2종.

## 5. REMOVE분 인용 manifest (18종 — PDF 제거 후 대체 서지)

| 제목 | 저자 | 연도 | DOI / arXiv | 공식 링크 |
|---|---|---|---|---|
| Formal Mathematical Reasoning: A New Frontier in AI | Yang, Poesia, He, Li, Lauter, Chaudhuri, Song | 2024 | arXiv:2412.16075 | https://arxiv.org/abs/2412.16075 |
| Abstract Interpretation: A Unified Lattice Model for Static Analysis of Programs by Construction or Approximation of Fixpoints (POPL'77, pp.238–252) | Patrick Cousot, Radhia Cousot | 1977 | 10.1145/512950.512973 | https://dl.acm.org/doi/10.1145/512950.512973 |
| Checking Safety Properties Using Induction and a SAT-Solver (FMCAD 2000, LNCS 1954) | Sheeran, Singh, Stålmarck | 2000 | 10.1007/3-540-40922-X_8 | https://doi.org/10.1007/3-540-40922-X_8 |
| Design and Synthesis of Synchronization Skeletons Using Branching Time Temporal Logic (Logics of Programs, LNCS 131, pp.52–71) | Clarke, Emerson | 1981 | 10.1007/BFb0025774 | https://doi.org/10.1007/BFb0025774 |
| Dependent Types in Practical Programming (CMU 박사논문; 출판판 POPL'99, pp.214–227) | Hongwei Xi; Xi & Pfenning | 1998/1999 | 10.1145/292540.292560 | https://dl.acm.org/doi/10.1145/292540.292560 |
| Formal verification of a realistic compiler (CACM 52(7):107–115) | Xavier Leroy | 2009 | 10.1145/1538788.1538814 | https://dl.acm.org/doi/10.1145/1538788.1538814 |
| LeanDojo: Theorem Proving with Retrieval-Augmented Language Models (NeurIPS 2023 D&B) | Yang 외 8인 | 2023 | arXiv:2306.15626 | https://arxiv.org/abs/2306.15626 · https://papers.nips.cc/paper_files/paper/2023/hash/4441469427094f8873d0fecb0c4e1cee-Abstract-Datasets_and_Benchmarks.html |
| Programming with Abstract Data Types (Proc. ACM SIGPLAN Symp. VHL Languages, pp.50–59) | Liskov, Zilles | 1974 | 10.1145/800233.807045 | https://dl.acm.org/doi/10.1145/800233.807045 |
| Program Slicing (ICSE-5, pp.439–449; 저널판 TSE SE-10(7):352–357) | Mark Weiser | 1981/1984 | 10.1109/TSE.1984.5010248 (저널판) | https://doi.org/10.1109/TSE.1984.5010248 |
| Property Directed Reachability with Extended Resolution (CAV 2025, LNCS 15931, pp.258–280) | Andrew Luka, Yakir Vizel | 2025 | 10.1007/978-3-031-98668-0_13 · arXiv:2505.18998 | https://link.springer.com/chapter/10.1007/978-3-031-98668-0_13 (CC-BY 4.0) · https://arxiv.org/abs/2505.18998 |
| SAT-Based Model Checking without Unrolling (VMCAI 2011, LNCS 6538, pp.70–87) | Aaron R. Bradley | 2011 | 10.1007/978-3-642-18275-4_7 | https://doi.org/10.1007/978-3-642-18275-4_7 |
| SMT-Based Model Checking for Recursive Programs (CAV 2014, LNCS 8559, pp.17–34) | Komuravelli, Gurfinkel, Chaki | 2014 | 10.1007/978-3-319-08867-9_2 · arXiv:1405.4028 | https://doi.org/10.1007/978-3-319-08867-9_2 |
| Subjective Logic (draft 2013-02-18; 정본 Springer 서적 2016) | Audun Jøsang | 2013/2016 | 10.1007/978-3-319-42337-1 (서적) | https://doi.org/10.1007/978-3-319-42337-1 · https://web.archive.org/web/20150131150636/http://folk.uio.no/josang/papers/subjective_logic.pdf |
| Temporal Induction by Incremental SAT Solving (ENTCS 89(4):543–560) | Eén, Sörensson | 2004 | 10.1016/S1571-0661(05)82542-3 (CC-BY-NC-ND 3.0) | https://doi.org/10.1016/S1571-0661(05)82542-3 |
| Counterexample-Guided Abstraction Refinement (CAV 2000, LNCS 1855, pp.154–169; 확장판 JACM 50(5)) | Clarke, Grumberg, Jha, Lu, Veith | 2000/2003 | 10.1007/10722167_15 · 10.1145/876638.876643 | https://doi.org/10.1007/10722167_15 |
| Program Synthesis (FnT Programming Languages 4(1-2):1–119) | Gulwani, Polozov, Singh | 2017 | 10.1561/2500000010 | https://doi.org/10.1561/2500000010 |
| Propositions as Types (CACM 58(12):75–84) | Philip Wadler | 2015 | 10.1145/2699407 | https://dl.acm.org/doi/10.1145/2699407 · https://homepages.inf.ed.ac.uk/wadler/papers/propositions-as-types/propositions-as-types.pdf |
| Combination of Evidence in Dempster-Shafer Theory (SAND2002-0835) | Carole J. Sentz, Scott Ferson | 2002 | 10.2172/800792 | https://www.osti.gov/biblio/800792 |

KEEP분 참고 링크: #13/#21 → https://link.springer.com/book/10.1007/978-3-031-90660-2.

## 6. 잔여 UNKNOWN (전부 마이너 세부 — 판정 무영향)

- #2 부가 타이틀 시트의 정확한 출처(OCR 도구 부재 — 논문 본체 식별·판정 무영향)
- #9 Weiser ICSE'81 원문 DOI(Crossref 미등재 — 저널판 TSE DOI 대체 인용으로 manifest 확정)
- #5 Xi thesis 현행 공식 소재(저자 현행 홈페이지에 thesis 링크 없음 — 식별 자체는 확정)
- #15 Eén-Sörensson NC 호환성(SAL 배포의 비상업 지위 미확정 — 판정은 보수 REMOVE로 확정)

## 7. 검증 명령 (read-only)

`git grep -n -i 'copyright'` / `'all rights reserved'` / `'©'` · `git ls-files '*.pdf' | wc -l` · `tar -tzf experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz | cut -d/ -f1 | sort -u` · `pdftotext`·`pdfinfo`·`pdffonts`·`pdfimages -list` · `git log --all --diff-filter=A --name-only -- 'docs/spec/*.pdf'` · `git log --follow -- LICENSE`
