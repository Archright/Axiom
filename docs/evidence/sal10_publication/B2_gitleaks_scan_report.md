# B2 — Full Git History Secret Scan Report (gitleaks, Gate 2-E1)

**스캔 일시**: 2026-11-05. **도구**: gitleaks 8.30.1(공식 release tarball, 기본 룰셋 유지). **커버**: `--log-opts="--all"` — 전체 714 ref(브랜치 623 = heads 424 + remotes, 태그 89). `git fetch --tags origin` 선행(rev-list 13,572→13,595(+23), main `73e1a792e→201ac6c54` 전진, 로컬 체크아웃·working tree 불변 0 변경). 스캔 규모 12,067 커밋·498.61MB·27.8초. **종료 코드 1(발견 있음)** — findings **4,882**(generic-api-key 4,875·jwt 7).

> **본 문서는 마스킹 요약본** — 실자격증명 실값은 포함하지 않는다. 원본 리포트(실값 포함, 8.5MB)는 로컬 사적 보관이며 **공개 저장소 반입 금지**. 실값 확인·폐기용 목록은 사용자 전용 핸드오프로 별도 관리한다.

## 1. Materiality 분류

### (a) 실제 자격증명형 — 14건, 고유 값 4종 (이력 노출 후 제거 — 전체 ref tip 잔존 0건)

**Context7 API 키(43자, `ctx7sk-` 접두)** — `src/gate/runners/context7_evidence_gate{,_shadow}.nim` 상수, 2026-06-09~07-11, 7건:

| 파일 | 라인 | 커밋 |
|---|---|---|
| src/gate/runners/context7_evidence_gate.nim | 27 | `1acf4cb1`·`c10e85ea`·`f54d7ace` |
| src/gate/runners/context7_evidence_gate.nim | 33 | `2fa61b00`·`5d7adc81` |
| src/gate/runners/context7_evidence_gate_shadow.nim | 25 | `ec573258`·`ae26063e` |

제거 경위: Context7 증거 체계 은퇴 커밋(`93378947a`·`b9f2175ae`)으로 게이트 파일 자체 삭제. **동일 키가 `docs/evidence/context7/registry.md` 이력에도 존재(gitleaks 미탐 — 전체 이력 git grep으로 확인: 게이트 2종 + registry.md 정확히 3개 파일, registry.md는 전체 43자 리터럴 9커밋)**.

**Mistral형 32자 api_key 3종** — `axiom.toml` `[leanstral]` 섹션(키 로테이션 흔적), 7건:

| 라인 | 커밋 | 시기 |
|---|---|---|
| 36 | `06ae18ba`·`7f387e61`·`bbe257a8` | 2026-06-08 |
| 40 | `254c2249`·`3c4d7b9b` | 2026-06-09 |
| 34 | `7b831185`·`cc207641` | 2026-06-16 |

제거 경위: "credential hygiene" 커밋(`5d7adc81`·`2fa61b008`)에서 `api_key = "${AXIOM_API_KEY}"` 환경변수화.

**위치 분포**: 6건 origin/main 도달 커밋, 8건 과거 workstream ref 전용. **현재 tip 잔존 0건.** 유효성(폐기 여부) 미검증 → **Remediation 최우선: 4종 폐기·재발급(사용자 실행)** + cutover `--replace-text` 침소 편입(파일 존치·값만 소멸).

### (b) 합성·테스트 픽스처·생성데이터(비자격증) — 4,851건 (99.7%)

- 3,477건 — hex64/40/32 해시: `evidenceKey`·CAS 루트 파일(파일명=내용 해시)·content hash(루트 3,017: data/e4e5/ledger.json 325·bidentity_verbatim.json 225 등)
- 1,037건 — `axiom-b-<sha1>-<hex>` CI 캐시 키(data/ci_cost 로그·reads)
- 272건 — experiments 레이블/lexer 토큰명(`inVerifiedFragmentV1`·`scanUint__test95…`)·stderr 로그
- 30건 — data 생성물(readiness camelCase 레이블 등)
- 28건 — tests 합성 키: `token = "sk-1234567890abcdef"`(tests/gateway*)·`key = "verify_key_abc123def456ghi"`·`AXIOM_GATE_BYPASS_TOKEN = "test-bypass-mcp-123"`·`actionKey: "abcdef1234567890"`
- 7건 — JWT 골든 픽스처: `data/golden/admission_landing/jwt.{good,expired,tampered,aud-mismatch,kid-unknown,other-workflow,workflow-sha-mismatch}.txt`(커밋 `c2bc90b1`, kid=`axiom-admission-test-01` — 합성 확정, main tip 현존 테스트 토큰)

