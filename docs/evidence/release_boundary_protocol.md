# Release Boundary Protocol — v\* enforcement matrix + 단일 POST A/B 사전 판정

> **Status: 실행 규약 (실행 전 고정).** ADR-0024(Owner 결정 #15) In Scope #6의 Phase 3 실험
> 규약이다. **채택 규칙은 실험 전에 여기 고정되며, 실험 결과를 보고 설계를 뒤집지 않는다.**
> 실행 결과는 §5에 회부한다(결과 없이 이 문서가 "완성"이 되는 일은 없다 — ADR-0024의
> "A/B 완료 전 단일 출하 경로 완성 선언 금지"와 동일 조항).

## 1. 목적과 범위

GitHub가 공식 문서로 보장하지 않는 두 미문서 영역을 **실측으로만** 확정한다:

1. tag ruleset이 **API로 생성된 ref**(`POST /git/refs`)와 **Release API의 자동 tag 생성**
   (`POST /releases`의 `tag_name` + `target_commitish`)에도 적용되는가.
2. Release 객체 creator를 제한하는 native gate는 없으므로, 인간이 **없는 v\* tag를 API로
   자동 생성**하는 경로를 ruleset이 막는가 (핵심 invariant의 마지막 연결).

대상 저장소: Archright/Axiom (private, org plan=enterprise 실측 2026-09-26).
전제(실험 시점, 역사적): `v*` tag ruleset(creation/update/deletion/non_fast_forward,
enforcement=active, bypass=Integration(Axiom release-authority App)만)이 Phase 3에서
생성되어 있었다 — **Owner 결정 #16(2026-09-26)으로 ruleset이 삭제되어 현재는 이 전제가
성립하지 않는다**(§2 NOTE).

## 2. v\* enforcement matrix (6칸 — 전부 실측, 예측 금지)

> **[NOTE 2026-09-26 — Owner 결정 #16]** v\* ruleset(`release-namespace-v`)이
> **삭제**되었다. 아래 matrix는 ruleset이 존재하던 시점의 실측 기록(역사적
> 증거)이며, 현재 상태에서는 human 셀(M1–M3) 전부 ALLOW가 정상이다.

행위자 × 연산. 각 셀은 독립 실행 후 HTTP 응답/거부 사유를 그대로 기록한다.

| # | 행위자 | 연산 | 기대 | 실제(§5) |
|---|---|---|---|---|
| M1 | human (사용자 토큰) | `git push origin v-test-m1` | BLOCK (ruleset 문서화 경로) | — |
| M2 | human | `POST /git/refs` (`refs/tags/v-test-m2`) | BLOCK (**미문서 — 실측 판정**) | — |
| M3 | human | `POST /releases` (`tag_name=v-test-m3`, `target_commitish=main tip`) | BLOCK (**미문서 — 실측 판정, 결정적 셀**) | — |
| M4 | release-authority App | `git push` equivalent 없음 (App은 git push 미사용) | N/A | — |
| M5 | release-authority App | `POST /git/refs` (`refs/tags/v-test-m5`) | ALLOW (bypass=App) | — |
| M6 | release-authority App | `POST /releases` (`tag_name=v-test-m6`) | ALLOW (bypass=App) | — |

- 테스트 태그는 `v-test-*`로 예약하고, 실험 종료 시 **App 토큰으로 제거**한다(bypass가 App에만 있으므로).
- M3가 **결정적 셀**: human의 신규 v\* tag 자동 생성 시도가 BLOCK이어야 A 채택 가능.

## 3. A/B 채택 규칙 (사전 등록 — 실험 전 고정)

- **[A] 단일 `POST /releases`** (`tag_name=vX.Y.Z`, `target_commitish=FROZEN_SHA`, `draft=false`):
  M6가 ALLOW **이고** M3가 **BLOCK**이면 **채택**. 더 작다(orphan tag object·ref 실패
  복구·태그 후 인간 race 제거).
- **[B] 4단계** (`POST /git/tags` → `POST /git/refs` → peel 단언 → `POST /releases`):
  M3가 BLOCK이 아니면 [A]를 **폐기**하고 [B]를 유지한다. 차단 불가 경로는
  ADR-0024 "잔여 한계"에 정직 기록한다 — **과장 금지**(Release 객체 creator는
  GitHub native policy로 제한되지 않는다).
- 채택 결과는 ADR-0024와 `release-ship.yml`의 `PUBLISH_PATH` 상수에 반영한다
  (**실행 결과: 2026-09-26 [A] 채택** — §5 실측).

## 4. 실패 모드 정의 (release-ship publish, ADR-0024 FAIL/UNCERTAIN)

- **definitive failure**: 4xx 확정 응답 → release 존재 확인(없음 확정) → tag 삭제 → **FAIL**.
- **ambiguous failure**: timeout / 5xx / 미판별 → **tag 삭제 금지 → UNCERTAIN** →
  수동 재확인 전 출하 금지. 네트워크 불확실성을 "Release 없음"으로 추정하지 않는다.
- release 존재가 확인된 상태에서는 어떤 경우에도 tag를 삭제하지 않는다.
- Immutable: tag 이름 재사용 불가 — 확정 실패 시에만 tag 정리, 그 후에는 version bump.

## 5. 실행 결과 (Phase 3 실행 시 기록 — 현재 미실행)

아래에 실행 일시·행위자·HTTP 응답·판정을 회부한다. 이 섹션이 비어 있는 한 ADR-0024는
"단일 출하 경로 완성"을 선언할 수 없다.

| 일시(UTC) | 셀 | 요청 요약 | 응답 | 판정 |
|---|---|---|---|---|
| 2026-09-26 | M1 | human `git push v-test-m1` | `push declined due to repository rule violations` | **BLOCK** |
| 2026-09-26 | M2 | human `POST /git/refs` (`refs/tags/v-test-m2`) | 422 `Reference update failed` — 대조 실험: 동일 방식의 비-v ref(`refs/tags/cetest-m2-control`)는 **201 생성 성공**(즉시 삭제) → v\* ruleset 특유 차단임을 증명 | **BLOCK** |
| 2026-09-26 | M3 | human `POST /releases` (`tag_name=v-test-m3b`, 없는 tag 자동 생성) | 422 `pre_receive: Repository rule violations — Cannot create ref due to creations being restricted` (**결정적 셀**) | **BLOCK** |
| 2026-09-26 | M5 | App `POST /git/refs` (`refs/tags/v-test-m5`) | 201 생성 — 이후 `DELETE`도 rc=0 (App이 ruleset bypass 주체임을 creation·deletion 양쪽에서 실측) | **ALLOW** |
| 2026-09-26 | M6 | App **단일 `POST /releases`** (`v-test-m6`, `target_commitish=main tip`, draft=false) | 201 — release id=397090641, tag 자동 생성 포함 ([A] 경로 실측) | **ALLOW** |

(M4: App의 git push 경로는 설계상 미사용 — N/A.)

잔여 정리 실측: M5 ref 삭제 rc=0 · M6 release 삭제 rc=0 + tag 삭제 rc=0 (immutable enabled 하에서도 release→tag 순 정리 경로 성공, 잔재 조회 전부 404/없음). v-test-* 예약 태그명은 회수 불가로 폐기(v-test-m6 포함 — 테스트 전용이라 영향 없음).

A/B 채택 확정: **[A] 단일 `POST /releases` 채택** (사전 규칙 충족: M3 BLOCK **and** M6 ALLOW).
`release-ship.yml` `PUBLISH_PATH: A` 반영(2026-09-26).

## 6. 동반 실측 (Phase 3 — 환경 게이트)

- `environment release-authority` protection read-back: `reviewers=[wintrover]`,
  `prevent_self_review=false`, **관리자 우회(UI `Allow administrators to bypass configured
  protection rules`) OFF 상태를 화면 확인으로 기록**(REST/GraphQL 미노출 — API 판정 불가).
  - **정정 (2026-10-20)**: `GET /repos/Archright/Axiom/environments/release-authority`는
    `can_admins_bypass: true`를 반환한다 — 위 "OFF(화면 확인)"과 "REST/GraphQL 미노출 —
    API 판정 불가" 서술은 **둘 다 사실과 다르다** (필드는 REST로 노출된다). 실측값 기준으로
    이 environment의 실효 범위는 required reviewer 밖 행위자 차단 + 거부 기회 + 감사 기록이며,
    동일 관리자는 자기 실행을 승인하거나 관리자 우회로 통과할 수 있다.
- 실행 정책: `authority-first-P-ship`(workflow_path=release-ship.yml,
  allowed_events=[workflow_dispatch], allowed_actors=[User 53123826]) 상태 조회 +
  **P-rpool(5564) allowed_events에 `workflow_call` 포함 확인**(누락 시 release-ship 위임이 정책에 차단됨).
- Immutable: `PUT /repos/Archright/Axiom/immutable-releases` → `GET`으로 `enabled: true`.

## 7. Release version consistency gate (Amendment G — 2026-10-19)

이 섹션은 ADR-0024 Amendment G의 검증 행렬이다. 실행 결과는 워크플로 run ID와 함께 아래에 추가한다.

| 케이스 | 입력 | 기대 결과 |
|---|---|---|
| negative: tag/package 불일치 | `validation_only=false`, `version=v9.9.9`, `target_sha=origin/main` | freeze ④~⑦ PASS → `verify-metadata` FAIL → full-l2/publish skipped → 태그/Release 미생성 |
| positive: 검증 전용 통과 | `validation_only=true`, `version=v0.3.7` | freeze skipped → `verify-metadata` PASS → full-l2 PASS → `verify-binary` provenance+`--version` PASS → publish **skipped** → `validation-only-assert` PASS |
| binary provenance | `ci-bootstrap-artifacts`의 `bin/ax` | `AXIOM_ROOT=<frozen checkout> bin/ax --check-provenance` PASS, `sha256`/`manifest.txt` 보존 |
| negative: 잘못된 artifact | frozen SHA와 다른 트리에서 빌드된 `bin/ax` | provenance FAIL → publish 미실행 |

**Quirk**: Nimble 0.22.2의 `nimble dump --format:json`은 `Error: Unknown option`을 출력하지만
**exit code 0**을 반환한다. 따라서 이 게이트는 `nimble dump --json`만 사용하고, JSON 필드
`version`의 존재·타입·semver 형식을 별도로 검증한다.

**범위**: 이 게이트는 `release-ship`이 생성하는 공식 릴리스 태그에 적용된다. 모든 `v*` 태그
push의 버전 일치를 주장하지 않는다(별도 태그 정책 결정 필요).

## References

- ADR-0024 결정 #15 · 계획서 Completion Evidence #2/#6/#7 (release-boundary authority 전환)
- GitHub 공식 문서: rulesets(available rules) · Releases API(anonymous create target_commitish
  "Unused if the Git tag already exists") · environment protection(prevent_self_review)
- 관련: `docs/evidence/canonical_run_graph.md`(P0 census) · `docs/spec/repository_surface_contract.md` 결정 #15
