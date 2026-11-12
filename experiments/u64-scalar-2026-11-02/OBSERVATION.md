# ③ u64 boundary-type-only — 운영 관측 기록 (u64-scalar-2026-11-02)

> Vertical Slice 관측 문서. 명령 → 관측 → 판정만 기록한다. MERGE_SHA 착지
> 전 측정(사전병합)과 착지 후 cold acceptance(독립 재현)를 구분하며, 선언은
> 판정을 대체하지 않는다.

## 0. 슬라이스 정의 (계약)

- **Ultimate Purpose**: Axiom이 증명할 수 있는 의미 범위를 u64 경계 타입으로
  확장하되, 증명하지 못하는 것(전폭 산술)은 명명된 이유로 계약에 남긴다.
- **Terminal Outcome**: u64 식별/파라미터/반환/상수가 양측 다리(Nim 디코더·
  Lean 참조추출기)에서 독립 디코드되어 eaAgree를 통과하고, 선언된 긍정
  명제는 Lean kernel로 Verified(인증서 발급), 선언된 부정 명제는 커널 거부
  → Z3 반증 모델 → 실제 rustc 재현으로 CONFIRMED(failed, exit 1),
  전폭 `+`는 생산자 벽에서 명명된 이유로 fail-closed unknown — 이 전부가
  고정 merge SHA의 독립 재현으로 재관측된 상태.
- **Out of scope (명시)**: width-64 산술(wrapping/checked), Ref/Adt, C7 전체
  문법 — 모두 `docs/spec/rust_certified_subset.md` §1의 선언된 후속 과제.

## 1. 사전병합 측정 (브랜치 HEAD = 798e83a5f, work/u64-scalar-2026-11-02)

### 1-a. 로컬 기계 검증

| 검사 | 명령 | 결과 |
|---|---|---|
| 엔진 빌드 | `make build` | exit 0 (36.2s) |
| Lean 빌드 | `cd proofs && lake build` | Build completed successfully (21 jobs) — RustReferenceExtractor(w=64 승인) 포함 |
| 단위 | `nim c -r tests/unit/test_llbc_to_canonical.nim` | u64 suite 10/10 포함 전 suite green |
| 게이트웨이 | `nim c -r tests/gateway/rust_subject_u64_boundary_test.nim` | **14/14** |
| CLI acceptance | `nim c -r tests/gateway/rust_lane_cli_acceptance_test.nim` | 전 suite green, **suite 8 4/4** (cli_acceptance_suite8.txt) |
| 회귀 | three_cases 10/10 · provenance_issuance 9/9 · obligation_render 11 · guard_attempt 34 · input_contract 39 | 전부 green |

### 1-b. CLI 실측 (신선 state, AXIOM_CHARON_BIN=pinned 0.1.281, GITHUB_TOKEN=`gh auth token`)

| 케이스 | exit | 판정 | reason(발췌, verbatim는 artifacts 참조) |
|---|---|---|---|
| A `--target axiom_u64_probe::u64_echo` (선언) | 0 | **verified 1/1 + 인증서** `5e7fb809…`(state build/certificates, irHash-keyed) | `∀ (x : Int), (0 ≤ x) → ((u64_echo x) = x)` — 하계 전용 가설의 **더 강한 정리** + lock 조건의 도메인 한정 주장 |
| B `--target axiom_u64_probe::u64_seven_mutant` (선언) | 0 | unknown(stage=kernel) | 커널 거부(omega) — in-repo 더러운 worktree에서 Zero-Footprint 거부로 **unconfirmed**(정직한 계약 모양; CONFIRMED는 아래 1-c에서 관측) |
| C `--target axiom_u64_probe::u64_add` (미선언) | 0 | unknown | `out-of-subset grammar (fail-closed): … full-width '+' outside the closed v1 set: the no-overflow obligation 'lhs + rhs < 2^64' is unrepresentable in the IR literal domain (int64) — u64 is boundary-type-only …` |
| D `--target axiom_u64_probe::u64_seven` (미선언) | 0 | unknown | `no derivable guard obligation (attempt ran; zero mechanical goals)` |

인증서(`5e7fb809…`): `axiom.certificate.v3`, `kernel: true`,
`status: certLeanVerified`, `reason: uap-lean-verified`, irHash ==
파일명(내용 주소화), leanProposition 위 표와 동일.

