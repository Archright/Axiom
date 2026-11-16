# VS-C3 toolchain 스코프 축소 — 반증 NO-GO (2026-11-16)

> **종류**: 조사 종결 기록 (NO-GO evidence). 목적은 후보 C3 — attest/admission-check 집계 잡의
> provision-scope를 `nim`으로 축소해 도구체인 복원 시간(설계 추정 ~15-20s)을 절감하는 안
> (설계 문서 §3 Tier 1, `docs/design/admission_gate_performance_cutover_design_2026-11-13.md`)의
> 구현 전 반박 검증이다. 결론: **NO-GO — 집계 잡은 사전빌드 ax의 소비자가 아니라 Lean 커널
> 재실행(witness)의 주체다.** 본 문서의 MERGE는 조사 종결 기록이지 구현 승인이 아니다.

관측 기준: 원격 main `605f9ba`(2026-11-16, admission-check.yml blob `9fa3903`) — 반증 1차 확인은
`09b42c5`(blob `69d110b9`)에서 수행했고 witness 스텝은 양 커밋에서 동일 위치(`:1449`)·동일 본문.
코드 인용 4종(`src/cli/cert_cli.nim`·`src/verification/attestation_orchestrator.nim`·
`src/verification/kernel_reexecution.nim`·`.github/actions/setup-axiom-toolchain/action.yml`)은
관측 시점 origin/main 블롭과 일치 확인. production ircheck 실물 실험은 §2 (run 43849381963,
build_sha `09b42c58`).

## 1. 반증 연쇄 — 집계 잡은 왜 Lean 도구체인을 요구하는가

C3의 전제(설계 §3): "집계 잡 = 사전빌드 ax 소비, mint류의 runtime 범위 선례(7-11s)". 반증:

1. **집계 잡(admission-check)의 witness 스텝이 인증 체인을 재실행한다.**
   `admission-check.yml:1449-1450` — `"[check] Attest witness-only (B-built ax kernel, H-derived
   data)"`, 발화 조건 `stage=='attest' && scope_sl08 && scope_sl03 && venue=='landing'`(모든
   landing 배치). `:1526`·`:1536` — `$BIN_AX cert attest --witness-only …`.
2. **CLI 진입점은 leanExe를 구성하지 않는다.** `src/cli/cert_cli.nim:833`(runWitnessOnlyCli) →
   `:867` `attestWitnessChainCas(…, defaultAttestationOptions(), …)` →
   `src/verification/attestation_orchestrator.nim:224-235` — `leanExe: ""`, `z3Path: ""`,
   `ircheckExe: ""`.
3. **Stage (c)는 인증서의 `leanSource` 재실행을 위해 컴파일러(Lean)를 직접 호출한다.**
   `attestation_orchestrator.nim:690-708`
   (attestKernelStage) — "fresh kernel re-execution … lean first, fail-closed" — `:698`
   `reexecuteLean(certLike, options.leanExe, …)`. `src/verification/kernel_reexecution.nim:467-472`:
   leanExe가 비어 있으면 `AXIOM_LEAN_CMD` env, 그마저 없으면 **폴백 `"lake env lean"`**.
   `:479-481` 임시 `.lean` 파일에 인증서의 `leanSource`를 쓰고 `--threads=1`로 실행,
   `:492-493` exit≠0 → `krCompileError`(체인 FAIL).
4. **워크플로우는 어떤 오버라이드도 제공하지 않는다.** admission-check.yml 전체 grep:
   `LEAN_SYSROOT`·`AXIOM_LEAN_CMD`·`AXIOM_Z3`·`AXIOM_IRCHECK` — 0건. 즉 stage (c)의 실제
   명령은 항상 `lake env lean`이다.
5. **nim 스코프는 lake/lean을 공급하지 않는다.** `tools` action `.github/actions/setup-axiom-toolchain/action.yml`
   — `:71` "~/.elan is the only path this scope drops", `:825` "Lake probe is full-scope only:
   the nim scope has no ~/.elan at all", `:960` Install Lean 4.33.0 (elan)은
   `provision-scope == 'full'` 전용, `:376` full 스코프 복원 경로에만 `~/.elan` 포함,
   `:874` PATH 추가도 full 스코프만.

→ nim 스코프 착지 시 witness의 `lake env lean`은 명령을 찾지 못해 예외/실패 → stage (c)
FAIL(fail-closed) → witness 스텝 exit 1 → 집계 required check red → merge queue 블록.

## 2. production ircheck 실물 실험 — stage (b)도 도구체인 파일에 의존한다

링크 수준의 elan 무의존(사전빌드 바이너리 = `ldd`가 glibc만 참조)과 실제 판정 수행은 별개다.
run 43849381963(2026-11-16T10:29:58Z, success)의 `admission-check-base-artifacts`
(ID 14216577336, 41,511,741B, zip sha256 `cf9757…`, manifest build_sha `09b42c58` — 파일 8종
digest 전부 실측 일치)로 실험:

| 검증 | 결과 |
|---|---|
| `ldd proofs/.lake/build/bin/ircheck`(119,585,096B, sha256 `1d0bb7…` = manifest 일치) | glibc 계열만(libc/pthread/dl/rt/m/ld) — libleanshared·elan 경로 없음. GLIBC 심볼 최대 2.17 |
| no-arg 실행: `env -i`(elan·HOME·PATH 부재) vs 일반 환경 | exit 1, stdout/stderr **byte-identical** — 프로세스 로드·진입은 elan 무의존 |
| `--check-file` 실입력(valid fixture 2종), bare env-i | **exit 1 `process 'lean' exited with code 255`** — 판정 실패 |
| 동일 입력, `LEAN_SYSROOT` + Init olean 셋(~400M, ~/.elan 밖)만 제공 | 전 6 fixture(valid 2·corrupt·truncated·empty·nonexistent)가 일반 환경과 stdout/stderr/exit **byte-identical**, 3회 반복 결정론적, 1회 ~180ms |

