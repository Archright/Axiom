# Northflank 보안 사고 대응 완료 기록 (2026-10-31)

> 대상: Northflank Security incident (2026-10-30, Identified / Major outage).
> 본 문서는 Axiom 측 대응의 **완료 기록**이다 — CI 비용 최적화 워크스트림
> (S1 · PR-4)과 분리된 보안 운영 워크스트림. 기준 시각: 2026-10-31T02:13Z (UTC).

## 1. 사고 요약 (외부 정본)

- [external] [status.northflank.com](https://status.northflank.com) — Security
  incident / Identified / Major outage.
- 공식 타임라인 (UTC, 전부 상태 페이지 게시분):
  - 10-30 11:43 Wiz threat alert 수신 → 12:02~13:05 패칭 → 13:05 Wiz CIRT 지원
  - 10-30 13:58 Identified — "모든 환경변수가 복호화됐다고 가정, 모든 키 폐기·교체"
  - 10-30 19:28 — workloads·secret groups·global secrets 즉시 교체 + addon 공개
    접근 차단 권고
  - 10-30 23:38 — "Northflank에 제공된 AI API 키 무단 사용 신고" (Wiz
    'Black October' 패턴과 일치)
  - 10-31 01:04 — 전 고객 audit log 활성화
- 권고 요지: 사용자 제공 시크릿 전량 교체, 발급처에서 기존 자격증명 폐기·재발급,
  AI 공급자 사용량·청구 검토.

## 2. Axiom 노출면 (기계 확인, 2026-10-31)

- [live] Northflank 평면에서 실행되는 워크플로 = `ci-provider-router.yml` 유일
  (`runs-on: [self-hosted, axiom-control]`, Northflank 호스팅 러너). 저장소 전역
  Northflank 참조 1건.
- [live] Northflank 평면에 **AI API 키 없음** — 사고의 AI 키 유출 경로와 Axiom는
  무관.
- [live] 노출 가정 대상 장기 자격증명: `CI_ROUTER_APP_PRIVATE_KEY` — GitHub App
  `axiom-ci-provider-router` (App ID 5438756, 소유자 Archright 조직, 설치 대상
  repo Axiom, 권한 `actions_variables:write` + `metadata:read`)의 개인키.
  router 잡이 매 실행 시 이 값을 Northflank 호스팅 러너 VM에 주입 — 10-23
  부트스트랩 이후 최근 7일 925회 실행. `GITHUB_TOKEN`·minted App token은
  단기(이미 만료).
- [derived] 실효 공격 반경 = Actions 변수 `CI_RUNNER_MAP` 1개(러너 라우팅)의
  조작. 코드 실행·시크릿 읽기·repo 내용 접근·워크플로 강제 실행은 App 권한
  부재로 불가.
- [live] 사고 창 무결성 관측: `CI_RUNNER_MAP` last_transition
  2026-10-30T07:46:09Z (BOOTSTRAP — 사고 식별 통보 이전) 이후 전이 0; 사고 창
  내 router 8런 전부 success.

## 3. 대응 조치 기록

| # | 시각 (UTC) | 조치 | 수행 주체 | 증거 |
|---|---|---|---|---|
| 1 | 10-31 02:05:36Z 이전 | App 개인키 재발급 + `.pem` 다운로드 (PKCS#1 RSA, 1675B) | 운영자 (GitHub App 설정 UI) | 파일명 `axiom-ci-provider-router.2026-10-30.private-key.pem` (GitHub 생성 타임스탬프 표기); 다운로드 존재 확인 02:05:36Z |
| 2 | 10-31T02:06:15Z | environment secret `CI_ROUTER_APP_PRIVATE_KEY` 교체 | 세션 (운영자가 명시 제공한 pem 경로, `gh secret set --env ci-provider-router` — §2.4 네이티브 클라이언트 경로, 값 미출력) | environments API `updated_at` 10-23T08:35:24Z → **10-31T02:06:15Z** |
| 3 | 10-31T02:06:46Z | 교체 직후 첫 router 실행 생성 (workflow_run 트리거 — 새 키 확정 사용) | GitHub | run 41158483095 |
| 4 | 10-31T02:07:40Z | 검증: run 41158483095 **success** — "Mint router App token"·"[router] Classify and act" 스텝 실제 실행 (skip 0) | GitHub Actions | `gh run view 41158483095` |
| 5 | 10-31T02:08Z | `CI_RUNNER_MAP` 무결성 재확인 — `updated_at` 10-30T07:46:10Z 불변 (`mode:ubicloud` / `UBICLOUD_ACTIVE` / `x64:ubicloud-standard-2` / generation 12) | 세션 (관측) | actions/variables API |
| 6 | 10-31 ~02:11Z | 구(10-23 등록) 개인키 삭제 | 운영자 (App 설정 UI — 키 관리는 REST 미노출, UI 전용) | 운영자 채팅 확인 |
| 7 | 10-31 02:12Z | 로컬 `.pem` 삭제 | 운영자 | Downloads `*.pem` 잔존 0 (기계 확인 02:12Z) |

- `CI_ROUTER_APP_ID`는 무변경 — 개인키 재발급은 App ID를 바꾸지 않는다
  ([GitHub 문서](https://docs.github.com/en/apps/creating-github-apps/authenticating-with-a-github-app/managing-private-keys-for-github-apps)).
- 순서 준수: 신규 키 발급(1) → secret 반영(2) → 실동작 검증(3·4) → 구키
  삭제(6) — 구키는 검증 성공 후에만 삭제되었다.

## 4. 판정

- **노출 창 폐쇄 완료**: 신규 키가 실운동(success 실행에서 토큰 발급·변수
  읽기 입증)한 뒤 구키가 삭제됨 — 10-23~10-30 사고 노출 가정 분의 잠재 유출
  사본은 이 시점부터 무효.
- **무결성**: 사고 전후 `CI_RUNNER_MAP` 비정상 전이 0, router 실패 0 — 악의적
  사용 흔적 관측 없음. 반경이 변수 1개로 좁아 관측 커버리지가 유효하다.
  (흔적 부재는 무해 증명이 아니다 — 폐쇄가 그 역할을 담당한다.)
- **AI 키**: Northflank 평면 부재(§2) — 별도 조치 불요.

## 5. 잔여 (본 기록 밖 — 별도 워크스트림)

1. 운영자 방침 (2026-10-31 채팅): Northflank를 Axiom에 더 사용하지 않는다.
   router `runs-on`의 Northflank 평면 제거는 **실행 경계 변경**이므로 별도
   절차(§2.5/§2.6 규율)로만 처리 — 본 대응 기록과 묶지 않는다.
2. Northflank 콘솔 저장 시크릿 점검·AI 청구 검토: AI 키 평면 부재(§2)·폐기
   방침으로 계정 폐기 시 소멸 예정. 폐기 전 콘솔 잔존 확인은 운영자 항목.
3. Northflank 계정 폐기/해지 시점: 운영자 결정 항목.

## 6. 재현 명령

```bash
gh api repos/Archright/Axiom/environments/ci-provider-router/secrets \
  --jq '.secrets[] | {name, updated_at}'
# → CI_ROUTER_APP_PRIVATE_KEY updated_at = 2026-10-31T02:06:15Z
gh api repos/Archright/Axiom/actions/variables/CI_RUNNER_MAP --jq '.value'
# → mode=ubicloud, x64=ubicloud-standard-2 (전이 없음)
gh run view 41158483095 --repo Archright/Axiom --json conclusion,event,createdAt
# → success / workflow_run / 2026-10-31T02:06:46Z
```
