# H_new 세대 승격 기록 — 컨트롤러 PR #227 (verdict ∥ publish) 착지 · §4.3 양 ruleset 재핀 · 첫 신세대 관측 (2026-10-17)

> **종류**: 실행 증거 문서 (generation promotion record) — 사전등록 `docs/evidence/serial_chain_dag_prereg_2026-10-17.md`(PR #889) 후보 A의 컨트롤러 회전·§4.3 ruleset 재핀·첫 신세대 production 관측의 사실 등록. 후보 A의 게이트·착지 절차 원본은 사전등록이며 본 문서는 이를 변경하지 않는다.
> **권위**: merge-admission 판정 권위는 GitHub에 있다(org ruleset · merge queue · native MERGE 커밋 — Authority ≠ Adapter). 본 문서의 수치는 전부 runs/jobs/rulesets API GET 관측값이다.
> **H_new**: `29094836bc4488280d98c22665470dcb2e54da1a` — Archright/.github 컨트롤러 HEAD (PR #227 native MERGE 커밋 `2909483`)
> **T_promotion**: 컨트롤러 PR #227 mergedAt **2026-10-16T23:52:43Z** · ruleset 재핀 readback **2026-10-17T00:35Z**

---

## 1. 세대 전환 체인 (후보 A — 컨트롤러 단독 회전)

| leg | PR/브랜치 | 커밋 | 시각 (UTC) | 내용 |
|---|---|---|---|---|
| 사전등록 | Axiom #889 | — | 2026-10-17 | 후보 A 사양·판정 게이트(§5)·착지 절차(§7) 고정 — no-peeking |
| Controller | Archright/.github **#227** | `30bb5ee` (branch `opt/verdict-needs-parallel-publish`) → MERGE 커밋 **`2909483`** | **2026-10-16T23:52:43Z MERGED** (native merge) | org 호출부 `admission-gate-v2.yml` `verdict` job `needs`에서 `mint-publish` 제거 → **`[mint-prepare, closure-deriver, anchor-resolve]`** |
| Ruleset | — (API PUT) | — | readback 2026-10-17T00:35Z | org ruleset **25218071**·**23943917** → sha H_new 재핀 (§2) |

근거: 사전등록 §2 분류 — publish→verdict는 artifact 소비가 전혀 없는 유일한 무소비 직렬 엣지(스케줄링 산물)이며, 본 회전은 그 엣지만 제거한다.

## 2. §4.3 dual-ruleset 재핀 (하나의 논리적 단위) — readback 2026-10-17T00:35Z

양 org ruleset을 **H_new = `29094836bc4488280d98c22665470dcb2e54da1a`**로 재핀했다. readback은 `gh api /orgs/Archright/rulesets/{id}` 로 **양 ruleset 모두 sha `29094836…` 표시를 확인**(2026-10-17T00:35Z)했다.

| ruleset | 이름 | before sha | after sha |
|---|---|---|---|
| 25218071 | axiom-admission-gate (`admission-gate-v2.yml`) | `5bfc9114` (H_v2 세대 — 사전등록 §7 판독값) | `29094836bc4488280d98c22665470dcb2e54da1a` |
| 23943917 | landing-integrity | `ade11572` (컨트롤러 2커밋 뒤처진 핀 — 사전등록 §7 기록) | `29094836bc4488280d98c22665470dcb2e54da1a` |

**수렴 노트**: 본 재핀은 사전등록 §7-1이 기록한 뒤처진 landing-integrity 핀(`ade11572`, #225 이후 미갱신)을 같은 논리적 단위에서 **H_new로 수렴**시켰다 — 재핀 후 양 ruleset은 동일 sha로 정합한다.

## 3. callee 회전 불필요 (컨트롤러 단독 변경)

변경은 컨트롤러(org 호출부) 단독이다. callee 핀은 건드리지 않았으며 트리거 시점에 내용 최신(content-current)이었다:

| callee | 핀 |
|---|---|
| `admission-check.yml` | `64f78ab7` |
| `certificate-mint.yml` | `9aaee76f` |
| `runner-pool` | `ba773d06` |

(출처: run 38983713057의 `referenced_workflows` — 재현 §7.)

## 4. 정직 절차 노트 — freeze 단계의 관측 공백 (주장 아님, 공백의 등록)

승격을 수행한 executor 에이전트가 승격 완료 후 정지(stall)하여 최종 보고가 없다. 그 결과 사전등록 §7-3의 **freeze 단계**(repo ruleset **20303214** `merge_queue.max_entries_to_build` 2→0, PUT 창 동안 유지)는 **소급 검증이 불가능하다**. 본 문서는 freeze의 실행을 주장하지 않는다 — 관측 가능한 사실만 등록한다:

- **관측된 종료 상태**: ruleset 20303214 `max_entries_to_build` = **2** (정상값) — 이는 "freeze가 실행 후 해제되었다"와 "freeze가 없었다" 양쪽과 모두 정합하며, 어느 쪽인지 판별하는 관측은 존재하지 않는다.
- **큐 상태**: Axiom merge queue는 창 전체에서 비어 있었다(2026-10-17T00:30Z 확인) — 재핀 PUT은 큐 영향 소지 없는 창에서 수행되었다.
- **결과**: 양 org ruleset 재핀은 큐 영향 없이 성공했고(§2 readback), 종료 상태는 정상이다.

→ **분류**: 이것은 **관측 공백(observation gap)의 정직한 등록**이지 freeze 발생의 기록이 아니다. 사전등록 §7-3 절차 대비 미검증 부분으로 남는다.

## 5. 첫 신세대 production 실행 (merge_group run 38990981390)

**바운드 런**: merge_group **38990981390**, created **2026-10-17T01:28:08Z** — **PR #892 착지**의 admission 런으로, H_new 세대 핀에서의 **첫 production 실행**이다.

| 잡 | 구간 (UTC) | 결론 |
|---|---|---|
| `mint-publish / publish` | 01:36:51 → 01:37:41 | success |
| `verdict / admission-check` | 01:36:51 → 01:37:40 | success |
| 롤업 `admission-check` | — | success |

- **병렬 겹침 49 s** — 양 잡이 01:36:51에 동시 시작(사전등록 §5-(i) 구조 성립의 직접 관측).
- **run 결론 success**, 롤업 `admission-check` success.
- **post-lane tail 190 s** (직렬 세대 기준 중앙값 291 s 대비).

**혼동 방지 기록**: run **38983713057**(run_started_at 2026-10-16T23:52:59Z)은 **직전 핀 세대**에서 실행된 런이다 — 이 런의 직렬 타임라인은 예상된 결과이며 본 승격의 효과 관측이 아니다(이 런은 §3 callee 핀 판독 출처로만 참조한다).

## 6. 판정 의무 처분 — J1–J4 공허 적용 (vacuous) 근거 등록

J1 semantic parity · J2 evidence equivalence · J3 cache soundness · J4 worker determinism(`docs/spec/ci_optimization_tcb_judgments.md:17-20`)에 대해: 본 변경은 **callee·검증 의미론 변경이 전혀 없다**(callee 핀 동일 — §3; verdict = `ax merge --dry-run --json` exit 계약 불변 — 사전등록 §4-1). 실행-의미론 입력이 불변이므로 **J1–J4는 이 근거와 함께 공허하게(vacuously) 적용**된다. 본 승격의 작동 증거는 런타임 관측(§5 — 병렬 + green + tail)이다.

- **§5-(ii) 절감 문턱 판정(중앙값 절감 > 30 s)은 ≥5-run 분산 인지 표본으로 별도 진행**한다 — 사전등록 게이트가 권위이며, 본 문서의 n=1 관측(tail 190 s)은 그 전제 데이터포인트일 뿐 판정이 아니다.

## 7. 재현 명령

```bash
# §2 ruleset readback — 양 org ruleset의 workflows 규칙 sha (H_new 확인)
gh api /orgs/Archright/rulesets/25218071 --jq '.rules[] | select(.type=="workflows") | .parameters'
gh api /orgs/Archright/rulesets/23943917 --jq '.rules[] | select(.type=="workflows") | .parameters'

# §4 freeze 종료 상태 — repo ruleset 20303214
gh api /repos/Archright/Axiom/rulesets/20303214 --jq '.rules[] | select(.type=="merge_queue") | .parameters'

# §5 바운드 런 + 잡 타임라인 (게이트 (i): publish ∥ verdict 겹침, tail 계산)
gh api repos/Archright/Axiom/actions/runs/38990981390 --jq '{id, event, created_at, conclusion}'
gh api repos/Archright/Axiom/actions/runs/38990981390/jobs \
  --jq '.jobs[] | [.name, .started_at, .completed_at, .conclusion] | @tsv'

# §3 callee 핀 + 직전 세대 런 구분
gh api repos/Archright/Axiom/actions/runs/38983713057 --jq '{id, run_started_at, conclusion, referenced_workflows}'

# §1 컨트롤러 PR #227 — merge 커밋/시각
gh api repos/Archright/.github/pulls/227 --jq '{merged_at, merge_commit_sha}'
```

---

*본 문서는 세대 전환의 등록 기록이다. 판정 기준의 원본은 사전등록(2026-10-17)이며 본 문서는 이를 변경하지 않는다 — §5-(ii)의 ≥5-run 게이트 판정은 별도 등록 문서로 진행된다.*
