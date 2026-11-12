# B-cache 키 narrowing — R3 단일 슬라이스 착지 증거

> **측정 커밋**: origin/main `75c338bd7a` 위 브랜치 `feat/bcache-input-closure-key`.
> **등록**: `docs/evidence/jcas_phase23_registrations_2026-10-09.md` §R3 (등록 → 착지 관계 유지).
> **측정 에이전트**: Kimi Code 서브에이전트 (2026-10-09).
> **정리 원칙**: 모든 수치는 이 문서의 실행 커맨드와 원 출력으로 재유도 가능하다 (§4 재현).

---

## 0. 요약 (결정)

B-layer 캐시 키의 identity 단위를 **전체 트리 OID → 컴파일 참여 입력 폐쇄 digest**로 교체했다.
효과: docs-only 커밋이 B 세대를 전진시키지 않는다(불필요한 콜드 리빌드 소멸). 대가 없음 —
src·staticRead 입력·컴파일 성공 술어 입력은 전부 키에 흡수되며, 판정(rebuild/J3)·probe 앵커
(B_PROBE)·restore 경로·skip 논리(S5)는 전혀 건드리지 않았다.

| | 구(트리 OID 단위) | 신(입력 폐쇄 digest 단위) |
|---|---|---|
| identity | `b9111761ca0828c2c5f8d6c9609d8b4beef62ee0` (HEAD `75c338bd7a` 트리 OID) | `5f4ef17fb34d3e6c523565f56b7b40b08ac32b94` |
| b_key | `axiom-b-b9111761ca08…-7c93305826feef1c61ce19a168847a5a5cae58fdf6984b1729cf9465aa2fb160` | `axiom-b-5f4ef17fb34d…-<recipe><a_fp>` |
| docs-only 커밋 | 키 전진 (§2.1 [2] 대조 실측: `b9111761… → 59bb8778…`) | 키 불변 (§2.1 [2] PASS) |

## 1. 안전 전제 4항 — 충족 실측 (착지 조건 1)

### ① 항상-리빌드 유지 (J3: 키≠verdict, 캐시=가속)

**관측**: 본 슬라이스 diff는 `git status`상 4 파일 — action.yml(keygen·b-verify·probe
주석/키 공식), ci-cache-publisher.yml(manifest buildSha 소스 2곳), runner-pool-acceptance.yml
(코멘트), tests/ci/test_b_cache_anchor.nim — 이다. 빌드 스텝(`make ci-compile`)·S5
eligibility(s5-gate, `AXIOM_S5_BUILD_SKIP`)·B-restore 경로 목록(9경로, cache-version 유도
입력)·restore-keys 금지 원칙은 **전혀 변경되지 않았다**. 키는 판정 입력이 아니다 — restore
성공 여부와 무관하게 재컴파일/재판정 경로는 구키 시절과 동일하다. 이 변경으로 어떤 스킵도
추가되지 않았고, 어떤 판정도 캐시에서 읽지 않는다 (기계 근거: `git diff --stat` 4 파일,
`make check-workflow-shell-syntax` PASS — run 블록 126개 전수 bash -n).

### ② 컴파일 성공 술어 입력의 키 소화

**설계**: 키 identity가 소화하는 폐쇄(§2.3 계산식 원문):
- src/ 전수(파일 바이트, `src/generated/` 제외 — BuildSourceHash와 동일 우주·동일 순환성 사유),
- staticRead 컴파일 입력 17종 **바이트** (`docs/spec/spec_registry.json`,
  `data/axiom_catalog.json`, `data/command_policy.json`, `data/stateless_whitelist.json`,
  `data/policy_manifest.json`, `data/feature_manifest.json`, `data/i18n/ko.json`,
  `config/gates.manifest.toml`, `config/gates.waiver.toml`, `config/templates/*.md` 3종,
  `proofs/proof_witness.json`, `proofs/lean-toolchain`, `lean-toolchain`, `axiom.nimble`,
  `tools/ci/smoke_test.nim`),
- 컴파일 성공 술어 입력 **술어 비트**(바이트 각인 아님 — 등록 표의 의미 그대로):
  `AGENTS.md`·`docs/agents/architecture.md`·`docs/agents/rules_workflow.md` 비공백성
  (`config/integrity.nims:15-20` staticRead `quit(1)` 게이트) 3종,
  `docs/spec/three_tier_contract_architecture.md`의 SPEC 셀 존재 비트 3종
  (`SPEC-T1-ASIRATIO/DURATION/VKDRATIO` — `spec_binding_macro`의 `"| <ID> |"` 셀 매칭).
