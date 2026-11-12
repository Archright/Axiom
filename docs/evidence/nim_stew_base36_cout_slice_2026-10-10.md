# Base36 C_out Slice Record — S2 판정 실행 · BUG_FOUND(C_out) 종결

> **Status**: Execution evidence record — SPEC-B36-COUT S2 슬라이스 (C_out 단일-기원 캐리어의 실제 파이프라인 판정 종결)
> **Created**: 2026-10-10
> **Terminology**: [docs/spec/bug_verdict_glossary.md](../spec/bug_verdict_glossary.md) (§2.2 공용 4요소 · §2.4 귀속 축 Bug Suspected · §2.4a–§2.4c 귀속 확정/우선순위/requirementSourceStatus · §3 반례 미발견 ≠ 안전)
> **Product contract**: [docs/spec/nim_stew_base36_cout_contract.md](../spec/nim_stew_base36_cout_contract.md) (S0, PR #689 병합) + `config/spec/nim_stew_base36_cout_spec.json` (soExplicit overlay)
> **Axiom revision**: 판정 코어는 **PR #694 (ROTATION)**로 main에 랜딩 — 커밋 `5bb0c628c`, merge OID `650699784e60a699390fdb931aea8ffb91b4ada8` (2026-10-10T07:48:54Z, merge-group admission-gate success). 본 문서·프로브·단위 테스트는 후속 NORMAL PR(본 PR)로 랜딩. 원 계측은 branch `feat/base36-cout-slice` = `bbc5ed150` + `a4a7af76b`에서 수행했고, 랜딩 시 **구조 분리**(ROT_ALLOWLIST 판정에 따른 회전/비회전 분리; 원 PR #693은 판정 원문과 함께 close)로 재구성되었다 — 코드 내용은 동일.
> **선행 슬라이스 병합 OID**: `15da70d87b60bc184fc755246c6d55e3cfd1d5a0` (PR #689 — `feat/base36-cout-contract` → `main`)
> **판정 코어 병합 OID**: `650699784e60a699390fdb931aea8ffb91b4ada8` (PR #694 — ROTATION: closure pin@H 재앵커 857행 정합 실측)

## Question

채택된 C_out 계약(`decodedLength(L) ≥ 2`, 도메인 `3 ≤ L ≤ 3`)을 **실제 파이프라인**(합성 → IR/BMC → P4 승격 → 재생 적합)으로 집행하여, 단일 반례 `s = "kzz"`에 대해 glossary §2.2 4요소가 갖춰진 **BUG_FOUND(C_out)** 판정을 산출하는가? 그리고 그 판정은 독립 state dir 재실행에서 결정론적인가?

## Context

- Subject: status-im/nim-stew clone at `/tmp/b36slice/nim-stew` — **읽기 전용** (Zero-Footprint Integrity)
- Axiom configuration: 로컬 게이트(pre-commit/pre-push), CI=0 표면
- Toolchain: Nim 2.2.10 (`~/.choosenim/toolchains/nim-2.2.10`), z3 4.13.3, Lean 4.33.0
- Experiment ID: `base36-cout-slice-2026-10-10`

## S1 — Subject 고정 (계약 소비, 재측정)

S0 계약 §1의 주체 바인딩을 본 슬라이스 실행일(2026-10-10)에 재측정:

| 항목 | 값 | 명령 |
|---|---|---|
| nim-stew HEAD | `1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` | `git -C /tmp/b36slice/nim-stew rev-parse HEAD` |
| `stew/base36.nim` blob sha256 | `b8a42a6ac6d1057fca0be079aac5750463729fdad771823f1be53b8723a5e0a8` | `sha256sum` |
| porcelain 상태 | **empty** (읽기 전용 유지) | `git status --porcelain` |

재생 적합 기록이 위 HEAD + blob 조합을 그대로 재측정한다(§4요소 ①·무결성 폴드) — 주체가 이동하면 본 기록은 자동 만료다(glossary §4).

## 5링크 사슬 — 보편 ↔ 단일 반례 (계약 §2 전수 기재)

| 링크 | 내용 | 소재 (본 실행 측정) |
|---|---|---|
| 1 | 보편 계약 C_out 채택 (양해 구간 고정) | `config/spec/nim_stew_base36_cout_spec.json` — soExplicit overlay, `validateCoutOverlayNode` 전수 fail-closed 검증(단위 스위트 1) |
| 2 | 구체 입력 `s = "kzz"`, `L = 3` | **기계**: solver 모델 `(define-fun length () (_ BitVec 64) #x…0003)` → 페이로드 `input.length=3` · **문자열**: overlay `canonicalDecisionVector.input = "kzz"` + 본 문서 |
| 3 | 독립 관측: `decode("kzz", buf ≥ 6) == Success`, `outlen = 2` | 외부 프로브(아래 명령·출력) — **파이프라인 사실 아님** (K 근원 계층) |
| 4 | 실제 반환식 평가: `decodedLength(3) = 1` (`(3*179) div 277`, 나머지 260) | **2다리**: solver `propertyViolated=(bvsge (bvsdiv (bvmul length #x…B3) #x…115) #x…2)` + replay `replay.verdict=rvAgree` |
| 5 | `s` ∈ C_out 적용 도메인 | **기계**: P4 pre 재검증(pre `3 ≤ L ∧ L ≤ 3` 하에서 `pre ∧ ¬post` discharge 실패 = 위반 확인, `counterexample_validator.nim` cvConfirmed) + accept 언어 논증(§스윕 — `decode(s, buf ≥ len(s)+3) == Success` 전건이 스위프 전체에서 성립) |

### 링크 3 — K의 외부 관측 (cmd + 출력, 2026-10-10 실측)

```
$ nim c --hints:off --path:/tmp/b36slice/nim-stew \
    -o:/tmp/b36slice/cout_probe_bin experiments/bug-verdict-e2e/cout_probe.nim
$ /tmp/b36slice/cout_probe_bin
=== point vectors ===
input=kzz L=3 need=6 status=Success outlen=2 bytes=05 0F dl=1
input=k00 L=3 need=6 status=Success outlen=2 bytes=00 00 dl=1
input=kzzzz L=5 need=8 status=Success outlen=3 bytes=19 A0 FF dl=3
input=k L=1 need=4 status=Success outlen=0 bytes= dl=0
input=k73 L=3 need=6 status=Success outlen=1 bytes=FF dl=1
input=k74 L=3 need=6 status=Success outlen=2 bytes=01 00 dl=1
=== D3 sweep: s='k'+xy over Sigma^2 ===
candidates=1296 viol=1076 ok=220
zcount0: viol=1040 ok=220 zcount1: viol=35 zcount2: viol=1
```

`kzz` → `Success`, `outlen = 2`, bytes `05 0F`, `dl(3) = 1` — `dl < outlen` 위반의 결정적 테스트 벡터. 프로브는 `nim-check: skip` 마커 커밋물로, 주체 트리 외부에서 `--path`로만 주체 모듈을 참조한다(주체 무변경 — 위 표 porcelain).

## K 근원 계층 + rvAgree 비클레임 (계약 §3 — 보고 의무 유지)

- **K 근원 계층**: `K = 2`는 **EXTERNAL_OBSERVATION**이다 — 주체 트리 외부 프로브의 `decode("kzz") → Success, outlen = 2` 실측(위 링크 3). 이는 파이프라인이 생성·검증한 사실이 **아니며**, 채택된 계약의 K-핀 조건(soExplicit)에 따라 **클레임 상수로 핀**된다. 파이프라인의 역할은 K에 대한 **반증**(`clDisproved`)이지 K의 재유도가 아니다.
- **rvAgree 비클레임 (Authority = 0)**: `replay.verdict=rvAgree`는 `decode` 실행 정확성을 검증하지 **않는다** — 캐리어 산술(`decodedLength(3) = 1`)의 실측 재현만을 진술하며, 어댑터는 관찰자로서 권위가 없다(`counterexample_replay_adapter.md` §3.6). `decode("kzz")`의 `outlen = 2` 관측 자체의 정확성은 이 체인이 보장하지 않는다. BUG_FOUND 보고는 (a) 파이프라인 반증 `clDisproved` ∧ (b) K의 외부 관측 근원 기록의 보고 결합 — 양쪽이 본 문서에 유지된다.

## 판정 실행 — 실제 파이프라인 (2026-10-10)

```
$ AXIOM_STATE_DIR=<state-dir> bin/ax prove \
    --project /tmp/b36slice/nim-stew --target "stew/base36.nim::decodedLength"
```

state dir은 저장소의 `data/verification_scope.lock`로 시딩(멱등 재생산: `bin/ax scope lock`). 파이프라인 관측:

| 단계 | 관측 |
|---|---|
| overlay 채택 | `base36 C_out overlay candidate accepted: decodedLength_cout_binding subject=decodedLength domain=3<=L<=3 claim=decodedLength(L) >= 2 decisionInput=kzz obligations=4 nonTrivial=3` |
| canonical leg | `[canonical-declined] decodedLength — evidence=lean_kernel_rejected` → BMC lane fall-through (계약 §2 — 열린 의무는 BMC lane에서 모델 바인딩) |
| BMC + P4 | solver SAT (`L = 3` 바인딩) → P4 witness admission `cvConfirmed` → **`vsDisproved`** (I3 binding — `counterexample_validator.nim` DECISION-0312) |
| 재생 적합 | `[ce-replay] decodedLength_cout_binding — replay agreed; BUG_FOUND payload assembled (14 records)` |
| claim leg | `clDisproved` |
| 노드 터미널 | `stew/base36.nim::decodedLength — failed` → `summary.failedCount = 1` → `runOutcome.verdict = FAIL` |
| 프로세스 exit | **exit 1** (`cli_outcome.nim` — `VERIFICATION_FAILURE`: 검증 실행, ≥1 실패 노드) |

### §2.2 4요소 — counterExample 페이로드 (14 records 중 대응 항목)

| # | 요소 | 기계 기록 (캡처 프로브 출력, 2026-10-10) |
|---|---|---|
| ① | exact subject commit | `replay.subjectGitRef=1853f20bdfeda61331a0b7e02f7aace0e88a0dfe` + `replay.moduleSha256=b8a42a6a…` (S0 핀과 일치) · `replay.moduleSha256AfterRun=` **동일** · `replay.porcelainClean=true` — 실행 전후 주체 무변경 |
| ② | exact input | `input.length=3` (solver 모델), `input.btype=0` (`Base36Lc`) — 문자열 `s = "kzz"`는 overlay 결정 벡터 + 본 문서 |
| ③ | 위반 서술 | `propertyViolated=(bvsge (bvsdiv (bvmul length #x00000000000000B3) #x0000000000000115) #x0000000000000002)` — `decodedLength(L) = (L·179) div 277 ≥ 2` 가 `L = 3`에서 거짓 (`(3·179) div 277 = 1`) |
| ④ | replay 기록 | `replay.verdict=rvAgree` (`propertyHolds == false` — 위반 재현) · `replay.exitCode=0` · `replay.nimVersion=Nim Compiler Version 2.2.10 [Linux: amd64]` · `replay.hostPlatform=linux-amd64` |

나머지 9 records는 무결성 폴드다: `replay.treeMerkle=25a296cd…`, `replay.nimHash=d9550056…` 등 — 페이로드 전체가 인증서 JSON 서명 범위에 묶인다(`ir_pipeline_runner.nim` ProofCertificate projection).

**exit-code 축의 정정 이력 (§0.9 — 마스킹 없는 기록)**: 최초 계측 실행(동일 커밋 `bbc5ed150`)에서는 P4 승격 반박이 노드 계층에 소비자가 없어 legacy UAP fall-through가 노드를 `no_obligation`으로 분류 → `failedCount=0` → **exit 0** (spin6 관측). `a4a7af76b`가 stage2Budget에 P4 `vsDisproved` 노드 터미널을 추가했다(기존 solver-lane hard-failure 터미널의 C20 후계 분기 — 신규 enum/producer/gate 없음; `cvSpurious`/`cvUnresolved` 재생 불일치는 종전 fail-closed fall-through 유지). 정정 후 모든 실행이 exit 1로 수렴한다.

## ∃-형 스윕 서술 (계약 §4 준수)

**∃-형 서술**: 유효 길이 `L = 3`의 accept 언어 입력에 대해 C_out 위반 입력이 적어도 하나 존재한다 — `s = "kzz"`가 그 반례다(링크 2–5). **∀-형 주장은 하지 않는다**: `L = 5`의 `'kzzzz'`는 등호 사례(`decodedLength(5) = 3 = outlen = 3`)라 ∀-형은 거짓이다.

**1,076 방법론** (미기록 수치 보고 금지 — authority_contract.md 준수; S0 측정의 커밋 프로브 재현):
- (도메인) `D₃ = 'k' ∔ Σ²`, `Σ = "0123456789abcdefghijklmnopqrstuvwxyz"`(`B36LcAlphabet`), `|D₃| = 1,296`
- (유효성) 주체 자체 accept 언어 — `decode(s, buf ≥ len(s)+3) == Success` — 스위프 전체에서 성립(프로브 `doAssert`)
- (집계) `|{s ∈ D₃ : outlen(s) > (3*179) div 277 = 1}| = 1,076` — zcount 분해: 0 → 1,040 / 1 → 35 / 2 → `'k00'` 1건; 비위반 220; 경계 `'k73'`(255 → 1B, 비위반) vs `'k74'`(256 → 2B, 위반)
- 실측: S0 `/tmp/b36slice/c_out_probe.nim` (2026-10-10) + 커밋 프로브 `experiments/bug-verdict-e2e/cout_probe.nim` 재현 — 두 실행 결과 동일

## 2계층 provenance (계약 §5)

| 계층 | 상태 | 근거 |
|---|---|---|
| 계약 계층 (Axiom-owned C_out) | **BUG_FOUND(C_out)** | vsDisproved(P4 cvConfirmed) ∧ clDisproved ∧ §2.2 4요소 ∧ 본 문서의 (b) K 근원 결합 |
| upstream (nim-stew base36) | **BUG_SUSPECTED** (귀속 라벨 — glossary §2.4) | docstring "estimated" 면책 · README/pinned RFC sizing 규범 부재 · in-tree 호출자 0건 (S0 계약 §5 유지) |

**승격 조건 (기본 불승격, fail-closed)**: S0 계약 §5의 3조건(pinned 텍스트 약속 위반 입증 / in-tree 호출자 피해 입증 / maintainer 인정) 중 하나가 입증될 때만 **Bug Confirmed**로 승격한다(구칭 `BUG_FOUND(upstream)` — glossary §2.4 개정으로 폐기된 명칭). 본 슬라이스는 승격 조건을 조사하지 않았으며 그 어떤 것도 입증하지 않았다.

**표시 축 정명 (canonical naming — glossary §2.4a–§2.4c; 표시 라벨 전용, 기계 값 아님)**:

- RULE 축 = **"Axiom-Defined Rule Violated"** — `vrFail ∧ clDisproved ∧ 공용 4요소(§2.2) ∧ claimOwnership.owner == "axiom-defined-rule"` (glossary §2.4 RULE 축 정밀도 규칙; `vrFail` 단독 불충분)
- 귀속 축 = **"Bug Suspected (upstream-spec; recordedDisclaiming)"** — E1/E2/E3 미입증 → Bug Confirmed 아님(glossary §2.4a); docstring "estimated"의 기록 면책 → `requirementSourceStatus = recordedDisclaiming`(glossary §2.4c — upstream-spec 플래그 표시, (a)형 확정 차단)

## 결정론 — 독립 state dir 2회 (A3)

동일 커밋(`a4a7af76b`)·동일 명령, 독립 state dir `/tmp/b36slice/ax_s2_stateJ1`·`ax_s2_stateJ2`, 순차 실행 (2026-10-10):

| 투영 | J1 | J2 | 일치 |
|---|---|---|---|
| `canonicalRunDigest` | `29db1e362ad17adb15a76b90bfad89f0d8043e0ed8b6f12f55f486f5b7241ccf` | 동일 | ✓ |
| `runAccountingDigest` | `982beeb9085ae2cddeb810b0f9dff937e45f6e1f53b494a3a14cb953a3eb1dfb` | 동일 | ✓ |
| `runOutcomeDigest` | `d9b254d4d834cea34e2aed3c4e3986e5308d0588f648fc102c24e60ab2a354e9` | 동일 | ✓ |
| 노드/요약 | `failed`, `failedCount=1`, `verdict=FAIL` | 동일 | ✓ |
| exit | 1 | 1 | ✓ |
| evidence CAS (콘텐츠 주소 `31badc3c…`) | `3522d17095b6…` | 동일 | ✓ |

캐리어 증거 아티팩트(`.axiom/cache/evidence/31badc3c6a09a7a5cba61ba63770a878894795a6e36d46abff2f1b88a24fc865.json` — 합성 캐리어의 completeness 증거)와 노드 선택·토폴로지 캐시도 바이트 동일. 차이가 난 파일은 타임스탬프 운영 아트팩트뿐이다: `logs/ax_proof_state.json`(벽시계 타임스탬프), `build/certificates/manifest.json`(`lastVerifiedAt` 필드 — 제거 시 5개 엔트리 완전 동일 실측), 실행 저널 커밋 id — 이들은 canonical 투영이 아니다.

## 단위·게이트 검증

- `nim r tests/unit/test_base36_cout_binding.nim` — **26/26 PASS** (클린 트리; 4 스위트: overlay 로드 fail-closed 11 · 합성 8 · 재생 5 · 판정 투영 3 — 판정 스위트는 실제 `runIrPipelineWithCas` 경로에서 vsDisproved ∧ clDisproved ∧ 4요소를 측정)
- `bin/ax prove` 판정 실행 3회(spin7 + J1 + J2) — 전부 exit 1, 페이로드 14 records, `replay agreed`
- pre-commit 게이트 (커밋 `bbc5ed150`·`a4a7af76b`): nim check gate PASS · anti-theater PASS · layer-enforcement PASS
- Subject tree: 실행 전후 porcelain empty (A4) — 재생 폴드 `moduleSha256AfterRun == moduleSha256`가 기계 확인

## 3축 분리 (A5)

| 축 | 값 | 근원 |
|---|---|---|
| 대상 판정 | **BUG_FOUND(C_out)** — `s = "kzz"`, `L = 3` | 본 문서 (vsDisproved ∧ clDisproved ∧ 4요소 ∧ K 근원 결합) |
| 프로세스 exit | **1** (`VERIFICATION_FAILURE`) | `cli_outcome.nim` 단일 사상 — `projectRunOutcome`: `failedCount > 0` |
| PR merge OID | merge authority는 GitHub이다(§2.3). S1 계약 슬라이스 = `15da70d87b60bc184fc755246c6d55e3cfd1d5a0`(PR #689) · 판정 코어(ROTATION) = `650699784e60a699390fdb931aea8ffb91b4ada8`(PR #694) · 본 증거 슬라이스 = 후속 NORMAL PR의 GitHub 네이티브 MERGE 커밋으로 확정 | GitHub |

## Evidence

- 주체 바인딩: 본 문서 S1 표의 명령 재실행으로 재현 가능.
- K 외부 관측: `experiments/bug-verdict-e2e/cout_probe.nim` (nim 2.2.10, `--path:/tmp/b36slice/nim-stew` — 주체 트리 무변경), 링크 3 cmd+출력.
- 판정 실행: `bin/ax prove --project /tmp/b36slice/nim-stew --target "stew/base36.nim::decodedLength"` — stderr `[ce-replay] … BUG_FOUND payload assembled (14 records)`, `ax_proof_state.json` nodeReports/summary/runOutcome.
- 판정 체인 캡처: `experiments/bug-verdict-e2e/cout_probe_verdict.nim` (S6 선례의 엔진 레벨 캡처 — overlay → 합성 → `runIrPipelineWithCas` → 페이로드 덤프 + reducer/VDA 투영).
- 결정론: J1/J2 state dir — 본 문서 결정론 표의 다이제스트.

## Classification

`Verified` — 커밋된 제품 계약(SPEC-B36-COUT)의 S2 집행 기록. 판정·투영·결정론·exit가 모두 기계 관측으로 입증됨.

## Non-Conclusions

- **NOT a memory-safety claim** — `decode`는 쓰기 전 `Overrun`으로 fail-closed한다(계약 §7). 위반은 "공개 sizing 헬퍼가 유효 입력의 디코딩 크기를 과소 보고"라는 C_out 위반일 뿐이다.
- **NOT an upstream Bug Confirmed** — upstream은 Bug Suspected(라벨 `BUG_SUSPECTED`)에 유지된다(§2계층; 승격 조건 미입증).
- `rvAgree`는 `decode` 정확성을 검증하지 않는다(Authority 0).
- 결정론 다이제스트는 타임스탬프 운영 아트팩트의 차이를 정당화하지 않는다 — canonical 투영에만 적용된다.
- 본 기록은 `decodedLength`가 다른 `int` 폭·도메인 밖(`L > high(int) div 179`)에서도 유효하다고 주장하지 않는다.

## Next Experiment

S3 후보: (1) 인증서 승격 축 — BUG_FOUND(C_out) 4요소의 인증서 바인딩(glossary §2.2 6번 의무의 vault 반영); (2) upstream BUG_SUSPECTED 승격 조건의 입증 절차 설계(glossary §2.4). 둘 다 §0.12 계약 개정 없이는 기존 계약의 소비로만 수행된다.