### 1-c. CONFIRMED 경로 관측 (게이트웨이·CLI, materialized-crate subject 바인딩)

- `rust_subject_u64_boundary_test` P7: 무장 provenance(subjectRoot=물질화
  git 크레이트) + z3 게이트 하에서 mutant의 커널 거부가 **CONFIRMED** —
  `counterexampleConfirmed == true`, payload `input._x=…`,
  `replay.verdict=rvAgree`(실제 rustc 실행 0 → 8 ≠ 7), 인증서 0건.
- CLI acceptance suite 8 (B): 신규 fixture가 미트래킹(사전 착지)이라 lane가
  물질화 크레이트로 수용 → subject git이 깨끗 → **failed + CONFIRMED,
  exit 1** 관측. (fixture가 main에 착지한 이후 CI에서는 in-repo 경로 +
  worktree-clean 이중 모양 계약이 suite 1과 동일하게 적용된다.)
- 경계 정직성(1-a 게이트웨이 A): 2^64-1 경계 리터럴은 int64 구체-평가
  도메인에서 `input literal unparsable: 18446744073709551615`로
  **명시적 거부** — 조용한 wraparound 없음.

### 1-d. 전달 (push 1회 원칙)

- 게이트 커밋 3건: `b5fec7a38`(코드+테스트 수정 9파일) →
  `b6b085ff2`(fixture 트리+신규 게이트웨이 테스트 7파일 — 첫 게이트
  커밋이 신규 파일을 미스테이징한 것을 발견·재커밋) → `798e83a5f`
  (pre-push dry-run의 핀 드리프트 4건 reanchor).
- `git push --dry-run` 2회(드리프트 발견 → 재앵커 후 PASS) → 실제
  **push 1회** → PR #1177 → merge queue → 관측.

## 2. MERGE_SHA 착지

- PR **#1177** — `gh pr merge 1177 --auto --merge --match-head-commit 798e83a5fb…`
  (HEAD OID 매칭, merge queue 경유).
- **MERGE_SHA = `d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622`** (merge commit,
  parents=2 — GitHub 네이티브 MERGE), mergedAt `2026-11-01T21:26:12Z`.
- 관측(`tools/ci/landing_observe.sh 1177`, 60~300초 간격 재관측):
  UNKNOWN(큐 진입 전) → PROGRESSING(롤업 SUCCESS, 큐 position=1,
  `AWAITING_CHECKS`, merge-group head `d1e59a9f…`) → **TERMINAL_SUCCESS**
  (state=MERGED, admission-gate run id `41351042632` conclusion=**success**,
  graphql↔rest 교차검증 일치). required-checks 0건을 SUCCESS로 해석하지
  않았다 — admission-gate merge_group 실행이 관측된 권한 행사다.

## 3. Cold acceptance (고정 merge SHA 독립 재현)

고정 대상: MERGE_SHA `d1e59a9f5b33dc4ea78537e5f6e01249fb8a5622`(detached
worktree `/tmp/cold_u64_main`). 러너 전문은 `artifacts/acceptance/
u64_cold_accept_run1_verbatim.txt`(run1)·`u64_cold_accept_run2_verbatim.txt`
(run2)이며 명령·환경
(케이스별 신규 `AXIOM_STATE_DIR`/`AXIOM_VAULT_DIR`, `AXIOM_CHARON_BIN`=
pinned 0.1.281, `GITHUB_TOKEN`=`gh auth token`, gitignored `proofs/.lake`
provisioning)이 그대로 보존된다. 43종 산출물 + SHA256SUMS.

### 3-0. 실행 우연 2건 (퀴크로 문서화)

- **fetch 누락 + `git rev-parse --verify` echo quirk**: MERGE_SHA는
  원격 병합 후 로컬 객체 저장소에 없었다. `git rev-parse --verify
  <full-40-hex>`가 객체 존재 확인 없이 입력 SHA를 echo해 1차 러너가
  `WORKTREE FAIL`로 즉시 중단됐다; `git cat-file -t`가 실재 확인 권한임을
  확인하고 `git fetch origin main` 후 재실행했다(parents=34c332910+
  798e83a5f 교차검증). → `docs/spec/git_rev_parse_verify_echo_quirk.md`