**probe/s3 판정**: probe|s3 이름 ref 50개 존재하나 findings 중 probe/s3 전용(비공유 이력) 커밋 **0건** — findings 커밋 35/3,085가 probe/s3 ref에 속하나 전부 다른 정상 ref에서도 도달 가능한 공유 이력. 합성 주입(probe/s3 4요건)이 스캔 결과에 배타적으로 나타나지 않음.

### (c) 우발 노출 후보 — 17건, 전건 식별자/레이블 오탐 (자격증명값 아님)

- 4건 `config/readiness_policy.json` — "z3VsDualDistinguishable"(정책 레이블, `c0bc7090`/`8538db89`/`e7201990`/`6c05ff6d`)
- 4건 `src/gate/runners/language_ban_gate.nim:163/166/209/212` — `AXIOM_BYPASS_REASON`(환경변수명, `1f3b58a2`·`8ee94b6f`)
- 4건 `.nimcache_test_daemon/@ptimes.nim.c` — Nim 컴파일 캐시 난독화 식별자(`a06a210d`·`bbffd724`)
- 2건 `src/core/schema/git_schema.nim:467` — "new-api"/"hotfix/urgent" 브랜치명 리터럴(`0103645f`·`f02bc77d`)
- 1건 `docs/design/nimtry_violations_design_manifest_2026-10-16.md:560` — yml 파일명 나열(`1e8a761b`)
- 2건 kimi-export 세션 전사본(`56f2a573`·`7d014a93`) — 값은 uuid 경로 매핑(오탐)이나 **커밋된 LLM 세션 전사본은 E2 제거 대상**(kimi-export 2종 — 사적 경로 노출로 invert-paths 편입)

## 2. 결과 요약

| 분류 | 건수 | 처리 |
|---|---|---|
| (a) 실자격증형 | 14 (고유 4종) | 폐기·재발급(사용자) + replace-text 침소 + 재스캔 확인 |
| (b) 합성·픽스처 | 4,851 | 분류 기록으로 잔존 허용 |
| (c) 오탐 | 17 | 식별자·레이블 판정 기록 |

## 3. 파일명 수준 예비 실측

.pem/.key/id_rsa/.env 등 **0건**(.env.example·.envrc는 빈 템플릿), `app_token_refresher.sh`(이력 전용) findings 0, `docs/history/searchweb_quota_investigation_2026_05_31.txt`는 플레이스홀더·빈 api_key만(실값 없음).

## 4. UNKNOWN·한계

- gitleaks 기본 룰셋 유지(지시대로) → `generic-api-key`가 해시·캐시키 대량 오탐(99.7%). 정밀 재스캔 시 `.gitleaks.toml` allowlist(evidenceKey/`axiom-b-` 패턴) 권장.
- 반대로 AWS AKIA+secret 페어·passphrase형·비정형 하드코딩은 기본 룰 매칭 밖 미탐 가능 — prefix형(ghp_/AKIA/xox/sk-/PRIVATE KEY) 실측 0건으로 파일명 수준 사전 조사와 정합.
- (a) 4값은 과거 노출이며 유효 여부 미검증 — 폐기·재발급은 사용자 Remediation.
- "12,067 commits scanned" ≠ rev-list 13,595 — diff 스캔 대상 커밋 계산 방식 차이(빈 diff 제외 추정).
- E5 독립 재스캔(PR refs mirror, 12,333 커밋)이 findings 4,882 동일 규모 재현 — PR 전용 실자격증형 0 확인.

## 5. Remediation 요구사항 (E2 cutover 입력)

1. **4종 키 폐기·재발급(사용자 실행 — §2.4 준수)**: Context7 1종 + Mistral 3종.
2. cutover `--replace-text`에 4종 실값 편입(파일 존치·값만 침소 — 게이트 2종·axiom.toml·registry.md 이력 전반. 실측 검증: Context7 키 리터럴은 3개 파일에만 존재, Mistral 3종은 axiom.toml 전용).
3. 재스캔: 침소 후 `gitleaks git -v --log-opts="--all"` → 자격증명형 findings 0 확인(합성·오탐은 분류 기록 잔존 허용).
4. 원본 리포트는 로컬 사적 보관만(공개 저장소 반입 금지 — 본 문서가 마스킹 증거).

## 6. 검증 명령

`git fetch --tags origin` → `gitleaks git -v --log-opts="--all" --report-format json --report-path <로컬 경로> .` (exit 1 — 발견 있음) · 분류 검증: findings JSON에서 RuleID·File·Commit 교차 집계 · Context7 키 위치: `git log --all -S"<값>" -- <경로>`·`git grep -l "<값>" $(git rev-list --all)`
