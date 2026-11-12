# MG Evidence Gate Activation Canary 2 — 2026-10-17

용도: **§4.3 사후 ruleset 재핀 의무 수행 직후**의 신세대(caller `2c81072d4a`)
merge_group 활성화 실측을 위한 docs-only 카나리 PR이다. 카나리 1(#897)은
org ruleset이 구(舊) 컨트롤러 HEAD(`29094836bc`)에 머물러 있어 구 caller +
구 callee(`64f78ab7d`)로 실행된 — 재핀 없이 남은 불완전 cutover의 직접
관측이었다. 본 카나리 2는 재핀 완료 후 **새 caller가 실제로 큐 실행에
편입되는가**를 증명한다.

## 재핀 의식 기록 (§4.3 — admission-generation.md)

- 드레인 관측: 2026-10-17T04:53:30Z — merge_group in_progress/queued 0건,
  auto-merge 무장 PR 0건.
- PUT 순서(하나의 논리 단위): org ruleset **25218071**(axiom-admission-gate)
  @ 2026-10-17T04:54:45.233Z → **23943917**(landing-integrity)
  @ 2026-10-17T04:54:46.053Z (간격 3ms).
- 재핀 값: workflows 규칙 `sha` `29094836bc4488280d98c22665470dcb2e54da1a`
  → `2c81072d4a68d701bde15a212db91aab1ae4cc5d` (컨트롤러 HEAD, PR #228
  머지 커밋).
- readback: 양 ruleset에서 정책 필드는 `sha` 단 하나만 변경 —
  enforcement·conditions·rules·bypass_actors 바이트 동일 (server 관리
  `updated_at` 제외).

## 기대 관측치 (merge_group 실행 — 활성화 증거)

- `referenced_workflows`의 `admission-check.yml` sha =
  `338c54150b0efdcab752734ddaadea12b9db41e8` — 재핀된 caller
  (`admission-gate-v2.yml@2c81072d4a`) 내부의 callee 핀. 구 caller 세대의
  `64f78ab7d…`가 관측되면 재핀 활성화 실패다.
- `[venue] venue=landing` — merge_group 이벤트.
- 4 subject 전부 `basis=EXECUTED` — merge_group venue에서는 판정재사용이
  차단되므로 force-execution 사유 문자열이 게이트 트리거를 지목해야 한다.
- 신세대 set-equality 출력: `[check] judgment subject set == SSOT: …(N
  subjects)` (불일치 시 `[check] FAIL-CLOSED: judgment decision subject
  set != SSOT — missing:[…] extra:[…]`).
- `basis=REUSED` = 0 (merge_group venue에서 재사용 없음).

## 기대 관측치 (pull_request 사전실행)

- `[venue] venue=preflight` — docs-only 변경, static-only 사전실행.
