# Trust-surface break-glass 착지 기록 — PR #214, #215 (2026-11-19)

> **Status**: 착지 기록(landing record). 본 문서는 **이미 발생한 두 번의 수동 착지를 사후 기록**하며, 어떤 정책·워크플로·ruleset도 변경하지 않는다.
> **Created**: 2026-11-19
> **Landings**: #214 `f943c424e6e027ab2c66307cfe5cb130643b81c8`, #215 `64d0fe2e62308400b96f1c1750b4b216c0663bf4`
> **선행 증거**: `docs/evidence/supply_policy_registration_2026-11-19.md` (패키지 신원·digest), `docs/spec/ci_acceptance_contract.md` (수용 계약 v3)

## §0. 이 문서가 기록하는 것

두 PR은 **신뢰 표면(trust surface) 경로를 변경**했기 때문에 App `5795152`의 `admission-check`가 설계대로 거부했고, 따라서 정상 merge queue 경로로 착지할 수 없었다. 각 PR은 MUST-T2a 위임 기록을 **병합 전에** PR 코멘트로 등록한 뒤, required check를 보유한 **두 ruleset**에 일시적으로 bypass를 부여하고 REST merge로 착지했다. 본 문서는 그 사실과 불변식 보존을 증거로 고정한다.

## §1. 권한 사슬

| 항목 | 값 |
|---|---|
| Operator (human architect) | `wintrover` — sole `@Archright/architect` member |
| Operator 지시 (verbatim) | "권한이 필요한 부분은 전면 승인한다." |
| 지시 맥락 | "Blocker는 해결하거나 현재 목표와 독립적이면 별도 작업으로 분리하되, Terminal Outcome은 반드시 달성하라." |
| 위임 기록 #214 | `issuecomment-7013153018` (병합 전 등록) |
| 위임 기록 #215 | `issuecomment-7013719796` (병합 전 등록) |
| 실행자 | agent (per-PR 명시 위임). 사람의 키 입력으로 기록하지 않으며, 독립적인 두 번째 승인자가 있었다고 주장하지 않는다(§0.9 honest-executor). |

## §2. PR #214 — 정책 v105 (FROZEN → CONTROLLED)

- **변경 대상**: `config/repository_surface.json` — `policyVersion 104 → 105`, `.github/actions/setup-axiom-toolchain/action.yml`을 `CONTROLLED`로 등록, `frozenExceptions.groups["trust-supply-path"]`(rationale + `approvedBy: human-architect/2026-11-19`) 추가.
- **거부 증거** (check-run `135646950542`, App `axiom-admission-verifier`):

```
Preflight verification rejected
venue=pull_request
head=88772ed5bc9d07a3d1bc86502a6ebe27cfb5a4bd
base=69d2dce090c95eef683c16bfecc5bfa388bc8704
run=44548899392 attempt=1 conclusion=success
trust_surface=FAIL — venue=pull_request manifest_ref=dd8502f touched=1
manifest_touched=1 diff_base=69d2dce reasons=mismatch:config/repository_surface.json
```

- **차단 사유의 성질**: 정책 위반이 아니라 **자기 참조**다. PR이 정책 파일 자체를 바꾸므로 App은 그 PR을 인증할 수 없다. 같은 head의 in-repo verdict는 `PASS`였다.
- **ruleset 사실**: `admission-check`를 요구하는 ruleset은 **두 개**다 — `27097366` (`main`, required contexts 7개)과 `27525972` (`main-admission`, `admission-check` 단독). 1차 시도에서 하나만 bypass했을 때 merge API는 405로 거부했고, 두 ruleset 모두 bypass한 뒤 성공했다. 이 사실은 이후 모든 break-glass 절차에 반영됐다.
- **스냅샷**: `/tmp/ruleset-214-before.json` sha256 `5df5cb8c449f352238ef995e5d36d5658175eb5c4c0604659ebef776f0ff6f73`, `/tmp/ruleset-214-before-2.json` sha256 `58357ddfa037a43977fe117171eab2db085c7fdad9cddf136218000ce600a8d6`.
- **착지**: merge `f943c424e6e027ab2c66307cfe5cb130643b81c8`. 직후 두 ruleset 원복, `bypass_actors=[]` 확인.
- **canonical main push CI**: `44552516770` (Push on main), `44552518012` (fresh-prove-observation), `44552518030` (trusted-writer-set), `44552518032` (axiom-operational-slice) — 모두 `success`.

