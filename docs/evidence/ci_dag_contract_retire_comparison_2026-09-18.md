# ci_dag_contract_gate retirement — 제거 전/후 게이트 입력·결과 기계 비교 증명

> 2026-09-18. Slice 2 (ci.yml retirement) — ci_dag_contract historical freeze retire.
> 목적: **ci_dag_contract_gate 제거로 인해 현재 살아 있는 admission invariant 또는
> execution authority에 대한 검사가 단 하나도 소실되지 않았음**을, 제거 전/후
> 게이트 입력과 결과의 비교로 기계적으로 증명한다.
> 기준: `origin/main` = b92178fcd (S1 merge_continuity retirement 포함).

---

## 1. 제거 전 게이트 입력·결과 (기계 기록)

### 1.1 ci_dag_contract_gate

입력 — `config/ci_dag_contract.json`:

```json
{
  "baselineCommit": "bd00af9a1",
  "freezeTag": "ci-dag-static-freeze",
  "workflowFile": ".github/workflows/ci.yml",
  "proofDoc": "docs/ci/dag_semantic_redesign.md",
  "jobs": [],
  "allowedNeedsEdges": [],
  "allowedEmptyNeeds": [],
  "intraJobSerialPairs": [
    { "job": "verify-integration-r2-proof",
      "steps": ["make verify-all", "make ci-lake-build"],
      "reason": "proofs/.lake write-write 충돌 (Makefile:912/594) — needs edge 아님, 동일 job co-location" }
  ]
}
```

`jobs=[]`, `allowedNeedsEdges=[]` — 매칭 대상 0. gate 소스(`tools/ci_dag_contract_gate.nim`)
는 workflowFile 존재 검사(fileExists) 후 그 내용의 jobs/needs 에지만 매칭하므로,
**jobs=[]인 tombstone에서 실질 매칭 대상이 없는 vacuous PASS**였다.

실행 출력:

```
$ bin/ci_dag_contract_gate
PASS: jobs=0, edges=0/0, empty-needs=
exit=0
```

> 이 게이트가 (긍정적으로) 검사하던 invariant는 오직 하나 —
> **"ci.yml이 존재하고, 존재하는 ci.yml의 모든 job/needs edge가 매니페스트와
> 일치한다"** — 였다. ci.yml이 tombstone(`jobs: {}`)이 된 2026-09-16 이후
> `jobs=0, edges=0/0`은 공집합 매칭의 vacuous PASS였다.

### 1.2 publication_scope_gate

입력 — `config/publication_scope.json`: 5개 워크플로 규칙
(`ci.yml`, `autoscaling_canary.yml`, `n8_canary.yml`, `admission_producer.yml`,
`canonical-main.yml`). (S1에서 `merge_continuity.yml` 규칙 제거 — 본 slice 시작 시점).

실행 출력:

```
$ bin/publication_scope_gate
PASS: workflows=5, registered=5, triggers+permissions conform
exit=0
```

이 게이트가 ci.yml에 대해 (긍정적으로) 검사하던 invariant:

- **I-1a**: ci.yml이 publication_scope.json에 등록되어 있다 (unknown-workflow 소멸).
- **I-1b**: ci.yml의 trigger set이 계약과 정확히 일치한다
  (`workflow_dispatch`만 — push/pull_request/schedule 등장 금지).
- **I-1c**: ci.yml의 `permissions: read-all`이 `contents: write`를 갖지 않는다.

---

## 2. 게이트 소스가 실제로 검사하는 규칙 요약 (제거 전 분석)

| 게이트 | 소스 | 검사 규칙 (ci.yml 대상) |
|---|---|---|
| ci_dag_contract_gate | `tools/ci_dag_contract_gate.nim` | (1) fileExists(ci.yml) — 파일 존재만, (2) jobs/needs edge 매칭 — **jobs=[]라 매칭 대상 0** |
| publication_scope_gate | `src/gate/runners/publication_scope_gate.nim` | (1) 등록 여부, (2) trigger set equality, (3) `contents: write` / `pull-requests: write` 등 permission 금지, (4) job_if_guard(ci.yml 규칙엔 선언 없음) |

