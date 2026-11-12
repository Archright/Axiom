# ADR-0031: org 정책 미러를 만들지 않는다 — Axiom-특정 정책의 단일 SSOT

## Status

**Accepted (2026-10-07)** — 아키텍처 결정 기록. 코드·워크플로 변경을 수반하지 않는다.
이 ADR이 하는 일은 부재의 선언이다: `Archright/.github` 트리에 Axiom 정책 파일의
사본(mirror)을 두는 대안을 **의도적으로 채택하지 않았음**을 기록한다.

## Context

`Archright/.github`의 `landing-integrity.yml`는 3체크 — `trust-surface-codeowners`,
`trusted-writer-set-pairing`, `merge-admission-sanity` — 로 타깃 저장소 트리의
Axiom 정책 파일(`config/policy/merge_admission.json`,
`config/trusted_writer_set.json`, `.github/CODEOWNERS`)을 검증한다. 워크플로
정의는 org 저장소가 공급하고(org-level `workflows` ruleset), 타깃 저장소의 PR에서
실행된다. 같은 정의가 org 저장소 자체의 PR에서도 발화한다.

두 환경에서 이 3체크의 운명은 구조적으로 갈린다.

- **타깃 저장소(Axiom)의 PR**: 3 입력이 트리에 존재하므로 3체크는 실제로
  작동한다. 실측(2026-10-07): PR #549·#552 head commit에서 3체크 전부 `success`.
- **org 저장소(`Archright/.github`) 자체의 PR**: 위 입력들이 **구조적으로 존재할
  수 없다** — org 트리는 workflows 2개(`admission-gate.yml`,
  `landing-integrity.yml`)와 profile뿐이다. 입력 부재는 fail-closed FAIL이므로
  org PR은 **상시 red**였다. 실측: PR #63 시대의 3체크 전부 `failure`
  (#57–#63이 이 상시 red 아래에서 착지된 선례다 — org 저장소에는 required
  checks가 없어 착지 자체는 가능했다).

PR #67(2026-10-07 merge)이 이 상태를 정직하게 전환했다: org 자기 트리 한정
(`github.repository == 'Archright/.github'`)으로 job-level `if:` 스킵을 도입해,
입력 부재를 baseless 항상-red FAIL이 아니라 **정직한 Skipped**(잡 표시명에 사유
"Skipped — mirror inputs absent" 명기)로 만들었다. 잡 이름만 바뀌고 check-run
id는 유지되며, job-level `if:`가 단일 게이트다 — 입력이 존재하는데 무효한 경로는
어디에도 만들지 않았고, 기존의 모든 FAIL 경로는 그대로 도달 가능하다.

이 전환 이후 남은 대안이 하나 있었다: org PR에서도 3체크가 "의미 있게" 도도록
정책 파일의 사본을 org 트리에 복제(mirror)하는 것.

## Decision

**미러를 만들지 않는다.**

- **Axiom 저장소 = Axiom-특정 정책의 유일 SSOT.** `config/policy/merge_admission.json`,
  `config/trusted_writer_set.json`, `.github/CODEOWNERS`의 권위는 Axiom 트리에만
  존재한다.
- **`Archright/.github` = 오케스트레이션·핀·범용 enforcement 전용.** workflow
  정의 공급과 핀 회전이 임무의 전부이며, 정책의 내용을 소유하지 않는다.
- **정책 사본의 이중 유지(synchronization handoff)를 의도적으로 허용하지
  않는다.** org 트리에 사본이 생기는 순간 "Axiom 트리의 정책"과 "org 트리의
  사본"이 어긋나는 상태가 가능해지고, 미러를 읽은 판정은 어느 쪽이 권위인지 다시
  묻게 된다. 이는 Dependabot 자동화로 제거한 **stale-pin 문제의 변형**이므로
  설계 후퇴다 — 조용히 늙어가는 사본을 다시 도입하는 것과 같은 종류의 결함이다.

## Consequences

- **org PR은 Axiom-특정 정책을 검증하지 않는다** — 정직한 Skipped(PR #67). 이는
  강제의 약화가 아니라, 권위가 그 트리에 없음을 정직하게 표기한 것이다.
- **타깃 저장소(Axiom)의 PR에서 3체크는 계속 fail-closed로 작동한다** — 입력
  부재 = FAIL 유지(실측된 워크플로 헤더 계약). 미러 부재로 타깃 쪽 강제가
  약해지는 것은 없다.
- **SSOT 원칙 보존** — 중복 의미 상태 금지(AGENTS.md §0.11·§1)를 정책 평면에서
  유지한다. 미러 생성은 곧 중복 의미 상태의 발생이다.
- **재검토 조건**: 향후 org PR에 정책 검증이 실제로 필요해지면 "미러 추가"가
  아니라 **"검증을 SSOT에서 읽는 방식"**(예: 판정 시점에 Axiom main에서 정책을
  fetch해 사용)으로 재검토한다.

## References

- 라이브 ruleset 실측(2026-10-07): Axiom(`Archright/Axiom`)의 required check는
  `admission-check` 단일(ruleset "main", enforcement active, 그 외 ruleset은
  required checks 없음); `Archright/.github`는 ruleset 0건.
- 3체크 실측: Axiom PR #549·#552 head에서 전부 `success`; org PR #63(상시 red
  시대)에서 전부 `failure`.
- `Archright/.github` 트리 실측: 루트 = `.github` + `profile`, workflows =
  `admission-gate.yml`, `landing-integrity.yml` 2개.
- `Archright/.github`의 `landing-integrity.yml` 헤더 — 타깃 저장소 fail-closed
  스크립트 + org 자기 트리 job-level skip(정직한 Skipped) 명시.
- org PR #67 (2026-10-07T10:46:30Z merge) — 정직한 Skipped 전환 도입.
- AGENTS.md §0.11(SSOT/어휘 권위)·§1(중복 의미 상태 금지).
