# Northflank 전환 계약 실행 운영 기질 선택 — operator 결정 요청서 (2026-11-02)

> **종류**: 인간(operator) 결정 요청서 (decision request). **이 문서는 결정을 대리하지 않는다.**
> 본 문서는 계약·정책·게이트 변경이 아니다 — `docs/evidence/` 기록 문서이며, 어떤 게이트도
> 본 문서를 소비하지 않는다. 사실·관측·선택지의 참조 나열만을 담는다(**권고 없음**).
> **Date**: 2026-11-02 · **Branch**: `work/northflank-medium-request` (worktree off `origin/main` @ `83ae548ae`)
> **Scope**: 본 문서 1건(신규) — 전환 계약·residual ledger 등 기존 정본 수정 0건.
> **결정 권한**: 운영 기질(medium) 채택은 **operator 전용**이다(AGENTS.md §0.3 신뢰 경계 —
> 에이전트는 기질 선택·프로비저닝·전환 실행을 대행하지 않는다).

---

## §0. 배경 — 전환 계약과 본 요청서의 관계

- 운영자 방침(2026-10-31): **"Northflank를 Axiom에 더 사용하지 않는다"**
  (`northflank_incident_response_2026-10-31.md` §5.1).
- 이 방침의 실행 절차는 PR #1187(GitHub native MERGE `4ee34ebb9`, MERGED)로 계약화됐다:
  `docs/spec/northflank_control_plane_transition_contract.md` — 전환·검증·롤백의
  순서·불변식·판정 항목을 사전에 고정한 정본이다.
- 계약 헤더 상태 행(원문): "**상태**: 계약 확정(2026-11-02) — 실행 대기(소유자:
  operator, 기질 결정)." 즉 절차는 정본화됐고, **남은 것은 코드가 아니라 권한**이다 —
  어떤 실행 환경(기질)을 운영 기질로 채택할지의 operator 결정이 선행될 때까지
  전환은 시작되지 않는다(계약 §1).
- 본 요청서는 그 결정을 **요청**하는 문서다. 계약을 재서술·개정하지 않으며, 후보·선정
  근거의 서술도 계약 §3–§4의 참조로 갈음한다(§1 표 — 중복 의미 상태 금지, AGENTS.md §1).
- 추적 아티팩트 현황(실측 §6-2): residual ledger
  (`docs/evidence/residual_issue_ledger_2026-10-31.md`)에는 Northflank **전환** 행이
  없다 — Northflank 언급은 RESID-10(청구액 확인, 별개 항목) 1건뿐이며, 전환의 유일
  추적 아티팩트는 위 계약 헤더 상태 행이다. 본 요청서는 ledger를 수정하지 않는다.

## §1. 요청하는 결정 (1건)

| ID | 결정 | 질문 | 판정 기준·후보 |
|---|---|---|---|
| **D1** | Northflank 전환 계약을 실행할 운영 기질 채택 | 전환 계약 §5 1단계의 운영 기질을 무엇으로 채택·프로비저닝할 것인가 | 계약 **§3(제어기 배치 3제약)·§4(대체 기질 판정 — 후보·표현 규율)** 참조. 본 문서는 후보를 새로 열거하지 않으며 §4 참조만으로 갈음한다 |

- 선택지의 나열·판정 기준은 계약이 권위다. 계약 §4는 기질의 최종 선정·프로비저닝·비용
  판단을 operator 결정 항목으로 규정하며, 본 요청서는 어느 후보도 권고하지 않는다.
- 이 결정 하나로 전환이 자동 실행되는 것은 아니다 — 결정 후 절차는 §4다.

## §2. 별개 대기 항목 — 본 요청서가 대체하지 않는 항목

아래 항목은 D1(기질 채택)과 **순서 종속성 없는 별개 판정**이며 본 요청서의 범위 밖이다.
본 요청서는 이 항목들에 대한 결정도 요청하지 않는다(각각 별도 소관).

1. **Northflank GitHub App 설치 해제** — 전환 계약 §6.1(App `northflank-cloud-build-run`,
   `repository_selection: all`; runs-on과 무관한 별개 표면 — 해제 시점은 operator 판정).
2. **Northflank 콘솔 계좌 폐기·시크릿 점검** — 전환 계약 §6.2 + 사고 대응 기록
   §5.2/§5.3(폐기 전 콘솔 잔존 확인은 운영자 항목, 폐기 시점은 operator 결정).
3. **RESID-10 — Northflank 청구액 확인** — ledger 행 원문: work_state/disposition
   **CLOSED / BLOCKED**, evidence_ref "API 403 관측 기록 (경로 접근 불가)",
   status_owner "외부 계정 소유자 (사용자)"(§6-4 재인용). D1과 독립이다.

## §3. 분리 원칙