ci.yml tombstone 내용(`.github/workflows/ci.yml` 8줄):

```yaml
name: ci-tombstone
on:
  workflow_dispatch:
permissions: read-all
jobs: {}
```

---

## 3. "소실되는 검사" 목록 산정 + 제거 후 대체 위치

| # | 제거 전 검사 (invariant) | 검사하는 게이트 | 삭제 후 이 검사는 어디서 대체/소멸되는가 |
|---|---|---|---|
| A | "ci.yml은 tombstones으로 `jobs: {}`를 가진다" | ci_dag_contract_gate (jobs=0 매칭) | **검사 대상 부재.** ci.yml 파일 자체가 삭제됨 — "존재하지 않는 파일이 tombstone인가"는 무의미해짐. freeze 기록은 git 역사 + `docs/ci/dag_semantic_redesign.md`(proofDoc)에 보존. |
| B | "ci.yml이 publication_scope.json에 등록되어 있다" | publication_scope_gate | **검사 대상 부재.** publication_scope.json에서 ci.yml 규칙 제거 → "등록되지 않은 워크플로" 자체가 소멸. 남은 4개 워크플로에 대한 동일 로직 검사는 그대로 유지 (5/5 → 4/4). |
| C | "ci.yml trigger set = {workflow_dispatch} (push/PR/schedule 금지)" | publication_scope_gate | **검사 대상 부재.** 파일 삭제로 트리거 존재 자체가 소멸. 이는 tombstone 정책(dispatch-only)의 결과물이며, policy는 git 역사 보존. |
| D | "ci.yml이 contents: write를 갖지 않는다" (permissions: read-all) | publication_scope_gate | **검사 대상 부재.** 파일 삭제로 대상 소멸. 단, **이 permission 정책은 canonical-main.yml/admission_producer.yml에도 동일 적용**되고 이들은 여전히 등록·검사됨 (contents_write=false in publication_scope.json). |
| E | admission invariant (requiredValidations) — ci.yml과 무관 | — (merge_admission) | **무관 확인.** `config/policy/merge_admission.json` requiredValidations 5건 **전부** workflowId 359582573 (admission_producer.yml) 바인딩. ci.yml 바인딩 0건. |
| F | trustSurface의 ci.yml 항목 — 파일 부재 시 매치 대상 없음 | merge_cli / merge_admission | **동작상 무해 (이번 slice에서 제거 안 함).** trustSurface는 "PR이 이 파일을 변경하면 auto-merge 거부"인데 파일이 존재하지 않으면 매치 대상이 없음. 제거는 별도 trust-surface cleanup slice 소관. |

> **소실 검사 0건**: A–D 모두 "이미 존재하지 않는 파일(ci.yml)에 대한 검사"였고,
> 파일 삭제로 검사 대상 자체가 소멸한다. E(admission)는 ci.yml 무관,
> F(trustSurface)는 무해 잔존. **살아 있는 admission invariant/execution authority
> 검사를 제거하는 항목은 0건.**

---

## 4. 제거 후 게이트 입력·결과 (기계 기록)

### 4.1 ci_dag_contract_gate

**게이트 자체 retire.** `config/ci_dag_contract.json`, `tools/ci_dag_contract_gate.nim`
삭제 + Makefile(`check-ci-dag-contract` 타깃, GATES_STATIC/PUSH_ADMISSIBILITY_GATES/
GATES_CI_VERIFYSTATIC 목록) + `.github/workflows/admission_producer.yml:136` step 제거.

검증:

```
$ test ! -f config/ci_dag_contract.json && test ! -f tools/ci_dag_contract_gate.nim && echo GONE
GONE
$ grep -c "ci-dag-contract" Makefile
0
```

### 4.2 publication_scope_gate

입력 — `config/publication_scope.json`: 4개 규칙 (ci.yml 규칙 제거).
`.github/workflows/ci.yml` 삭제.

실행 출력:

```
$ bin/publication_scope_gate
PASS: workflows=4, registered=4, triggers+permissions conform
exit=0
```

### 4.3 비교표

