# Upstream Reporting Contract — `ax report --upstream` (발견→재현→판정→보고)

> **Status**: Committed contract — upstream 보고 레인의 조작 계약 (§0.12 계약 선행 — 구현은 별도 workstream)
> **Created**: 2026-10-31
> **AGENTS.md 참조**: §0.12 (제품 계약 선행 · 수직 슬라이스), §2.4 (자격 증명 권한 — `gh auth` 네이티브 클라이언트 전용), §0.3 (신뢰 경계), §0.9 (극장 금지), §2.3 (per-output authority), §5 (SSOT 위치), §4 (GUARDIAN)
> **Related**: [bug_verdict_glossary.md](./bug_verdict_glossary.md) (§2.2 정준 발견 모델 + 판정표 — 2026-10-31 2차 판정 모델), [productization_contract.md](./productization_contract.md) §11 (`ax report --upstream` 표면), [bug_attribution_grounds_file.md](./bug_attribution_grounds_file.md) (근거 기록 스키마), [authority_contract.md](./authority_contract.md) §2 (verdict authority)
> **Report target (검증된 사실)**: `status-im/nim-libp2p`는 `iftech/nim-libp2p`로 redirect된다 — canonical 저장소(isFork=false, issues 활성). 보고 대상 = `iftech/nim-libp2p`.

---

## 1. 성격·목적 — 보고는 1급 운영 요구다

의심 결함(suspected defect)은 **실제로 유지보수자에게 도달해야** 한다. 제품 체인은 발견→재현→판정→**보고**의 4단계다 — 보고 계층이 없으면 앞 세 단계의 결과는 upstream에서 아무 효과도 갖지 못한다.

- 본 계약은 이 레인에 한해 종전의 한계 — "새 계약 없이 Axiom 측 행위 없음"(종전 슬라이스 계약의 non-claims 전제: `nim_stew_base36_cout_contract.md` §7, `nim_libp2p_bytesview_slice_contract.md` §7 — "수정 결정은 주체 유지보수자의 몫") — 을 대체한다. 보고는 이제 **1급 운영 요구(first-class operational requirement)**다.
- 대체는 이 레인에만 적용된다 — 주체 소스 트리에 대한 Zero-Footprint/READ-ONLY 규율은 불변이다(§3).
- 게이트·CI required check·기계 판정 enum은 `bugAttribution`·`reportStatus`를 소비하지 않는다 — bug_verdict_glossary.md §1 (불변).

## 2. 권한 분리 (authority separation)

| 대상 | 소유주 | 경계 |
|---|---|---|
| 주체 코드 + 요구 기록 | subject repo | **READ-ONLY** — 소스 Zero-Footprint(§3). 요구 채택 기록(`recordedBinding`)을 만들 수 있는 유일한 권위 |
| 명제 채택 (proposition adoption) | user | soExplicit 채택 행위(overlay 채택 선례) |
| 기계 반증 (`propositionVerdict`) | engine (`ax prove`) | VDA guarded 기존 어휘의 소비(`authority_contract.md` §2) — 외부 쓰기 0 |
| 귀속 (`bugAttribution`) | attribution classifier | bug_verdict_glossary.md §2.2 판정표의 순수 함수 |
| 이슈 번호·URL·코멘트·상태·알림 | GitHub | issue 상태의 유일한 권위 — 관측 대상이지 생산 대상이 아니다(AGENTS.md §2.3 per-output authority) |
| 수용·수정 여부 | external maintainers | Axiom이 대신 결정하지 않는다 |