## §3. PR #215 — 공급 사다리 (action.yml)

- **변경 대상**: `.github/actions/setup-axiom-toolchain/action.yml`의 `Install system deps` 스텝만. tier 0 `ldconfig` hit → tier 1 고정 버전 APT → tier 2 Release asset(sha256 핀) → tier 3 승인된 공식 미러 순회 → tier 4 `external_dependency: libpcre3 unavailable` + `exit 1`.
- **핀 값**: version `2:8.39-15build1`, sha256 `62b2ea8d178a59495df00b777660377e0fb8d716be3fc552439796f77f515d43`, asset `https://github.com/Archright/Axiom/releases/download/supply-pins-libpcre3-8.39-15build1/libpcre3_8.39-15build1_amd64.deb`.
- **거부 증거** (check-run `135664041860`):

```
Preflight verification rejected
venue=pull_request
head=e6de9d49a4d1e8ef05c49957e9048d29a824e2fa
base=f943c424e6e027ab2c66307cfe5cb130643b81c8
run=44553721707 attempt=1 conclusion=success
trust_surface=FAIL — venue=pull_request manifest_ref=f943c42 touched=1
manifest_touched=1 diff_base=f943c42 reasons=mismatch:.github/actions/setup-axiom-toolchain/action.yml
```

- **사전 조건 확인**: merge queue 엔트리 `totalCount = 0` (ruleset 조작 시점).
- **스냅샷**: `/tmp/rs215-a.json` (`27097366`) sha256 `a617d69810cbbfcf1dee9a6f823e7c453a58938f7d07b05f104480bbd45fe7a9`, `/tmp/rs215-b.json` (`27525972`) sha256 `f3b5dde14992130f9ef144ff2839a833095810ba2974a2f527a8735ed5488fd7`.
- **착지**: merge `64d0fe2e62308400b96f1c1750b4b216c0663bf4`, `mergedAt = 2026-11-19T15:32:56Z`.
- **원복 검증**: 두 ruleset을 `PUT`으로 원복한 뒤 재조회. 스냅샷과 현재 값의 차이는 서버가 덧붙이는 `id`/`source`/`source_type`뿐이며 `name`/`target`/`enforcement`/`rules`/`conditions`는 동일하다. `bypass_actors`는 두 ruleset 모두 `[]`.
- **canonical main push CI**: `44556049973` (Push on main) `success`, `44556035924` (trusted-writer-set) `success`, `44556036040` (fresh-prove-observation) `success`, `44556035970` (axiom-operational-slice) `success` — 이 실행이 **새 공급 사다리의 첫 실제 운영 실행**이다.

## §4. 보존된 불변식

| 불변식 | 착지 후 상태 |
|---|---|
| required contexts | `admission-check`(App `5795152`) + `bsec-integrity`, `debt-registry-gate`, `generation-acceptance`, `axiom-operational-slice`, `publication-integrity`, `readiness-verdict` — 변경 없음 |
| App 신원 | `5795152` (`axiom-admission-verifier`) — 변경 없음 |
| trust surface | 17개 경로 유지. `action.yml`은 제거가 아니라 **CONTROLLED로 등록**되어 계속 보호 대상 |
| 공급 무결성 | `--allow-unauthenticated`·무검증 `dpkg -i`·비공식 미러 없음. 버전·sha256 불일치는 설치 거부 |
| 실패 시맨틱 | 모든 공급 실패 시 `external_dependency` 메시지와 함께 비정상 종료. admission skip의 success 승격 없음 |
| merge authority | GitHub ruleset. Axiom은 병합 권한을 재구현하지 않음 |

## §5. 이 기록이 하지 않는 것

- ruleset·required check·App을 **변경하지 않는다**.
- 거부된 App 판정을 성공으로 **재분류하지 않는다** — 두 PR의 `admission-check`는 `failure`로 남는다.
- 두 번째 사람의 독립 승인이 있었다고 **주장하지 않는다**.
- 수용(acceptance) 표본을 **확장하지 않는다** — cohort 경계와 측정은 `docs/spec/ci_acceptance_contract.md`를 따른다.