1. 에이전트·문서는 **조사·요청**만 수행한다. 기질 선택·프로비저닝·전환 실행·롤백 실행은
   **operator 전용**이다(AGENTS.md §0.3 — "차단 해제"를 위한 신뢰 경계 우회 금지).
2. 결정 이전에 에이전트가 기질을 선택·프로비저닝·전환하는 것은 결정 대리다 — 금지된다.
3. 본 요청서는 옵션을 계약 §4 참조 방식으로만 제시하며 **권고를 포함하지 않는다**.
   결정을 유도하는 서술(우위 비교·정량 평가의 재구성)도 의도하지 않는다.

## §4. 결정 후 절차 (기존 계약 위임 — 신규 절차 아님)

D1 결정이 내려진 뒤의 경로는 기존 전환 계약이 이미 고정하고 있다 — 본 요청서는 새
절차를 만들지 않는다.

1. operator가 기질을 선정·프로비저닝한다(계약 §5 1단계 — 선정 근거(3제약 대조) 기록 포함).
2. 이후 전환·검증·롤백은 **기존 전환 계약의 절차를 그대로 실행한다**: §5 실행 순서
   (단일 일관 세대 전환 6단계 — 기질 결정 → 신규 러너 canary → runs-on·그룹 7 세대 전환
   → 기존 잡 drain → 라벨 소비자 0 확인 → 전환 후 관측·시계 오프셋 정리), 롤백 경로,
   failure semantics는 계약 원문이 권위다(AGENTS.md §2.5/§2.6).

## §5. 결정 권한·절차

- **결정 권한**: D1은 **operator 전용**이다. 에이전트·자동화는 이 결정을 대리할 수 없다.
- **본 문서의 지위**: 계약·정책 변경이 아니다. `docs/evidence/`의 기록 문서이며 어떤
  게이트도 소비하지 않는다. 결정 착지에 필요한 절차 변경(있으면)은 별도 변경집으로
  수행된다 — 본 문서는 그 변경집을 예고하지 않는다.
- **결정 기록**: 방법(본 문서 갱신, 별도 결정 문서, 이슈 등)과 시점은 operator가 정한다.
- **ledger 미수정**: 본 요청서 착지는 residual ledger에 Northflank 전환 행을 추가하지
  않는다(§0 — 현재 전환 추적 아티팩트는 계약 헤더 상태 행).

## §6. 실측 기록 (Completion Evidence — command → observation)

측정 일시 2026-11-02, 전부 읽기 전용. 기준 revision: `origin/main` @
`83ae548ae5f58eb6b39578bb35fd62db172aab6b`.

| # | 명령 | 관측 |
|---|---|---|
| 1 | `git rev-parse origin/main:docs/spec/northflank_control_plane_transition_contract.md` | `a848ce2925375a13c980912f0f35a6ee6797a942` — 본 문서가 참조하는 계약 문서의 blob SHA |
| 2 | `git grep -c -i northflank origin/main -- docs/evidence/residual_issue_ledger_2026-10-31.md` | `1` — Northflank 언급은 1건뿐(146행 `### RESID-10 — Northflank 청구액 확인`). **Northflank 전환(기질 선택) 행은 ledger에 존재하지 않는다** |
| 3 | `git show origin/main:docs/spec/northflank_control_plane_transition_contract.md` 헤더 | 상태 행 원문: `**상태**: 계약 확정(2026-11-02) — 실행 대기(소유자: operator, 기질 결정).` |
| 4 | `git show origin/main:docs/evidence/residual_issue_ledger_2026-10-31.md` (146–154행) | RESID-10 행 원문: `work_state / disposition` = `**CLOSED / BLOCKED**`, `evidence_ref` = `API 403 관측 기록 (경로 접근 불가)`, `verified_at` = `2026-10-31T01:43Z`, `status_owner` = `외부 계정 소유자 (사용자)` |
| 5 | `gh pr view 1187 --repo Archright/Axiom --json state,mergeCommit` | `state=MERGED`, `mergeCommit=4ee34ebb905218e9d44a8e6af1bab8183d92a2bb` — 전환 계약의 착지 PR 확인 |

## 참조

- `docs/spec/northflank_control_plane_transition_contract.md` — 전환·검증·롤백 절차
  정본(§3 3제약, §4 후보·표현 규율, §5 실행 순서, §6 별개 판정 항목). 본 문서는 그
  어느 절도 재서술하지 않는다.
- `docs/evidence/northflank_incident_response_2026-10-31.md` — 운영자 방침(§5.1),
  노출면 실측(§2), 별개 operator 항목(§5.2/§5.3)
- `docs/evidence/residual_issue_ledger_2026-10-31.md` — RESID-10(Northflank 청구액
  확인 — 본 요청서와 독립)