- recipe_hash(4종 config) + a_fp — 기존 그대로 별도 성분.

**실측** (§4 하니스 [3][4][5][6][8] + test (k4)(k5)(k6)): src 바이트·spec_registry 바이트·
axiom_catalog 바이트 → 키 전진. AGENTS.md 비공백 바이트 교체 → 키 불변 / 비우기 → 키 전진.
SPEC 무관 행 편집 → 키 불변 / 필수 셀 제거 → 키 전진. **술어 입력이 키를 움직이고, 술어와
무관한 바이트는 움직이지 않는다 — 술어 소화의 양방향 실측.**

**폐쇄 표류 가드**: test (k12) — src 전수 literal `staticRead` 대상(src 밖)과 src의
`{.spec("…")}` 사용 ID를 기계 스캔해 keygen 폐쇄 목록과 대조한다. 신규 staticRead·spec()
추가 시 이 테스트가 keygen 갱신을 강제한다 (미배선 모듈까지 보수 포함). 유일한 수동 항목은
`data/axiom_catalog.json` — computed-path staticRead(`verified_axioms_catalog_part1.nim`
`dataPath` 상수)라 literal 스캔 밖이며, 본 리뷰에서 배선 확인 임포트 클로저
(gate_consts·certificate_manager 경유 4종 바이너리 도달)로 선제 추가했다. computed-path
신규 staticRead는 literal 가드의 사각지대다 — 잔여로 §5에 기록.

**주의(문서 정합)**: staticRead의 nim-캐시 추적 유무는 문서 간 입장이 갈린다 —
`docs/spec/config_nims_hermetic_cache_quirk.md` §6.4 (vmdeps opSlurp 가짜 include 등록,
ko.json 실측 1모듈 재컴파일) vs `docs/spec/lean_toolchain_binding_quirks.md` (witness
stale → `nim c` exit 0 실측, 2026-10-09). 본 슬라이스는 이 논쟁과 무관하게 성립한다:
B 페이로드는 **프리빌트 바이너리 + nimcache**를 exact-key로 운반하므로, 키 폐쇄가 유일한
아티팩트 경계 무효화 계약이다 (컴파일러가 추적하든 아니든 키 소화는 필요·과소 무해).

### ③ identity 단위 일괄 전환 (§2.5 4점)

한 PR = 한 세대. 4점 전부 본 diff에서 동일 세대 전환:
1. **keygen** — `b-identity` = 폐쇄 digest (git 객체 유도, 아래 §2.2).
2. **save-side manifest `buildSha`** — ci-cache-publisher lane-1이 `verify.outputs.tree_build`
   → `keygen.outputs.b-identity`로 전환; base-seed lane은 원래 keygen 출력 소비(확인),
   env명 TREE_BUILD→B_IDENTITY로 정합화. gateway-jobs-measure는 exp-* 네임스페이스
   (`buildSha: exp-<ref>`) — 네임스페이스 단위 불변, 변경 불필요.
3. **b-verify `EXPECT_BUILD_SHA`** — 어차피 keygen `b-identity` 출력 소비 → 자동 전환;
   재유도 공식(`axiom-b-<identity>-<recipe><a_fp>`)·신뢰 입력 원칙 불변.
4. **B_PROBE 신뢰 트리 재유도** — keygen에 **신규 출력 `b-probe-tree`**(cache-build-source의
   트리 OID, exp-*는 공백)를 추가하고 probe가 그것을 소비해 `git archive` materialize.
   probe 앵커는 키 identity(폐쇄 digest)와 **독립**으로 유지 — 비순환 앵커 보존
   (restored binary `--check-provenance` vs 신뢰 트리 src).

in-place 혼합 없음: 구세대 엔트리(트리 OID 키)는 신세대 키와 절대 매칭되지 않고(문자열
키 상이), 오염 시 b-verify 재유도 불일치 → fail-closed 폐기 → 콜드 폴백. 구세대 엔트리는
캐시 자연 만료로 퇴출된다 (기존 LRU 경계, 이 슬라이스 소관 아님).