| 게이트 | 제거 전 입력 | 제거 전 결과 | 제거 후 입력 | 제거 후 결과 | 변화 |
|---|---|---|---|---|---|
| ci_dag_contract_gate | manifest(jobs=[], edges=[]) + ci.yml 존재 | PASS jobs=0, edges=0/0 | (게이트 retire) | — | 검사 invariant가 "존재하지 않는 파일이 tombstone인가"뿐이었음 (§3 A) |
| publication_scope_gate | 규칙 5건 (ci.yml 포함) + 5 workflow 파일 | PASS 5/5 | 규칙 4건 (ci.yml 규칙 제거) + 4 workflow 파일 | PASS 4/4 | ci.yml 규칙 소멸 (§3 B–D), 남은 4개 워크플로 검사는 동일 로직 |

---

## 5. 실행 topology 불변 증명

- **Makefile 게이트 목록**: `GATES_STATIC`에서 `check-ci-dag-contract`만 제거,
  나머지 게이트 전부 유지 (`check-arch`, `check-mcp`, `doc-path-validator`,
  `check-decision-binding`, `check-topology-drift`, `check-decision-graph-drift`,
  `check-publication-scope`, `check-manifest-consistency`, `check-cert-manifest-drift`,
  `check-cert-integrity`, `check-cert-integrity-fast`, `check-scope-consistency`).
  `PUSH_ADMISSIBILITY_GATES`에서 `check-ci-dag-contract`만 제거 (check-debt/
  check-nim-theater/doc-path-validator/check-determinism 유지).
- **admission_producer.yml verify-static job**: `make check-ci-dag-contract` step
  1개 제거 + 나머지 step 전부 무변 (mutation-harness → env-check → … → sloc-verify
  → git purity). 실행 순서·gate set 유지.
- **소비자 0건**: `workflow_run:` 소비자 0건, `uses: ./.github/workflows/` 0건,
  dispatch 호출 0건.

---

## 6. 관련 검증

```
$ bin/publication_scope_gate          # PASS: workflows=4, registered=4
$ test ! -f config/ci_dag_contract.json && test ! -f tools/ci_dag_contract_gate.nim   # GONE
$ grep -c "ci-dag-contract" Makefile  # 0
$ nim c -r tests/gate/test_publication_scope_gate.nim   # 0 failed
```

---

## 7. 실행 기록 (PR #127, 2026-09-18, merged)

- **PR**: <https://github.com/Archright/Axiom/pull/127> (MERGE commit `19037824690d00febc2dcdd4c7653fdf34a67313`)
- **admission run**: `35332273359` (head `43e2b9da8`) — **10 job 전부 success**.
  verify-static step에서 "Verify CI DAG contract" step이 실제로 제거된 것 확인 —
  변경 후 남은 23개 step(verify-static)이 전부 정상 실행 → **실행 topology 불변 실증**.
- **post-merge canonical-main run**: `35333958642` (push, head = merge commit)
  `landing` job **failure — `[bind]` L3b trust-surface fail-closed**:
  - L0/L1/L2/L3a×5 **전부 PASS** (verify-static/r1/r2-unit/r2-proof/check-readiness-start ←
    admission_producer.yml 359582573, conclusion=success)
  - L3b(trust-surface check)에서 exit 1 — `[continuity]`·`[accept]` **skipped**.
  - 원인: 본 PR이 `.github/workflows/admission_producer.yml`(trustSurface closure
    멤버, merge_admission.json v1.4.0)을 수정 → bind의 trust-surface predicate가
    fail-closed로 거부. **설계된 동작**(trustSurface 파일을 바꾸는 PR은 bind fail →
    manual merge 필요, ADR-0022). 게이트 RED·슬라이스 결함이 아님.
- **비교 선례**: S1 PR#126 merge(b92178fcd)는 trustSurface 파일을 건드리지 않아
  bind PASS → continuity **CC_NO_CERT fail-closed** → accept skipped. #127은
  trustSurface(admission_producer.yml)를 건드려 bind에서 fail-closed. 두 경우 모두
  **head cert 부재로 인한 설계된 fail-closed 경계**이며, 본 슬라이스가 소실시킨
  live invariant는 0건(§3).