원인: `proofs/IR/MetaCheckIR.lean` `checkIRFromBytes`가 런타임에
`Lean.initSearchPath (← Lean.findSysroot)` + `importModules #[Init]` 수행 — `findSysroot`는
`LEAN_SYSROOT` env 우선, 없으면 **PATH의 `lean --print-prefix`를 spawn**한다. 즉 ircheck의
런타임 의존은 elan(버전 매니저)이 아니라 **Lean 4.33.0 툴체인 파일(Init olean)의 존재**이며,
nim 스코프는 그 파일도 복원하지 않는다(§1.5).

**부수 관측(운영 위험 기록)**: PATH에 elan shim만 있고 툴체인이 없는 환경(빈 HOME)에서 `lean`
호출 시 shim이 cwd 상위의 `lean-toolchain`을 해석해 미설치 툴체인을 **자동 설치**했다(관측치
2.9G, known-projects에 저장소 경로 기록). "elan shim은 남고 툴체인만 없는" 구성은 예기치 않은
대용량 네트워크·디스크 소비를 유발할 수 있다 — 향후 스코프 설계 시 배제할 것.

## 3. 영향 — nim 스코프를 착지했다면 관측될 결과

- stage (c) `lake env lean` 부재 → witness FAIL(§1) — fail-closed이므로 **무결성 위반은
  아니나 required check가 항상 red**가 되어 merge queue가 영구 블록(CI 가용성 정지).
- stage (b) ircheck 판정도 sysroot 부재로 실패(§2) — (b)+(c) 모두 붕괴.
- 부수로 B-cache 키(`axiom-b-${b_identity}-${recipe_hash}${a_fp}` — action `:348-352`)의
  a_fp 변동에 의한 B-MISS·artifact 채널 전환은 도달 전에 무의미해진다.

C3' 계획이 함께 검토한 운영 절차(queue freeze·ruleset 재핀·.github callee 핀 회전)는 본
반증으로 전부 불필요해졌다 — docs-only 변경은 trustSurface를 만지지 않으므로 epoch cutover
없이 일반 큐 경로로 착지한다(선례: docs-only PR의 큐 통과).

## 4. 부수 검증 기록 (C3'와 무관하게 유효 — 향후 epoch cutover 재검토용)

- **Queue freeze(V1, 공식 문서)**: `max_entries_to_build=0`은 새로운
  `merge_group.checks_requested` dispatch를 억제하고 대기 PR은 값을 1 이상으로 올릴 때까지
  진행하지 않는다(GitHub docs). 이미 실행 중인 잡은 취소되지 않아 별도 drain
  (`gh api repos/Archright/Axiom/actions/runs?event=merge_group&status=in_progress` 등)이
  필요하다. 0은 branch protection UI로 불가(1-100 범위) — ruleset REST로만 설정 가능하며
  PUT은 ruleset 전체 교체(GET→수정→PUT)다. 올바른 순서는 **freeze-first**: concurrency 0 →
  readback → in-flight drain → 재핀 → readback → 복원(빈-큐 확인→변경의 TOCTOU 제거).
- **Artifact 채널(V3, 코드)**: manifest-verified artifact 다운로드·검증은
  `scope_sl08 && venue=='landing'`이면 b-cache HIT 여부와 무관하게 매 landing 실행된다.
  7멤버 중 5종(bin/ax·install_ax_cas·ircheck·derive_checker_closure·jq)은 artifact가 애초에
  primary 경로(mv -f가 B-restore 사본을 덮어씀) — B-MISS는 새 비용이 아니라 예상된 캐시
  동작이다. manifest 검증(sha256 digest 7종 + build_sha==B + 전 실패 경로 exit 1)은
  A-cache와 독립된 신뢰 경로다.

## 5. 판정과 잔여 옵션

- **C3 = NO-GO.** 설계 문서 §3의 C3 행은 반증으로 폐기(§9 갱신)되었고, [승인-1]의 잔여
  범위는 C6(~1-4s)·C7(적색 경로만, 그린 SLO 0s)로 축소된다 — Tier 1은 사실상 소멸한다.
- 잔여 최적화 경로는 둘뿐이다:
  - **Tier 3(제품/도구 코드, 계약 보존, 별도 슬라이스)**: lane(0) evidenceId 배터리
    (`make test-fast-one` 2건, 99s/77s)·s1a 단일 테스트(150s)의 실행 시간 자체. C4 선례
    (s1a 150.6s→56.5s, SHA-256 반복 계산 memoization, 일반 workstream PR #59)와 동형 접근 —
    중복 계산이 프로파일링으로 증명될 때만, 검사 EXECUTED·판정 재계산·증거 키는 불변.
  - **Tier 2(C1-rev, [승인-2] 아키텍트 판정 대기)**: lane 분할 개정, ~99s. per-lane
    evidenceId 독립성 약화를 수반하므로 본 반박 검증의 범위 밖에서 별도 승인 절차가 필요.
- 본 문서는 조사 종결 기록이다 — 측정하지 않은 계산을 중복이라 주장하지 않았고, 증명되지
  않은 생략을 최적화라고 부르지 않는다. 배터리 99s의 내부 분해는 별도 Tier 3 조사가 수행한다.
