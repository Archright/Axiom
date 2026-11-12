# M7 위임 실행 모델 — 진단 execution의 Actions 위임 (착지 기록, 2026-10-12)

**Workstream**: `ci/m7-delegated-execution` (M7 위임 실행 모델 — 사용자 승인 "병합 진행해", 2026-10-12)
**정본 계약**: `docs/spec/diagnostic_execution_delegation.md` (본 기록은 그 계약의 착지 증거다)
**선행 정책 PR**: policy/surface-v77-m7-delegated — 본문의 신규 워크플로 2건에 대한
FROZEN(`.github/**`)→CONTROLLED 선등록(v51 knownBlindSpots 자기승인 차단의 수용 경로 —
PR #745/#751 choreography 선례). policyVersion 76→77. 실측: base(v76) × 본문 워크플로
diff(A×2) = FAIL(FROZEN/SURFACE_FORBIDDEN), v77 × 동일 diff = PASS(violations 0).
**착지: PR #771 MERGED 2026-10-12T03:50:26Z (merge commit 93f06f29, merge queue
그룹 머지)** — CI repository-surface FAIL 관측은 base-policy binding(v76) 하의 예상
동작(관측 전용·required 아님 — repository_surface.yml 헤더 계약)이며 병합을 막지 않았다.

## 1. 해소된 모순 → 채택된 설계

이전 계획의 모순: (a) App 개인키 로컬 접근 불가 ∧ (b) 로컬 토큰 민팅 코드 부재 ∧ (c)
로컬 도구가 `actions/create-github-app-token` 토큰 사용 — 동시 불성립(그 액션은 job 안에서만
동작, post step revoke, 토큰 미로컬). 채택: **토큰을 로컬로 가져오지 않고 진단 EXECUTION을
Actions로 위임**(`.github/workflows/diagnostic-authority.yml`).

## 2. 착지물 (변경 내용)

| 파일 | 변경 | 내용 |
|---|---|---|
| `.github/workflows/diagnostic-authority.yml` | 신규 | in-job 민팅(pinned `actions/create-github-app-token@bcd2ba4` v3.2.0 — release-ship.yml 동일 핀) + explicit `permission-*`/`repositories` 입력 + 같은 job 진단 실행 + 시크릿 부재 fail-closed 게이트 + `add-mask`(토큰 비기록·artifact 0) + canary 화이트스위치 |
| `.github/workflows/trusted-writer-set.yml` | 신규 | `verify_trusted_writer_set.sh` CI 배선(pull_request@main + push@main, `contents: read` 단일, jq 의존만) — 기존 수동/조직 부분 복제본만 존재하던 TWS 검증의 저장소 내 집행점 |
| `tools/ci/m7_canary_drill.sh` | 신규 | canary deny drill — §4 실측 참조 |
| `tools/merge_ruleset_drift_monitor.nim` | 수정 | M7 no-fallback 가드(라이브 fetch 경로) + 헤더 credential 계약 갱신 |
| `tools/ci/landing_observe.sh` | 수정 | 동일 가드(실패 폐쇄 → UNKNOWN exit 2) + `[CRED]` 라인 |
| `tools/ci/pareto_harness.nim` | 수정 | 동일 가드(`--github-run` ingest 경로; `--from-json` 오프라인 무관) |
| `tools/ci/observe_fault_streak.nim` | 수정 | 동일 가드(main 진입) |
| `tools/ci/local_ci_gates.nim` | 수정 | 동일 가드(`--pr` 경로) |
| `src/cli/merge_cli.nim` | **후속 rotation slice로 이동** | credential 선택 `AXIOM_DIAG_TOKEN` > `GITHUB_TOKEN` + strict fail-closed + credential-source 로그 계약은 확정·스펙 §4 기재. 착지는 본 PR에서 제외 — pin member 변경(ROTATION 주체) ∧ 본 PR changed set의 비멤버 14건이 A2 allowlist ①과 정합 불가(merge_group 2026-10-12 06:25 UTC ROT_ALLOWLIST 실측). 별도 rotation slice(pin 재앵커 + member/A2 companion 전 경로)로 직후 착지 |
| `tools/setup_branch_protection.nim` | 삭제 | 분해(decommission) — §5 참조 |
| `docs/spec/merge_authority_integrity.md` | 수정 | §10 잔여 항목을 분해 결정 기록으로 갱신 |
| `docs/spec/diagnostic_execution_delegation.md` | 신규 | 정본 계약(등록 스펙·워크플로 계약·no-fallback·canary·종료 조건·feasibility) |

## 3. 종료 조건 (정본 어휘 — 이전 "발급 권한 없음" 단축 서술의 교정)