### ④ 자연실험 근거 (docs는 성공 술어 게이트다)

등록 §R3의 CI 자연실험(PR #613 사이클 런 `37816610651`: base 트리 유도 B 엔트리 exact-hit,
복원 `bin/ax` 소스 정합성 통과 — PR의 docs 바이트는 빌드 입력 불참)과 `BuildSourceHash`의
docs 불포함(`tools/hermetic_build.nim` walkDirRec(srcDir))을 계승하며, 본 슬라이스의
**직접 실측** §2.1 [2]가 이를 대체한다: docs-only 합성 트리에서 신 키 불변 + 구 키 전진의
동일 하니스 대조. 보조로, worktree에서 `make ci-bootstrap` 산출 바이너리로
`bin/ax report --canonical-digest` ×2 동일(§3) — docs·워크플로만 손댄 트리에서 컴파일
산출 불변의 재확인.

## 2. 키 before/after + 회귀 실측 (착지 조건 2)

### 2.1 실측 하니스 (합성 트리 — 커밋 없는 트리 변형)

`git read-tree`/`hash-object`/`write-tree`로 HEAD 트리를 변형한 합성 트리 8종에서 구/신
keygen 공식을 재계산 (§4 재현 — `/tmp/bcache_measure/harness.sh` 출력 전문 보존):

| # | 시나리오 | 신 키(폐쇄) | 구 키(트리 OID) | 판정 |
|---|---|---|---|---|
| 0 | 기준점 HEAD `75c338bd7a` | `5f4ef17fb34d…` | `b9111761ca08…` | — |
| 1 | 동일 커밋 2회 재계산 | 동일 | 동일 | PASS — 결정론 |
| 2 | docs-only (신규 docs 파일) | **불변** | 전진 `b9111761…→59bb8778…` | **PASS — 무효화 소멸** |
| 3 | src/.nim 바이트 변경 | 전진 | 전진 | PASS — 민감성 보존 |
| 4 | spec_registry.json 바이트 | 전진 | 전진 | PASS — 술어 입력 소화 |
| 5 | AGENTS.md 비공백 교체 / 비우기 | 불변 / 전진 | 전진 / 전진 | PASS — 비공백 술어 비트 |
| 6 | SPEC 무관 행 / 필수 셀 제거 | 불변 / 전진 | 전진 / 전진 | PASS — 셀 매칭 술어 |
| 7 | src/generated 변경 | 불변 | 전진 | PASS — 우주 제외 |
| 8 | data/axiom_catalog.json 변경 | 전진 | 전진 | PASS |

하니스 10/10 PASS. 신 키는 (동일 입력 ⇒ 동일 키)와 (다른 빌드 입력 ⇒ 다른 키)의
상호검증을 모두 만족하고, 구 키 대비 **docs-only 전진만 소멸**된다 (과소 무효화 없음 —
[3][4][8] 대조).

### 2.2 신 키 유도 원문 (action.yml keygen — 계산식 고정)

`cache-build-source` 커밋의 git 객체에서 `git archive`로 폐쇄 경로를 materialize해
(Linux runner, `LC_ALL=C sort` 정규화) 다음 성분을 하나의 `sha256sum`으로 소화,
40-hex: ① `find src -type f ! -path 'src/generated/*'` 전수 sha256 ② staticRead 17종
per-file sha256(부재 = keygen fail-closed exit 1) ③ 비공백 비트 3종 ④ SPEC 셀 존재 비트 3종.
**작업 트리가 아닌 git 객체 유도** — admission 레인은 체크아웃(merge 트리)과
cache-build-source(base.sha)가 다른데, 키는 커밋 대상 트리에서만 결정된다. 미커밋 오염
무시 실측: test (k10) + 하니스(작업 트리 dirty 상태로 전 시나리오 실행).

### 2.3 테스트 (기계 검증 — 착지 조건 2·3)

`nim c -r tests/ci/test_b_cache_anchor.nim` — **27/27 PASS**:
- 기존 15/15 유지 — b-verify 앵커링 9 + probe 6 (스텝 본문 원문 추출 실행; probe는
  `b-probe-tree` 템플릿으로 갱신, mechanics 불변).
