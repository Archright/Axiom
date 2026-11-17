# MUST-T2a trust-surface landing 위임 기록 — DEBT#550 findRepoRoot 수리 (PR #132)

> 본 문서는 `docs/agents/rules_workflow.md` §2.8 MUST-T2a의 per-PR·시점명시 위임 기록이다.
> **병합 명령 실행 전에 커밋된다.** 기록자 ≠ 승인자: 본 문서의 작성자는 agent
> (wintrover의 대리 실행자)다. rotation의 실제 승인 주체는 사용자(wintrover)이며
> 에이전트는 실행자일 뿐, 자가 승인하지 않는다.

## §1. 승인 원문 (사용자 = 인간 아키텍트 wintrover)

- **전면 승인 원문 1**: "권한이 필요한 부분은 전면 허가한다." — 2026-11-16
  (Authority Preflight 요청문 내; Terminal Outcome·범위와 함께 제시된 명시).
- **전면 승인 원문 2**: "권한이 필요한 부분은 전면 승인한다." — 2026-11-16
  (반복 명시 — 백그라운드 병렬 진행 지시와 동일 메시지).
- **per-PR 위임 맥락**: 사용자의 지시 "남은 이슈들 중 계획이 필요 없는건 모두
  백그라운드 병렬 서브에이전트로 … 해결해주고" 및 "목표는 코드 작성 완료가 아니라
  실제 운영 상태다. `구현 → 검증 → PR → merge → canonical main/production 실행 →
  acceptance`를 실제 명령과 관측 가능한 증거로 끝까지 확인하라." — 본 PR은 그
  지시의 직접 산출물(DEBT#547/550 workstream)이며, 본 기록은 그 단계의
  per-PR·시점명시 위임이다.

## §2. per-PR 위임 기록

- **PR**: Archright/Axiom #132 — `workstream/vs-debt547-550-reporoot`
  (병합 대상 head = 본 기록 커밋의 SHA; 기록 직전 head `520d1e616e22c21ec4ec1e6aacbf69414f2ca21f`).
- **위임 시점 명시**: 2026-11-17/18 (본 커밋 타임스탬프가 시점 증거).
- **위임 병합 수행 주체**: agent under explicit per-PR delegation from wintrover.
- **실행 명령 (MUST-T2a ③ — manual lane only, 원샷)**: (i) ruleset 27097366에
  일시 bypass actor 등록(PUT), (ii) REST 병합 엔드포인트
  `PUT /repos/Archright/Axiom/pulls/132/merge`(merge_method=merge, sha=병합 시점
  head 40자), (iii) bypass 제거·ruleset 무결 복원(PUT) + `RESTORE_IDENTICAL`
  readback. `--auto` 암은 MUST-T1 위반이므로 사용하지 않는다(원샷 수동 병합).

## §2.1 큐 경로 폐쇄 실측과 rotation 메커니즘 (2026-11-17, 병합 전)

- **verifier App preflight 거부 (실측)**: head `520d1e6`의 check-runs —
  `axiom-admission-verifier`(App 5795152)가 `admission-check` **failure** 발행:
  `trust_surface=FAIL — mismatch:config/trusted_writer_set.json (total 1)`,
  output_title `Preflight verification rejected` (2026-11-17T15:16:42Z).
  `config/policy/trust_surface_manifest.json` §"purpose": "A PR that alters any
  listed path cannot receive the independent verifier's admission-check; such
  changes require the audited break-glass lane and an explicit epoch rotation."
  `config/trusted_writer_set.json`는 그 15경로 중 1개다 — 본 PR은
  `trustedCheckerTreeClosure`의 `src/core/utils/repo_root.nim` pin을 수리본
  blob(`3c50452…`)으로 re-anchor하므로, verifier preflight를 정상 경로로 통과할
  수 없다(구조적, 실패 아님).
- **re-anchor는 pin 변경이 아님 (기계 계약, `tools/ci/epoch_transaction_gate.nim`
  주석)**: "a trustedCheckerTreeClosure re-anchor (a closure member changed in the
  same PR → the derived closure refresh) with the pin VALUE
  trustedAdmissionWorkflowSha unchanged … is NOT a pin change: it passes layer 1
  with a loud NOTE while layers 2/3 still verify the record at HEAD, and the
  closure CONTENT equality (TWS == derived closure at H) stays owned by the
  merge-time rotation check." 본 PR의 `trustedAdmissionWorkflowSha` = `d27feae…`
  불변, `config/policy/epoch_manifest.json` 불변 → 별도 epoch rotation 불요.
- **ADR-0041 §2.6 선언**: "Trust-surface PRs do not ride the auto-merge queue …
  lands through the audited break-glass lane (MUST-T2a: bypass activation →
  native merge → bypass restoration, all timestamps and readback recorded)."
  아키텍트의 선행 사례: PR #121(§`docs/evidence/readiness_required_check_activation/must_t2a_rotation_landing.md`),
  PR #127(`docs/evidence/vs_perf_attr_acceptance_2026-11-16.md` §10.4) — 동일 3단계.
- **실행 전제 (본 기록 작성 시점 실측)**: (1) head `520d1e6`의 체크 —
  **33 pass / 1 fail(위 verifier preflight뿐) / 13 skip / 0 pending**, 나머지
  required contexts(admission DAG 내부 job 포함) 전원 success; (2) 큐 비었음
  (`git ls-remote origin 'refs/heads/gh-readonly-queue/*'` = 0행 — mid-queue
  mutation ban 준수).

## §3. 착지 후 절차 (본 위임 범위 밖 — 각각 별도 관측·기록)

1. 병합 커밋(main)에서 `bin/ax` release 재빌드 → `make test-fast-one
   T=tests/unit/test_repo_root.nim`·`T=tests/unit/test_vkd_determinism.nim`
   재실행 green 관측.
2. ruleset 27097366 `bypass_actors == []` 및 pre/post 스냅샷 동일
   (`RESTORE_IDENTICAL`) 확인.
3. PR #130(동일 결함의 병렬 PR) — #132 착지 후 중복 종결 사유 코멘트 기록.