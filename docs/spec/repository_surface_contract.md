# Repository Surface 계약 (Product Surface 판정 계층)

## 목적

**verification·authority·trust boundary에 닿는 표면은 명시적 승인 없이 변경 불가** —
이것이 보호 표면(FROZEN 열거)에 대한 유일한 trust 불변식이다. 계약(Product Surface) 밖으로
복잡도가 신규 유입되는 것을 막는 것은 그 수단일 뿐 목적이 아니다.

위 진술은 FROZEN 열거가 **표시하는 trust 의미**에 대한 사실 진술이지, 이 게이트가 그 열거를
집행한다는 주장이 아니다 — 판정 계층은 verdict를 낼 뿐 권한을 가지지 않으며, merge에 결합되는
강제는 GitHub의 몫이다 (§판정 계층).

"repo의 모든 파일이 사전 목록화되어야 한다"는 규칙이 아니다. 그것은 **inventory 관리
방식**이며 trust 불변식이 아니다 — 미등록 파일의 수정은 그 파일이 이미 트리에 있었다는
뜻이고, 그 자체로 새로운 capability를 trust 표면에 유입시키지 않는다. 반대로 **경로
대체(신규 민감 파일 추가)·authority 표면 수정·경계 삭제**는 새 trust를 만들어 들이거나
기존 trust를 약화시키므로 이 게이트가 개발자에게 알려야 하는 대상이다 (v51, 2026-10-02).

이 문서는 판정 계층만 정의한다 — merge 강제 결합은 별도 계약(merge admission)이
담당한다 (§범위 한계).

## 등급·규칙표

| 등급 | ADD | MODIFY | DELETE |
|---|---|---|---|
| PRODUCT (제품 표면, 기본값) | PASS | PASS | PASS |
| CONTROLLED (통제 표면 — scrutiny inventory) | PASS | PASS | PASS |
| FROZEN (authority 경계 — 명시 열거) | FAIL | FAIL | FAIL |

- `defaultClass: PRODUCT` — **미등록 경로는 일반 코드로 취급한다.** 사전 등록이
  불필요하다.
- 해석 순서: PRODUCT → CONTROLLED → FROZEN, **먼저 맞은 것이 이긴다.** FROZEN glob에
  겹치는 CONTROLLED 항목이 남아 있으면 PASS로 판정되어 FROZEN 규칙이 무력화된다 —
  FROZEN에 넣는 경로는 CONTROLLED에서 함께 제거해야 실제로 동결된다 (v51).
- CONTROLLED는 강제 경계가 아니라 **검토 대상 목록(inventory)** 이다. 의미는 "이 경로는
  정책에 등록되어 있어 봤다"이며, 규칙 자체는 전 op PASS다.
- 디렉터리 glob은 FROZEN에서만, 그리고 "그 디렉터리 전체가 하나의 권위 표면"인 곳에만
  쓴다 — 열거가 아니라 폐쇄-기본(fail-closed)이 목적이므로, 디렉터리 안의 새로 만들어진
  파일도 승인 없이는 못 들어오게 한다.

## FROZEN이 표시하는 trust 의미 (trust 분석, v51)

FROZEN은 "이 경로의 **trust 의미**가 바뀌면 정책 PR을 거쳐야 한다"를 **표시**한다. 아래
세 갈래는 그 등급이 겨냥하는 위협의 분류이지 이 문서가 집행한다는 주장이 아니다 — 판정 결과를
merge에 결합하는 강제는 별도 계약의 몫이다 (§범위 한계). 막히는 위협은 세 갈래다:

1. **신규 민감 파일 무단 추가** — trust 표면에 새로운 진입점을 심는 행위. ADD: FAIL.
2. **기존 authority 표면 수정** — 게이트 러너·워크플로·집행 훅·정책 임계를 약화시키는
   행위. MODIFY: FAIL.
3. **authority 표면 삭제** — 검사를 통째로 제거하는 행위. DELETE: FAIL (v51에서 PASS에서
   변경 — 아래 §DELETE 규칙 변경 근거).

**막지 않는 것**: 미등록 일반 파일의 수정·추가. 그 파일은 이미 트리에 있었고(또는
product 코드이고), 사전 목록에 없다는 사실 자체가 trust 변화가 아니다. v17–v50에서
반복된 "정책 선행 PR → 본문 PR" 2단계 절차는 이 구분을 하지 못해서 생긴 것이지,
보호해야 할 threat model이 아니었다.

FROZEN 열거 대상과 근거:

| 경로 | trust 근거 |
|---|---|
| `AGENTS.md` | 헌법 SSOT (AGENTS.md §-1 아키텍트 동결) |
| `config.nims` | 빌드 입력 주입 (§-1 importEncapsulation 동결) |
| `Makefile` | 실행 게이트 집합의 단일 정의점 (`PUSH_ADMISSIBILITY_GATES` + 모든 레시피). 이를 감시하는 `check-push-admissibility-integrity`도 Makefile 타깃이며 `push-admissibility`에 배선되어 있지 않아 독립 방어가 없다 — 판정 루트의 단일 실패점 |
| `ci/checker.mk` | gateway/부트스트랩 실행 코드의 단일 정의점 (자체 헤더가 변경 금지 원칙 대상으로 명시) |
| `config/repository_surface.json` | 본 정책 자신 |
| `config/trusted_writer_set.json` | `contents: write` 를 가질 수 있는 workflow 집합 (ADR-0022) |
| `config/executor_authority.json` | mint-domain TrustedExecutorSet (ADR-0021 D7) |
| `config/app_landing_binding.json` | Landing App 신원 = 런타임 변이 권위 (ADR-0025) |
| `config/publication_scope.json` | 발행 허용 범위 결합 |
| `config/policy/**` | 정책 임계값·상태 기록 (epoch manifest, merge admission 등) |
| `.github/**` | Owner 결정 #12의 trusted CI 정의(`.github/workflows/**`, `.github/actions/**`) + CODEOWNERS + Dependabot 위임 갱신 권위(#13(5)) |
| `.githooks/**`, `tools/hooks/**` | 로컬 집행 훅의 설치 위치와 구현 |
| `src/gate/**` | 검증 엔진 TCB (게이트 러너·gateway·contract) |
| `vendor/**` | ed25519 서명 검증 코드 |

