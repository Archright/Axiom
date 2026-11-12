# MG 증거 게이트 사후 추증 — PR-venue 재사용 구조 비고 · allowlistOk 차세대 효과 · NEG-CTL 원장 · 샌드박스 드릴 상호참조 (2026-10-17)

> **종류**: 증거 추가 기록 (docs-only 사후 추증) — 계보: [ci_epoch_record_mg_evidence_gate_2026-10-17.md](ci_epoch_record_mg_evidence_gate_2026-10-17.md), [mg_evidence_gate_prereg_2026-10-17.md](mg_evidence_gate_prereg_2026-10-17.md), [mg_evidence_gate_canary_2026-10-17.md](mg_evidence_gate_canary_2026-10-17.md), [mg_evidence_gate_canary2_2026-10-17.md](mg_evidence_gate_canary2_2026-10-17.md). 본 문서는 판정을 만들지 않는다(Reporter) — merge-admission 권위는 GitHub(ruleset 20303214)와 기존 정본(`docs/spec/admission_generation.md`, ADR-0025/0027/0032)에 그대로 있다.
> **측정 원문**: 런·로그·API 관측은 모두 2026-10-17 실측(`gh run view --log`, `gh api`, 로컬 텔레메트리). 원문 인용은 전부 그대로 복사다(각주 없음 — 인용부 안은 편집 불가).
> **적용 세대**: 신세대 callee blob `1c9848a74b4767faa696138c2985d267d73f65ac` (PR #895 착지, 세대 기록은 epoch record §2.2).

---

## 1. PR-venue 재사용의 구조적 비고 (금지 부재로서의 보존)

ADR-0032의 venue 분리에서 **PR venue는 정적 preflight**다 — (b) "pull_request 이벤트에서 각 leg는 정적/구조 검사만 수행한다… B-tree 빌드, GO-critical 커널 E2E, D9 스테이징, witness 서명, full mint 체인은 PR에서 실행하지 **않는다**". 착지 자격의 유일 정본은 merge_group verdict이며 "(a) … PR venue의 결과는 착지 자격이 아니다". 따라서 신세대의 실행 강제(판정 CAS 강제 술어)가 PR venue에 닿지 않는 것은 결함이 아니라 venue 분리의 귀결이다 — **"PR 사전검사 재사용 유지"는 이를 금지하는 규정이 존재하지 않기에(금지 부재) 구조적으로 보존**된다. 강제 술어는 `merge_group` 단일 조건(명시 env `AXIOM_JUDGMENT_CAS_FORCE_EXECUTED=1` + 보조 벨트 `GITHUB_EVENT_NAME=merge_group`)이고, PR venue에서는 양 트리거 모두 부재다.

실측 근거 — 카나리 2(PR #900)의 PR 사전실행 런 **39004512386**(`admission-gate`, event `pull_request`, head `canary2/mg-evidence-gate-activation-2026-10-17@1275d65cf`, conclusion success, run_started_at 2026-10-17T04:57:54Z) 로그 원문:

```text
venue=preflight — fast static preflight only; landing verification is the merge_group venue (ADR-0032 (a),(b))
```

정적 전용임이 런 자신의 판정 라인으로 명시된다(ADR-0032 (f)의 `PREFLIGHT PASS —` 계열 관측점). 재사용 보존의 의미는 **단위 계약 시나리오 (ii)**가 담보한다 — `tests/unit/test_judgment_cas.nim` (G11, "gate inactive (PR venue, no force env) → REUSED preserved for EVERY subject"):

```nim
expect(plan.mode == jReused,
  "[" & subjectName(s) & "] gate inactive (PR venue) → jReused preserved (got " & plan.reason & ")")
```

**잔여 표면**: 실행 재사용이 남는 유일 표면은 **직접 `workflow_call` 호출**이다 — callee가 호출자의 `event_name`을 상속함은 실측됐고(prereg 인용: MG 런 → `venue=landing`, PR 런 → `venue=preflight`), 직접 호출 시 event는 `workflow_call`이 되어 벨트는 발화하지 않는다(단위 시나리오 5: "명시 `0` + `workflow_call` | 게이트 OFF (벨트는 merge_group만)"). 즉 신세대가 차단한 것은 merge_group 착지 venue의 재사용이며, PR preflight 재사용과 workflow_call 직접 호출의 재사용은 차단 대상이 아니다(각각 ADR-0032의 venue 분리와 계보 유지가 지배).

## 2. allowlistOk=false 차세대 효과 검증 (등록 경로의 main 도달 확인)

MG run 38997388474의 `{"closureChange":true,"allowlistOk":false,...}`(prereg §7 등록 근거)는 동반 4경로가 회전 허용목록 밖이었던 실측이다. 그 해소 등록(prereg §7.2)이 **main에 도달했는지**를 원문으로 검증한다:

```text
$ git show origin/main:src/cli/merge_cli.nim | grep -n -A6 RotationAllowlistExtra
224:  RotationAllowlistExtra*: seq[string] = @[
```

열거형 말단(같은 소스, 라인 264–267)에 4경로가 존재한다:

```nim
    "data/benchmarks/perf_latest.json",
    "docs/evidence/ci_epoch_record_mg_evidence_gate_2026-10-17.md",
    "docs/evidence/mg_evidence_gate_prereg_2026-10-17.md",
    "tests/unit/test_judgment_cas.nim"]
```

등록 커밋 `62dbeab8b`("fix(trust): 회전 완결 — 클로저 멤버 3경로 재앵커(48a33ede4 blob) + 동반 4경로 RotationAllowlistExtra 등록")는 PR #895를 통해 main에 착지했다(merge commit `338c54150`, 2026-10-17). prereg §7.2의 등록 효력 문구 — "**판정기는 B 체크아웃 빌드 바이너리로 이 열거형을 소비하므로, 본 등록은 다음 세대부터** 이 4경로의 회전 분류를 해소한다" — 와 정합한다: 이후 회전의 판정기는 main(또는 그로부터의 후보 트리)에서 빌드되므로, 4경로는 다음 회전부터 허용목록 내로 분류된다(자기 PR 판정에 쓰일 수 없었던 #826과 동일 구조).

## 3. 부정 대조(NEG-CTL) 원장 기록 — 3계층 거부 실측

위반 커밋 `7541b874706311049200920c09ab14c63d373e86`(브랜치 `negctl/mg-evidence-gate-2026-10-17`)은 `.github/workflows/admission-check.yml` blob을 `ad7c12ffa79326020b05182ec9f1f35c0d9d7816`으로 바꾸고 TWS 기록을 동반하지 않았다(핀은 `config/trusted_writer_set.json:41` `trustedAdmissionWorkflowSha` = `1c9848a74b4767faa696138c2985d267d73f65ac`, `config/policy/epoch_manifest.json:9` `productionExecutionPin` = 동일). PR #901("[NEGATIVE CONTROL — DO NOT MERGE] expected-set shrink probe: d2_persist dropped from go-critical lane-1")은 **3계층 모두에서 거부**됐다:

- **L0 — 로컬 epoch_transaction_gate 푸시 거부**: 텔레메트리 `~/.cache/axiom/push-admissibility/log.jsonl:1740` 원문:

  ```json
  {"ts":"2026-10-17T05:22:36Z","oid":"7541b874706311049200920c09ab14c63d373e86","ref":"negctl/mg-evidence-gate-2026-10-17","result":"FAIL","duration_s":17,"sha256":{...},"budget_s":120}
  ```

  원인: **blob↔TWS 불일치** — epoch_transaction_gate의 3계층 판정(G2 engine-pin closure = SliceEngine callee 3종 + TWS `productionExecutionPin` 기록 + manifest 필드는 "전체로 닫혀야" 함)에서 위반 커밋은 admission-check.yml blob만 바꾸고 페어 기록을 바꾸지 않았다 → reason code `EPOCH_TRANSACTION_INCONSISTENT`(`tools/ci/epoch_transaction_gate.nim` 상수 `ReasonInconsistent`).

- **L1 — PR-venue TWS 핀쌍 어검(fail-closed 2종 원문)**: 위반 커밋의 PR 런 2건이 failure:

  1. 런 **39006228881**(`landing-integrity`, `pull_request`, failure) — check `verify-trusted-writer-set`:

     ```text
     WRITER_SET: FAIL — admission-check.yml blob sha mismatch: expected=1c9848a74b4767faa696138c2985d267d73f65ac actual=ad7c12ffa79326020b05182ec9f1f35c0d9d7816 (pair invariant violated) (fail-closed)
     ```

  2. 런 **39006228876**(`trusted-writer-set`, `pull_request`, failure) — check `trusted-writer-set-pairing`:

     ```text
     verify_trusted_writer_set: FAIL (exact TrustedWriterSet equality violated — fail closed)
     ```

- **L1.5 — 큐 편성 봉쇄**: 위반 브랜치의 merge_group 런은 **0건**(API `actions/runs?branch=negctl/mg-evidence-gate-2026-10-17&event=merge_group` → `total_count 0`, 브랜치 전체 런 6건은 모두 `pull_request`), PR #901은 `mergeable_state: blocked`, `merge_queue_entry: null`(2026-10-17 API 관측; PR은 mergedAt 없이 CLOSED).

**라이브 대조군**: 동시간대 PR #902("fix(experiments): p0d2f replay_formal helper prefix + Q3 concurrency quirk")는 정상 병합 — mergedAt **2026-10-17T05:43:23Z**, merge commit **`60f2952853420eb7606f0d12fbb1cf5ae45f58f0`**(선행 팁은 카나리 2 머지 커밋 `32bd93279`). 같은 큐가 같은 시간대에 정상 후보는 병합했으므로, #901의 봉쇄는 큐 전역 장애가 아니라 위반 커밋에 대한 선택적 거부 관측이다. 위반 커밋은 main에 도달 불가다 — `git merge-base --is-ancestor 7541b8747 origin/main` → exit 1.

**공식 문서 근거**: GitHub Docs "Managing a merge queue" ([링크](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/configuring-pull-request-merges/managing-a-merge-queue)) — 설정 "Only merge non-failing pull requests" 설명에서 Enabled(Yes)인 경우 "**All pull requests must satisfy required checks to be merged.**"; Failing CI 섹션 — "if there are failed required status checks … **the pull request will be removed from the queue**".

**정직 노트**: 위 L1.5의 blocked·entry null·MG 0건은 **실측 관측**(API 응답 값)이고, "봉쇄"의 편성 의미론(ALLGREEN — required checks 미충족 PR은 그룹에 들어가지 않는다)은 **문서가 규정**한다. 본 원장은 규정된 경로가 해당 사건에서 실제로 닫혔음을 기록할 뿐, 문서의 규정을 대체하지 않는다.

## 4. 샌드박스 복구 훈련 상호참조 (Archright/update-probe)

샌드박스 저장소 `Archright/update-probe`의 복구 런북 드릴이 동일한 착지 경로 의미론을 샌드박스에서 1:1 검증했다(전문: [docs/evidence/sandbox_recovery_drill_2026-10-17.md](https://github.com/Archright/update-probe/blob/2d860f07de8c62f198afc0d00362f5413c764bbd/docs/evidence/sandbox_recovery_drill_2026-10-17.md), 라벨 원문 **"SANDBOX DRILL — NOT a production window record"**). 생산 ruleset 20303214는 일절 접촉 없음(드릴 문서 §선언).

- **PR #5** "Sandbox drill payload 2026-10-17 (legitimately blocked queue entry)" — MERGED 2026-10-17T02:47:07Z, merge commit **`4f5ef69240c17d65562efe1196eb97deb002eb2e`** = 평가 창 내 유일 착지.
- **PR #6** "SANDBOX DRILL evidence — sandbox recovery drill 2026-10-17" — MERGED 2026-10-17T02:53:02Z, merge commit **`2d860f07de8c62f198afc0d00362f5413c764bbd`** = **복원된 큐 경유 MERGE**(queue entry `gh-readonly-queue/main/pr-6-*`, `admission-check` GREEN 후 큐 착지 — payload 실패는 `pr-5-*` ref 스코프).
- **핵심 산물**: ruleset 스냅샷 통화성(사전 복제본 1,255 bytes vs 드릴 시점 신선 `[snap]` **1,479 bytes** — 복원 대상은 신선본), 평가 창 **6,505ms**(open PUT 시작 → close PUT 완료), history **정확 2버전**(53585474 창 개방 / 53585483 창 폐쇄, actor wintrover 단일), 6필드(enforcement·name·target·conditions·rules·bypass_actors) byte 복원 **IDENTICAL**(문서 기록 `[verify]×6` — 6회 연속 GET 대조 IDENTICAL), **정확히 1회 착지**(first-parent Δ=1, 2부모 머지 커밋 77ae0dd+396c4ba=PR #5 head).
  - 정직 노트: 본 추증 의뢰서의 "IDENTICAL×7" 표기와 달리 드릴 원문 기록은 6회 연속 GET·6 IDENTICAL 라인이다. 본 문서는 원문 기록(×6)을 따른다.
- **runbook 실용 발견 2건**: (1) ruleset API는 `merge_queue` 규칙 PUT에서 **7파라미터 전체 + 대문자 `"MERGE"`** 필수 — 7회 422 `Invalid property /rules/4: data matches no possible input` 거부 후 성공(거부 자체는 상태 변화 0을 GET으로 검증); (2) **PR 자신의 required check가 실패하는 동안 merge queue는 편성되지 않는다**(130초 관측: `gh-readonly-queue/*` ref 부재, merge_group 런 부재) — 큐 마비 상태의 재현은 큐 진입 런(merge_group)을 실패시켜서 수행한다(merge_group 런 **38995951958** completed/FAILURE → PR #5 dequeue).

## 5. 잔여 명시 (open register — 중복 기록하지 않는다)

1. **certificate-mint P7c "적색 런 append 금지" — 별도 계획 필요**: 착지 런이 ledger append 후 RED로 끝나는 경우의 exactly-once 원장 상태는 prereg §6.1이 out-of-scope로 명시한 뉘앙스다. append 금지(또는 조건부 append)로의 수습은 (a) 계약 개정(`docs/spec/certification_continuity_contract.md` — P7c-x 계보: PR #626 3주체 append 배선, `venue=='landing'` 조건 부여 e036c82e4/#651·a24abfc8e/#656)과 (b) **org 핀 회전 의례**(certificate-mint.yml은 org 중앙 저장소 `Archright/.github` 소유 — 핀 callee 잠복 결함 선례: `docs/evidence/incident_pinned_callee_deadlock_bypass_2026-10-09.md`)를 수반한다. 본 추증은 계획 필요 사항으로만 기록한다.
2. **G10(e) 허메틱 수정 — 동시 진행**: prereg §6.2 기록 결함(changed-tree 드릴이 HEAD~1 트리를 써서 docs-only 커밋 조합에서 `k3 != k1` 실패 — 환경 의존)의 수정이 진행 중이다. 2026-10-17 기준 **로컬 브랜치 `fix/judgment-cas-g10e-hermetic-2026-10-17`** 존재(원격 푸시·PR 미확인 — `gh pr list` 검색 0건). PR이 발생하면 본 항은 해당 번호로 갱신 가능하다.
3. **ADR-0027 상태 정합 · waiver 정본 — 계획 필요 목록**: `docs/adr/0027-queue-delegation.md` Status는 **"PROPOSED (2026-09-29)"**인데, ADR-0032·ADR-0025 Amendment E는 merge_group 실행 경로의 도입을 선행 사실로 참조하며 MG 런 가동은 실측된 상태다(본 추증 §3 대조군 포함). 상태 정합(PROPOSED 표기 ↔ 도입 현실) 갱신과 `config/decision_binding.waiver.*` 정본과의 정합 점검은 별도 계획 항목이다. 본 추증은 현 상태를 관측 기록할 뿐 갱신을 수행하지 않는다.
