# §1b 자립 번들 `ax report` 전 표면 관측 — 기계 검증 증거 (2026-11-09)

> **종류**: 수용 관측(acceptance observation) 기록. **판정 권위는 기계 관측이며, 이 문서는 그 기록이다.**
> **Date**: 2026-11-09 · **Branch**: `workstream/ax-report-bundle-observation` (base `b9aba2a` = main @ PR #30 merge — 본 문서 착지 시점 기준이며, 관측 자체는 §2의 관측 tip `df378f6`에서 수행됨)
> **관측 대상**: §1b Binary Distribution Contract(`docs/spec/productization_contract.md` §1b) 자립 번들이 무소스·무토큰 환경에서 `ax report` **전 문서화 표면**(plain · `--json` · `--canonical-digest` · `--help` · `--state-file`)을 제품 계약(§1:23 documented commands · §7 CLI Contract 표)대로 산출하는지 — S2c 관측(`docs/evidence/s2c_standalone_bundle_observation_2026-11-08.md`)이 prove·capability 표면을 종결한 뒤의 후속 관측.
> **관측 원본**: 본 문서의 모든 관측값은 관측 세션(작업 `agent-fa0iwpd7`)이 남긴 최종 보고 로그에서 전사했다 — 수치·exit 코드·해시는 원문 그대로이며, `…`로 끝나는 해시는 원문이 축약형으로 기록한 값이다(임의 복원 아님). 관측 산출물은 /tmp 휘발 경로(`rbr-*`)에 있었으므로, 정본 관측값의 저장 기록은 이 문서가 유일하다.

---

## §1. 관측 계약

관측 기준은 다음 계약 조항이다(`docs/spec/productization_contract.md`):

- **§1:23 Documented commands (v1 contract surface)**: `ax prove`, `ax report`(각각 help surface 필수).
- **§7 CLI Contract 표 `ax report` 행**: exists ✔ · help ✔ · success `0` · verification-failure `1`(SATISFIED) · json schema `axiom.report.v1` · stdout/stderr split.
- **§7 Report document schema identity (Phase 5)**: `ax report --json` 문서 최상위 `"schemaVersion": "axiom.report.v1"`.
- **§7 Report flag surface (2026-10-21)**: `ax report`가 받아들이는 인자는 `--json`·`--state-file <path>`·`--canonical-digest`·`resilience` 서브커맨드뿐(`--upstream`은 2026-10-31 계약 선언 — §11).
- **§7 VKD 실측값**: `ax report --json` → `metrics.vkd` = **0/23 = 0.0%** — 문서화된 측정 truth(이 값은 측정이며 목표가 아님).
- **§7 one-run-exit 규칙**: `projectRunOutcome` 유일 규칙 — `CONTINUE → 0`, `BLOCK → 1`, `UNRESOLVED → 1`; `ax report --json`은 그 얇은 투영(`computeReportExitCode`).
- **§7 exit 3 = INVALID_INPUT**: 지원되지 않는/잘못된 입력 → 문서화된 non-success이며 verification claim이 아님.
- **§1b 루트 해석(§1b:40)**: `AXIOM_ROOT` env 최우선 → 미설정 시 바이너리 위치에서 상향 `.axiom_root`/`axiom.toml` 앵커 탐색(첫 앵커 종료). 트리 밖 앵커 미스는 fail-closed.
- **§1b 배포 자산**: 번들 tar.gz = `ax`(루트 직접 배치) + `config/spec/` + `data/verification_scope.lock`·`data/baseline.json`·`data/bug_attribution/` + 루트 앵커 `.axiom_root`.
- **§1b exit 5-state 무변경**: 확정 disproof는 exit 1(VERIFICATION_FAILURE).

판정 양성 기준: §1b 자립 번들에서 prove exit 1(VERIFICATION_FAILURE — S2c 기대치 재현)로 만들어진 상태를 원본으로, `ax report` 전 표면이 위 계약 조항과 부합하는지, 결정론(바이트 동일)·Zero-Footprint·음성 대조 fail-closed가 유지되는지를 관측으로 판정한다.

## §2. 관측 환경

| 항목 | 값 |
|---|---|
| 관측 시각 | 2026-11-08 16:4x–17:1x UTC (KST 2026-11-09 새벽) — 관측 세션 기록 기준 |
| 관측 tip | `origin/main` = `df378f603070c243afbd8718a22df3d08a9d90fb` — 관측 시작·종료 양 시점 fetch로 재확인, **이동 없음** |
| 관측 브랜치 | `workstream/report-bundle-root-seam` @ df378f6 (origin/main에서 생성, §2.1/§2.7 준수) — **커밋 0, 트리 클린** (porcelain 0; bin/ax 재빌드는 gitignored 산출물) |
| 번들 | 문서화 절차(S2c 증거 §3) 그대로: `nimble build`(Nim 2.2.10) → `--check-provenance` OK → bundle_tool CI 동일 플래그 컴파일 → assemble/verify PASS(tree-equality+runtime 포함) |
| 결속 | bundleSha256 `814862b9fc6fe8d75768c9b197e8d1ddeed3b8a48f4c19c64fe65306f62d8852` · binarySha256 `32cc80d5e7e1…` · sourceCommit=buildSha=df378f6 · v0.6.0 |
| 서브젝트 | Archright/nim-libp2p @ `a130a7f322…`(S2c 핀 — 전체 SHA는 S2c 증거 §2에 기록: `a130a7f32219909bdcda14b7f1e64d0804fc832`) `/tmp/rbr-subject` · state `/tmp/rbr_state`(lock 시드) · vault `/tmp/rbr_vault` |

## §3. 기계 관측 (전부 명령→관측→exit)

### 3.1 prove — 상태 원본

**prove(번들, `env -u AXIOM_ROOT -u AXIOM_READ_TOKEN`, CWD=/tmp)** — exit 1 VERIFICATION_FAILURE(확정 disproof·GateVerdict FAIL): S2c 기대치 재현. **이후 모든 report 관측의 상태 원본**이다.

### 3.2 §1b 번들에서 `ax report` 전 표면

| 명령 | 관측 | exit |
|---|---|---|
| `ax report` (plain) | Soundness Registry 대시보드(VKD 0.0%) | 1 |
| `ax report --json` | `schemaVersion: axiom.report.v1` · `metrics.vkd {verified:0, total:23, ratio:0.0}`(계약 §7 문서화 실측값과 동일) · `runOutcome {verdict:FAIL, gateVerdict:FAIL}` — prove 판정의 정직 반영, one-run-exit 규칙(§7) | 1 |
| `ax report --canonical-digest` | digest `bcf6d99f…` 산출 | 0 |
| `ax report --help` | 사용법 29줄(`ax report [--json] | --upstream…` 포함) — §1:23 help surface 계약 | 0 |
| `ax report --state-file <path>` | env 해석 문서와 **바이트 동일** | 1 |

## §4. 불변성·해시·대조

- **결정론**: `--json` 재실행 **바이트 동일** · 번들 디렉터리 내부 실행(CWD=번들 루트) 바이트 동일(CWD 독립) · `AXIOM_ROOT=<번들>` 이스케이프 해치(§1b:40) 바이트 동일
- **Zero-Footprint**: 서브젝트 pre/post HEAD 동일(`a130a7f`), 0 dirty, `bytesview.nim` sha `b205c969…` 불변
- **음성 대조(앵커 없는 ax 단독 복제)**: 문서화된 에러 `"ax report must be executed within an Axiom repository worktree. Set AXIOM_ROOT env var or run from project root."` — **exit 3 fail-closed** (INVALID_INPUT)
- **무상태 신선 번들(환경변수 전부 제거)**: `"proof state not found: <번들>/logs/ax_proof_state.json"` — exit 3 fail-closed
- **대조군(리포지토리 루트, 동일 상태)**: exit 1·동일 metrics. 유일한 차이는 `runOutcome.readTimeRevalidation.established:false`(강등). 격리 대조(리포지토리 prove→리포지토리 report, 신규 상태)는 강등 **없음**(established) — 즉 강등은 "번들 바이너리가 쓴 상태를 리포지토리 바이너리가 읽은" 상대-실행 정체성 결속((b) 지문+(e) 에포크 불일치, `src/verification/accounting/run_accounting.nim:409,421`)의 **설계 동작**(§15.3 — 결속 불능 상태는 INCONCLUSIVE로 강등, `docs/spec/execution_accounting_contract.md`)이며, §1b 고객 경로(번들 prove→번들 report)는 established로 정상이다.

## §5. 후보 결함 가설 판정

**기각(관측 근거)**: `src/cli/report_cli.nim:436`의 레거시 `findRepoRoot()`(§1b 시임 `findRepoRootStrict`와 다른 폴백 보유)는 —

1. `AXIOM_ROOT` env 최우선
2. `getAppDir()` 상향 앵커 탐색에서 번들 루트의 `.axiom_root`를 **1단계에서 정상 적중**(관측: 이로 인해 3종 VKD 입력 전부 정상 해석)
3. 폴백 `parentDir(startDir)`는 앵커 미스에만 발동하고 `report_cli.nim:437-439`의 명시적 앵커 가드가 곧바로 fail-closed 에러(exit 3)로 전환

— 관측된 모든 경우에서 §1b:40 루트 해석 계약과 행동적으로 동등했다. `ax report`의 문서화 명령·플래그·exit·스키마·help 표면 전부 계약 부합.

## §6. Non-Conclusions / Follow-up 후보 (범위 밖, 미수정·미관측 명시)

- **저널 생산자/판독자 루트 분리(관측됨, 개선 여부는 미판정)**: prove의 TrustCommit 저널은 vault에 기록됨(실측: `/tmp/rbr_vault/data/trusted/journal` 3+ entries — cert_writer/vault_manifest의 baseDir=vault)인데, report VKD 판독은 `activeJournalRoot` 우선순위(DECISION-0673, `src/core/trusted/trust_commit.nim:115`)로 `AXIOM_STATE_DIR/data/trusted/journal`을 먼저 봄(실측: 빈·부재 → `listCommitIds`가 `ok([])` 반환 → 분자 0). **리포지토리 맥락에서도 동일 동작**(번들 특유 아님)이고 이번 런은 certRed/disproof 주장이라 분자는 어느 쪽도 0 — 인과 영향 없음. 단 certGreen 성공 런에서 DECISION-0673이 경고하는 "유효 증거 비가시화" 시나리오 여부는 **관측되지 않았다** — Follow-up 실험 후보.
- `--upstream`·`resilience` 서브커맨드는 관측하지 않았다(외부 쓰기·보조 표면, §1b 관측 범위 밖).
- report CLI의 알 수 없는 옵션 조용한 무시는 계약 §7에 문서화된 기존 잔류 갭(수정은 회전 핀 경로 전용) — 미접촉.

## §7. 판정 및 착지

**판정 — 결함 없음(Verified / contract-conformant)**: `ax report`는 §1b 무소스·무토큰 자립 번들에서 제품 계약대로 동작한다(§3–§5 관측 전면). 관측으로 판정했으므로 관측 세션은 수정을 수행하지 않았다(§2.2 — 결함이 아니면 관측 보고로 종결). 본 문서는 그 관측값의 정본 기록을 `docs/evidence/`에 착지하는 문서 비행이다(docs-only — 코드·워크플로·게이트·핀·도구 변경 0건).

**착지**: 본 문서 커밋 후 PR(base main) 생성, 즉시 `gh pr merge --auto --merge --match-head-commit "$(git rev-parse HEAD)"`로 auto-merge 무장(수동 merge 금지 — merge authority는 GitHub, §2.3). merge SHA·랜딩 상태는 최종 보고서에 기록한다(정본 = GitHub).