## DELETE 규칙 변경 근거 (v51)

Owner 결정 #3(2026-09-21)은 "guard가 DELETE를 항상 허용하므로 표면 감소는 점진적
ratchet에 맡긴다"를 근거로 FROZEN DELETE를 PASS로 두었다. 그 전제는 `defaultClass:
FROZEN` 구모델에서 성립했다 — 그때 FROZEN은 "authority 표면"이 아니라 "미등록 파일"을
포함한 전 저장소 allowlist였고, 삭제 차단이 무관한 파일 청소를 막았기 때문이다.

v51에서 FROZEN은 **열거된 authority 경계**로 재정의되었다. 이 집합에는 "무관해서
삭제해도 되는 파일"이 존재하지 않는다 — 삭제는 검사·워크플로·집행 훅의 제거이고,
따라서 trust 변경이다. 그러므로 DELETE를 FAIL로 바꾼다.

Owner 결정 #3의 **대량 삭제 프로그램 금지 결론은 그대로 유지**된다 — 대량 삭제를
프로그램화하지 않았다는 판단은 변경되지 않는다. 그러나 v51이 **이 정책 파일 자체를**
FROZEN으로 동결했으므로, 이전 문구의 "삭제는 여전히 정책 PR 경로로 가능하다"는 전제는
**더 이상 성립하지 않는다** — 정책 파일 자신의 진화는 §Owner 결정 #1(아래)이 확인한
**문서화된 수용 리스크 경로**, 즉 Owner가 `--no-verify` 우회를 수용-risk로 명시한 그
경로(`git push --no-verify`)를 통해서만 가능하다. 변경된 것은 "삭제가 자동 통과한다"는
전제와, "정책 변경은 정책 PR로만 간다"는 전제 둘이다.

## base-policy 바인딩 (self-modifying loophole 차단)

판정은 PR의 정책이 아니라 **BASE_SHA(main과의 merge-base)의 정책**을 사용한다.
PR이 `config/repository_surface.json`을 수정해도 그 diff에는 적용되지 않으며,
정책 변경은 main에 착지한 뒤 비로소 효력을 갖는다. 이로써 "자기 자신을 허용하도록
정책을 바꾸는" 루프홀을 차단한다.

## 판정 계층 (adjudication layer)

**merge authority는 GitHub다** — CODEOWNERS(`.github/**`·`Makefile`·`AGENTS.md`·
`config/repository_surface.json`·`/config.nims`·`src/gate/**` 등 @Archright/architect) +
main ruleset 20303214(required check `admission-check` strict + `update`/`creation` 규칙으로
직접 push 차단 + merge queue) + merge 방식 제한(AGENTS.md §2.3). 판정 계층의 FAIL은 그
자체로 merge를 막지 않는다 — GitHub은 이 판정을 required check로 소비하지
않는다(`config/policy/merge_admission.json` `requiredValidations`는 `admission-check`
단독이며 repository-surface는 필수가 아니다).

판정은 아래 세 층에서 같은 규약으로 반복 계산된다. 어느 층도 merge 권한을 부여하거나
거부하지 않는다.

1. **로컬 pre-push preflight** — `make push-admissibility` →
   `check-repository-surface`(Makefile)가 merge-base(origin/main, HEAD)의 정책 ×
   브랜치 diff로 판정하고 FAIL이면 push를 차단한다. 개발자가 `--no-verify`로 우회할 수
   있는 **개발자 피드백 장치**이며 집행점이 아니다.
2. **CI `repository-surface`** — `pull_request@main`으로 자동 발화되는 조언적 관측
   (advisory observation)이다(2026-09-22 PR 자동 관측 복구 — workflow_dispatch 전용이
   아니다). required check가 아니며, FAIL 관측은 PR에 남지만 merge를 닫지 않는다.
3. **`tools/surface_guard.nim`** — 순수 verdict 계산기. authority가 아니다
   (`Authority ≠ Adapter`).

## 결정론 보장

동일 정책 + 동일 diff → 동일 verdict. `tools/surface_guard.nim`은 로컬에서
재현 가능한 직렬 판정을 수행하며 순서·문자열·정규화 오차가 없도록 한다.

## 클로저 산출 명령

- `tools/product_surface_closure.nim`: 제품 표면에서 도달 가능한 비-src 파일을
  산출하여 CONTROLLED 목록에 개별 추가한다 (broad wildcard 금지).

## 알려진 사각지대

- `when defined(...)` 조건부 import는 추적되지 않는다.
- 매크로 생성 import(컴파일타임 axiomRegistry)는 보이지 않는다.
- `config.nims --import` 주입(`config/effects.nims`)은 빌드 입력이지 소스 엣지가 아니다.
- choosenim 툴체인 모듈(`compiler/**`)은 저장소 밖에서 해석된다.
- **v51**: FROZEN 열거 밖에서 새로 발명된 authority 표면은 PRODUCT로 판정된다
  (ADD/MODIFY PASS). 경계는 기본값이 아니라 열거로 닫힌다 — 열거 누락은 이 게이트가
  잡지 못한다.
- **v51**: 게이트가 실제로 소비하는 **규칙 데이터** `src/policy/**`
  (`python_shell_exemptions.nim` → `language_ban_gate`, `build_constraint.nim` →
  `tools/hermetic_entry.nim`)는 동결하지 않는다. 후속 정책 버전 후보로 남긴다.
- **v51**: `data/debt_registry.json`·`data/debt_ledger.json`·`data/architecture_debt.json`·
  `data/feature_manifest.json`는 CONTROLLED(검토 대상, 전 op PASS)이며 부채 원장 변조는
  이 게이트의 범위 밖이다.
- **v51**: rename은 새 경로에 대한 ADD로, 이전 경로는 항상 PASS인 암묵적 DELETE로
  판정된다(`surface_guard.nim`의 동결 규칙) — `rules.FROZEN.DELETE`와 무관하게 이전
  경로 삭제는 막히지 않는다.

## 범위 한계

이 문서는 **판정 계층만** 정의한다. 판정 결과를 merge에 결합(required check 등)하는
강제는 별도 계약의 몫이며, 이 계약의 범위 밖이다.

## Owner 결정 기록 (2026-09-21)

플랫폼·집행 모델에 대한 owner 결정(2026-09-21 질의·응답으로 확정):

1. **플랜 미승급·비결제 확정** — GitHub Team 승급과 호스팅 러너 과금 해제는 하지 않기로
   확정했다. 로컬 pre-push 게이트가 상시 유일 강제점이며(일시적 한계가 아닌 확정된 집행
   모델), `--no-verify` 우회는 문서화된 수용 리스크로 남는다. (2026-09 공식 문서 검증:
   Free private는 ruleset·push ruleset·required check 전무 — Team 승급 시에만
   "Restrict file paths" push ruleset이 열린다.)
   **[superseded 전제, 2026-10-05]** — 괄호 안의 "ruleset·push ruleset·required check
   전무" 전제는 폐기되었다. 현행: main ruleset 20303214에 required check
   `admission-check`(strict), `update`/`creation` 규칙(직접 push 차단), merge queue가 살아
   있고, CODEOWNERS가 `.github/**`·`Makefile`·`AGENTS.md`·`config/repository_surface.json`·
   `/config.nims`·`src/gate/**` 등을 `@Archright/architect`에 결속한다. 관측 근거: FROZEN인
   `config.nims`을 수정한 PR #475가 merge되었다 — 승인 권한을 배정한 주체가 없었고,
   `update` 규칙 부재로 직접 push 경로가 열려 있었다. **플랜 미승급 결정 자체는 유지**된다
   (러너 과금 대상만 해당). "로컬 게이트가 유일 강제점"은 사실이 아니다 — `--no-verify`로
   preflight를 우회해도 merge 권한은 생기지 않는다. merge authority는 GitHub이지 이 게이트가
   아니기 때문이다(AGENTS.md §2.3, §판정 계층).
2. **CI 복구 방향 확정** — self-hosted 플릿은 "큐잉-후-공급자"(job 큐잉 시 jitconfig
   공급 → 러너 일회성 집행 → 소멸, ADR-0023 유지) 방향으로 복구한다. 실행은 별도
   ADR/계획으로 진행하며, 영속 러너 전환과 호스팅 러너 대체는 기각했다.
3. **FROZEN 삭제는 프로그램화하지 않는다** — guard가 DELETE를 항상 허용하므로 표면
   감소는 점진적 ratchet에 맡기고, 대량 삭제 Phase 프로그램은 만들지 않는다.
   **[superseded 전제, 2026-10-05]** "guard가 DELETE를 항상 허용"은 성립하지 않는다 —
   v51이 `rules.FROZEN.DELETE`를 PASS → **FAIL**로 바꾸었다(Owner 결정 #17(c)). 결론
   ("대량 삭제 Phase 프로그램 금지")은 **유지**된다.
4. **`src/gate/runners/gate_hook.nim` CONTROLLED 승격 승인** — 활성 강제 경로
   (pre-commit)의 fail-open 결함(스테일 수령증 0ms 단락회용, gate_hook.nim:203-212)
   수정을 위한 명시적 표면 변경으로 승인. 정책 승격 PR → 코드 수정 PR 2단으로 착지한다.
5. **`docs/adr/0023-scale-set-authority-supersession.md` CONTROLLED 승격 +
   ratification 승인** — on-demand 러너 플릿 설계 확정(ADR-0023 ratify +
   Amendment A1: scaleset-adapter 메커니즘을 polling reconciler로 대체,
   1 VM=1 jitconfig, external-JIT-only, warmFloor=0, 구현은 CI 복구 시점)을 위한
   명시적 표면 변경으로 승인. 정책 승격 PR → 본문 수정 PR 2단으로 착지한다.
6. **온디맨드 러너 플릿 reconciler(axfleet) 구현 승인** — ADR-0023 Amendment
   A1의 구현. 결정론 decide + 관측 fail-closed(mutation 0) + 단일 control host
   mutation authority. 수반 결정론 유닛 테스트 파일을 PRODUCT 표면에 개별
   등록한다(test_surface_guard.nim 선례). 정책 승격 PR → 코드 PR 2단으로
   착지한다.
7. **Proof Unit Catalog·consistency/reconcile 게이트 표면 승격 (2026-09-23)** —
   사용자 승인 CI 최적화 계획(feature/proof-unit-catalog, A0~A3)의 신규 3파일
   (A0 Proof Unit Catalog, A0′ consistency gate, A3 reconcile gate)을 ADD 허용을
   위해 **PRODUCT에 개별 등록** (선례 6과 동일, broad wildcard 금지), 동 계획이
   수정하는 16개 경로(ADR-0017/0019·tiers 스펙·merge/certification 계약·
   rules_workflow·operations·debt 자료 4·selector·IMPACT_CLOSURE·pre-push·
   테스트 2)를 **CONTROLLED에 개별 등록**한다. 정확한 경로 목록의 유일 권위는
   `config/repository_surface.json`이며 본 기록은 결정만 서술한다 — 신규 파일은
   본문 PR(2단 2/2)에서 추가되어 본 정책 PR 스냅 시점에는 미존재하는 것이
   정상이다. 정책 승격 PR → 본문 수정 PR 2단으로 착지한다
   (본체 = feature/proof-unit-catalog 4커밋).
8. **CI 비용·공급자 조사 보고서 표면 승격 (2026-09-23)** —
   CI 비용·공급자 조사의 시점 보고서(과금 양자화·무결성 MUST 필터·Pareto 판정) 신규
   1건을 ADD 허용을 위해 **PRODUCT에 개별 등록**한다 (선례 6·7과 동일, `docs/**`
   broad wildcard 금지 — FROZEN 기본 계약 불변). 정확한 경로 목록의 유일 권위는
   `config/repository_surface.json`이며 본 기록은 결정만 서술한다 — 신규 파일은
   본문 PR(docs/ci-provider-cost-investigation 브랜치)에서 추가되어 본 정책 PR 스냅
   시점에는 미존재하는 것이 정상이다. 정책 승격 PR → 본문 추가 PR 2단으로 착지한다.
9. **실행-컴퓨트 변이 권한 GHEC 이전 비준 — 신뢰 경계 변경 (2026-09-23)** —
   신뢰 경계(trust-boundary) 변경으로서 Owner가 비준한다. authority-first 순서:
   **Owner 결정(본 건) → verifier pinning → INV-1 merge-group 그래프 증명 → THEN
   플릿 삭제**. **본 결정은 플릿을 삭제하지 않는다** — 플릿 삭제는 증명 성공 후 별도
   단계에서만 실행된다. (a) 본 결정은 #1(호스팅 러너 수용 기각)·#2(호스팅 러너 대체
   기각)·#5/#6(axfleet 단일 control host mutation authority 비준) 중 **호스팅
   러너를 거부한 부분 또는 axfleet을 유일한 실행 변이 권한으로 명명한 부분을
   supersede**한다. (b) 실행-컴퓨트 변이 권한(execution-compute mutation
   authority)은 GitHub Actions on GHEC로 이전되며, GitHub-hosted 러너가
   **잡 격리·신규 VM 보장을 플랫폼 계약으로** 공급한다 — 공식 보장 문구:
   "GitHub automatically provisions a fresh virtual machine. All steps within
   that job execute on the same VM... Once the job completes, the virtual
   machine is automatically decommissioned." (c) 용량 상한 D3=16을 **재비준**한다
   — 상한 **값은 정책으로 유지**되며, 강제(enforcement)는 `decide.nim`
   (reconciler config 상한)에서 **플랫폼 동시성(matrix caps)**으로 이동한다.
   (d) 신뢰 규칙 M1(잡 격리 신규 VM + 잡 종료 후 소멸, `--ephemeral` 1 VM=1 job —
   `docs/reports/ci_provider_cost_investigation_2026-09-23.md`)은 **그대로
   유지** — 보장의 **제공자만** axfleet에서 GitHub-hosted 러너로 변경된다.
   (e) 후속 의무: 호스트 증명 TCB 문구(`docs/spec/certification_continuity_contract.md`
   RunnerPoolSpecDigest 참조, ~58/64행)는 해당 계약의 **CONTROLLED 절차로만**
   개정한다 — 본 결정은 그 개정 의무를 기록하며 해당 파일을 직접 수정하지 않는다.
10. **Surface CONTROLLED 성장 경로 확립 — 정책 규칙 v4 (2026-09-24)** —
    GHEC 이전에 수반되는 신규 워크플로 2건(측정 전용 merge-queue probe
    `probe-merge-queue.yml`, B-pinned admission producer `admission-check.yml`)과
    `.github/pull_request_template.md` 수정이 표면래치에 필요해졌으나, 실측
    (`make check-repository-surface` exit 2 — template이 FROZEN MODIFY)과 규칙
    구조상 **CONTROLLED·FROZEN 모두 ADD=FAIL**이라 "정책 승격 PR → 본문 PR" 2단
    패턴이 CONTROLLED에는 기계적으로 성립하지 않음이 확인되었다. 본 결정으로:
    (a) 정확 경로 3건을 CONTROLLED에 개별 등록한다 — `.github/pull_request_template.md`,
    `.github/workflows/admission-check.yml`, `.github/workflows/probe-merge-queue.yml`.
    (b) `rules.CONTROLLED.ADD`를 FAIL → **PASS**로 바꾸고 본 문서의 등급·규칙표를
    같은 값으로 정정한다 — 2단 패턴(정책 PR로 등록 → 본문 PR로 파일 ADD)이 문서된
    대로 작동하게 만드는 최소 수정. **FROZEN의 ADD·MODIFY는 불변**이므로 미등록
    경로(광범위 `.github/**` glob)는 여전히 차단된다. 등록 자체는 정책 PR만이
    가능하므로 표면 성장은 여전히 명시적 정책 통제를 거친다.
    (c) `policyVersion` 3 → 4. 번호 9는 in-flight인 GHEC 신뢰경계 이전 결정
    (`feature/ghec-migration`)이 선점한다. 선례 #6·#7·#8과 동일하게 신규 파일은
    본문 PR에서 추가되어 본 정책 PR 스냅 시점에는 미존재하는 것이 정상이다 —
    정책 승격 PR → 본문 추가 PR 2단으로 착지한다 (본체 = `feature/ghec-migration`).
11. **CAS 랜딩 검증 게이트 — 소거 3종 전제조건 재정의 + 실행/제어평면 권위 분리 (2026-09-24)** —
    Owner가 #9의 authority-first 순서 중 **"INV-1 merge-group 그래프 증명"을
    "CAS 랜딩 검증"으로 재정의**한다(#9 supersede 범위 확장 — ADR-0023 Amendment A3).
    INV-1 merge-group 그래프는 merge-queue prefix-chain 증명이며, merge queue가
    소거 대상이므로(본 결정) 그 증명은 폐기된다. authority-first 순서:
    **Owner 결정(본 건) → verifier pinning → CAS 랜딩 검증 → THEN 소거 3종**.
    CAS 랜딩 검증의 게이트 구성: (a) `parents(M)==[B,H] ∧
    tree(M)==GitHub-returned merge tree` 실측 ≥N회(N은 시행 계획에서 확정),
    (b) `updateRefs` CAS **성공 + 거부(reject → 변화 없음)** 양쪽 실측,
    (c) 착지 후 `ax cert continuity` ccPassed. **플릿(Hetzner)·merge queue·자체
    용량 controller(decide.nim ceiling/supply 규칙, reconcile.nim supply loop)
    — 소거 3종 — 은 이 게이트 통과 후에만** 실행된다. 권위 분리: **runtime
    mutation authority = Landing App**(updateRefs로 main을 옮기는 유일한 런타임
    행위자), **control-plane authority = GitHub 조직/엔터프라이즈 거버넌스**
    (ruleset/App 설정 변경 — 런타임 경로 밖의 별도 층). Owner 결정 #10이 등록한
    측정 전용 merge-queue probe 워크플로는 merge-queue 소거를 전제하므로
    **retire를 승인**한다(실제 삭제는 게이트 통과 후 별도 lane이 실행).
    **#11 amendment (ADR-0027, 2026-09-29 — Merge Queue 위임 채택)**: ADR-0027이
    본 결정 중 merge queue 관련 부분을 supersede한다. (a) merge queue는 '소거
    대상'에서 **위임 대상**(native GitHub merge queue — 후보 인증 경로)으로
    전환되며, '소거 3종'은 플릿(Hetzner)·자체 용량 controller로 축소된다 —
    **커스텀 queue/orchestrator 금지는 유지**된다. (b) 본 결정이 승인한
    merge-queue probe **retire는 철회**되고 probe는 **재등록**된다(Phase 0
    측정 — ADR-0027). (c) '실측 ≥N회 gate' 문구는 **재해석**된다: 큐 채택은
    **Phase 0 probe 측정(α|β) 이후에만** 착수한다(γ = STOP) — 게이트 강도는
    유지하며 약화하지 않는다. 본 기록은 supersession 사실만 서술하며 상세
    문구는 ADR-0027이 수록한다(결정 #11 본문·원래 정책 문구는 직접 수정하지
    않는다).
12. **Authority-first 실행/정의 권위 주체 분리 (2026-09-25)** —
    최상위 invariant: 일반 repository actor는 (i) 승인된 production workflow 외의
    workflow를 **생성**하거나, (ii) 허용되지 않은 actor/event로 production
    workflow를 **실행**하거나, (iii) trusted CI 정의(`.github/workflows/**/*`,
    `.github/actions/**/*`)를 **수정**할 수 없다. 정의 변경의 신뢰 주체는
    **OrganizationAdmin과 Landing App**이다 — push ruleset의 bypass 특성상
    Landing App에도 직접 push 권위가 포함된다. PR merge 경로는 별도의 merge
    권위(결정 #11 체계)가 추가로 요구하는 경우에만 사용한다. 3축 control-plane 위임:
    (a) **생성** = push ruleset(file_path_restriction, path exception 없음,
    bypass = OrganizationAdmin + Integration 4879411), (b) **실행** = workflow
    execution protections(org-level evaluate → 관측 → 일치 검증 → active;
    RepositoryRole: Write 기반, named identity 금지), (c) **실행내용** = Actions
    allowlist + full-SHA pin. calibration 순서(의도 → 관측 → 일치 검증 → active)와
    P-mint provenance binding 4구성(upstream admission-check only + completed +
    success + upstream head_sha binding)을 **privileged transition의 정의**로
    확정한다. 잔여 권위는 org owner의 정책 disable/delete/bypass이며, 판정 범위는
    일반 actor 기준이고 주장은 "현행 활성 정책에 의한 차단"이다 — lifecycle
    registry를 만들지 않음을 재확인한다. 전환 트리거: 첫 Write-role member 실재 시
    RepositoryRole: Write class positive probe + 정의 경로 push deny 실증. 정책
    evaluate는 repository target 미지원으로 org-level(Axiom conditions)만
    사용한다.
    **#12(b) ratification (ADR-0024 결정 #15, 2026-09-26)**: P-rpool(5564)
    실행 정책의 named identity(명시 actor) 지정은 #12(b)의 "RepositoryRole:
    Write 기반, named identity 금지"와 상충한다 — ADR-0024가 이 이탈을
    ratified한다: #12(b)는 첫 Write-role member 실재 시 전환(RepositoryRole:
    Write class positive probe + deny 실증, 90일 내 ADR 개정)이 발동하는 전환
    프레임이며, 전환 완료 전 단일 운영자 실정에서 named identity 실행 정책은
    명시적 예외로 유지된다. 본 기록은 ratification 사실만 서술하며 상세 문구는
    ADR-0024가 수록한다(결정 #12(b) 본문·원래 정책 문구는 직접 수정하지 않는다).
13. **Authority-first 후속 6건 처분 (2026-09-25)** — Owner 결정 #12 체계의
    후속 처분 6건을 확정한다:
    (1) **`ax verify` 단일 canonical interface는 신설하지 않는다** — 현행 검증
    entrypoint/게이트를 유지한다. 독립 consumer가 2번째로 생겨 제품 계약이
    필요해질 때만 §0.12 절차로 신설한다.
    (2) **merge authority는 현행 유지** — 로컬 게이트 + L2 + native MERGE.
    CI를 merge authority로 격상하지 않는다. **(ADR-0027 확장, ratify 시)**:
    merge authority 집합에 **플랫폼 큐 경유 네이티브 MERGE**(GitHub Merge
    Queue 경유 착지)가 추가된다 — '현행 유지'는 해당 확장 이후의 집합에도
    성립한다.
    (3) **실험 CI 외부 격리 미신설** — 새 시스템/정책을 만들지 않는다. Axiom은
    production CI만 허용하는 현행 창설 봉쇄 구조로 충분하며, 실제 실험 수요가
    생기면 단일 lab repo를 만든다.
    (4) **org/enterprise 확장은 미래 항목** — 미래에 repo custom property
    `ci_authority_profile=authority-first` → org-level Actions policy
    (`repository_property` conditions) → workflow actor/event policy의 property
    기반 프로파일로 통합한다. 형제 저장소 workflow inventory와 공통 invariant
    확인 후 단일 시점에 적용하며, 지금은 미적용이다.
    (5) **SHA-pin 갱신은 GitHub Dependabot version updates에 위임** — Dependabot은
    SHA reference(`owner/action@<commit>`) 갱신을 지원하므로 Renovate 등 외부
    권위를 도입할 필요가 없다. 보안 alert와 version update는 별개다(SHA-pin
    action은 보안 alert 미생성이 플랫폼 한계). 실행 가능성을 위해 platform
    bypass가 필요해도 그 대상은 GitHub native Dependabot으로 한정한다 — 잔여
    권위로 기록.
    (6) **정기 재검증 automation은 미신설** — 정책은 GitHub Actions execution
    protections가 지속 집행하고 policy insights도 플랫폼이 제공한다. 검증 흐름 =
    정책 변경 → GitHub native read-back → 검증 → 완료. 새 검증 workflow는 새
    authority surface가 된다.
    최종 구조: **GitHub = Rulesets(authority) + Actions policies(authority) +
    Dependabot updates(갱신)** / **Axiom = verification semantics만 담당**.
14. **CI Pareto 실험은 동일 repository의 non-authoritative measurement plane에서 수행한다 (2026-09-25)** —
    결정 #13(3)의 본질은 repository 분리가 아니라 **authority/production-path 분리**임을
    재정의한다. 실험의 목적은 새 CI 시스템 운영이 아니라 동일 검증 계약 아래 실행 계획·
    하드웨어·병렬성 후보의 측정이다. 실행판과 권위판의 경계:
    ```
    Production path:  admission → mint → MergeAdmissible → Landing CAS   = AUTHORITATIVE
    Experiment path:  smoke / T_train / T_holdout                         = OBSERVATIONAL
                                      X authority boundary
    ```
    (1) smoke 및 T_train/T_holdout 실험 실행은 production authority path와 별개인
    **observational execution**이며, merge-admissibility, certificate ledger,
    Landing CAS의 입력 또는 권위 증거 생산자가 아니다.
    (2) 실험 workflow는 명시적 실험 trigger로만 실행하며 production merge gate
    (required check)로 승격하지 않는다. 실행 권한 차단의 실체 = 최소권한
    `permissions` + required-checks 미포함 + certificate ledger writer 권한 없음 —
    즉 **lab repo 수준의 authority isolation을 workflow 실행 권한으로 구현**한다.
    경로 allowlist(표면 정책)는 성장을 기록할 뿐, 격리 TCB가 아니다.
    (3) 별도 lab repository는 현재 추가하지 않는다. 별도 repository는 실험
    execution 자체가 production repository의 authority boundary를 침범하는 요구가
    발생할 때만 별도 ADR로 검토한다 — lab repo는 원본 접근 토큰·SHA binding·
    lab→production ingest 권위·provenance·workflow drift 등 새 trust boundary를
    낳으므로 성능 최적화의 수단으로 만들지 않는다.
    (4) 단일 판정 규칙: **"이 실험 실행이 production state transition을 유발하거나
    그 권위 증거를 생산할 권한이 있는가?"** — NO이면 동일 repository의 측정 도구로
    실행하며, YES일 때 격리·lab ADR를 검토한다. 현재 smoke/T_train은 NO.
15. **Release-boundary authority 전환 — 출하 단일 경로 (2026-09-26)** —
    릴리스 출하를 "임의 tag push → CI 발화"에서 **"release-ship.yml dispatch
    (실행 정책 제한) → freeze 바인딩 → full L2 위임 → environment 확인 →
    `axiom-release-authority` App만 v* tag 생성"** 단일 경로로 전환한다.
    (a) ADR-0017 Amendment A1.3의 tag push 발화·수동 push 절차는
    **supersede**한다 (full L2 의무는 유지 — runner-pool workflow_call
    force_full+target_sha 위임). (b) `certification_continuity_contract.md`
    §10.2 GitHub App minter **재개를 승인**한다 (이연 사유였던 플랜 제약은
    org enterprise 실측 2026-09-26으로 소멸). (c) 결정 #1(CI 복구 방향)·
    #12(b)(named identity 금지 — P-rpool 명명 identity와의 상충을 ADR-0024가
    ratification)를 **갱신**한다. (d) 권위 모델 정확 문구(v* App-only, Release
    객체 creator는 GitHub native gate 부재)·부정적 정의([3])·provenance(peel)·
    2중 유일성·FAIL/UNCERTAIN 처리·단일 POST 실험 규칙·잔여 한계의 **전 문구는
    ADR-0024**가 수록하며, 본 기록은 결정만 서술한다. (e) 표면 v16:
    출하 워크플로·동 ADR·release boundary protocol **3경로를 개별
    등록**한다 (정확 경로 목록의 SSOT는 `config/repository_surface.json`
    v16 — 본 기록에는 경로를 옮겨 적지 않는다; 선례 #7·#8 — 신규 파일은
    본문 PR에서 추가되어 본 정책 PR 스냅 시점에는 미존재하는 것이 정상.
    정책 승격 PR → 본문 수정 PR 2단으로 착지).

16. **릴리즈 사전 제약 폐기 — v* 태그 자유화 (2026-09-26)** —
    태그 사용성이 릴리즈 엄격성보다 우선한다. (a) v* tag ruleset
    (`release-namespace-v`)의 namespace 예약과 App-only 생성 제약을
    **폐기**한다 — 모든 태그(v* 포함)를 개발자 milestone으로 허용하며,
    규칙셋 삭제는 본 결정의 플랫폼 단계로 수행한다. (b) 출하 인프라
    (release-ship.yml·axiom-release-authority App·release-authority
    environment·authority-first-P-ship·P-rpool workflow_call·Immutable
    releases)는 **제약이 아닌 선택 도구로 현상 유지**하며, 존치 여부는
    후속 결정으로 미룬다. (c) "태그 push → 무거운 CI 0회"는 유지한다
    (tag push 트리거 제거는 ADR-0024 Phase 2의 성과로 불변, A1.3 회귀 금지).
    (d) release-ship의 "기존 태그 없음" freeze 규칙은 현상 유지 — 사전에
    찍어둔 버전 태그가 있으면 그 버전 출하는 fail-closed로 거부된다.

17. **Surface trust 불변식 분리 — FROZEN을 실제 보호 경계로 축소 (2026-10-02,
    refactor/workstream-authority)** — 본 결정은 §목적의 trust 불변식 정의를 바꾸고
    정책 `policyVersion` 50 → 51로 확정한다. 경로 목록의 유일 권위는
    `config/repository_surface.json`이며 본 기록은 결정만 서술한다.
    (a) `defaultClass`를 `FROZEN` → **`PRODUCT`**로 바꾼다 — 미등록 경로는 일반
    코드로 취급하고 사전 등록을 요구하지 않는다. "모든 파일이 사전 목록화되어야 한다"는
    inventory 관리이지 trust 불변식이 아니기 때문이다.
    (b) `FROZEN`을 전 저장소 allowlist에서 **열거된 authority 경계**로 재정의한다
    (§FROZEN 표 참조). 보호 대상은 검증 엔진 자체, 집행 훅, 플랫폼 권위 정의,
    정책 임계·신원 결합이다. 해석 순서가 PRODUCT→CONTROLLED→FROZEN first-match이므로,
    FROZEN glob에 흡수되는 CONTROLLED 51건을 CONTROLLED에서 제거한다 — 잔존하는 한
    해당 경로(집행 지점 `.githooks/pre-push`와 본 정책 파일 포함)는 실제로는 동결되지
    않았다. 남은 144건의 CONTROLLED 의미는 불변하다.
    (c) `rules.FROZEN.DELETE`를 PASS → **FAIL**로 변경한다(§DELETE 규칙 변경 근거).
    결정 #3의 "DELETE 항상 허용" 전제는 default-FROZEN 구모델에 기댄 것이므로 열거된
    경계에는 승계되지 않는다. #3의 "대량 삭제 프로그램 금지" 결론은 **유지**된다.
    (d) `binding`(base-policy)과 `classResolutionOrder`는 **불변**이다 — 정책 변경과
    그것이 정당한 변경은 같은 PR에 함께 착지할 수 없다는 불변식은 이 축소의 대상이
    아니다. 이 결정 자체도 착지 전까지 효력이 없으며, 그 발효 시점은 policy PR 착지
    이후다.
    (e) §클로저 산출 명령의 broad wildcard 금지 관례는 유지한다 — FROZEN은 "그
    디렉터리 전체가 하나의 권위 표면"인 곳에서만 디렉터리 glob으로 폐쇄-기본을 얻는다.
    (f) §알려진 사각지대에 신규 5건을 기록한다 — 열거 밖 발명 표면, 게이트 규칙
    데이터 `src/policy/**`, 부채 원장, rename 암묵적 DELETE, base-policy 착지 지연.

18. **decision-authority 단일화 workstream 표면 6건 FROZEN → CONTROLLED 재등록
    (2026-10-03, policy/surface-v52-decision-authority)** — 사용자 승인 계획 v5
    (decision authority 단일화)의 SL-05 원자 페어·핀 회전·trusted admission workflow
    갱신이 위 6개 FROZEN 경로의 수정을 요구하므로, 정책 `policyVersion` 51 → 52로
    확정한다. 경로 목록의 유일 권위는 `config/repository_surface.json`이며 본 기록은
    결정만 서술한다.
    (a) `src/gate/slice_catalog.nim`·`src/gate/topology_spec.nim`·
    `src/gate/manifest.d/readiness-start-gate.json`·`config/policy/epoch_manifest.json`·
    `.github/workflows/admission-check.yml`·`config/trusted_writer_set.json` 6경로를
    FROZEN 열거·glob에서 제외하고 **CONTROLLED에 개별 등록**한다 — broad wildcard
    금지 관례는 유지하며, 나머지 FROZEN glob 14건은 불변이다.
    (b) 근거: v25/v26/v27이 이 경로들을 CONTROLLED로 선등록했다가 결정 #17(b)의
    FROZEN 축소 때 상위 glob 흡수로 실동결 상태가 되었다. 본 결정은 그 부분의 재개로,
    workstream 본문 PR이 base-policy v52를 merge하는 즉시 MODIFY가 PASS로 개방된다.
    (c) 정책 PR 자신은 FROZEN(본 정책 파일) 수정이므로 §DELETE 근거가 명시한 수용
    리스크 경로(`--no-verify`)로만 push 가능하다 — Owner 결정 #1 유지. 본문 PR에는
    `--no-verify`를 적용하지 않는다(base-policy self-authorizing 루프홀 차단 목적
    유지). 정책 PR의 감사 추적은 본 기록과 PR 본문이다.

19. **Authority 선언 — 결정권자·신뢰 뿌리·관측→차단 승격 규칙 확정 (2026-10-09,
    docs/authority-declaration, 개정 2026-10-10)** — "Authority 선언 + 관측 모드
    게이트" 슬라이스의 Slice 0(권한 선언)으로서, 관측 모드 게이트 체계의 권위를
    **기존 장치로의 등록**으로 확정한다 — 새 authority 장치는 만들지 않는다.
    authority·writer·device 3분리 상세 문구는 ADR-0033(`docs/adr/0033-authority-declaration.md`)
    이 수록하며 본 기록은 결정만 서술한다. 정책 `policyVersion` 71 → 72로 확정한다
    (재번호: v71은 PR #658이 선착지 소진 — v64=PR #555 후착 재기반 선례) — 신규
    정책 파일 `config/policy/observation_gates.json`(관측 스위치 기록)을 CONTROLLED에
    **선등록**한다(FROZEN glob `config/policy/**` 흡수 차단; 선례 v22 policy kind,
    2단계 = 본문은 후속 워크플로 배선 슬라이스에서 추가). 경로 목록의 유일 권위는
    `config/repository_surface.json`이다. **효력 개시 = 워크플로 배선 슬라이스 착지**
    — 승격 규칙·관측 표시·기록 계약 조항은 관측 러너 호출자가 배선되는 후속
    슬라이스에서 발화하며, 그 전까지는 선언(dormant)이다.
    (a) **결정권자(authority) = wintrover(인간 아키텍트)** — 에이전트는 기록·집행만
    담당하며 승인권이 없다. 에이전트 임시키 서명은 접근 제어가 아니라 사후 감사
    흔적이다(`tools/agent_bypass_sign.nim` 보안 모델 선례 — "cryptographic audit
    trail, not access control").
    (b) **신뢰 뿌리(trust root) 고정** — GitHub main ruleset 20303214(required
    check `admission-check` strict + `update`/`creation` 규칙 + merge queue)와
    blob-sha 핀 2종(`config/executor_authority.json` — mint-domain
    TrustedExecutorSet, `config/trusted_writer_set.json` —
    `trustedAdmissionWorkflowSha`·`trustedCheckerTreeClosure`)이 신뢰 뿌리다.
    신뢰 뿌리는 플랫폼 권위 + 콘텐츠 주소 핀으로 고정되며, 관측 오라클이 새로운
    신뢰 뿌리가 되는 것을 금지한다.
    (c) **승격 규칙(관측 → 차단)** — 관측 모드 게이트의 차단 승격은 다음을 모두
    만족할 때 Owner만 발동한다: ① 증거 = **N=3회 연속(순차) merge-group(MG) 라운드**
    — 라운드 = merge_group `checks_requested` 1건(서로 다른 G), 카운트 단위 = 런당
    1개 positive 라인 × 서로 다른 head SHA, 미관측·에러(OBSERVER-FAULT)·**취소·
    미발화** 라운드는 미계수 + **연속 단절**(UNKNOWN은 링크가 아니다 —
    §2.3·§4 fail-closed). N회 positive는 **WOULD-BLOCK 배출 부재(증거 클래스 E-A,
    저장소-상태 클레임)**만 증명하고 탐지력은 **음성 주입 시험(증거 클래스 E-B)**이
    담당하며 승격 증거는 두 클래스 모두 충족 시에만 인정한다 — **E-B는
    E-B-min(관측 슬라이스의 존재 증명 fixture)과 E-B-full(위반 클래스별 주입의
    전 클래스 완료)로 나뉘며 E-B-full은 차단 승격의 필수 선행 조건이다**(E-A만으로는
    탐지력 없는 게이트의 침묵과 구별 불가). 위반 클래스 유니버스는 게이트 검사
    목록에서 기계 유도하고, E-B fixture 디렉터리가 유일 원천이다(ADR-0033 상세).
    ② **wintrover의 명시 승인**. ③ **γ=STOP 재의결 조건** — WOULD-BLOCK 관측 시
    **Owner가 오탐/진양성을 판정**하고 **미판정 기본값은 승격 불가(fail-closed)**다.
    오탐 판정 시 승격 중단·재의결(단순 계수 리셋이 아님). **OBSERVER-FAULT 연속
    K=3 판정은 집계 명령(승격 증거 집계와 동일한 GET-only 명령 1개)이 계산하고 그
    출력 고정 라인이 마커**이며, 감시는 비필수 빨간 체크(자동) + 집계 명령(승격
    판단 시 Owner 필수 실행, 그 외 임의 재실행)이다 — 워크플로는 런마다 무상태이므로
    러너가 연속을 세지 않는다(개정 2026-10-10: "고정 라인 마커 + step summary로
    러너가 표시" 문구는 무상태 러너가 계수할 수 없다는 실측으로 폐기). 승격 증거의
    영속은 승격 PR이 N회 payload 전문 + sha256 + identity(gate|B|H, run_id, verdict)를
    `docs/evidence/`에 커밋하는 것으로만 성립한다(ADR-0022 D1 — run URL은 만료
    포인터로 격하).
    (d) **#13(6) 처분 — 관측 오라클의 authority 부인** — manifest-consistency
    관측 오라클은 authority를 주장하지 않는다(advisory 성격). 결정 #13(6)의
    "새 검증 workflow는 새 authority surface가 된다" 원칙에 따라, 관측 스위치
    정책(`config/policy/observation_gates.json`)은 관측 모드의 기록이지 새
    authority surface가 아니며, 관측 결과는 merge 권한을 부여·거부하지 않는다
    (§판정 계층 — Authority ≠ Adapter).

20. **관측 전용 워크플로의 #13(6) 해석 + 승격 비용 고지 (2026-10-10,
    docs/observer-contract-v73)** — 관측 슬라이스의 착지 경로를 확정한다.
    (a) **#13(6) 해석**: "required가 아니고 최상위 `permissions: contents: read`인
    관측 전용 워크플로는 authority surface가 아니다" — 권한을 실제로 부여하는 것은
    ruleset의 required 목록과 bypass=0이며 이는 플랫폼이 소유한다(결정 #13(6)의
    유지이지 개정이 아니다). 정책 `policyVersion` 73 → 74로 확정하고
    `.github/workflows/observation.yml`을 CONTROLLED에 선등록한다(2단계 = 본문은
    관측 워크플로 PR에서 추가).
    (b) **승격 비용 고지**: 차단 승격은 "결정 하나"로 끝나지 않는다 — required는
    1개 불변이므로 강제(enforcement)는 결국 `admission-check` 안으로 들어가야 하며
    그것은 **TWS 원자 페어 회전(그리고 창 가능성)을 부르는 판정 경로 배선 슬라이스
    를 수반**한다. Owner는 이 비용을 알고 승격을 판단한다. 단, 증거가 γ=STOP으로
    끝나면 그 배선 비용은 영영 발생하지 않는다.
    (c) **관측 신원 = 재유도**(사전 등록 없음): 계수 시
    `H:.github/workflows/observation.yml == B:.github/workflows/observation.yml`과
    `gateSourceBlobOid`(B 재유도)만 단언한다 — 고정 등록값을 두지 않는다(바이너리
    해시 등록은 소스 변경마다 회전하는 유지비 덫으로 기각).
    (d) **결손 원인 분류(2계층)**: 결손은 허용하되 전건에 원인이 기록되고 **원인
    불명 0건**이어야 한다. payload 내장 `fault_cause`(timeout/gate/toolchain) +
    run-level 분류(런 부재·`jobs==0`·cancelled=platform, 부재 ∧ 경과 ≥ 상한=timeout).
    판정 내용(verdict·violations·judgmentKey)만이 재실행 동일성의 단언 대상이다
    (binary sha 등 비결정 필드는 envelope).
    (e) **효력 개시 = 관측 워크플로(β2) 착지 후 첫 머지부터** — β2 자기 런은 B에
    파일이 없어 계수에서 제외된다(손실 1건). 감시 주체 = (c)의 집계 명령을 실행·
    기록하는 자(승격 판단 시 Owner 필수).

## 외부 근거 (AGENTS.md §0.5)

- https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets
- https://docs.github.com/en/pull-requests/how-tos/merge-and-close-pull-requests/troubleshooting-required-status-checks
- https://git-scm.com/docs/git-diff
