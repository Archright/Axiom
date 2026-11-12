# Judgment CAS REUSED HIT/MISS 근본 원인 — #611 HIT vs #613 MISS 실측 판정

> **성격**: 사고 분석(root-cause) 증거 — Judgment CAS의 REUSED HIT율에 관한 실측 모순
> (#611 사이클 HIT vs #613 사이클 MISS)의 원인 규명과 계약 불변식 판정.
> **정본 계약**: `docs/spec/test_judgment_cas_contract.md` (§4 9성분, §5 REUSED 5조건 —
> 본 분석으로 **v1.0.1 정정** 착지). **기구(code) 변경 0건** — 판정이 (ii) 정당한 무효화였다.
> **실측 창**: 2026-10-08T16:48–18:05Z (GitHub Actions REST · 런 로그 · 레저
> `refs/heads/axiom/evidence-cas` fetch) + 2026-10-09 로컬 (`git rev-parse` 트리 OID 재계산).
> **작성**: 2026-10-09. 브랜치 `docs/judgment-cas-reused-hit-root-cause`.

## 1. 실측된 모순

| 사이클 | PR-run | MG-run | 결과 |
|---|---|---|---|
| #611 (code fix) | 37811664465: plan `EXECUTED — no record for the current closure` → s1a fresh 310.5s → judgment append `b5b10096965b…` (17:04:02Z) | 37813905412 (10m54s): plan `REUSED — record b5b10096965b re-verified` → s1a 스킵, Lean 0회 | **HIT** |
| #613 (docs-only) | 37818247021 (10m43s): plan `REUSED — record 7468b24376a7 re-verified` (17:44:50Z) → s1a 스킵 | 37819660335 (14m43s): plan `EXECUTED — no record for the current closure (fresh judgment)` (17:56:25Z) → s1a fresh 재실행 | **MISS** |

"docs-only PR은 클로저가 같아야 한다"는 기대와 달리 #613의 MG 런이 재실행했다.

## 2. 원인 — 9성분 중 무엇이 달라졌나: **성분 ⑤ 하나뿐**

계약 성분 ⑤(피험 트리 identity)의 실제 원 계산 경로는 **B^{tree}**다 — 실행자/검증자 트리
(workspace root = B checkout, `admission-check.yml` judgment-plan 스텝의
`git rev-parse HEAD^{tree}`; 워크플로 주석 "the workspace root IS the B checkout — Gate A").
런별 실측값(로그 env 덤프 + 로컬 `git rev-parse` 일치 확인):

| 런 | 이벤트 | B (base) | tested tree ⑤ | plan 판정 | judgment 레코드 |
|---|---|---|---|---|---|
| 37811664465 | pull_request #611 | `347c1fc0` (pre-#611 main) | `e0ab44fd13b1…` | EXECUTED | append `b5b10096…` (fingerprint `ca7c197b…`) |
| 37813905412 | merge_group #611 | `347c1fc0` (main 무이동) | `e0ab44fd13b1…` | **REUSED b5b10096** | append exactly-once 0 (no-op) |
| 37815459591 | merge_group #612 | `685704829` (#611 병합) | `c00e7da049e9…` | EXECUTED | append `7468b243…` (fingerprint `55cf4ea8…`) |
| 37818247021 | pull_request #613 | `685704829` (base 스냅샷 동결) | `c00e7da049e9…` | **REUSED 7468b243** | append exactly-once 0 (no-op) |
| 37819660335 | merge_group #613 | `c2f486cb` (#612 병합 후 main) | `99e3e640741c…` | **EXECUTED (MISS)** | append `cbc4bdad…` (fingerprint `55cf4ea8…`) |

- **#611 HIT**: 두 레인의 B가 동일(`347c1fc0`) → 동일 클로저 → 동일 키.
- **#613 PR-run HIT**: PR base 스냅샷(`685704829`, 분기 push 시점 ~17:26Z 동결)이 #612 MG-run의
  B와 동일 → `7468b243` 재검증 성공. **docs-only PR 자체는 키를 움직이지 않는다** (H/G 트리 불입 실증).
- **#613 MG-run MISS**: `merge_group.base_sha`는 큐 생성 시점(17:50:28Z)의 main head =
  `c2f486cb` — 그 사이 **#612(fix(cert): 검증자 표면 코드 수정, 17:34:14Z 병합)가 착지**해
  B^{tree}가 `c00e7da0…` → `99e3e640…`로 전진. 차분 = #612의 5파일
  (`src/cli/cert_cli.nim` · `src/verification/certificate_verifier.nim` ·
  `docs/spec/cert_lifecycle_contracts.md` · `src/generated/build_metadata.json` ·
  `data/architecture_debt.json`) — `git diff 5e81acfd8994 62b76bcc3d88` 실측.
- 툴체인·env·recipe·소스 클로저는 양 레인 동일 (PR-run이 cross-run REUSED로 통합 실증;
  툴체인 fingerprint `55cf4ea8…` 양쪽 동일). 달라진 것은 **성분 ⑤뿐**이다.

## 3. 후보 원인 심판 (작업 지시 4건)

| 후보 | 판정 | 근거 |
|---|---|---|
| (a) git HEAD 바인딩 — 매 커밋 무효화 | **부분 기각** | 바인딩은 HEAD/H/G가 아니라 **B^{tree}**. PR 자체 커밋(docs 포함)은 키에 불입 — #613 PR-run의 cross-run REUSED가 실증. 무효화되는 것은 **main 측 커밋**(검증자 세대 전진)뿐 |
| (b) PR append 키 ≠ MG 조회 키 (파생 불일치) | **버그 아님 (기각)** | 양 레인 모두 **자기 B를 정확히 측정**했다. 서로 다른 B → 서로 다른 (올바른) 키. 파생 코드의 결함 없음 |
| (c) append 타이밍 레이스 | **기각** | 조회 대상 레코드(`7468b243`)는 consult(17:56:25Z) **23분 전**(17:33:11Z)에 원장 존재. 본 사이클은 애초 PR-run이 append 없이 REUSED(no-op) |
| (d) env 스냅샷 런간 드리프트 | **기각** | 양 레인 workspace 경로 동일(`/home/runner/work/Axiom/Axiom`), TMPDIR/PATH 축 동일 — cross-run REUSED가 env·recipe·핀 전체 일치를 증명 |

## 4. 판정: **(ii) 정당한 무효화 — 기구 수정 없음, 계약 문구 정정**

1. **무효화시킨 델타(#612)는 검증자 자신의 표면 코드 변경이다** (`ax cert verify` 진입점 —
   `cert_cli.nim` +55/−31, `certificate_verifier.nim`). 계약 §5(e) 도구 정체성은
   "B executor tree의 바이너리 identity" 일치를 REUSED의 필수 조건으로 요구하고, Gate A
   (자가인증 방지 — `build_sha==B`, "no self-build — authority 정규성 [B1]")이 그 이유다.
   새 검증자 세대에서 구세대 판정을 무재측정으로 넘기는 것은 계약 위반이며, 검증자 회귀가
   낡은 판정을 통과시킬 수 있는 극장 경로가 된다.
2. **작업 지시의 예시 수정("HEAD 바인딩을 실제 관찰 축으로 정정")은 #613을 HIT로 만들 수 없었다** —
   관찰 축(성분 1–4, 6–9)은 이미 양 레인에서 동일했고, 유일한 차원 ⑤를 축소하면
   #613은 "검증자 세대 변경을 넘는 재사용"이 돼 §5(e)를 깬다. 즉 관측된 MISS는
   어떤 축실한(faithful) verifier-identity 바인딩 아래에서도 동일하게 발생한다.
3. **계획 불변식 문구가 부정확했다**: "테스트가 읽지 않는 변경(docs 등)에는 closure가 같아야
   한다"는 절반만 참이다. 정정: **"테스트가 읽는 입력과 검증자 세대(B^{tree})가 같으면
   closure가 같아야 한다"** — main 측 커밋(docs 포함)은 세대를 전진시켜 세대당 1회의
   fail-closed 재측정을 유발하고, PR 자체 커밋은 클로저에 불입된다. 계약 §4 v1.0.1로 착지.
4. **잔여 보수성 여유(후속 후보, 본 사건 원인 아님)**: docs-only main 커밋도 B^{tree}를
   전진시킨다(검증자 바이너리 의미는 불변) — 세대당 1회의 과잉 재측정. §2.2 범위 폐쇄
   원칙에 따라 본 변경에서 다루지 않는다 (축소 시 §4/§5(e) 개정 + 회귀 드릴 필요).

## 5. 본 변경의 라이브 재실측 (예측 — falsifiable) — 실측 결과는 §7

본 PR은 docs-only이고 B = `62b76bcc`(#613 병합)로 고정된다. 원장 최신 judgment 레코드
`cbc4bdad…`의 세대는 `99e3e640…`(#612 세대)이므로:

- **예측**: PR-run = `EXECUTED — no record for the current closure` → s1a fresh 실행 + append;
  MG-run = B 동일(`62b76bcc`) → **`REUSED` (Lean 0회) — #611과 동일 형상의 HIT**.
- 세대 내 안정성 부수 예측: 같은 세대에서 docs-only 커밋을 추가 재푸시하면 PR-run도
  `REUSED`로 전환한다 (성분 1–9 전체 불변).
- 위배 시(예: 측정창 내 툴체인 재회전, 타 PR 선복합)는 §2 표의 축이 그대로 설명한다 —
  세대 축의 추가 이동.

## 6. 재현 명령

```
gh api repos/Archright/Axiom/actions/runs/37811664465 --jq '{event,head_branch,created_at}'
gh api repos/Archright/Axiom/actions/runs/37819660335 --jq '{event,head_branch,created_at}'
gh api repos/Archright/Axiom/actions/runs/<id>/logs -H "Accept: application/vnd.github+json" > run.zip
unzip -p run.zip "*.txt" | grep -a "AXIOM_JUDGMENT_CAS:"                 # plan 라인
unzip -p run.zip "*.txt" | grep -aE "^AXIOM_JUDGMENT_CAS_TESTED_TREE_OID" # 실측 B^{tree}
git fetch origin 'refs/heads/axiom/evidence-cas:refs/remotes/origin/ecas'
git log --format='%H %cI %s' origin/ecas | head -12                      # append 타임라인
git rev-parse c2f486cbf070069dc52dcfd7fc6bf97d8ba5e77c^{tree}            # = 99e3e640741c…
git diff 5e81acfd8994 62b76bcc3d88 --stat                                # #612 차분 5파일
```

## 7. 라이브 재실측 결과 — 본 변경 착지 사이클 (2026-10-08 22:43–23:25Z 실측)

본 문서를 착지시킨 사이클(#615)과 동시대 사이클(#614)의 런 로그·원장 실측. §2의
세대 축(B^{tree})이 모든 판정을 예측한 대로 설명한다.

| 사이클 | 레인 | 런 | B (base) | tested tree ⑤ | plan 판정 | s1a | judgment 레코드 |
|---|---|---|---|---|---|---|---|
| #614 PR | pull_request | 37855296277 | `62b76bcc` | `e82c720a…` | EXECUTED (22:48:55Z) | fresh | **append `fa6282ba…`** (22:56:19Z) |
| #614 MG | merge_group | 37856697279 | `62b76bcc` | `e82c720a…` | **REUSED `fa6282ba`** (23:03:46Z) | **스킵 — Lean 0회** | no-op 0 |
| #615 PR (본 문서) | pull_request | 37855875817 | `62b76bcc` | `e82c720a…` | EXECUTED (22:54:43Z) | fresh | mint no-op 0 — `fa6282ba`는 consult 96초 후 #614가 append (경합, exactly-once 유지) |
| #615 MG (본 문서) | merge_group | 37857801048 | `18bb557f` (#614 병합 — **새 세대**) | `7601c375…` | EXECUTED (23:14:31Z) | fresh (`basis=EXECUTED — fresh judgment measured`) | **append `086987c4…`** (23:24:21Z) |

**판정**:

1. **#614 사이클 = #611 형상 HIT의 라이브 재실측** — PR-run `EXECUTED`+append → MG-run
   `REUSED — record fa6282ba13b0 re-verified (closure re-derivation + executionEpoch +
   per-read re-hash all passed)`, s1a 스킵(Lean 0회). 핀 회전 후 세대(`e82c720a`)에서
   제3 사이클로 재현 — §5의 주 예측 적중.
2. **#615 MG는 §5의 "위배 시" 예측 케이스 그대로** — 큐 진입(23:09Z) 전 #614 병합(23:0xZ)으로
   base가 `62b76bcc`→`18bb557f` 전진 → 새 세대 fail-closed 재측정. 모순이 아니라
   §4 세대 스코프 불변식의 적중이며, #613 사이클과 동일 기구의 재현이다.
3. **동시 세대 경합의 원장 정합성**: #614 PR-run과 #615 PR-run이 같은 세대 같은 키
   (`fa6282ba`)로 경합 — 늦은 consult(#615)는 정당히 `no record`→EXECUTED, 늦은 mint는
   `idempotent no-op (already stored, append exactly-once: 0)`. 원인 후보 (c) 타이밍
   레이스의 재반증이자 exactly-once 원장 불변의 라이브 실증: 경합이 있어도
   fail-closed + exactly-once 외의 결말은 없다.
4. 세대당 원 실행 1회 + 이후 재사용(§4 v1.0.1 불변식)이 관측된 전체 판정 분포
   (EXECUTED 3건 · REUSED 1건, 모두 세대 축으로 설명)와 정합한다.