- **`make build` 스탬프 → porcelain 오염 → Zero-Footprint fail-close**:
  빌드가 트래킹된 `src/generated/build_metadata.json`(gitHash·
  commitCount·generatedAt·경로 목록)을 재생성해 cold worktree가 dirty
  상태로 케이스에 진입했다. → `docs/spec/
  build_metadata_stamp_porcelain_quirk.md`

### 3-a. run1 — 빌드 직후(dirty porcelain) 관측

| 항목 | 관측 |
|---|---|
| 엔진 | detached HEAD = `d1e59a9f5`, `make build` exit 0, `ax --check-provenance` OK — embedded BuildSourceHash == live src tree(`7211238942987599411`) |
| A | exit 0, **verified + 인증서 `5e7fb809…`**(irHash가 premerge와 동일) |
| B | exit 0, unknown — 커널 거부(omega, `a ≥ 0 | a := _x`) 후 **counterexample unconfirmed(cvUnresolved)**: replay harness는 실제 컴파일·실행되어 `AXIOM_REPLAY_BEGIN/8/AXIOM_REPLAY_END`(exit 0, 관측값 8 ≠ 명제 7)을 냈지만, post-run Zero-Footprint porcelain 검사(`rust_replay_adapter.nim:704-728`)가 ` M src/generated/build_metadata.json`을 보고 **fail-close** — 관측과 판정의 분리가 계약대로 작동 |
| C | exit 0, unknown — 전폭 `+` 벽, reason이 premerge와 **바이트 동일**(`COLD==PREMERGE: True`) |
| D | exit 0, unknown — `no derivable guard obligation`(zero mechanical goals) |
| 서브젝트 | fixture 3파일 sha256 사전/사후 동일(`SUBJECT_IMMUTABLE=yes`) |

### 3-b. run2 — 트래킹 파일 HEAD 복원(clean porcelain) 관측

`git checkout -- src/generated/build_metadata.json`으로 MERGE_SHA 커밋
내용 복원(porcelain empty 확인) 후, 동일 엔진·동일 환경에서 4케이스 재실행.

| 케이스 | exit | 판정 |
|---|---|---|
| A `u64_echo` | 0 | **verified 1/1 + 인증서 `5e7fb809…`** — 3회 연속 독립 민팅(premerge·run1·run2)에서 irHash 동일 |
| B `u64_seven_mutant` | **1** | **failed — counterexample CONFIRMED**: `input._x=0`, `propertyViolated=(= result #x0000000000000007)`, `replay.verdict=rvAgree`, **`replay.subjectGitRef=d1e59a9f5b33dc…`(반례 증거가 고정 merge SHA에 결속)**, `replay.treeMerkle=b8107e84…`, `moduleSha256` 사전=사후, `porcelainClean=true`, rustc `1.95.0 (59807616e 2026-04-14)`·rustcHash·componentsHash·channel·profile 전부 기록 |
| C `u64_add` | 0 | unknown — 벽 reason이 **다시 바이트 동일**(`RUN2==PREMERGE: True`) |
| D `u64_seven` | 0 | unknown — zero mechanical goals |

- run2 종료 후 porcelain 여전히 empty(`PORCELAIN_EMPTY_AFTER=YES`) —
  prove·replay 경로가 서브젝트/리포 트리에 쓰지 않음(Zero-Footprint)을
  재관측했다. `SUBJECT_IMMUTABLE_RUN2=yes`.

### 3-c. 인증서 결정론 — 의미 코어와 실행 우연의 분리

premerge 인증서(`artifacts/premerge/5e7fb809….json`)와 run2 인증서
(`artifacts/acceptance/cold_run2_certificate_5e7fb809.json`) 비교:

- **동일(의미 코어)**: irHash(파일명) `5e7fb809…`,
  `receiptArtifactIdentity 5fa8fc13…`, `receiptExecutionContract
  c99e5bed…`, `receiptInvocationContract`(동일 content-addressed
  `/tmp/axiom_kc_5fa8fc13….lean`), `receiptTheoremIdentity
  'u64_echo_post'`, `receiptToolchainFingerprint 8a364bab…`,
  `observedAxiomSet [Quot.sound, propext]`, `observedSorryScan []`.
