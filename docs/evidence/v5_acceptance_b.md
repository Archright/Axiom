# v5 acceptance B — 동일 closure 재사용 관측 차량

N-제외 `.md` 단독 변경 → 판정 closure는 PR #1014(acceptance A)가 발화한 v5 기록(`evidenceKey=148a4fac53d5…`)과 동일.
기대: plan이 5조건(per-read re-hash 포함)을 통과해 `basis=REUSED`·`decision=REUSED`·`verdict=UNKNOWN`으로 승인,
s1a 테스트 skip, EXECUTED 대비 착지 시간 단축, MERGED. `verdict=UNKNOWN`은 실행 결과가 아니다(재인증 승인 근거).