- 신규 12/12 — (k1) 결정론·(k2) docs-only 무효화 소멸·(k3) src 민감성·(k4) registry
  바이트·(k5) SPEC 셀/무관 행·(k6) 비공백 비트·(k7) 클로저 파일·(k8) 클로저 부재
  fail-closed·(k9) exp-* 원문 전달·(k10) 미커밋 오염 무시·(k11) generated 제외·
  (k12) 정적 클로저 표류 가드.

보조 회귀: `tests/ci/test_verify_b_artifact.nim` **8/8 PASS**(verify 스텝 무변경 확인),
`make check-workflow-shell-syntax` **PASS**(run 블록 126 전수).

## 3. J3 + G7 + canonical digest (착지 조건 3·4)

- **J3 (HIT여도 판정 재계산)**: 본 diff는 restore→verify→probe→빌드 체인의 스킵/무조건성을
  전혀 바꾸지 않았다 (§1-①). 캐시=가속 원칙은 action.yml 헤더 계약 그대로.
- **G7**: `make verify-contract-release-e2e-full` — **PASSED** (`G7 pass
  (tier=dual-verified status=not_verifiable vaultPath=)` — release `bin/ax` E2E, fail-closed
  target의 종료 판정 PASS).
- **`bin/ax report --canonical-digest` ×2**: worktree 실증명 상태(`bin/ax prove --target
  normalizeMaxWorkers` 실행 후 생성, logs/ax_proof_state.json)에서 2회 →
  `01dbe6baf9128205782fa9df3056c3a01dca3154d761ad9847ead1dd55581073` ×2 동일.
  docs-only 트리 digest == merge 트리 digest의 등록 §R3 직접 실측과 같은 방향 — 본 브랜치는
  src/docs 바이트를 전혀 바꾸지 않았으므로 컴파일 산출 불변이 이 값의 재현성으로 보강된다.

## 4. 재현 (본 문서 전체)

```bash
# 하니스 (합성 트리 키 유도 대조) — /tmp 사본, 커밋 불필요
bash /tmp/bcache_measure/harness.sh

# 테스트
nim c -r --hints:off tests/ci/test_b_cache_anchor.nim          # 27/27
nim c -r --hints:off tests/ci/test_verify_b_artifact.nim       # 8/8
make check-workflow-shell-syntax                                # 126 PASS

# G7 + digest ×2
make verify-contract-release-e2e-full
bin/ax report --canonical-digest && bin/ax report --canonical-digest

# 구/신 키 원 계산 (HEAD 기준)
git rev-parse HEAD^{tree}                                       # 구 identity
# 신 identity: action.yml keygen step 원문 실행 (cache-build-source=HEAD)
```

## 5. 잔여 (범위 외 발견 — Follow-up)

1. **computed-path staticRead 사각지대**: `data/axiom_catalog.json`처럼 변수 경로 staticRead는
   literal 스캔 가드(k12)가 커버하지 못한다 — (k12)는 literal만 기계 강제. 후속: 스캐너가
   computed-path 후보(`staticRead(<expr>)` 존재 파일)를 WARN 목록으로 보고하는 확장.
2. **`src/policy/embedded_agents_docs.nim` 배선 재관측**: 4종 ci-compile 바이너리 임포트
   클로저에 미배선(2026-10-09 확인 — importer는 tools 2곳뿐) → AGENTS.md 바이트는 비공백
   비트로만 키 소화. 배선이 추가되면(바이너리 각인 발생) k12 동적 스캔+리뷰가 keygen에
   바이트 소화 승격을 요구하게 된다 (등록 §R3 비고의 조건 충족).
3. **구세대 B 엔트리**: 트리-OID 키 엔트리는 신세대 키와 매칭 불가로 자연 만료 대기 —
   강제 무효화 아님 (캐시 LRU 경계는 GitHub 소관).
4. **s5-gate 코멘트 정합화**: runner-pool-acceptance의 probe 앵커 서술을 b-probe-tree로
   갱신함(코멘트만 — probe 로직은 호출자 checkout 기반 무변경).

## 변경 이력

| 버전 | 날짜 | 변경 |
|---|---|---|
| v1.0.0 | 2026-10-09 | R3 슬라이스 착지: 전제 4항 실측, 합성 트리 하니스 10/10, test_b_cache_anchor 27/27, G7+digest ×2, identity 4점 일괄 전환 |