- **상이(실행 우연, 설계상)**: `modulePath`(실행 루트 경로), 실행 정체성
  다이제스트(`executionIdentity`/`executionContractDigest`), 서명,
  journal/trust refs — 무엇이 증명됐는지가 아니라 어디서·어떤 실행으로
  증명됐는지를 기록하는 필드(④ 슬라이스의 의미 비교 원칙과 동일 구조).

따라서 "인증서 바이트 동일"은 주장하지 않는다 — **증명 내용의 정체성이
독립 실행에서 안정적으로 재현**됐다고 기록한다.

### 3-d. 증거 무결성 정정 (폐쇄 후속 커밋)

첫 폐쇄 커밋(PR #1178)에서 `git add`가 .gitignore 패턴(`*.log`·`*.sh`·
`*.diff`)에 걸린 증거 파일 8종을 조용히 건너뛰어, 커밋된 SHA256SUMS가
리포에 없는 파일을 참조했다(fresh clone에서 `sha256sum -c` 불가 — 증거
무결성 결함). ④①② 슬라이스 관례(증거 산출물 `.txt` 재명명)에 따라 8종을
재명명하고 두 매니페스트를 재생성·검증했다:
`check_provenance.txt`·`make_build.txt`·`runner_run{1,2}_output.txt`·
`run1_build_metadata_diff.txt`·`u64_cold_accept_run{1,2}_verbatim.txt`
(acceptance)·`cli_acceptance_suite8.txt`(premerge). 내용은 재명명만으로
보존되며 원본 확장자는 이 노트에 기록된다. 퀴크 문서화:
`docs/spec/evidence_manifest_gitignore_quirk.md`.

## 4. 서브젝트 불변성

- fixture 3파일(`src/lib.rs`·`axiom_u64_probe.llbc`·`axiom.specs.json`)
  sha256: run1 pre == run1 post == run2 == §1 커밋 지문
  (`ee24768…`·`9016f6fb…`·`7f75e346…`) — 3시점 전부 동일.
- replay harness는 `include!("<abs>")`로 서브젝트를 스플라이스 — 서브젝트
  트리에 기록 없음(`rust_replay_adapter.nim` 모듈 계약).
- run2 전·후 porcelain 모두 empty — 유일한 트리 변경은 빌드 스탬프뿐이며
  이는 HEAD 복원 후 재관측했다(§3-a/§3-b).

## 5. 판정

§0 계약(Terminal Outcome) 대 수용 증거:

| 계약 항목 | 관측 증거 | 판정 |
|---|---|---|
| u64 경계 타입 양측 독립 디코드 + eaAgree | 게이트웨이 14/14(§1-a), cold A verified | 달성 |
| 선언 긍정 명제 Lean kernel Verified + 인증서 | cold run2 인증서 `5e7fb809…`(irHash 3회 안정, 의미 코어 동일 §3-c) | 달성 |
| 선언 부정 명제 커널 거부 → Z3 → 실제 rustc 재현 CONFIRMED(failed, exit 1) | run2 B: exit 1, CONFIRMED, `subjectGitRef=MERGE_SHA`, `rvAgree`, `porcelainClean=true` | 달성 |
| 전폭 `+` 명명된 이유 fail-closed unknown | run1·run2 C: reason이 premerge와 바이트 동일(2회) | 달성 |
| 전체가 고정 merge SHA 독립 재현으로 재관측 | detached `d1e59a9f5`에서 run1·run2 관측 행렬 | 달성 |

**계외 보너스 관측(Zero-Footprint 음성 대조)**: 동일 엔진·동일 서브젝트·
동일 SHA에서 worktree cleanliness만 달리한 두 실행이 `CONFIRMED(exit 1,
failed)`와 `cvUnresolved(exit 0, unknown)`로 갈렸다 — Zero-Footprint
계약이 운영 환경에서 실제로 판정을 좌우함을 기계 관측으로 확정했다.

이 슬라이스의 Terminal Outcome은 **VERIFICATION_COMPLETE**(경계 타입
u64 행 v1.1의 완결). width-64 산술·Ref/Adt·C7 전체 문법은
`docs/spec/rust_certified_subset.md` §1의 선언된 후속 과제로 남는다.
