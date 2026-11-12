# MG Evidence Gate Activation Canary — 2026-10-17

용도: org pin rotation(Archright/.github PR #228 — admission-check pin
`64f78ab7d178` → `338c54150b0e`) 이후 신세대 merge_group 증거 게이트의
활성화 실측을 위한 docs-only 카나리 PR이다. (Axiom PR #895 세대 전환,
callee blob `1c9848a74`.)

## 기대 관측치 (merge_group 실행 — 활성화 증거)

- `referenced_workflows`의 `admission-check.yml` sha = `338c54150b0e…`
  (정확히 `338c54150b0efdcab752734ddaadea12b9db41e8` — 활성화 시점 핀).
- venue=landing: 4 subject 전부 `basis=EXECUTED` — merge_group에서는
  판정재사용이 차단되므로(force-execution) 사유 문자열이 게이트 트리거를
  지목해야 한다(자연 MISS와 사유 문자열로 구별).
- subject 집합 동등성(set-equality): expected == observed 일치 라인.
- `basis=REUSED` = 0 (merge_group venue에서 재사용 없음).

## 기대 관측치 (pull_request 사전실행)

- `venue=preflight` — 변경 없는 subject에 대한 `basis=REUSED` 허용.
  신규 트리라 records 부재로 자연 MISS `EXECUTED`가 될 수도 있다 —
  어느 쪽이든 사유 문자열로 정직 기록한다. PR-venue 재사용 보존은
  유닛 계약 시나리오 (ii)가 이미 담당한다.