- **검증 권한 ≠ 보고 권한**: `ax prove`는 **외부 쓰기가 0**이다(로컬 검증·증거 산출만). `ax report --upstream`이 **유일한 외부 쓰기 표면**이다.
- **자격 증명 경로 (HARD RULE)**: 외부 쓰기는 `gh` CLI 서브프로세스로만 수행되며, GitHub 자격 증명은 `gh auth`(네이티브 클라이언트)로만 확보한다(AGENTS.md §2.4). GitHub App·fine-grained PAT 등 다른 경로는 **명시적으로 제외**된다 — 파일시스템·환경변수·키링 탐색으로 자격 증명을 발견·대체하지 않는다. GitHub Actions 실행 시 `GITHUB_TOKEN`/`GH_TOKEN` 환경변수는 gh의 **공식 네이티브 인증 경로로 승인**된다([gh environment](https://cli.github.com/manual/gh_help_environment)) — 구현상 ax는 토큰을 직접 읽지 않고 `gh` 자식 프로세스가 환경 상속(environment inheritance)으로 소비한다.

## 3. Zero-Footprint 정교화 — 소스 무변경 ≠ 무통신

- **소스 트리 변경 금지 (불변)**: 런 전후 주체 소스는 바이트 동일이어야 한다 — 모듈 sha256 pre/post 일치, `git -C <subject> status --porcelain` 상시 공백(기존 subject pin 계약과 동일).
- **이슈 생성은 통신 행위다**: upstream 이슈는 유지보수자의 저장소에 남는 기록이지 주체 소스 트리의 변경이 아니다. 본 계약은 이 통신 행위를 **명시적으로 승인**한다 — Zero-Footprint Integrity는 "소스 무변경"의 계약이지 "무통신"의 계약이 아니다.

## 4. findingKey 계약 — 결함의 결정론적 정체성 (v2 정체성 모델)

동일 결함 → 실행·환경·경로와 무관하게 동일 findingKey — 증거 보강으로도 불변이다. findingKey 입력은 **모든 계층에서 키 정렬된 canonical JSON**이며, 정체성은 그 SHA-256이다:

```
findingKey = SHA-256( canonicalJson({
  "repository":  <resolved owner/name — redirect 해소 — 예: "iftech/nim-libp2p">,
  "subject":     "<modulePath>::<symbol>",
  "proposition": { specId, ruleId, ruleVersion,
                   canonicalSpecIRDigest: <canonicalSpecIR의 canonical digest> }
}) )
```

- **findingKey 의미 고정 (HARD RULE)**: 하나의 finding = 하나의 (repository, subject, 채택 명제) 신원이다. 동일 명제 아래 서로 다른 반례·독립 결함 후보는 같은 finding으로 수렴해 같은 이슈에 연결된다 — "하나의 명제 아래 독립 결함을 별개 이슈로 분리"하는 것은 본 계약의 미래 개정 사안이며 이 slice의 범위가 아니다.
- **반례는 정체성이 아니라 증거다**: `counterexample`(모델 바인딩의 정규화 바인딩 목록)은 findingKey에서 제외되며 증거 투영(`evidenceDigest`·receipt 증거 필드)에만 남는다.
- **evidenceDigest — 증거 무결성 투영**:

```
evidenceDigest = SHA-256( canonicalJson({
  claimOutcome, machineVerdict, rowStatus, quartetPayloadDigest,
  machineEstablished,
  "counterexample": <모델 바인딩의 정렬된 key=value 집합>,
  subjectCommit, subjectBlob
}) )
```

  증거 보강으로 evidenceDigest는 변할 수 있으나 findingKey는 불변이다.
- **legacyFingerprints**: v1 지문(`reportFingerprint` — 위 findingKey 식에 `"counterexample"` 멤버가 포함된 식; 코드 실측: `src/cli/upstream_report_cli.nim` `composeReportFingerprint`)의 과거 값 목록 — 마이그레이션·이슈 재연결용 기록(§6 레거시 조회).
- **제외 항목 (findingKey에 절대 진입 금지)**: 타임스탬프 · 런 ID · 임시 경로 · 런별 digest(`canonicalRunDigest`/`claimId`/`evidenceId`) · **커밋 SHA와 blob SHA** — 커밋·blob은 evidenceDigest·receipt 증거 필드에만 남는다. **커밋을 넘어 이어지는 하나의 결함은 하나의 이슈에 링크된다.**
- `repository`는 redirect 해소 후의 **resolved canonical owner/name**이다(§7 2단계).
- 결정론: 동일 결함은 여러 런에 걸쳐 동일 findingKey를 낸다 — 키 정렬 canonical JSON + SHA-256은 저장소의 canonical digest 규율(`productization_contract.md` §6 정렬 직렬화)과 동일한 결정론 계열이다.

## 5. 보고 상태 기계 (`reportStatus`)

`reportStatus ∈ {READY, SUBMITTED, DUPLICATE, BLOCKED, FAILED, RECONCILIATION_REQUIRED}` — bug_verdict_glossary.md §2.2 정준 발견 모델의 제4필드.

| 상태 | 의미 |
|---|---|
| `READY` | 증거 완비(공용 4요소 + 근거 기록), 아직 제출하지 않음 |
| `SUBMITTED` | 이슈 생성 확인 — 번호+URL을 GitHub로부터 **관측** |
| `DUPLICATE` | 동일 findingKey의 기존 이슈 존재 — 기존 URL을 링크하고 **아무것도 생성하지 않는다** |
| `BLOCKED` | 생성 불가 — 403(권한/상호작용 제한)·404(대상 미해결)·410(issues 비활성)·429(rate limit 일시 제한)이 **각각 별개 사유**로 기록(§8) |
| `FAILED` | 확인된 비생성으로 제출 실패, 또는 원격 상태 검증 불가 |
| `RECONCILIATION_REQUIRED` | 생성 시도했으나 응답이 모호 — **재생성 전 기존 이슈 재질의가 필수**다. 맹목 재시도 금지 |

- 전이: `READY → SUBMITTED | DUPLICATE | BLOCKED | FAILED | RECONCILIATION_REQUIRED`; `RECONCILIATION_REQUIRED → SUBMITTED | DUPLICATE`(재질의 관측 후).
- fail-closed: 모호한 응답은 결코 `SUBMITTED`로 승격되지 않는다(AGENTS.md §0.9 — 확인 없는 성공 표기는 극장이다).

## 6. 멱등성 제어 — 순차적 멱등, exactly-once 아님

- **단일 작성자 (single writer)**: 동일 findingKey에 대해 동시 병렬 생성 시도를 하지 않는다.
- **생성 전 findingKey 조회**: 이슈 생성 전에 동일 `findingKey`의 기존 이슈를 조회한다(검색 + 기존 이슈 직접 재질의의 회수 경로 — `RECONCILIATION_REQUIRED` 복구 포함).
- **레거시 receipt 조회 (v1 마이그레이션)**: `<findingKey>.json` 레저 미스 시 기존 레거시 receipt들(파일명 = v1 지문, §10)을 스캔해 신원 triple(repository + subject + proposition의 canonical 동등)이 일치하는 이전 receipt에서 증거(이슈 번호·URL·verdict·attempts)를 승계하고 그 지문을 `legacyFingerprints`(§4)에 기록한다. 일치가 다중이면 fail-closed `BLOCKED`(모호성)다. 최초 제출 시각은 GitHub 이슈 `created_at`(GitHub authority, §2)에서 백필할 수 있다.
- **수신 즉시 영속화**: GitHub 관측(번호+URL) 확인 직후 receipt를 기록한다(§10) — 관측과 기록 사이의 창을 최소화한다.
- **모호 응답 → `RECONCILIATION_REQUIRED`**: 성공으로 낙관하지 않는다.
- **정직한 보장 경계 (HARD RULE)**: GitHub API에는 원자적 유일성 제약이 **없다**. 본 계약의 멱등성 제어는 **순차적 멱등성(sequential idempotency)**만 제공하며 **exactly-once를 주장하지 않는다** — 보장의 과장 금지(AGENTS.md §0.9·§0.11).

## 7. 사전 확인 절차 (pre-flight)

생성 시도 전 순서:

1. **`gh auth status`** — 자격 증명 존재·유효 확인(AGENTS.md §2.4 — 유일하게 승인된 경로).
2. **대상 해석 (target resolution)** — redirect를 추적해 resolved canonical owner/name을 기록한다. 검증된 사실: `status-im/nim-libp2p` → `iftech/nim-libp2p`(canonical, isFork=false, issues 활성). findingKey(§4)·receipt(§10)는 해석된 이름을 사용한다.
3. **저장소 접근 확인** — 대상 저장소의 가시성·접근 가능 여부.
4. **issues 활성 확인** — issues 비활성 저장소면 410 경로(§8).
5. **권한 검증의 유일한 권위는 실제 생성 결과다** — `gh auth` 성공은 생성 권한을 **함축하지 않는다**. 저장소 interaction-limits는 이슈 생성을 협력자로 제한할 수 있다(403 → `BLOCKED`, §8).

## 8. 오류 분류 (fail-closed 매핑)

| HTTP | 의미 | `reportStatus` |
|---|---|---|
| 403 | access denied / creation restricted (interaction-limits 또는 org policy) | `BLOCKED(사유)` |
| 404 | target unresolvable (저장소 미해결) | `BLOCKED(사유)` |
| 410 | issues disabled | `BLOCKED(사유)` |
| 429 | rate limited (primary/secondary rate limit — rate-limit 토큰을 가진 403과 동일 처리) | `BLOCKED(사유)` |

403은 권한 거부 외에 rate limit일 수 있다 — GitHub 공식 문서상 primary/secondary rate limit 초과는 `403` 또는 `429`로 응답한다([Rate limits for the REST API](https://docs.github.com/en/rest/using-the-rest-api/rate-limits-for-the-rest-api)). 상태 매핑(403 → `BLOCKED(사유)`)은 불변이며, `blockedReason`은 gh 출력 텍스트의 rate-limit 지시자("rate limit", "too many requests", "retry after") 유무로 두 조건을 구분해 기록한다 — 지시자가 있으면 일시 제한(rate-limit transient restriction)으로, 없으면 권한/생성 제한으로 기록되며 어느 쪽이든 자동 재시도는 없다.

`BLOCKED`는 재시도로 해소되는 상태가 아니다 — 권한 부여·제한 해제 등 **조건 변경**을 요구하며, 조건 변경 후의 재시도는 사용자 명시 하에 새 제출 시도로 수행한다. 자동 재시도 루프를 만들지 않는다.

## 9. 이슈 본문 계약

- **템플릿 준수**: 대상 저장소에 이슈 템플릿이 존재하면 그 구조를 따른다 — 템플릿은 **명시적으로 fetch**한다(`gh`는 비대화형 모드에서 템플릿을 자동 적용하지 않는다).
- **자립 최소 재현 (self-contained minimal reproduction)**: Nim snippet + 정확한 pinned commit + 모듈 sha256 — 유지보수자가 우리 도구 없이 재현할 수 있어야 한다.
- **위반 명제의 평문 진술**: 어느 동작이 어느 입력에서 어긋나는가 — 엔진 용어가 아니라 유지보수자의 언어로.
- **요구 근거의 명시 (HARD RULE)**: `BUG_SUSPECTED` 보고는 결코 "이 프로젝트가 그 동작을 보장/약속했다"고 주장하지 않는다 — 기대가 **추론되었고 검증자가 채택했음**을 정직하게 진술한다(bug_verdict_glossary.md §2.4a — E2/E3는 `recordedBinding`을 만들지 못한다).
- **영향(impact)과 불확실성(uncertainty)**을 명시한다.
- **`findingKey` 값을 본문에 포함**한다 — 중복 탐지·추후 링크의 앵커.
- **Axiom 내부 정보 금지**: certificate·엔진 내부·파이프라인 세부는 이슈 본문에 넣지 않는다 — 유지보수자에게 필요한 것은 독립적으로 재현 가능한 증거지 우리 파이프라인의 내용이 아니다.

## 10. SSOT — receipt 기록

- **`data/upstream_reports/<findingKey>.json`이 기계 소비 authoritative receipt다**: 제출 기록 — `status`, 이슈 번호, URL, `findingKey`, `legacyFingerprints`(§6 레거시 승계 기록), subject pin(commit + module sha256), 명제 정체성(specId/ruleId/ruleVersion), 타임스탬프(증거 필드로 기록).
- **`docs/evidence`의 Markdown 기록은 DERIVED 인간 가독 투영이다**: receipt JSON의 digest를 참조하는 파생 문서이며 **독립적으로 편집되지 않는다** — 불일치 시 JSON이 정본이다(AGENTS.md §5 — 기계 정본은 data/, 실행 증거 기록은 docs/evidence/).
- 파일명이 findingKey이므로, 동일 결함의 재제출은 동일 파일의 상태 갱신으로 귀결되며 증거 보강(`evidenceDigest` 변화)에도 파일명은 안정이다(§6 멱등성).
- **v1 receipt(파일명 = v1 지문, `schemaVersion: upstream-report-receipt-v1`)는 마이그레이션 소스로 읽기 가능하다**(§6 레거시 조회) — `<findingKey>.json`이 이후의 authoritative 위치다.

## 11. 보고 대상 판정 규칙

| `bugAttribution` / `propositionVerdict` | 보고 여부 |
|---|---|
| `BUG_FOUND` | **보고한다** — E1 근거 기록 동반(bug_verdict_glossary.md §2.4a) |
| `BUG_SUSPECTED` | **보고한다** — A-essentials 충족 기록 동반; 요구 근거는 추론·채택으로 표기(§9) |
| `UNKNOWN` | 보고하지 않는다 — 추가 조사 대상 |
| `NOT_DISPROVED` (`propositionVerdict`) | 결코 보고하지 않는다 — 결함 미성립 |

공용 4요소(bug_verdict_glossary.md §2.2)는 모든 보고의 전제다 — 결측 시 어느 귀속이든 `READY`에 도달하지 못한다.

## 12. Non-claims

- NOT a claim of exactly-once delivery — 순차적 멱등성만 제공한다(§6).
- NOT an automation of maintainer acceptance — 수용·수정·우선순위는 유지보수자의 권한이다(§2).
- NOT a gate/required-check/enum surface — 귀속·보고 상태는 보고 입력 상태다(bug_verdict_glossary.md §1).
- NOT a relaxation of Zero-Footprint on source — 이슈는 통신 행위이지 소스 변경이 아니다(§3).
- NOT bulk issue automation — 하나의 findingKey ↔ 하나의 이슈; `DUPLICATE`는 아무것도 생성하지 않는다(§5).
