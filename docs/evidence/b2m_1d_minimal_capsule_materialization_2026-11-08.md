# 1d — 최소 오프라인 증명 캡슐 materialization M: 실험 증거 착지 — Acceptance(M) = PASS (2026-11-08)

> **Status**: Observation evidence record — **1d 사전계약(`docs/spec/capsule_minimal_materialization.md`) 하의 materialization M 실험(선택·격리 실행×2·4축 acceptance)의 관측·판정 증거 착지**. 실험 실행은 저장소 외부 캠페인 디렉터리(`b2m_1d/`)에서 수행됐다 — 본 착지 시점까지 저장소 무수정(Stage A′·선택·Stage B′ 전 스테이지 `git status --porcelain` 0행·커밋 0건·서브젝트 무접근-수정). 기계 출력·오류 문자열은 관측 원문 그대로 인용한다(재작성·요약·번역 없음). Axiom4에 착지하는 것은 본 문서 + 기계 판독 산출물(`docs/evidence/b2m_1d_2026-11-08/`).
> **Created**: 2026-11-08
> **Written at**: branch `workstream/1d-minimal-capsule-evidence`, branch base = origin/main `895e3cabd2ded8f8acb808b563dc71b44e43c137` (1d 계약 MERGE_SHA₁ `ca06476a51fb2a50bb5c4c1803f26a87495a996c` — PR #15 — 및 erratum PR #18 MERGE_SHA `bc91247e64c2b295b08f418828213e21824c1a98` 포함)
> **Governing docs**:
> - [docs/spec/capsule_minimal_materialization.md](../spec/capsule_minimal_materialization.md) (1d materialization 사전계약 — MERGE_SHA₁ `ca06476a51fb2a50bb5c4c1803f26a87495a996c`, PR #15; §5.1 표 digest erratum 정정 #18 MERGE_SHA `bc91247e64c2b295b08f418828213e21824c1a98`)
> - [docs/spec/aeneas_generation_contract.md](../spec/aeneas_generation_contract.md) (1a 세대 계약 — §5 세대 identity·§6.4 append-only·§9 fail-closed)
> - [docs/spec/mathlib_hermetic_boundary.md](../spec/mathlib_hermetic_boundary.md) (1c 격리 경계 — §4.2·§4.3·§9)
> - [docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md](b2_hermetic_proof_capsule_2026-11-04.md) (원본 B-2 capsule — 판정 기준값 정본)
> - [docs/evidence/b2_capsule_detached_acceptance_2026-11-04.md](b2_capsule_detached_acceptance_2026-11-04.md) (원본 detached — §5.1~§5.4)
> - [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](b1_gate_a_minimal_proof_2026-11-04.md) (B-1 Gate A — §4.10 mutation·§5.3 해시 인벤토리)
>
> **원칙**: 본 문서는 1d 계약 §15가 규정한 "증거 PR" 파동이다 — 계약의 사전등록 아래 수행된 실험 관측(Stage 0 기준 확정 → Stage A′ 재프로비저닝 → 선택 단계 → Stage B′ 격리 실행)을 착지한다. 관측 원문의 정본은 캠페인 디렉터리의 스테이지별 보고서·기계 판독 파일이며, 본 문서는 그 인용·정리·판정 종합이다(각 스테이지 관측의 재실행이 아니다). serde_json·Aeneas·Charon에 대한 어떤 참·거짓 주장도 하지 않는다(§Non-Conclusions).

7-field identity (준수 — 실험 identity):

- PROJECT_UNDER_TEST: **materialization M** — `b2m_1d/` 캠페인 디렉터리(최소 .ltar 집합 S 캐시 `capsuleM/cache/` 1,478파일·102,362,602B + Stage A′ 재프로비저닝 leanproj(루트 빌드 미수행 pristine) + elan toolchain v4.35.0 + stage_b.sh 재구성본(sha `9197a0f0…54e39`) + sandbox 구성). 서브젝트 참조 identity: serde_json v1.0.154 @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` (READ-ONLY 불변 — 사전·사후 manifest `8045f3b1…c7cd4` 동일)
- REVISION: `8c535a260ce561eaab4111aafc29038eb9f77ff3` (서브젝트 HEAD — generation.json `subject.git_head` 정본; 실험 전 스테이지 서브젝트 무변형)
- AXIOM_REVISION: MERGE_SHA₁ `ca06476a51fb2a50bb5c4c1803f26a87495a996c` (1d 계약 착지, PR #15) + erratum #18 MERGE_SHA `bc91247e64c2b295b08f418828213e21824c1a98` (§5.1 표 digest 정정 — 본 문서 §10 Deviations 1 참조)
- CONFIG: **세대 G** — generationId `aeneas-gen/nightly-2026.11.03-ab34bd2+charon-0.1.304+lean-v4.35.0`(1a §5.0). G 동일성은 §5 관문(1a §5 결속 요소 전 항목 재실측 대조)으로 기계 판정 — 관측 일치. M의 구성·인벤토리 결속은 `capsuleM/inventory.json`(sha256 `7d96a4ad…`)이 정본
- TOOLCHAIN_ID: elan **leanprover--lean4---v4.35.0** — bin 4종 재실측 lean `bf8d54e4…ceb38`·lake `8ba83c98…95e1`·leantar `06d613df…7bf3`·clang `df2e7d9b…b9d2` (1a §5.3 기준값과 전부 일치) · lake-manifest `fd3d5b0e…44bd7` · 실행 게이트 bwrap **0.9.0** (binary sha `e3189038…30f71`)
- SCOPE: **1d 실험 증거의 착지** — Stage 0(기준 확정)·Stage A′(4계층 재프로비저닝)·선택 단계(최소 집합 S)·Stage B′(격리 실행×2·4축 acceptance) 관측의 인용·종합과 기계 판독 산출물 수록. **범위 밖**: 실험의 재실행, mutation 재실행(§12 — 상속 판정만), 캡슐 추가 축소, Aeneas 정식 채택(DEFER), 타 머신 재현·이식형 hermetic(§13), 제품 계약 주장(AGENTS.md §0.12)
- EXPERIMENT_ID: `b2m_1d` (campaign ② 최소 오프라인 증명 캡슐 재건 1d — 실험 단위 materialization M)

---

## 1. Question

1d 계약이 사전등록한 제약 최적화 문제(§7) —

```
min |M|  s.t.  ProofGeneration(M) = G          (§5 관문 통과 — 세대 G identity)
              ∧ Acceptance(M) = PASS           (§11 4축 전부)
              ∧ NetworkAccess(M) = DENIED       (§10 격리 관측)
              ∧ Run₁′(M) = Run₂′(M) = Original  (§11.2 재현축 — 원본 기록값)
```

— 이 제약식이, 소실된 원본 B-2 캡슐(180,040파일·11,353,320,247B)을 대체하는 신규 materialization M(공식 Mathlib 캐시 선택 수단의 전이 import 폐쇄 기준 최소 .ltar 집합 S = 1,478개·102,362,602B — 원본 9,031개·455,355,304B의 16.37%/22.48%)에 대해 기계 관측으로 충족되는가? 특히 (1) §5 G 동일성 관문이 재실측 전 항목 일치로 통과하는가, (2) bwrap 네트워크 차단·고정 식별 실행 기반에서 2회 독립 실행(Run₁′·Run₂′)이 원본 B-2의 커널 판정(axioms 2행 바이트 동일·sorryAx 0·Built 5 실재 재컴파일)과 산출물 identity(olean digest 5종)를 원본 기록값과 동일하게 재현하는가, (3) 판정은 4축(§11)과 §8·§12·§14 규칙 아래 어떻게 종결되는가?

## 2. Context (실험 identity)

- **세대 G**: 1a §5 결속 요소 전체로 고정 — generationId `aeneas-gen/nightly-2026.11.03-ab34bd2+charon-0.1.304+lean-v4.35.0`. 원본 `generation.json`(sha256 `efdced76b105cc4843aad99cbe2f4eedab039439742870c34d85107e5d1b5133`)·`sha256(inventory.json)`(`742ec2c0f78c3490621d42c67e6f88698f5588422f95b1fcf612a5af9f1d781e`)은 1a §6.4 append-only 불변 — M 실험의 모든 산출은 새 기록으로만 추가됐다(Stage 0 추출 정본: 원격 main capsule §5.2 임베딩 전문 15,272B, 자기검증 sha 일치).
- **원본 캡슐 소실**: 2026-11-08 캠페인 관측 — 6경로 전수 확인(Stage 0 기록). 세대 identity는 1a §5 결속 기록의 순수 함수이므로 소실이 세대 G의 identity·capsule·detached 증거 기록에 영향을 주지 않는다(1d §1 P0 해소).
- **materialization M**: 1d §4 실험 단위 — 캐시(S)·증명 입력(leanproj 코어 9파일)·증명 도구(toolchain bin 4+lib 5)·실행 스크립트(stage_b.sh 재구성본). M의 인벤토리 결속(`capsuleM/inventory.json`, 239,160B, sha256 `7d96a4adef97267ee60a8b63fabdd4d847e52e89a263b8054520704a4697a6dd` — 자기참조 회피로 자기 자신은 열자에서 제외하고 그 digest를 기록에 결속)은 1c §3.2 양식 준용·원본 Stage A 결속과 별개 판정이며, §4.2 부분집합·동일성 조건(S 전수가 원본 인벤토리 항목의 이름 기준 부분집합·대응 파일 sha256·bytes 동일)으로 원본과 계약상 연결된다.
- **AXIOM_REVISION**: 원격 `Archright/Axiom` main — 1d 계약 MERGE_SHA₁ `ca06476a51fb2a50bb5c4c1803f26a87495a996c`(PR #15, 2026-11-08). 실험은 저장소 무수정 상태로 수행(전 스테이지 porcelain 0행). §5.1 표 TypesExternal_Template.lean digest 전사 오류는 erratum PR #18(MERGE_SHA `bc91247e64c2b295b08f418828213e21824c1a98`)로 정정 착지됐다 — 정본 anchor(b1 Gate A §5.3, 64자 `514fbfd9…cccfef485`)와 Stage A′·B′ 실측이 byte-exact 일치하므로 관문 판정·본 증거에는 무영향(§10 Deviations 1).
- **실행 기반(계약 §6.2 관측)**: Linux Mint 22.3 (noble)·x86_64·kernel `6.17.0-42-generic`·glibc `2.39-0ubuntu8.9`·bwrap `0.9.0` (binary sha256 `e318903862396f96de3df57264e0158682b952fd3fb53ac23d876413e7b30f71`) — 전부 원본 기준값(capsule §5.2 `execution_base`)과 일치. 계약 §6.3: 열거되지 않은 축은 미측정이며 "실행 기반이 모든 면에서 동일하다"는 주장이 아니다.
- **실험 단계(파동)**: Stage 0(기준 확정 — baseline) → Stage A′(4계층 재프로비저닝·회복) → 선택 단계(최소 집합 S 산출·검증) → Stage B′(bwrap 격리 실행×2 + 4축 acceptance) → 본 증거 착지. 각 단계의 관측 원문·기계 판독 파일은 §6 Evidence에 digest와 함께 수록한다.

## 3. Scope

- **범위 안**: (a) 4스테이지 관측의 인용·정리 — Stage 0(원격 증거 무결성·로컬 생존 자산 재실측)·Stage A′(Layer 1~4 재프로비저닝·pipeline 회복·재작성 digest 대조)·선택(get-·lookup·deps-json 폐쇄·bytes 대조·상한)·Stage B′(사전 관문·격리 실행×2·4축 판정·사후 불변), (b) 4축 판정표와 Acceptance(M)=PASS 종합, (c) digest 사슬(inventory.json·acceptance.json·selection.json·실행 관측 기계 판독 파일), (d) mutation 상속 판정(§12), (e) 대형 산출물의 로컬 내구 위치·재구성 방법 기록, (f) 기계 판독 산출물의 저장소 수록.
- **범위 밖**: 실험 재실행·관측 재수행(본 문서는 착지 기록), mutation 재실행(§12 — 인용 조건만), rustc·charon·aeneas 격리 실행(§9 — 회복 실행은 프로비저닝 기록), 캡슐 추가 축소·Aeneas 정식 채택(DEFER)·타 머신 재현·이식형 hermetic(§13)·업스트림 게시(별도 승인 전 금지)·제품 계약 주장(AGENTS.md §0.12).
- 착지는 본 문서 + 기계 판독 산출물만 — `src/`·§-1 보호파일 무변경. required checks 관측 후 merge queue → GitHub native MERGE로 착지한다(AGENTS.md §2·§2.3 — required checks 0건은 UNKNOWN/NOT READY).

## 4. Procedure (실험 수행 절차 — 각 스테이지 관측 원문 인용)

> 정본: `b2m_1d/stage0/baseline.md`·`stageA/report.md`·`capsuleM/selection_report.md`·`stageB/report.md` 및 각 기계 판독 파일(§6). 아래는 그 절차·관측의 인용이다.

### 4.1 Stage 0 — 기준 확정 (baseline, 2026-11-08)

원격 main 증거 문서 4건을 `gh api contents`로 fetch해 git blob sha·크기 대조(capsule blob `375671f5434847a02ba8272f65d6ce046f8face4` 41,192B·detached blob `0d5b840012008149f933a6b8bc5a85da3a1c6046` 19,656B — 기대와 정확 일치), capsule §5.2 코드펜스에서 generation.json 전문(15,272B)을 바이트 단위 추출해 sha256 자기검증(`efdced76…` — §5.1 기록 정본 digest와 동일). 로컬 생존 자산 재실측: `.ltar` 9,031파일·455,355,304B(원본 Stage A 물리 산출물), elan v4.35.0 bin 4종+lib 5종 sha256, rustc 2종, 서브젝트 HEAD·전수 manifest, bwrap sha·버전. 판정(원문): **원격 증거·세대 정본 무결성 PASS(MATCH) — 로컬 생존 자산 27 MATCH / 2 MISMATCH(`~/.cargo/bin/charon` 0.1.281·charon-driver — 정본은 소실된 aeneas 번들 내장이었음) / 1 NOT_MEASURABLE(lake-manifest — 캡슐 내 파일) — MERGE_SHA 11/11 로컬 MISSING(2026-11-06 rip-and-replace 재생성 세대 기인, 아카이브 repo 생존 실측)**. 기계 판독본: `stage0/baseline.json`.

### 4.2 Stage A′ — 4계층 재프로비저닝·회복 (2026-11-08)

**Layer 1 (network 재취득)**: aeneas 번들 tarball `ed0e336c…7651f5e`(158,648,932B) release 재취득 → aeneas `12e6042c…53a9c`·charon `42267416…32a59c`·charon-driver `bb0f4073…00e9` binary sha256 대조 — 전부 MATCH. elan v4.35.0 4종·서브젝트 HEAD `8c535a26…`(clean)·작업트리 manifest `8045f3b1…`·frozen Cargo.lock `1bc62b1a…` 일치. 원격 증거 문서 3종 fetch·대조(capsule 41,192B diff 0).

**Layer 2 (pipeline 회복)**: `CARGO_NET_OFFLINE=true charon cargo --preset=aeneas --start-from 'serde_json::value::_::as_bool'` → LLBC. stageA 경로 실행본은 `5bdddbfe…`(287,360B — §4.11 경로 의존 필드 1개·+38B 정확히 일치), **원본 경로 적합 실행(`/tmp/b1_gate_a/out/as_bool.llbc`)이 원문 raw LLBC를 byte-exact 재현**:

- LLBC: `cfa5a04f99d55a54ebe098b30256712078c6ff271791ab8b6200de311a5e3dfc` (287,322 B) — **MATCH**
- `aeneas -backend lean -split-files` → 생성 Lean 3종: `Types.lean` `229ec176…2914f60`(1,729B)·`Funs.lean`(원본) `e0fec2a8…41951b32`(1,306B)·`TypesExternal_Template.lean` `514fbfd947d7cb617d81046e60e874b59301b766a52a4b16af4bd72cccfef485`(1,134B) — **전부 MATCH(LEAN_IDENTICAL, byte-exact)**

**Layer 3 (재작성+digest 대조 — 세션 로그 재생)**: B-1 세션 wire.jsonl의 Write/Edit/Bash `tool.call` 원문을 동일 순서로 재생해 stage_b_inputs 9파일 재작성 — **9/9 byte-exact**(lakefile `8a435a42…`·lean-toolchain `ca5f1f60…`·lake-manifest `fd3d5b0e…`(재구성 — 방법·근거 명시)·PrintAxioms `73bb45f7…`·AsBool `a57ea416…`·Funs(1토큰 수정본) `abaca6f6…`·Spec `c072867f…`·Types `229ec176…`·TypesExternal `646ebd42…`) + **stage_b.sh 재구성본 `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39`(969B) MATCH**. mathlib materialization: `MATHLIB_CACHE_DIR=~/.cache/mathlib lake exe cache unpack` — 관측 원문 `Decompressing 9030 file(s) (1 already decompressed)`(총량 9,031, 원본 warm-cold 차이 무해)·manifest 불변(`fd3d5b0e…`)·`lake update` 미실행.

**Layer 4 (cache 실행파일)**: materialize된 mathlib 패키지 cache 실행파일 `a8b0bf25…90d624`(119,669,648B) — MATCH(판정축 아님, 일치 기록).

**bytes 측정(수정안②)**: stageA 전체 158,005파일·8,548,366,327B — leanproj 153,007파일·7,754,673,864B(.lake/packages 148,317·7,248,549,958B / deps/aeneas-lean 4,673·504,319,893B)·elan 17,938·3,137,937,993B. 판정: **프로비저닝 성공(PASS) — 4계층 전 판정축 MATCH, fail-closed 0건**.

### 4.3 선택 단계 — 최소 집합 S (2026-11-08, 네트워크 허용 구간)

공식 Mathlib 캐시 선택 수단(`lake exe cache get-`)으로 루트 5모듈(AsBool·AsBool/Funs·AsBool/Spec·AsBool/Types·AsBool/TypesExternal)의 전이 import 폐쇄 .ltar 집합 S를 신규 캐시 dir에 산출·검증했다(pin `56a005855ea17e0b0958f73ec801ae140b0a1679`·endpoint `https://cache.mathlib.org/mathlib4-master`).

- **리터럴 인자 퇴화 quirk(관측)**: 계약 §7 인자를 문자적으로 실행한 `get- AsBool AsBool.Funs AsBool.Spec AsBool.Types AsBool.TypesExternal`은 exit 0·다운로드 0건이다 — 루트의 직접 import가 전부 비캐시 모듈(`AsBool.*`·`Aeneas`)이라 `getFileImports`의 `isPartOfMathlibCache` 순회 필터가 Mathlib 폐쇄 도달을 차단한다(부록 A 의미론의 downstream 비캐시 경유 클래스 관측 — 로그 원문 보존).
- **실현 인자 실행(최종 S 산출)**: 폐쇄 내 비캐시 모듈 전체 271모듈(5 AsBool 루트 + 266 도달 aeneas-lean 모듈)을 인자로 지정 — 비캐시 모듈의 캐시 패키지 진입 가장자리는 전부 이 루트 집합에서 순회되고 캐시 모듈 간 import는 필터 통과로 전부 순회되므로 get- 폐쇄 = 진폐쇄의 캐시 패키지 부분과 정확히 일치한다(관측: 집합 일치). 관측 원문: `Attempting to download 1749 file(s) from leanprover-community/mathlib4 cache at https://cache.mathlib.org/mathlib4-master` / `Warning: 271 file(s) were not found in the cache.` / `Downloaded all available files (271 not in the cache).` — **exit 0, 다운로드 1,478건**.
- **폐쇄 정합(부분 독립 교차검증)**: get- 다운로드 파일(해시명) 1,478 · `lookup` 매핑 해시 1,478(모듈↔해시 단사·전 파일 comment `git=mathlib4@56a0058…`) · `lean --deps-json` 폐쇄 cached 모듈 1,478 — 세 집합 전부 일치. 세 경로의 폐쇄 계산은 `parseImports'` 파서를 공유하므로 이 교차검증은 **부분 독립**이다(§9 Non-Conclusions).
- **§4.2 부분집합·동일성 조건(기계 검증)**: S의 1,478 파일 전수는 생존 로컬 캐시(원본 Stage A 물리 산출물, 재실측 9,031·455,355,304B) 항목의 이름 기준 부분집합이며 대응 각 파일 sha256·bytes 동일 — **bytes 대조 1,478/1,478 MATCH·불일치 0·로컬 부재 0**. 원본 인벤토리 외 파일 0건.
- **상한 대조**: |S| = 1,478 ≤ 사전 측정 상한 1,795 — PASS(초과 아님).
- **최종본 봉입**: 신규 다운로드본을 `capsuleM/cache/`에 봉입(무결성 재검증 1,478/1,478). cached 패키지별 분포(기록): Mathlib 1,193·Aesop 132·Batteries 77·ImportGraph 35·Qq 14·Plausible 13·ProofWidgets 10·LeanSearchClient 4.

판정: **PASS(선택 단계)** — 공식 선택 exit 0·폐쇄 정합·bytes 대조 1,478/1,478·상한 미초과·UNKNOWN 0건. 기계 판독본: `capsuleM/selection.json`·`records/`·`logs/`.

### 4.4 Stage B′ — bwrap 격리 실행 ×2 + 4축 acceptance (2026-11-08)

**사전 관문(§5·§6 — 전 항목 재실측)**: elan toolchain bin 4종+lib 5종 sha256·leanproj 코어 9파일 sha256+bytes·`capsuleM/cache` 1,478파일 전수 sha256+bytes(selection.json 대조)·lake-manifest·stage_b.sh(`9197a0f0…`)·서브젝트 manifest(b1 §4.1 원문 방식 전수 재해시)·identity-only 항목(aeneas·charon·charon-driver·LLBC 원문 재현본·생성 Lean 3종·Cargo.lock)·로컬 .ltar 캐시(9,031·455,355,304B)·실행 기반(OS·kernel·glibc·bwrap sha·ldd closure·시스템 lib 6종·toolchain 내부 lib 8종) — **전부 기준값과 일치 → 관문 PASS, 실험 개시**(`stageB/gate/gate_5.json`·`gate_6_2.json`).

**캡슐 M 완성·동결(§4)**: 캐노니컬 트리 digest(정렬 순회 정규 파일 전수 sha256 → `<sha256>  <relpath> <bytes>` 직렬화의 sha256)로 cache S·leanproj 전체·deps/aeneas-lean·.lake/packages·toolchain 5개 트리 digest 산출 → `capsuleM/inventory.json`(239,160B) 작성·동결(sha256 `7d96a4adef97267ee60a8b63fabdd4d847e52e89a263b8054520704a4697a6dd`).

**bwrap 실행 구성**: 원본 `generation.json` `sandbox_config.bwrap_args`(58 토큰)을 그대로 준용 — 토큰 단위 대조 차이는 ro-bind/bind 소스 경로 4곳뿐(`/toolchain`←elan toolchain·`/tmp/b1_gate_a/leanproj`←`stageA/leanproj`·`/cache`←`capsuleM/cache`·`/workspace`←`stageB/run<N>`; 내부 경로·symlink 4종·/proc·/dev·tmpfs /tmp·clearenv·env 6종(PATH·HOME=/tmp/home·LANG=C.UTF-8·TMPDIR=/tmp·LAKE_NO_CACHE=true·MATHLIB_CACHE_DIR=/cache)·chdir·die-with-parent·`/bin/bash /workspace/stage_b.sh` 전부 원문과 동일). 각 실행은 pristine ro-bind 원본에서 `cp -a --reflink=auto` 자체 복사로 시작(실행 산출물 재사용 없음). 캐시 조작은 `lake exe cache unpack`만(get 계열 격리 하 미실행 — §10 금지 목록 준수)·루트 `.lake/build` 삭제 후 빌드(1c §6).

실행 관측 원문(`stageB/run<N>/run.log` [0]~[7], 1,690B·32행·두 실행 완전 패리티):

```
== [0] sandbox state ==
uid=1000 gid=1000 groups=1000,65534
ls: cannot access '/home': No such file or directory
ls: cannot access '/root': No such file or directory
curl_exit=6
== [1] workspace copy ==
== [2] force fresh root compile ==
== [3] cache unpack ==
Already decompressed 1478 file(s)
== [4] build ==
✔ [1796/1801] Built AsBool.TypesExternal (2.8s)        ← run2′: (3.1s)
✔ [1797/1801] Built AsBool.Types (2.1s)                ← run2′: (1.9s)
✔ [1798/1801] Built AsBool.Funs (1.8s)                 ← run2′: (1.6s)
✔ [1799/1801] Built AsBool.Spec (1.8s)                 ← run2′: (1.7s)
✔ [1800/1801] Built AsBool (1.6s)                      ← run2′: (1.6s)
Build completed successfully (1801 jobs).
== [5] print axioms ==
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
== [6] artifact digests ==
e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58  /workspace/leanproj/.lake/build/lib/lean/AsBool.olean
bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9  /workspace/leanproj/.lake/build/lib/lean/AsBool/Funs.olean
5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816  /workspace/leanproj/.lake/build/lib/lean/AsBool/Spec.olean
d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8  /workspace/leanproj/.lake/build/lib/lean/AsBool/Types.olean
a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8  /workspace/leanproj/.lake/build/lib/lean/AsBool/TypesExternal.olean
== [7] ro-mount check ==
touch: cannot touch '/toolchain/.write_test': Read-only file system
toolchain_readonly=ok
touch: cannot touch '/cache/.write_test': Read-only file system
cache_readonly=ok
touch: cannot touch '/tmp/b1_gate_a/leanproj/.write_test': Read-only file system
inputs_readonly=ok
```

소요: Run₁′ **48.4s**(16:43:36.9→16:44:25.3)·Run₂′ **52.3s**(16:48:53.8→16:49:46.2)·bwrap exit 0(각 1회 성공 — 재시도·수정·중단 없음). 로그 [6]의 sha256sum 출력과 샌드박스 종료 후 호스트 직접 재측정이 일치(관측 원문과 산출물 실체의 이중 확인).

## 5. Result

### 5.1 4축 판정표 (§11)

| 축 | 측정값 | 기대값(원본 기록) | 판정 |
|---|---|---|---|
| **1. 판정축(MUST)** | Run₁′·Run₂′ 각: `#print axioms` 2행 바이트 동일(§4.4 원문)·sorryAx 0·Built 5(모듈별 컴파일 시간 1.6~3.1s 관측 — 실재 재컴파일) | 2행 바이트 동일·sorryAx 0·Built 5 | **PASS (2/2 실행)** |
| **2. 재현축(MUST)** | olean 5종 sha256 전부 일치(§5.3 표)·Run₁′=Run₂′ 정규화 full-log diff **0행(0B)**·bwrap exit 0·jobs 1801·빌드 완료 행 동일 | olean 5종 원본 digest·실행 간 동일·원본 관측과 판정·재현 동일 | **PASS** |
| **3. §5 재실측축(MUST)** | 사전 관문 전 항목 MATCH(§5.1·§5.2·§5.3·stage_b.sh·서브젝트·identity-only·로컬 .ltar 9,031/455,355,304B) + 사후 무변동(§5.6) | 전 항목 일치 + 사전→사후 불변 | **PASS** |
| **4. 기록축(기록)** | decompressed **1,478**(원본 9,031)·jobs **1801**(원본과 동일 관측)·bytes(S) 102,362,602·파일 수 비율 16.37%·bytes 비율 22.48%·curl_exit 6·소요 48.4s/52.3s | 변동 허용·값 기록 | **RECORDED** |

**종합**: 4축 전부 충족 + §5 관문 통과 + §6 판정 통과 → **Acceptance(M) = PASS**. §8(olean digest 불일치 시 PASS 발행 금지) 해당 사항 **없음** — 불일치 0건, §8 절차 미발생. §7 제약식의 4조건이 기계 관측으로 충족됐다: ProofGeneration(M)=G(§5 관문)·Acceptance(M)=PASS(4축)·NetworkAccess(M)=DENIED(§10 격리 관측)·Run₁′=Run₂′=Original(§5.3·§5.4).

### 5.2 판정축 원문

두 실행 공통(run.log [5] — capsule §5.5 원문과 바이트 동일):

```
'AsBool.Spec.as_bool_bool_some' depends on axioms: [propext, Quot.sound]
'AsBool.Spec.as_bool_non_bool_none' depends on axioms: [propext, Quot.sound]
```

sorryAx 0 — 허용 가정 집합 `[propext, Quot.sound]` 외 sorry 부재(1c §7·Gate A §4.8). Built 5: `✔ [1796/1801] Built AsBool.TypesExternal` → `AsBool.Types` → `AsBool.Funs` → `AsBool.Spec` → `AsBool` → `Build completed successfully (1801 jobs).` — 원본 기록(1801 jobs·Built 5 동일 순서)과 동일. 루트 `.lake/build`는 pristine 상태(사전 부재 — 관문 실측)에서 `rm -rf` no-op로 실행·신규 컴파일 강제의 의미는 원본과 동일(§10 Deviations 2).

### 5.3 재현축 — olean 5종 (Run₁′ = Run₂′ = 호스트 직접 재측정 = 원본)

| olean | sha256 (원본 기록값 = 두 실행 관측값 — capsule §5.5) |
|---|---|
| `AsBool.olean` | `e5b1ef421f5ebccb6aa35ebeff066db35dd944e97dbfcace61362c8d43340d58` |
| `AsBool/Funs.olean` | `bdf7f0ff6dfc84804d36a640348e9a5af6fe9f1d7e8c8a63b41ce099a6133ad9` |
| `AsBool/Spec.olean` | `5f604d403600172d402091048aebdba1e646c39a30fbe19ff095dfec6601f816` |
| `AsBool/Types.olean` | `d66574f5f531a479d158654351aef301446b61ab7da47684526360a2fd396db8` |
| `AsBool/TypesExternal.olean` | `a41a0bed960f683f4134dddd3edb72da8cd067f369ea66c5d516404ff8bd09b8` |

### 5.4 실행 간 동일성

모듈별 컴파일 시간(2.8/2.1/1.8/1.8/1.6s vs 3.1/1.9/1.6/1.7/1.6s)만 상이 — capsule §5.5 절차 준용 정규화(시간 제외) 후 full-log diff **빈 문자열**(`stageB/run1_run2_normalized.diff`, 0B). [0] 관측도 동일: `uid=1000 gid=1000 groups=1000,65534`·/home·/root 부재·curl_exit=6·unpack `Already decompressed 1478 file(s)`·[7] ro-mount 3종 ok.

### 5.5 네트워크 주장·실행 기반 관측

"**외부 네트워크 통신 불가능 상태에서 실행**"로 기록한다(bwrap `--unshare-net` + /etc 미마운트). curl_exit=6은 관측값일 뿐 시도 부재의 증명이 아니다(capsule §5.5·expected_verdict 원문 준용). 실행 기반은 §2 Context 관측(Mint 22.3·kernel `6.17.0-42-generic`·glibc `2.39-0ubuntu8.9`·bwrap `0.9.0` sha `e3189038…30f71`) — 계약 §6.1 MUST(toolchain bin 4종+lake-manifest)·계약 §6.2 전 항목 일치, 계약 §6.3 목록 밖 차이의 자동 PASS화 0건.

### 5.6 사후 불변 확인 (§11.3 종결 조건)

- 서브젝트: manifest `8045f3b1…` 무변동·HEAD `8c535a26…`·porcelain 0행 (사전=사후)
- M ro-bind 구성요소: 코어 9파일·toolchain bin 4·lib 5·stage_b.sh·S 캐시 1,478 전수 — 전부 무변동(`stageB/gate/post_run_files.json`)
- 트리 digest 사전=사후(`stageB/gate/trees_post.json`): leanproj 전체 `3a4cd397…`(153,006파일·7,754,673,852B)·deps/aeneas-lean `762f22ef…`·.lake/packages `bcf757c7…`·toolchain `c00fd0ef…`(17,925파일·3,137,937,793B — 원본 캡슐 toolchain per_dir와 정확히 동일)·cache S `d51c7700…`
- `capsuleM/inventory.json` sha256 사후 재실측 `7d96a4ad…` 결속값과 일치
- 저장소(Axiom4): porcelain 0행 — 실험 기간 커밋 0건·무수정

### 5.7 mutation 상속 판정 (§12)

상속 조건(전부) = §5 전 항목 재실측 일치(§5.1·§5.2 — G 동일성) 및 stage_b_inputs 9파일 대조 일치 = §5 관문 통과 그 자체 → **충족**. 따라서 B-1 mutation 음성 대조 증거(Gate A §4.10 — `json_mut/src/value/mod.rs` 1라인 `Some(b)`→`None` 치환 시 Lean 번역 실패 원문 `⊢ False`·exit 1·clause 1 킬·clause 2 생존)는 **"B-1에서 실행·기록된 관측의 인용"**으로 M의 실험 기록에 상속된다(재실행 아님 — 1a §4.2 인용 규칙). 상속 조건 위반 0건.

## 6. Evidence

### 6.1 기계 판독 산출물 — 저장소 수록본 (20파일·바이트 동일 복사)

아래 파일은 캠페인 원본(`b2m_1d/`)에서 **바이트 동일 복사**로 `docs/evidence/b2m_1d_2026-11-08/`에 수록했다(무결성은 원문 digest와의 대조로 검증 가능):

**stageB — 4축 acceptance 기계 판정·실행 간 동일성**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/stageB/acceptance.json` | `d9b0c136e8e03914a4789eed2d3b60fa7f8b4b65ee10ea1cc12f92ec260a9db8` | 12385 |
| `b2m_1d_2026-11-08/stageB/run1_run2_normalized.diff` | `e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855` | 0 |

**stageB/gate — 계약 §6.2 실행 기반·사후 파일 무변동·실행 관측 파싱**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/stageB/gate/gate_6_2.json` | `34ccd73b4d25d7a23294d8f4a9d18378237984400a0f9cfb782aac368b2cce0e` | 1753 |
| `b2m_1d_2026-11-08/stageB/gate/post_run_files.json` | `8f242ded984c69278aeafb5a302d8344dcb1ea5ff219fabea8e51e84660d7274` | 4943 |
| `b2m_1d_2026-11-08/stageB/gate/run_observations.json` | `0debe88462c57247f8b8c324ab167d509f6f824ceb8d03004e4b93c8287fa5d3` | 3396 |

**stageB/run1·run2 — 격리 실행 관측 원문·stage_b.sh**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/stageB/run1/bwrap_exit.txt` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` | 2 |
| `b2m_1d_2026-11-08/stageB/run1/run.log` | `3b5419e0c6b93759661bc06a4bcc67e74909f3e0d9869c9f8aa6b492ac77fbc9` | 1690 |
| `b2m_1d_2026-11-08/stageB/run1/stage_b.sh` | `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39` | 969 |
| `b2m_1d_2026-11-08/stageB/run1/t_end.txt` | `ebbd351a9165ec8805b3fe3d9a91419492dbccfa7a406fef792483a656876d1f` | 36 |
| `b2m_1d_2026-11-08/stageB/run1/t_start.txt` | `156ef70161de40dbf172cb65ea70bfaa6cbb44003ccec44d6dc9d6adf358b7d2` | 36 |
| `b2m_1d_2026-11-08/stageB/run2/bwrap_exit.txt` | `9a271f2a916b0b6ee6cecb2426f0b3206ef074578be55d9bc94f6f3fe3ab86aa` | 2 |
| `b2m_1d_2026-11-08/stageB/run2/run.log` | `0e76e3bc77999394a5b8a20488397ad2c47ec85f5aba2e7917f706f19a49ae67` | 1690 |
| `b2m_1d_2026-11-08/stageB/run2/stage_b.sh` | `9197a0f02f829455b62660f9f8894bfa04430a1060b4ee731c0ee52d3fd54e39` | 969 |
| `b2m_1d_2026-11-08/stageB/run2/t_end.txt` | `b389ad558e1a9651eb7fa6c2765f92452b2e4f4c17b3309d0a36344568d744e3` | 36 |
| `b2m_1d_2026-11-08/stageB/run2/t_start.txt` | `d579d7cdaee34872f0f5dd2e9114556a9c86114f15097df838de0016169815cf` | 36 |

**stageB/tools — 트리 digest 재현 스크립트**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/stageB/tools/tree_digest.py` | `0696fce12475ef07eb1225e9d87bc029e3630aea7513333f42f81e324aca93ce` | 1705 |

**capsuleM/logs — get- 관측 원문**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/capsuleM/logs/get_minus_literal5roots.log` | `101a82b3a14404bf70669085064de8d7ad942d3a2659ac3db5b9bbbf696b6ba5` | 792 |
| `b2m_1d_2026-11-08/capsuleM/logs/get_minus_realized.log` | `578f677abc7cce5d9154ab0832f185cdddd4686ddd8f41b5fb5e7ed1c0b0718f` | 4717 |

**capsuleM/records — 폐쇄 인자·cached 모듈 목록**

| 파일 | sha256 | bytes |
|---|---|---|
| `b2m_1d_2026-11-08/capsuleM/records/closure_cached.txt` | `d172af5cb42ef7a0247cf8927b873f0b18bfa4f4388a6da7cc88ecac028c4a11` | 44552 |
| `b2m_1d_2026-11-08/capsuleM/records/closure_noncached_roots.txt` | `c38bb0c52e0aa8a7e147c8d75ed1507de5f563c33f987cb4b004c144a96fa8ac` | 7439 |

### 6.2 기계 판독 산출물 — digest 결속 수록 (20파일·저장소 미수록)

아래 파일은 관측 기록의 일부로 **호스트 홈 디렉터리 절대경로**(캠페인 디렉터리·elan toolchain·cargo 등의 로컬 경로)를 포함한다. 저장소는 publication-tree PII 스크럽(2026-11-08 착지 방향 — 호스트 경로 패턴 잔존 0)을 준수하므로, 이 파일들은 **원문을 수정 없이 그대로 수록하지 않고 sha256·bytes 전수를 본 문서에 결속**한다 — 기계 기록의 원문을 재작성(경로 마스킹)하면 digest identity가 붕괴하므로, 무결성 원칙(digest 사슬)을 우선해 digest 결속 수록으로 착지한다. 원문은 캠페인 로컬 내구 위치(`b2m_1d/` — §6.3)에서 열람·대조 가능하며, 소실 시 §11 Repro Block의 경로로 재산출해 digest 대조로 검증한다.

| 파일(로컬 내구 위치 `b2m_1d/` 기준 상대경로) | sha256 | bytes |
|---|---|---|
| `stage0/baseline.json` | `04effa6d882f41d63e1a2e7546439273fb1f491afa532fff7c357208d3ba817f` | 14215 |
| `capsuleM/selection.json` | `72a07e0658439d82b0c739f863e0126efebe41365e304df19de32e36b28ef85b` | 309187 |
| `capsuleM/inventory.json` | `7d96a4adef97267ee60a8b63fabdd4d847e52e89a263b8054520704a4697a6dd` | 239160 |
| `capsuleM/records/bytes_compare.json` | `a245b9af0f5d1b7763488b96d96d254fdb5ef7454bd42eac035e2c2a6a1ba7b0` | 244459 |
| `capsuleM/records/deps_closure.json` | `7c8a05d398a19ab09a08f3f7115d6fe3c59f43a304f9c90b782a464a04df9ace` | 140554 |
| `capsuleM/logs/lookup_closure_cached.log` | `aae66a70e484d32baa75d5579d9eccd652a4e89a1dd608d9a6b590c44f5b88fa` | 276605 |
| `capsuleM/logs/lookup_roots5.log` | `4cb71ce2f35fc44abba1f191250f508885dd89522d152053e6645d83fd6adf20` | 410 |
| `capsuleM/logs/lookup_sameargs_271.log` | `6f1098e66ebb6416e62ffe3f90d57e284991ca2f28a47ca3a5c6ea7e9ae88c76` | 419 |
| `capsuleM/tools/build_selection.py` | `98459f65a56b3c55845861c67e4141bacc96625453cb1a08bad4bdb1f76f08cf` | 5029 |
| `capsuleM/tools/bytes_compare.py` | `02e7ed95d0ec76f724c3a698ec752c0e10a1ca8ee78f65035423c4fd49ea517b` | 2460 |
| `capsuleM/tools/deps_closure.py` | `108f3af59dadf590e446eeb63a76037d6f76b396b8247610ccadaf0988cc505e` | 6777 |
| `stageB/gate/gate_5.json` | `6eac1d592607a431655a47038bad8be03937363fdb0d150ac7e4436394cd77a8` | 13153 |
| `stageB/gate/trees_leanproj.json` | `4ca95c52424fb6ffb500933446ff199e6a1dde1fa97525775835e372bd2254ac` | 1062 |
| `stageB/gate/trees_post.json` | `64f8cf7124f6cb6b80a9c965c857fc056f528e39d6aeb338685c20fa872f2e43` | 1721 |
| `stageB/gate/trees_toolchain_cache.json` | `441b40961d6d82d9b423a5da1be89deaa0efd1a34619f2c687dced48890fa99a` | 661 |
| `stageB/tools/parse_run.py` | `5546b43279d60db3af11d153df773a17ed44e37374dc7e7220a157b8de9d360b` | 2517 |
| `stageB/run1/bwrap_args.json` | `dd49195ee22e852c94fce796db6bf000438d8544f81b6be0bb956b6f8ad170f9` | 1904 |
| `stageB/run1/bwrap_cmd.sh` | `bad624dd885f25e419293f9d0a961ead76bd82a6c0b78939aba8e0106901bd04` | 1167 |
| `stageB/run2/bwrap_args.json` | `3496de774bd47de6f2e1dda9842585d763e1ca1fc57da0112250cecfe255b87f` | 1904 |
| `stageB/run2/bwrap_cmd.sh` | `a571cbbf8994be35b625d1b38af501f15184434b21a708716787c654497ba405` | 1167 |

### 6.3 대형 산출물 — 로컬 내구 위치 (저장소 미수록)

| 산출물 | 위치(로컬 내구) | 규모 | 결속 |
|---|---|---|---|
| Stage A′ 전체(번들·tools·json_copy·charon-target·out·leanproj·records·logs) | `b2m_1d/stageA/` | 158,005파일·**8,548,366,327B** | `stageA/inventory.json`(sha256 `a82a7ae79d40b3f52fa481b692c9930cf741ce5d7001ab7f6c9a82c3c184de0a`)·`stageA/report.md` |
| leanproj(코어 9 + deps/aeneas-lean + .lake/packages materialization) | `b2m_1d/stageA/leanproj/` | 153,007파일·7,754,673,864B (트리 digest 열자 기준 153,006·7,754,673,852B — 심볼릭 링크 1개 12B 계상 방식 차이, stageA report.md 원문) | 코어 9 digest(§4.2)·트리 digest `3a4cd397…` |
| 최소 집합 S 캐시(최종본) | `b2m_1d/capsuleM/cache/` | 1,478파일·102,362,602B | `capsuleM/selection.json`(전수 sha256·bytes)·트리 digest `d51c7700…` |
| Stage B′ 실행 산출물 leanproj(olean 5종 포함) | `b2m_1d/stageB/run1/leanproj`·`run2/leanproj` | 각 7.7G | `run.log` [6] olean digest·트리 digest |
| elan toolchain v4.35.0 | `~/.elan/toolchains/leanprover--lean4---v4.35.0` | 17,925파일·3,137,937,793B | bin 4·lib 5 sha256(§4.4 관문)·트리 digest `c00fd0ef…` |
| 원본 .ltar 로컬 생존분(원본 Stage A 물리 산출물) | `~/.cache/mathlib` | 9,031파일·455,355,304B | Stage 0 재실측·§4.3 bytes 대조 1,478/1,478 |

**재구성 방법(대형 산출물 소실 시)**: 위 §6.1·§6.2의 증거 digest 사슬로 전 단계 재현이 가능하다 — 원본 캡슐 소실 이후 본 캠페인이 실제로 수행한 복원 경로가 그 증명이다: (0) 원격 main 증거 문서의 기록값(generation.json 전문·olean digest·axioms·sandbox_config — Stage 0 추출·자기검증) → (1) aeneas 번들 재취득(sha 대조)·세션 wire.jsonl tool.call 원문 재생으로 stage_b_inputs 9파일·stage_b.sh byte-exact 재작성·`lake exe cache unpack` materialization(Stage A′) → (2) 공식 `get-` 폐쇄로 S 산출·로컬 생존분과 byte 대조(선택) → (3) bwrap 격리 실행×2(Stage B′). 각 단계의 산출물 digest가 기록값과 일치하는 한 재구성은 검증 가능하다(§11 Repro Block 참조).

### 6.4 관측 원문 정본 (스테이지별)

- `b2m_1d/stage0/baseline.md`·`baseline.json` — Stage 0 기준 확정
- `b2m_1d/stageA/report.md`·`records/`·`logs/` — Stage A′ 4계층
- `b2m_1d/capsuleM/selection_report.md`·`selection.json`·`records/`·`logs/` — 선택 단계
- `b2m_1d/stageB/report.md`·`acceptance.json`·`gate/`·`run1/`·`run2/`·`run1_run2_normalized.diff` — Stage B′
- 정본 근거: 1d 계약 본문·`stage0/extracted/generation.json`(sandbox_config.bwrap_args 권위 원천)·`stage0/extracted/acceptance_baseline.json`(판정 기준값)·b1 Gate A §5.3·§4.10

## 7. Classification

**Acceptance(M) = PASS** — 판정축(2/2 실행)·재현축·재실측축 전부 통과, 기록축 값 기록, §5 관문·§6 판정 통과, §8 불일치 0건, fail-closed 이벤트 0건(UNKNOWN 0건). 결과 분류: **재현 성공** — 원본 B-2 판정(axioms 2행·sorryAx 0·Built 5)·산출물 identity(olean 5종 byte-exact)·실행 간 동일성(정규화 diff 0B)의 오프라인 최소 캡슐 재현 관측.

## 8. Interpretation

- **세대 G 재실행의 입증**: 동일 결속 입력(§5 관문 전 일치)·동일 격리(§10 준용)·동일 실행 기반(계약 §6.2 일치)에서, 캡슐 캐시를 원본 9,031 .ltar에서 공식 폐쇄 기준 S 1,478 .ltar로 축소한 M이 원본의 커널 판정과 산출물 identity·실행 간 동일성을 그대로 재현했다. §7 제약식의 4조건이 기계 관측으로 충족됐다(§5.1).
- **축소의 직접 관측**: unpack 관측 `Already decompressed 1478 file(s)`는 M이 S(1,478)만 봉입했다는 사실의 직접 관측이고(원본 `9031`), jobs 1801은 빌드 플랜이 캐시 크기와 무관하게 동일함을 보여준다. 파일 수 비율 16.37%·bytes 비율 22.48%는 서로 다른 사실로 별도 보고됐다(남은 7,553파일이 평균보다 작은 파일들로 구성됨).
- **bwrap 인자 축실성**: 58 토큰 전수 대조에서 차이는 소스 경로 4곳뿐 — 격리 구성(§10)이 원본과 동일하게 유지됐음을 토큰 단위로 기계 확인했다.
- **원본 캡슐 소실 이후의 회복 경로 확립**: 세대 identity(1a §5 순수 함수)·물리 재프로비저닝(Stage A′ 4계층)·최소 선택(공식 폐쇄)이 분리되어, 원본 캡슐 없이도 세대 G의 재실행 전제를 digest 일치로 회복·실행할 수 있음이 관측됐다(1d §1 P0 해소의 실험적 확인).

## 9. Non-Conclusions

- **본 판정의 범위**: M의 판정은 "M이라는 구성(캐시 S + Stage A′ materialization 상태 leanproj + elan toolchain) 아래에서 원본 판정이 재현됐다"는 관측이다. 제품 계약의 범위·준비성 주장이 아니다(AGENTS.md §0.12).
- **빈 패키지 from-scratch S 충분성 입증 아님**: M의 leanproj 패키지 빌드 영역은 Stage A′ materialization(전체 9,031 언팩) 상태를 포함하며 — **원본 캡슐 inputs도 동일 구조였다(원본 unpack 관측이 "Already decompressed 9031 file(s)" no-op)**. 본 실행은 "빈 패키지 빌드 상태에서 S만으로 처음부터 재현된다"를 입증하지 않는다 — S의 최소성은 공식 `get-` 전이 폐쇄 정의·선택 단계 검증에 근거하며, 본 실행은 unpack-over-S의 관측으로 S 봉입을 확인한 것이다.
- **전역 최소성 비주장**: "최소"는 공식 `get-` 전이 import 폐쇄 기준이다(§7). olean 단위·bytes 단위 최소 집합 존재 가능성을 부정하지 않는다.
- **offline ≠ 이식형 hermetic**: M의 격리는 본 호스트·본 실행 기반(계약 §6.2)의 관측이다. 타 머신 이식성·범용 hermetic 재현을 주장하지 않는다(§13).
- **캐시 hit ≠ 성공**: unpack 성공·.olean 존재·캐시 hit는 acceptance가 아니다(1c §6 — 판정축은 커널 판정·재현축은 산출물 identity).
- **교차검증의 부분 독립성**: 선택 단계의 세 경로(get-·lookup·deps-json) 폐쇄 계산은 `parseImports'` 파서를 공유한다 — 파서 자체의 오류는 본 교차검증으로 검출 불가다(부분 독립 교차검증으로 정직 기록).
- **mutation 증거는 인용**이지 M의 실행이 아니다(§12). **계약 §6.2 일치의 의미**: 열거된 항목의 대조 결과일 뿐 "실행 기반이 모든 면에서 동일하다"는 주장이 아니다(계약 §6.3) — 관측되지 않은 축은 미측정이다.
- **G 재실행 ≠ Aeneas 정식 채택**(§13 — DEFER 유지)·**rustc binary sha 원본 일치 비주장**(generation.json이 version+commit 문자열로만 identity 결속)·**원본 실행 소요시간과의 대조 불가**(원본 run1/run2/run3의 wall-time 기록 미확보 — 본 실행 소요 48.4s·52.3s는 관측 기록일 뿐 원본 대조축이 아니다)·**상한 1,795의 측정 방법 원천 미확보**(capsule_min_measure 방법론 미문서화 — 본 실험은 상한 미초과만 기계 판정) — **2026-11-09 S2 조사로 해소**: 원천 확정(원본 run up-to-date 작업 수 1,801−5−1·`summary_numbers.json` 기계 수치 원문 `dep_jobs_before_first_root: 1795`·측정 2026-11-05) → [b2m_1d_s2_provenance_2026-11-09.md](b2m_1d_s2_provenance_2026-11-09.md)·**캡슐 inputs 75파일 차이 가설 미검증**(원본 153,082 vs M 153,006+심볼릭 1 — b1 post-build 상태 가설) — **2026-11-09 S2 조사 결과**: deps/aeneas-lean MATCH·`.lake/packages` MISMATCH(신규 발견·최유력 원인 .git 클론 시점 상태)·동일 find 기준 76파일·4,779,264B·"작동상 무관" 실험적 지지(stage_b.sh `rm -rf .lake/build`+4축 PASS) → [같은 문서](b2m_1d_s2_provenance_2026-11-09.md).

## 10. Deviations (성공 판정과 무결 명시 — Stage B′ 보고 원문 인용)

1. **계약 §5.1 표 전사 오류(erratum) — 해소됨**: 생성 `TypesExternal_Template.lean` 인라인 digest가 62자(무효 sha256 길이 — `ef` 2자 누락)였다. 정본 anchor(b1 Gate A §5.3 — 원격 main 사본 2종 모두 64자 `514fbfd947d7cb617d81046e60e874b59301b766a52a4b16af4bd72cccfef485`)과 Stage A′·B′ 측정값이 byte-exact 일치하므로 관문 판정은 anchor 기준 MATCH였다. 계약 문서 내 무효 길이 digest는 전수 스캔 결과 이 1건뿐이었고, **erratum PR #18(MERGE_SHA `bc91247e64c2b295b08f418828213e21824c1a98`)로 정정 착지됐다** — 본 증거는 정정 후 계약을 인용한다. (범위 밖 관측: 동일한 62자 전사가 1a §5.5 표에도 존재한다 — 본 PR은 무변경, 별도 follow-up.)
2. **[2] no-op**: M의 leanproj는 pristine(루트 .lake/build 사전 부재 — Stage A′가 의도적으로 루트 빌드 미수행)이므로 `rm -rf .lake/build`는 삭제 대상 없이 실행됐다. 원본은 post-b1-build 상태에서 동일 삭제를 수행 — 어느 쪽이든 빌드 시작 시점의 상태는 "루트 빌드 산출물 부재"로 동일하며, Built 5행의 모듈별 컴파일 시간 관측이 실재 재컴파일의 기계 증거다.
3. **unpack 관측치 차이**: `Already decompressed 1478` vs 원본 `9031` — 기록축(§11.4) 변동 허용 항목이며 S 축소의 자연한 결과다.
4. **toolchain 실체**: 원본 캡슐 toolchain 사본(소실) 대신 elan 설치본을 ro-bind — 파일 통계(17,925·3,137,937,793B)가 원본 캡슐 toolchain per_dir와 정확히 일치하고 §5.3 bin/lib 재실측이 전부 일치한다.
5. **관측 장치 파일의 workspace 내 존재**: run.log·t_*.txt·bwrap_exit.txt 등이 rw-bind된 /workspace 안에 기록됐다 — stage_b.sh는 `/workspace/leanproj` 경로만 접근하므로 간섭 0.
6. **unpack 방식**: `lake exe cache unpack`만 사용(get 계열 격리 하 미실행) — §10 금지 목록 준수. `--try-cache` 미사용·LAKE_NO_CACHE=true 프로세스 전체 적용.

## 11. Repro Block (재구성 경로 — 대형 산출물 소실 시)

```bash
# 0) 정본 기록값 확보 (원격 main 증거 문서 — Stage 0 절차)
gh api repos/Archright/Axiom/contents/docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md?ref=main
# → §5.2 generation.json 전문(sha256 efdced76b105cc…d1b5133 자기검증)·§5.5 판정 기준값

# 1) Stage A′ — 4계층 재프로비저닝 (stageA/report.md Procedure 원문)
gh release download AeneasVerif/aeneas nightly-2026.11.03-ab34bd2 -p aeneas-linux-x86_64.tar.gz -D bundle/
# tarball sha256 대조(ed0e336c…) → aeneas·charon·charon-driver binary sha 대조
# 세션 wire.jsonl tool.call 원문 재생 → stage_b_inputs 9파일 + stage_b.sh byte-exact 재작성
# charon cargo --preset=aeneas --start-from 'serde_json::value::_::as_bool' (CARGO_NET_OFFLINE=true)
#   → LLBC cfa5a04f…11a5e3dfc (원본 경로 적합 실행 — §4.11 경로 의존 필드)
# aeneas -backend lean -split-files → Types/Funs/TypesExternal_Template.lean (514fbfd9…cccfef485)
# MATHLIB_CACHE_DIR=~/.cache/mathlib lake exe cache unpack → materialization(9,031)

# 2) 선택 — 최소 집합 S (capsuleM/selection_report.md Procedure 원문)
MATHLIB_CACHE_DIR=<새 dir> lake exe cache get- <폐쇄 내 비캐시 모듈 271>   # exit 0, 1,478 dl
# → S = 1,478 .ltar·102,362,602B · bytes 대조 vs ~/.cache/mathlib (1,478/1,478)

# 3) Stage B′ — bwrap 격리 실행 ×2 (stageB/report.md Procedure 원문·bwrap_args.json 전문 —
#    §6.2 digest 결속 파일·로컬 내구 위치 b2m_1d/stageB/run<N>/bwrap_args.json)
bwrap --unshare-net --ro-bind /usr /usr … --ro-bind <elan>/leanprover--lean4---v4.35.0 /toolchain \
  --ro-bind <stageA>/leanproj /tmp/b1_gate_a/leanproj --ro-bind <capsuleM>/cache /cache \
  --bind <stageB>/run<N> /workspace --clearenv --setenv PATH … --setenv LAKE_NO_CACHE true \
  --setenv MATHLIB_CACHE_DIR /cache --chdir /workspace --die-with-parent \
  /bin/bash /workspace/stage_b.sh
# 기대(원문): curl_exit=6 · Already decompressed 1478 file(s)
#   Build completed successfully (1801 jobs). · axioms 2행(§5.2) · olean 5종(§5.3)
#   toolchain_readonly=ok · cache_readonly=ok · inputs_readonly=ok · bwrap exit 0
# Run₁′=Run₂′: 시간 정규화 full-log diff 0B · 사후 불변(트리 digest 5종·inventory 7d96a4ad…)

# 4) 무결성 대조 — 수록본은 §6.1 표 digest와 대조·digest 결속 파일(§6.2 표)은
#    로컬 내구 위치 원문 또는 재산출본과 대조
sha256sum docs/evidence/b2m_1d_2026-11-08/stageB/acceptance.json   # d9b0c136e8e03914… (§6.1)
sha256sum b2m_1d/capsuleM/inventory.json                          # 7d96a4adef97267e… (§6.2 — 로컬 내구 위치)
```

실행 기반: Linux Mint 22.3 (noble base)·x86_64·kernel `6.17.0-42-generic`·glibc `2.39-0ubuntu8.9`·bwrap `0.9.0`(`e3189038…30f71`) — 원본 B-2와 동일 호스트·동일 실행 게이트 관측.

## 12. Next Experiment (후속 — 본 캠페인 범위 밖 기록)

- 1a §5.5 표의 동일 62자 전사 오류 정정(erratum follow-up — §10 Deviations 1).
- 캡슐 추가 축소(§7의 S 이하)·Aeneas 정식 채택 adjudication(DEFER)·타 머신 재현·이식형 hermetic — 전부 별도 계약·승인 필요(§2 non-goals).
