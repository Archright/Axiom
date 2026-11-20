# Rotation allowlist 사전등록 — 생성 데이터 산출물 1경로 (ADR-0025 Amendment A6)

- 작성일: 2026-11-19
- 작성자: agent (wintrover의 대리 실행자)
- 결정: ADR-0025 Amendment A6 (A2 회전 동반 집합 유한 확장)
- 코드: `src/cli/merge_cli.nim` `RotationAllowlistExtra` +2경로
- 상태: 사전등록 — 본 PR 착지 전 계측 완료, 착지 후 사후 관측으로 닫는다

## 1. 실측 — 차단은 1경로였다

PR #191(DEBT#118 loss-marking 회전, head `ccf4fab`)의 merge-group verdict는
`reasonCode=ROT_ALLOWLIST`로 NOT-ADMIT였다. verdict JSON `rotationCheck`:

```json
{"closureChange":true,
 "changed":["config/trusted_checker_closure.json","data/architecture_debt.json",
            "src/core/trusted/ast_to_ir.nim","src/generated/type_registry_metadata.json",
            "src/infrastructure/external_ir_materializer.nim"],
 "allowlistOk":false,"subjectDeltaZero":false,"genesis":false,
 "oldAnchorOk":true,"newAnchorOk":true,"delegatedToPlatform":true}
```

`rotationAllowlistOk`(src/cli/merge_cli.nim:839-855) 판정 결과:

| changed 경로 | 판정 근거 | 결과 |
|---|---|---|
| `config/trusted_checker_closure.json` | `RotationClosurePath` | IN |
| `data/architecture_debt.json` | `RotationAllowlistExtra` | IN |
| `src/core/trusted/ast_to_ir.nim` | pin@B 키 | IN |
| `src/infrastructure/external_ir_materializer.nim` | pin@B 키 | IN |
| `src/generated/type_registry_metadata.json` | 어디에도 없음 | **OUT** |

즉 차단 원인은 생성 파일 1개다. 나머지 4경로는 이미 허용 집합 안이므로
allowlist 확장은 "회전의 필수 동반 1경로"에 한정된다.

## 2. 파일 사실 (기계 검증 가능)

- 이 파일은 **컴파일 대상이 아니다** — Nim 소스가 아닌 JSON 데이터이며
  `src/core/encoding/type_logic_registry.nim:3`이 런타임에 로드한다.
- **SSOT writer**: `tools/hermetic_build.nim:751`("Generate and write
  type_registry_metadata.json (idempotent)"), `:1281` 생성 로그, `:1284`
  "unchanged (idempotent)". 빌드가 재생성하는 산출물이며 수기 편집 대상이 아니다
  (`docs/guides/axiom_gate_commit_staging_contract.md:20,77` — 보호 대상 생성 파일).
- **산출물 계약**: `docs/spec/artifact_determinism.md:123` — `bin/sync_topology`
  산출물, 결정론 요구.
- **필연 동반**: PR #191 diff는 이 파일에 44줄만 추가한다 — 신규 심볼
  `checkedBinOp`(ast_to_ir.nim), `containsUnsupportedBinOp`/
  `lossFreeTranslationContradictsBody`(external_ir_materializer.nim)의 생성 항목.
  회전 대상 코드가 심볼을 추가하면 이 파일의 항목 추가가 필연이다.
- **closure 비멤버**: `config/trusted_checker_closure.json` 890 멤버 중 0건
  (실측 `grep -c`). 본 개정은 이 사실을 변경하지 않는다.

## 3. 판정 — 기존 개정 경로(A2 (iii))와 동일 fix class

- A2 (iii): "다른 companion path 추가는 향후 회전 실측 시 동일한 개정 경로
  (본 amendment 스타일)로만 한다." — 본 문서 + ADR Amendment A6이 그 경로다.
- A2 (i)의 의도는 "손으로 쓰는 production 코드의 회전 편승 금지"다. 이 파일은
  빌드 재생성 데이터 산출물이므로 그 의도 대상이 아니다(Amendment A6 §1).
- A4 규율: **열거형만, glob 없음** — `src/generated/**` 접두 확장은 없다.
- A2 (ii): ① allowlist는 ROTATION 경로에서만 평가된다. **NORMAL 경로의 이
  파일 취급은 불변**이며, 본 등재는 회전 승인 범위만 최소 확장한다.

## 4. 비확장 증명 (기대 관측)

| 관측 | 기대 |
|---|---|
| `rotationAllowlistOk("src/generated/type_registry_metadata.json", pinB)` | true (등재) |
| `rotationAllowlistOk("src/generated/other.json", pinB)` | false (glob 아님) |
| `rotationAllowlistOk("src/regular_change.nim", pinB)` | false (A2 (i) 유지) |
| NORMAL PR(closureChange=false)에서 이 파일 변경 | ① vacuous-true — 종전과 동일 |
| 테스트 | `tests/cli/test_merge_cli.nim` allowlist 케이스 전건 유지 |

회귀 테스트는 기존 케이스(`rotationAllowlistOk: A2 amendment rotation-companion
paths allowed`, `:1347-1357`)가 `RotationAllowlistExtra` 전건을 순회하므로
신규 2경로를 자동 포함한다 — 코드 변경과 동일 착지 단위에서 검증된다.

## 5. 잔여 사실 (본 개정 범위 밖 — 후속 판정)

이 파일이 closure 멤버가 아니라는 사실은 별도 신뢰 경계 판정 대상이다:
(1) NORMAL 경로에서 이 파일 변경의 허용 여부, (2) 증명 런타임 입력으로서의
권위. 본 개정은 "회전이 이 파일을 동반할 수 있다"만 승인하며, 위 판정을
선취하지 않는다. 후속 슬라이스에서 다룬다.

## 6. MUST-T2a 위임 기록 (merge 명령 전 기입)

- 대상 PR: `#192` (fix(admission): allow the generated type-registry metadata companion in rotation)
- 위임 원문(사용자): "권한이 필요한 부분은 전면 승인한다" (2026-11-19, 이 세션)
- 실행 명령: `gh pr merge 192 --merge` (1회, `--auto` 금지 — MUST-T1)
- 실행자: agent under explicit per-PR delegation from wintrover (기록자 ≠ 승인자)
- 착지 경로: `TRUST_SURFACE_MODIFIED` → dryRunExit 0 → 수동 병합 1회
  (MUST-T2 / MUST-T2a (3) manual lane only)