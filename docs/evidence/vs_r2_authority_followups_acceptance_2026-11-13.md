# VS-R2 Authority-First 후속 런타임 최적화 (VS-R2a / VS-R2b / VS-R2c / VS-R2d) & U1 LTO 실측 — 수용 증거 (2026-11-13)

> **종류**: 실행 증거 기록 (acceptance evidence). 목적은 VS-R1/VS-C1 착지(`13e1604a`) 이후 계획 없이 즉시 결정론적으로 해결 가능한 4개 Authority 위임 슬라이스(VS-R2a Z3 OS `poll(2)` 위임, VS-R2b 저널 클로저 인메모리 검증, VS-R2c 콘텐츠 SHA 기반 AST 단일 파싱 메모, VS-R2d Vault 매니페스트 배치 단일 쓰기)의 구현·검증 결과와 U1 LTO A/B 실측 데이터를 한 문서에 고정하는 것이다.
> **권위**: 본 문서는 기록이며 어떤 판정도 대체하지 않는다. 착지 판정 권위는 GitHub ruleset(`main` #27097366, `axiom-admission-gate` #25218071, `landing-integrity` #23943917)·6대 required checks·merge queue다(`Authority ≠ Adapter`, AGENTS.md §2.3).
> **브랜치**: `workstream/vs-r2-authority-followups` (base: `main` `5fd3cc0d45d9f03c9c6a198dd1d1577336b002f6`).

---

## 1. 슬라이스 정의 및 Authority 경계 (Claims & Authority Architecture)

| 슬라이스 | 대상 사실 / 작업 | 단일 Authority | 변경 전 중복·낭비 | 변경 후 구조 |
|---|---|---|---|---|
| **VS-R2a** | Z3 영속 워커 파이프 대기 | OS 커널 `poll(2)` (`src/verification/solver/z3_pool.nim`) | `poll(fd, 1, 0)` 비블로킹 프로브 + `sleep(5)` / `sleep(1)` 폴링 루프 | `z3WorkerWaitData(process, deadlineMs)`가 남은 시간(`min(remaining, high(int32))`)을 `poll(2)`에 위임; `POLLIN or POLLHUP or POLLERR` 준비 반환 및 `EINTR` 시 동일 절대 deadline 재계산 |
| **VS-R2b** | 저널 클레임 VKD 클로저 검증 | `verifyCertificateClosureNode` (`src/verification/certificate_verifier.nim`) | `verifyJournalClaimClosure`가 이미 메모리에 있는 `JsonNode`를 직렬화해 임시 파일에 쓰고 `verifyCertificateClosure`가 다시 읽어 파싱 후 삭제 | `verifyCertificateClosureNode(certNode, certPath, projectRoot)`가 인메모리 `JsonNode`를 직접 검증; 파일 어댑터(`verifyCertificateClosure`)와 저널 어댑터가 단일 구현 공유 |
| **VS-R2c** | 동일 소스 바이트 반복 AST 파싱 | `parseStringAST` (`src/core/parser_utils.nim`) | `selectProofCandidates`가 후보당 동일 모듈 바이트를 3회(`computeCanonicalAstHash`, `measureExtractionAgreement`, `measureSourceBindingInventory`) 재파싱 | `sha256Hex(content)` 키 기반 스레드 로컬 FIFO 메모(용량 16)가 오류 없는 `PNode`를 반환; 3회 파싱 → 1회 파싱(`parsesExecuted=1, memoHits=2`) |
| **VS-R2d** | Phase-13 Vault 매니페스트 영속화 | `atomicWriteManifest` (`src/verification/vault_manifest.nim`, 호출부 `src/cli/axiom_engine.nim`) | `runBatchVerification` 루프 내부에서 인증서마다 전체 매니페스트 직렬화 + 임시파일 원자적 교체 + `vault-manifest` 저널 커밋 N회 반복 | 루프 내부는 `mergeResult` 인메모리 병합만 수행하고 루프 경계(`if irBatch.certificates.len > 0`)에서 `atomicWriteManifest` 1회 호출 |

---

## 2. 변경 표면 (Change Surface)

| 파일 | 표면 등급 | 변경 요약 |
|---|---|---|
| `src/verification/solver/z3_pool.nim` | `PRODUCT` | `z3WorkerHasData`를 블로킹 `z3WorkerWaitData(process, deadlineMs)`로 교체; `waitForSentinel`의 `sleep(1)` 및 쿼리 루프의 `sleep(5)` 바쁜 대기 제거 |
| `tests/unit/z3_budget_clamp_test.nim` | `PRODUCT` | `Z3WorkerWaitData` 블로킹 `poll(2)` 왕복·응답 지연 상한 회귀 테스트 추가 (10/10 PASS) |
| `src/verification/certificate_verifier.nim` | `PRODUCT` | `verifyCertificateClosureNode*` 추출 및 기존 파일 기반 `verifyCertificateClosure*`를 얇은 어댑터로 유지 |
| `src/verification/cert_reconcile.nim` | `PRODUCT` | `verifyJournalClaimClosure`에서 임시 파일 생성·쓰기·재파싱·삭제 왕복 제거 (`DECISION-0672` / `DECISION-0671` 프라그마 바이트 보존) |
| `src/core/parser_utils.nim` | `PRODUCT` | `sha256Hex(content)` 키 기반 스레드 로컬 `PNode` 메모(용량 16) 및 `parseMemoStats`/`resetParseMemoStats` 추가 (`src/core/` `procCount <= 952` 불변식 보존) |
| `src/core/ast_hash.nim` | `PRODUCT` | `nkIdent`의 `hash(n.ident)`가 포인터가 아니라 인터닝된 문자열 해시(`PIdent.h`)임을 명시하도록 주석 정정 |
| `docs/spec/nim_ast_node_shape_quirks.md` | `DOC` | §0.5 Quirk Mandate에 따라 Q4(`hash(PIdent)` = `PIdent.h` 문자열 해시, 2개 독립 `IdentCache` 실측 프로브) 문서화 |
| `tests/test_ast_hash_whitespace.nim` | `PRODUCT` | VS-R2c 파서 메모 3대 변조 시나리오(동일 경로 재호출·동일 바이트 길이 내용 변조 무효화·공백 변형 키 분리 및 AST 해시 불변) 추가 |
| `src/cli/axiom_engine.nim` | `PRODUCT` | `runBatchVerification` Phase-13 루프에서 `manifest.atomicWriteManifest(manifestPath)`를 루프 경계로 1회 호이스팅 |
| `tests/verification/test_wave5b_commit.nim` | `PRODUCT` | Test 7 추가: 4회 `mergeResult` + 1회 `atomicWriteManifest`가 정확히 1개의 `vault-manifest` 저널 레코드와 바이트 동일 재작성을 생성함을 검증 (7/7 PASS) |
| `src/generated/type_registry_metadata.json` | `CONTROLLED` | 허메틱 컴파일에 따른 생성 타입 레지스트리 정합화 |
| `data/architecture_debt.json` | `CONTROLLED` | `bin/debt_engine --regen-arch` 정합화 (`debt_engine --validate` 1610/1610 PASS) |
| `config/trusted_writer_set.json` | `CONTROLLED` (`trustSurface`) | `bin/reanchor_pin --ref HEAD --write`로 변경된 클로저 멤버 SHA 재앵커 (멤버십 수 890개 불변) |

---

## 3. Trust Parity & 회귀 검증 결과 (J1 · J2 · J3 · 5-State)

| 검증 항목 | 실행 명령 | 관측 결과 |
|---|---|---|
| 정본 빌드 & Provenance | `make -f ci/checker.mk ci-compile -j4 && ./bin/ax --check-provenance` | `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree` (`exit 0`) |
| 계약 보존 (G1/G2/G4/G6/G7) | `make verify-contract` | `[PASS] g1, g2, g6g4, g7` — `verify-contract PASSED` (`exit 0`) |
| 종단간 증명·커널 재실행 (G7) | `make verify-contract-release-e2e-full` | `[cert] Verify: PASS (kernel re-execution — lean=re-executed, z3=unsat, leanchecker=passed)`, `G7 pass (tier=dual-verified)` (`exit 0`) |
| VS-R1 10종 변조 배터리 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/unit/test_capture_toolchain_fingerprint.nim` | `Results: 15 passed, 0 failed` (`exit 0`) |
| VS-R2a Z3 `poll(2)` 배터리 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/unit/z3_budget_clamp_test.nim` | `Z3BudgetClamp` + `Z3WorkerLease` + `Z3WorkerWaitData` 전부 `[OK]` (`exit 0`) |
| VS-R2b 저널 클로저 배터리 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/unit/test_journal_vkd_report.nim` | 24 OK / 0 FAIL (`exit 0`) |
| VS-R2c AST 메모 변조 배터리 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/test_ast_hash_whitespace.nim` | 기존 5건 + 신규 3종 변조 시나리오 전부 `PASS` (`exit 0`) |
| VS-R2d 매니페스트 배치 배터리 | `AXIOM_HERMETIC_BUILDING=1 nim c -r tests/verification/test_wave5b_commit.nim` | Test 1–7 전부 `PASSED` (`exit 0`) |
| 성능 회귀 게이트 | `make perf-check` | `[PERF OK] LeanKernelVerification: 0.0% change` (`exit 0`) |
| 부채 레지스트리 검증 | `./bin/debt_engine --validate` | `Checks: 1610 total, 1610 passed, 0 failed` (`exit 0`) |

---

## 4. U1 LTO vs No-LTO 실측 데이터 (코드 변경 없음, 측정 증거)

동일 소스 트리(merkle digest `62f0c2f4f71ca83ab8e3688f4bde2b0edea9c9ff1f241b9b78979d6c61f1507b`)에서 `-d:release`(기본 LTO: `-flto -flto-partition=balanced -flto=2`)와 `-d:release -d:axiomNoLto` 두 바이너리를 독립 nimcache로 콜드 빌드하고, 워밍업 후 교차(A, B, A, B…) 실행하여 측정했다.

| 측정 항목 | LTO (`-flto=2`) | No-LTO (`-d:axiomNoLto`) | 차이 / 판정 |
|---|---|---|---|
| 전체 콜드 빌드 (`nim c -d:release`) | **124.98 s** (user 233.75s, maxrss 1.12 GB) | **65.00 s** (user 217.35s, maxrss 1.12 GB) | No-LTO가 **-59.98 s (-48.0%)** 단축 |
| **단독 링크 단계 (`gcc -o …`)** | **98.89 s** (user 178.57s, maxrss 403 MB) | **0.29 s** (user 0.17s, maxrss 84 MB) | LTO가 링크 시간을 **341배 (+98.60 s)** 소모 |
| `ax report --json` (7회 교차 평균) | **0.166 s** | **0.165 s** | 차이 +0.001 s (+0.4%, 측정 오차 내 동일) |
| `ax cert verify --kernel` (3회 교차 평균) | **69.500 s** | **68.180 s** | No-LTO가 오히려 -1.32 s (-1.9%) 빠름 (외부 Lean/Z3 커널 지배) |
| `ax report --canonical-digest` (3회 교차 평균) | **0.160 s** | **0.160 s** | 차이 **0.000 s (0.0%)**, 출력 다이제스트 **바이트 동일** |

- **결론**: Axiom CLI의 런타임 비용은 외부 검증 커널(Lean 4 / Z3)과 I/O가 지배하며, 호스트 Nim 바이너리의 `-flto=2`는 런타임 이득이 0%인 반면 매 릴리스 링크마다 **~99초**를 추가 소비하고 `-Wlto-type-mismatch` / `-Wstringop-overflow` 경고를 유발한다. 단, 기본 빌드 플래그 변경은 `config.nims` 및 CI 빌드 정책 결정 사항이므로 본 PR에서는 측정 증거만 기록하고 별도 계획 항목으로 분리한다.

---

## 5. MUST-T2a 수동 병합 위임 기록 (Pre-Merge Delegation Record)

본 변경은 Tier C checker closure에 속한 파일(`src/cli/axiom_engine.nim`, `src/core/parser_utils.nim`, `src/verification/cert_reconcile.nim`, `src/verification/certificate_verifier.nim`, `src/verification/solver/z3_pool.nim`)의 git blob SHA를 `config/trusted_writer_set.json`에 재앵커(`bin/reanchor_pin --ref HEAD --write`)하므로 `config/policy/merge_admission.json`의 `trustSurface`를 터치한다.

- **적용 규칙**: `docs/agents/rules_workflow.md` §2.8 `MUST-T1` / `MUST-T2` / `MUST-T2a`.
- **위임 원문 및 일자 (2026-11-13, 운영자 `wintrover`)**:
  - *"목표는 코드 작성 완료가 아니라 실제 운영 상태다. `구현 → 검증 → PR → merge → canonical main/production 실행 → acceptance`를 실제 명령과 관측 가능한 증거로 끝까지 확인하라. 선언, PR 생성, 로컬 테스트, 부분 CI 성공은 완료가 아니다."*
  - *"남은 이슈들 중 계획이 필요 없는건 모두 백그라운드 병렬 서브에이전트로 context7 mcp 외부 인터넷 공식문서를 통해 가장 이상적이고 우아하고 근본적이며 결정론적으로 해결해주고, 그 후 남은 계획이 필요한건 왜 계획이 필요한건지 자세히 보고해줘"*
- **Executor 기록**: `agent under explicit delegation from wintrover (2026-11-13)`.
- **준수 사항**: `--auto` arming 사용 금지(`MUST-T1`); PR 생성 후 6개 필수 체크(`admission-check`, `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`)가 모두 `success`로 완료된 것을 L1 관측으로 확인한 뒤, 단발 수동 큐 진입 명령 `gh pr merge <N> --merge`만 실행한다.