> **감시 정상 작동 ∧ 로컬 진단 프로세스의 발급 루트 접근 불가 ∧ 진단 App의 상한 밖 권한
> 발급 불가 ∧ 운영 credential의 변경 행위 거부 입증**

교정 근거: 진단 App의 민팅 능력은 상한 경계 안에서 존재하고("발급 권한 없음"이 아님),
로컬 프로세스의 발급 루트(App PEM) 접근 불가는 별개 속성이다 — 두 속성을 하나의 술어로
뭉뚱그리면 극장이 된다(§0.9). 현재 상태(착지 시점):

| 논항 | 상태 | 근거 |
|---|---|---|
| 감시 정상 작동 | **구조 배치 완료 / 첫 실행 대기** | diagnostic-authority.yml 착지; 시크릿 부재 시 fail-closed 실패가 정상(게이트 작동 확인 — §4 G4) |
| 로컬 진단 프로세스의 발급 루트 접근 불가 | **성립** | 로컬 토큰 민팅 코드 0(전수 구조상 App PEM 소비 경로는 워크플로 step 유일); 도구는 명시 env 1개만 읽음(§4) |
| 진단 App의 상한 밖 권한 발급 불가 | **구조 배치 완료 / 응답 관측 대기** | 설치 상한(read-only 5개) + per-issuance 등식 요청 착지; 실효 스코프는 발급 응답 미노출로 **UNKNOWN 기록**(§3 계약 — 요청 지정 ≠ 검증 스코프) |
| 운영 credential의 변경 행위 거부 입증 | **드릴 준비 완료 / 첫 실행 대기** | m7_canary_drill.sh 착지(dry-run 실측 §4); TEST PR 준비 후 첫 실실행이 입증 위치 |

## 4. 기계 검증 (명령 → 관측 → 판정)

- `bash -n tools/ci/m7_canary_drill.sh` → PASS.
- canary dry-run: `--canary-pr 999 --repo Archright/Axiom --dry-run` → 요청 계획(GET control,
  GET preflight, PUT merge; headers/ body; optional ruleset leg) + 판정 규칙 출력, 네트워크 0,
  exit 0 실측.
- canary no-token guard: `AXIOM_DIAG_TOKEN` 미설정 + 실모드 → "FAIL — AXIOM_DIAG_TOKEN
  absent … fallbacks: none, by design", exit 2 실측(gh-auth 폴백 구조 부재 확인).
- Nim 컴파일: 수정된 4개 도구 + `src/cli/main.nim` `nim check` 전부 exit 0(credential 헬퍼
  추출 리팩터 후 재확인 포함).
- `make build` → exit 0(✅ Build successful; decision-binding WARN 38건은 기존 에스컬레이션
  임계 미도달 경고 — 본 slice 무관).
