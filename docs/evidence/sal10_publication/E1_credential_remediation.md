# E1 — Credential Remediation Closure Report (VS-A)

**판정**: `CREDENTIALS_RECOVERED` — **폐기 4종·교체 0종** (2026-11-05)

> **마스킹 원칙**: 본 문서는 실값을 포함하지 않는다. 값 식별은 값1~값4 라벨과 발급기관·형식·위치로만 한다. 실값 목록은 사용자 전용 핸드오프(로컬 사적 보관·공개 저장소 반입 금지)로 관리한다. 검증 스크립트(`vs_a_recover.sh`·`vs_a_probe_ctx7.sh`)도 핸드오프 경로를 인자로 포함하므로 로컬 사적 보관이며, 본 문서에는 출력(PASS/FAIL·HTTP 상태 코드)만 기록한다.

## 1. 배경 — 이력 노출 4종 (B2 §(a) 정본)

B2 gitleaks 전체 이력 스캔(2026-11-05·12,067 커밋·findings 4,882)에서 실자격증형 14건·고유 값 4종 확정 — 현재 tip 잔존 0건(전부 과거 커밋):

| 값 | 발급기관·형식 | 이력 캐리어 | 노출 시기 |
|---|---|---|---|
| 값1 | Context7 API 키(43자·`ctx7sk-` 접두) | `src/gate/runners/context7_evidence_gate{,_shadow}.nim` 상수 + `docs/evidence/context7/registry.md`(계 16커밋) | 2026-06-09~07-11 |
| 값2 | Mistral API 키(32자) | `axiom.toml:36`(3커밋) — 유일 live 설치 `~/.leanstral_api_key` | 2026-06-08 |
| 값3 | Mistral API 키 | `axiom.toml:40`(2커밋) | 2026-06-09 |
| 값4 | Mistral API 키 | `axiom.toml:34`(2커밋) | 2026-06-16 |

값1은 게이트 파일 은퇴 커밋로, 값2~4는 `api_key = "${AXIOM_API_KEY}"` 환경변수화("credential hygiene" 커밋)로 각각 tip에서 제거됐다.

## 2. 발급기관 폐기 완결 4/4

VS-A의 Trust Fact는 발급기관의 무효화다(§2.4 — Git·로컬 삭제는 그 자체로 폐기가 아니다). 확인 방법과 기계 증거:

| 값 | 발급기관 폐기 확인(2026-11-05) | 기계 증거 |
|---|---|---|
| 값1 | 사용자 대시보드 확인 — 2026-06~07 생성 키 부재(과거 삭제) | **차등 프로브 `REVOKED_CONFIRMED`** — 값1 응답 401(§2.1) |
| 값2 | 사용자 Mistral 콘솔 삭제 확인 | 로컬 purge — `~/.leanstral_api_key` 삭제(삭제 전 기록: 권한 600·33B·2026-07-28) |
| 값3 | 사용자 Mistral 콘솔 삭제 확인 | 이력 노출만(원래 live 사용 0 — agent-134 매핑) |
| 값4 | 사용자 Mistral 콘솔 삭제 확인 | 이력 노출만(원래 live 사용 0 — agent-134 매핑) |

### 2.1. 값1 차등 프로브 (2026-11-05·exit 0)

엔드포인트 `https://context7.com/api/v2/search`(현행 키 로테이션 래퍼와 동일 엔드포인트·헤더 3종). 키는 stdin 파이프로만 전달되며 출력은 HTTP 상태 코드·판정 문구뿐이다(값 미노출):

```
NEGATIVE_CONTROL_HTTP=401
CURRENT_KEY[0]_HTTP=429
CURRENT_KEY[1]_HTTP=200
CURRENT_KEY[2]_HTTP=200
CURRENT_KEY[3]_HTTP=200
OLD_VALUE1_HTTP=401
VERDICT: REVOKED_CONFIRMED
```

