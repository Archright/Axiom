# AGENTS.md §2.8 — proposed clause, held back by the surface policy

**Status**: PROPOSED, not applied. `AGENTS.md` is a `FROZEN` path in
`config/repository_surface.json` (class entry `AGENTS.md`, `FROZEN.MODIFY = "FAIL"`), so a
pull request that edits it cannot pass `repository-surface`.

**Measured, not asserted.** `bin/surface_guard --policy config/repository_surface.json`
on the diff that included the AGENTS.md edit returned:

    "verdict": "FAIL", "reasonCode": "SURFACE_FORBIDDEN",
    violations: [{ "path": "AGENTS.md", "status": "M", "changeClass": "FROZEN",
                   "op": "MODIFY", "reasonCode": "SURFACE_FORBIDDEN" }]

The same guard on the docs-only change set returns `"verdict": "PASS"`. The
`selfAmendment.allowedPaths` exception cannot clear it (four paths, `AGENTS.md` is not one
of them) and `frozenExceptions` does not list it — the two lanes
[ADR-0050](../adr/0050-english-only-phase1-authority-records.md) §a.4 names are the same
two lanes that apply here.

**Why this file exists rather than the edit.** AGENTS.md §-1 declares the file immutable
without the human architect's explicit instruction, and the surface policy encodes that
declaration as a machine check. The instruction to write this contract is not by itself a
`frozenExceptions` carve-out, and quietly producing a red `SURFACE_FORBIDDEN` on a
reviewer's screen is indistinguishable from a real boundary violation. So the clause is
prepared here, complete and verbatim, and the docs contract
([venue_execution_contract.md](../spec/venue_execution_contract.md)) carries the normative
content in the meantime — it is outside the trust surface, the manifest, and the checker
closure.

## Two lanes for applying it

1. **Policy PR first, body PR second** — register `AGENTS.md` in
   `config/repository_surface.json` `frozenExceptions.paths` (base-policy binding means the
   carve-out must land before the body PR is judged), then apply the clause below verbatim.
   A `frozenExceptions` entry needs a `rationale` and `approvedBy`, which is the human
   architect's act.
2. **Operator-authorized break-glass landing** — the lane used for
   `docs/evidence/breakglass_trust_surface_landing_2026-11-20.md`, with the same
   consequences: the App's `admission-check` is `failure` at merge time and the merge is
   manual.

Neither lane is chosen here. This document only makes the clause ready for whichever one
the architect picks.

## The clause (verbatim, Korean — the language of AGENTS.md)

Place immediately after §2.7, before `## §3. 환경 (빌드 & 툴체인)`.

```markdown
### 2.8 merge venue 실행 계약 (HARD RULE)

required context가 **어느 commit에서 무엇을 보증하는가**는 venue별로 다르다. 이 절은 그 차이와 그 차이가 허용되는 조건을 고정한다.

- **venue는 required context의 skip으로 정해지지 않는다.** venue는 job 내부에서 `github.event_name`으로 판정한다(ADR-0032). required context를 발행하는 job과 admission leg는 모든 venue에서 실행되며, 그 job-level `if:`는 absent·`always()`·`!cancelled()`만 허용된다(R3, 기계 강제 — `docs/spec/ci_admission_budget_contract.md` §4).
- **skip된 job은 `Success`로 보고된다** — 조건으로 skip된 job은 required check라도 병합을 막지 않는다. 따라서 required context 안의 unit이 skip되면 그 green은 "실행되지 않았다"와 구별되지 않는다. skip은 **명명된 basis + 보상 증거**를 가져야 한다: (a) landing venue가 같은 unit을 실행하거나, (b) skipping venue에서 실행된 step이 skip된 대상의 명명된 속성을 단정하고 수행한 검사를 출력한다. 둘 다 없는 skip은 §0.9 극장이다.
- **PR-venue green은 착지 증거가 아니다.** 착지 자격의 정본은 merge_group venue의 `admission-check` 하나뿐이다(ADR-0032 (a),(f)). PR green을 착지 증거로 인용하는 것은 금지된다.
- **required context는 merge_group venue에서 skip될 수 없다** — 유일 예외는 `anchor-resolve`이며, aggregate가 event 조건과 함께 인라인으로 단정한다.
- **step-level `if:`는 기계 강제 대상이 아니다** — required job 내부의 step skip은 리뷰 강제이며, 계약 §3.2 등록이 유일한 강제다.
- **변경 권한**: trust surface 경로는 break-glass로만 착지하고(`docs/spec/break_glass_protocol.md`), `.github/workflows/admission-check.yml` blob 변경은 TWS/epoch 핀 원자 페어 회전이다. `(workflowPath, job id, context name)` 3중항이 불변이면 ruleset 재등록은 불필요하다 — context name은 job id이며 job-level `name:` 키로 바뀌지 않는다.
- **Acceptance**: required context의 unit을 한 venue에서만 실행하게 만드는 변경은 계약 §5의 4개 질문에 모두 답하고 같은 커밋에서 계약 §3.2를 갱신해야 수용된다. 답하지 못하는 변경 = silent pass = 거절.

계약: [docs/spec/venue_execution_contract.md](docs/spec/venue_execution_contract.md). 측정·감사: [docs/evidence/pr518_venue_execution_measurement_2026-11-27.md](docs/evidence/pr518_venue_execution_measurement_2026-11-27.md).
```

The clause is Fact / Invariant / Authority / Acceptance only; no numbers, no procedure, no
measurement. Every quantity it implies lives in the two linked documents (§5 SSOT).

## What the clause does not change

It adds no required context, no check, no verdict, no gate tool, and no build step. The
seven contexts of `config/policy/merge_admission.json` and ruleset `27097366` are
untouched by it and by the two documents it links.