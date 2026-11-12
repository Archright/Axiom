# S2 로컬/CI 패리티 기계장치 (Local/CI Parity Machinery)

> **실험**: 실험 가속화 — 로컬과 CI에서의 선택(Selection) 결과 동일성 보장
> **작성일**: 2026-09-05
> **관련 문서**: `docs/spec/canonical_execution_semantics.md` (S2 매핑: §5, §7)

---

## 4단계 패리티 프로토콜 (4-Step Parity Protocol)

S2 관문은 로컬과 CI가 **동일한 semantic 입력**에 대해 동일한 선택 결과를 산출하는지를 4단계로 검증합니다.

| 단계 | 검증 대상 | 설명 |
|---|---|---|
| **①** | `semanticInputIdentity` | 변경 집합 다이제스트, 그래프 다이제스트, 유니버스 다이제스트, 정책 다이제스트가 byte-equal |
| **②** | `selection.derivationDigest` / `status` | 선택 도출 증명서와 상태가 동일 |
| **③** | `plan.planDigest` | 실행 계획 다이제스트가 동일 |
| **④** | 실행 결과 동일성 | 선택된 unit의 실행 결과가 동일 (S4 투영 골든 게이트에서 검증) |

**핵심 원칙**: 다이제스트 값은 오직 **semantic 입력**의 순수 함수여야 합니다. 절대 경로, 호스트명, 타임스탬프, PID 등 부수적(incidental) 상태가 다이제스트에 포함되면 안 됩니다 (DEBT#417 선례).

---

## 로컬 실행 명령

```bash
# 1. symbols-file 생성 (선택적 — 토폴로지 스캔이 너무 무거한 경우 필수)
#    JSON 스키마:
#    {
#      "symbolDeps":        { "symA": ["symB"], ... },
#      "symbolDependents":  { "symB": ["symA"], ... },
#      "fileSymbols":       { "src/core/foo.nim": ["src/core/foo.nim::bar"], ... }
#    }

# 2. 로컬에서 선택 보고서 생성
nim c -r --path:src --path:tools tools/selection_report.nim \
  --base HEAD~1 --head HEAD --symbols-file fixtures/symbols.json \
  --output docs/reports/selection_report_local.json

# 3. CI에서 동일 명령 실행 (동일 base/head + 동일 symbols-file)
#    (CI 스크립트는 동일한 명령을 실행합니다)

# 4. 두 보고서 비교
nim c -r --path:src --path:tools tools/selection_digest_compare.nim \
  docs/reports/selection_report_local.json \
  docs/reports/selection_report_ci.json
```

---

## CI 실행 명령

CI에서 실행할 때는 **동일한 base/head 조합**과 **동일한 symbols-file**을 사용해야 합니다:

```bash
selection-report --base $BASE_REF --head $HEAD_REF \
  --symbols-file $SYMBOLS_FILE_PATH \
  --output docs/reports/selection_report_ci.json
```

`$SYMBOLS_FILE_PATH`는 동일 커밋에서 생성된 symbols-file이어야 합니다.

---

## ④번 게이트: 실행 결과 동일성

**④번 게이트 (실행 결과 동일성)**는 이 도구가 직접 검증하지 않습니다.

이유:
- 실행 결과는 선택된 unit을 실행해야만 확인 가능합니다
- 로컬과 CI에서 실행 환경이 다를 수 있습니다 (타임아웃, 리소스 제약 등)
- 실행 결과의 동일성은 **S4 투영 골든 게이트** (`Project(FullResult, Selected) == PrunedResult`)에서 검증합니다

도구는 ①–③번 게이트만 검증하고, ④번은 `"deferred-until-execution"`으로 기록합니다.

---

## CI-side Enforcement 주의사항

CI-side enforcement는 **S5 인프라 트랙 승인**이 필요합니다.

`.github/workflows/ci.yml`은 `§-1` 불변 파일이므로, S2 관문의 CI 자동화는 S5 인프라 트랙 승인 후에만 CI.yml에 게이트를 추가할 수 있습니다.

현재 이 문서에 기술된 도구들은 **로컬 검증용**이며, CI 통합은 S5 승인을 기다립니다.

---

## Exit Code 계약

| Exit Code | 의미 | 대응 |
|---|---|---|
| 0 | `planStatus` = VALID (`ssValid`) | V1 영향받은 검증 인증 허용 |
| 2 | `planStatus` = FALLBACK_REQUIRED (`ssFallbackRequired`) | V2 전체 인증 필요 |
| 1 | 오류 (인자, I/O, 내부 오류) | CI 실패 처리 |

이 계약은 `tools/ci/impact_closure_selector.nim`의 exit 계약과 동일합니다.