- **음성 대조**(형식만 맞춘 가짜 키): 401 — 엔드포인트가 인증을 강제함을 증명
- **양성 대조**(현행 키 4종): 429×1·200×3 — 엔드포인트·현행 키 정상(429는 유효-키-스로틀 응답으로, 가짜 키가 401을 받는 배치에서 401이 아닌 응답은 인증 통과의 증거)
- **검증 대상 값1**: **401** — 가짜 키와 동일한 인증 계층 거부 = 발급기관에서 무효 상태 확정

**현행 도구 무영향**: kimi-code 현행 Context7 키 4종(`~/.kimi-code/context7-keys.json`)은 값1과 전부 MISMATCH(값을 출력하지 않는 메모리 비교 실측) — 값1 폐기가 현재 MCP 도구 체인에 영향을 주지 않는다.

## 3. 로컬 표면 증명 (기계 검증·2026-11-05)

`vs_a_recover.sh check` — 핸드오프의 노출 후보 토큰이 live 표면(키 파일·환경 변수 전체·`axiom.toml`·`.envrc`·`.env.example`)에 잔존하는지 검사. 출력은 라벨·PASS/FAIL·위치명·카운트만:

```
값1: PASS — live 표면 미발견
값2: PASS — live 표면 미발견
값3: PASS — live 표면 미발견
값4: PASS — live 표면 미발견
통계: 섹션 4개, 후보 토큰 6개
RESULT: PASS
```

(exit 0. 기준선: 로컬 purge 전 `값2: FAIL — KEY_FILE(ROTATION_PENDING)`·`RESULT: FAIL` → purge 후 `RESULT: PASS` — 상태 전이가 기계 관측됨. GitHub Secrets 배포는 0건 — agent-134 사용처 매핑: 값2만 live였고 값1·3·4 현 사용 0.)

## 4. 교체 0종 — LLM 백엔드 비활성 (Mistral legacy)

사용자 결정(2026-11-05): Mistral은 더 이상 사용하지 않는 legacy — purge. 따라서:

- **교체(re-issue) 0종** — 신규 자격증명이 등장하지 않는다(노출 면적 증가 없음·rotate 미사용)
- **LLM 백엔드 비활성·`by simp` 결정론 폴백 운영** — 폐기 전부터 엔드포인트 DNS 사망으로 실효 네트워크 사용 0이었으므로 기존 실효 상태와 동일
- `AXIOM_LLM_API_KEY` 유일 유효 소비 경로 — 키 파일 부재 시 `NEED_API_KEY` 플레이스홀더로 안전 열화(breakage 없음·토큰 아님)
- `.envrc` LLM 블록 제거는 Gate 3 PR에서 실행(스테이징 대기 — 본 PR 범위 아님)

## 5. 잔여 (E1 종결 후 추적 — Gate 2·Gate 4 입력)

E1의 종결 범위는 "발급기관 폐기 + 로컬 표면 증명"이다. 이력 청소는 cutover(E2) 범위로 남는다:

1. **Git 이력 침소 대기**: cutover `--replace-text`가 4종 실값을 침소(파일 존치·값만 소멸 — B2 §5.2). 실행 전까지 과거 커밋에 값이 존재하나 폐기 완결로 유효성은 0 — 침소는 이력 위생(공개 표면 확정)
2. **침소 후 gitleaks 재스캔**: 자격증명형 findings 0 확인(B2 §5.3) — Gate 4 필수 항목
3. **핸드오프 PRIVATE 문서 폐기**: **cutover 완료 후에만** 폐기 — 침소 치환 파일 생성이 4종 실값을 필요로 하므로 지금 폐기 금지
4. **CircleCI `axiom-leanstral` context**: 사용자 확인 잔여(flip 전제 — context 내 자격증명 부재 확인·제거·미사용 확인 중 택일로 종결)

## 6. 검증 명령

- 로컬 표면: `bash vs_a_recover.sh check` → `RESULT: PASS`(exit 0) — 스크립트·핸드오프는 로컬 사적 보관
- 값1 폐기: `bash vs_a_probe_ctx7.sh` → `VERDICT: REVOKED_CONFIRMED`(exit 0)
- 이력 노출 위치 재확인: B2 §6(마스킹 정본)