- `bin/nimtry` → **PASS — 4138 violations (debt anchored), 0 new**. 주: credential 가드를
  `resolveDiagnosticCredential` 헬퍼로 추출하면서 runMergeCli effective SLOC를 78로 유지
  (4 카운트 라인)해 위반 fingerprint가 베이스라인과 동일 — `data/nimtry_baseline.json`
  **무변경**(PR #765 앵커 존중, `git diff` 0 실측).
- `make check-determinism` → PASS (Toolchain pins OK).
- `bash tools/ci/git_access_scan.sh` → PASS — git sites=64, breakers=0, depth-1; 신규
  워크플로 2건(diagnostic-authority, trusted-writer-set) 모두 "depth-1 (breakers enforced)",
  run blocks 내 git 호출 0 실측. UNRESOLVED 목록은 컴파일 아티팩트 인벤토리 전용(exit 0).
- `make check-nim-theater` → PASS (no theater patterns detected).
- `make doc-path-validator` → 초기 FAIL 1 warning(분해된 `tools/setup_branch_protection.nim`
  참조 미해결) → `tools/ci/doc_reference_policy.json` HISTORICAL_ALLOWED carve-out(선례
  comment 형식) 후 **PASS(모든 문서 경로 유효)** 재실행 확인.
- `bash tools/ci/validate_workflow_shell.sh` → PASS (154 blocks, 0 failures — 신규 워크플로
  2건 포함).
- `bash tools/ci/monitor_purity_scan.sh` → PASS.
- merge_cli credential 행위 프로브: 본 PR 트리에서 제거된(rotation slice 이동) 구현에 대해
  실측 완료 — (i) `AXIOM_DIAG_STRICT=1` + 토큰 부재 → "refusing GITHUB_TOKEN …
  fail-closed" 로그 + exit 1; (ii) 양 env 부재 → "credential-source=GITHUB_TOKEN (fallback
  …)" + "no credential" 로그 + exit 1(기존 동작 보존); (iii) `AXIOM_DIAG_TOKEN=<stub>` →
  "credential-source=AXIOM_DIAG_TOKEN" 로그 확인. 정본 기록은 rotation slice 착지 증거로
  이관된다.
- **선존재 drift (본 diff 미관여, PR 본문에도 기록)**: (a) `make check-imports` FAIL 1건 —
  `tools/ci/pareto_harness.nim` `import tools/sha256_native`(도입 0ef85393a = origin/main
  조상 실측; GATES_FAST/local-ci 소속, pre-push·required CI 불포함); (b)
  `attestation_witness.nim` provenanceValidationError 2건 — 베이스라인 동일 존재.

## 5. setup_branch_protection.nim 처분 — 분해 (decommission)

`docs/spec/merge_authority_integrity.md:166-169`(착지 시점)이 기록한 미해결 공백에 대한 후속:
전수 검색에서 (a) 호출자 0, (b) Makefile/빌드 배선 0, (c) debt 레지스트리·architecture_debt
참조 0을 실측했고, 페이로드는 ruleset 권위 이전 이전의 구식 branch protection
(`all-gates-passed` — 현행 ruleset required check는 `admission-check`)을 겨냥했다. 등록 시
M1의 "write 경로의 단일 권위 주체"가 회복되지 않고 operator identity 제2 쓰기 경로가
합법화될 뿐이므로 **분해**를 택했다. 파일 삭제 + integrity 문서 §10 갱신. 폐기 기록은
권한·면제를 갖지 않는다(§2.5).

## 6. TWS CI 배선

`.github/workflows/trusted-writer-set.yml` — `tools/ci/verify_trusted_writer_set.sh`는
네트워크·쓰기 0의 순수 로컬 판정(git blob + jq)이라 러너 기본 토큰 외 credential 불요.
`pull_request`(머지 커밋의 워크플로 집합) + `push@main`(착지 상태) 발화. 스크립트의 blob
sha는 `git rev-parse HEAD:` 재유도라 스크립트 자체 계약과 정합. **required check 승격은
인간 액션**(ruleset required checks 편입)으로 남는다 — 승격 전 어드바이저리 관측
(계약 §8).

## 7. feasibility 실측 요약

정본: `docs/spec/diagnostic_execution_delegation.md` §7 표. 요지 — Nim 도구는
setup-axiom-toolchain(repository_surface.yml 동일 공급 경로, pinned Nim 2.2.10) +
`nimble install -y checksums@0.2.2`(integrity manifest bootstrap — repository_surface.yml
선례)로 실행 가능; `gh`/`jq`/`unzip`은 러너 프리인스톨; `ax merge --dry-run`은 `bin/ax` 빌드
수반으로 opt-in; local_ci_gates는 서브스트레이트 빌드가 최중량이라 기본 미배선(수동
dispatch용으로 문서화). 차단 요소 없음.

## 8. 잔여 (정직 기록)

1. 진단 App 등록 자체는 인간 게이트다 — 등록 전 diagnostic-authority job의 실패는
   fail-closed 정상이다.
2. 발급 응답(`permissions`/`repositories`/`expires_at`)은 pinned 액션이 노출하지 않는다
   (action.yml@bcd2ba4 실측: outputs = token/installation-id/app-slug) — 실효 스코프는
   **UNKNOWN**으로 기록되며, 응답 관측 경로가 확보될 때 갱신된다. 요청측 지정을 검증
   스코프로 서술하지 않는다.
3. canary 첫 실실행은 TEST PR·TEST 대상 준비 후 수행된다 — 본 착지는 드릴의 dry-run까지를
   검증한다(네트워크 실시도, 실거부 캡처는 첫 실행 기록이 정본).
4. `trusted-writer-set.yml`의 required 승격은 인간 액션으로 남는다.
5. **merge_cli credential 선택 — 후속 rotation slice (본 PR 분할)**: `src/cli/merge_cli.nim`은
   `trustedCheckerTreeClosure` pin 멤버라 그 변경은 ROTATION 주체가 되고, 본 PR changed set의
   비멤버 14건이 A2 allowlist ①과 정합 불가(merge_group 2026-10-12 06:25 UTC
   ROT_ALLOWLIST 실측 — prNumber 775, newAnchorOk=false). 분할: 본 PR은 NORMAL 주체로
   착지(merge_cli 변경 제외), credential 선택은 pin 재앵커(`config/trusted_writer_set.json`
   ④ pin@H==derived(H)) + pin member/A2 companion 전 경로 구성의 별도 slice로 직후 착지.
