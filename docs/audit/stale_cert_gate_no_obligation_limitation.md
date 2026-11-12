# Ops 기록 — stale_cert_gate의 NO_OBLIGATION 전환 한계

> 날짜: 2026-09-05 · 관련: DEBT#446 (stale_cert_gate sourceHash-only 한계, OPEN) · 업그레이드 경로: DEBT#437 (지연) · 관측: W6 커밋 과정에서 실측

## 1. 관측된 동작

1. 소스 변경(예: `topology_dependency.nim`의 unresolved-edge 보존 수정)으로 해당 심볼의 인증서(sourceHash)가 stale 판정.
2. `bin/ax vkd sync` 실행 → **자동 정리 안 됨** (출력: 자동 재빌드 1줄뿐).
3. `bin/ax prove --target <symbol>` 재검증 → **NO_OBLIGATION** (현재 verifier가 해당 심볼에 더 이상 증명 의무를 산출하지 않음).
4. NO_OBLIGATION 심볼은 **새 인증서를 산출하지 않으므로** `ax cert reconcile --apply`(fresh reference 필요)의 대상이 아님.
5. 남은 유일한 경로 = **수동 볼트 정리**: `src/verification/certificates/<irHash>.json` 파일 제거 + `manifest.json`의 해당 entries 항목 제거 (둘을 함께 제거해 정합 유지).

## 2. 근본 원인

`stale_cert_gate`(`tools/stale_cert_gate.nim`)는 인증서의 `sourceHash`와 staged 소스 지문만 비교한다. 인증서가 **더 이상 유효하지 않은 종류**(심볼이 NO_OBLIGATION으로 전환)일 때, gate가 안내하는 두 가지 복구 경로(fresh cert 존재 시 reconcile, 미존재 시 `ax prove --target`) 모두 새 인증서를 만들 수 없는 경우를 다루지 못한다. DEBT#446의 sourceHash-only 한계의 구체적 표현.

## 3. 반복 절차 (재발 시)

```bash
# 1) stale 심볼 확인
bash .githooks/pre-commit   # STALE: <path>::<fn> 출력
# 2) NO_OBLIGATION 여부 확인
bin/ax prove --target <path>::<fn>   # [NO_OBLIGATION] 확인
# 3) obsolete 인증서 정리 (볼트 + manifest 동시)
grep -rln "<fn>" src/verification/certificates/*.json   # 대상 파일
#  - 해당 .json 삭제 + manifest.json의 entries에서 modulePath+functionName 일치 항목 제거
# 4) git add + pre-commit 재실행
```

## 4. 권고

- DEBT#437(derived artifact 동기화) 업그레이드 시, NO_OBLIGATION 전환 심볼의 인증서 자동 폐기를 포함해야 한다.
- 그 전까지 위 수동 절차가 유일한 복구 경로임을 이 기록으로 남긴다.