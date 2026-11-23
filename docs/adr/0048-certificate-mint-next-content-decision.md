# ADR-0048: `certificate-mint.yml`의 다음 content 승인 여부 — DEBT#554 fail-open 경로의 레인 결정

## Status

**Accepted — 옵션 2 (trust ceremony) 채택, 옵션 1 기각 (2026-11-23)**

- **일시·권한**: 2026-11-23 — 저장소의 단독 아키텍트(`wintrover` —
  `@Archright/architect` 단독 멤버)가 **현 세션에서 본 결정 기록 작업 전반에 부여한
  포괄 승인**을 결정 근거로 기록한다. 이 승인은 세션 단위 포괄 승인이지 서명·날인된
  문서가 아니다 — 본 기록은 서명 아티팩트를 주장하지 않고, 독립적인 두 번째 승인자나
  위원회를 주장하지 않는다(§0.9 honest-executor; 같은 기록 관행:
  `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:21`).
- **결정 내용·효과**:
  1. **옵션 2 채택** — `.github/workflows/certificate-mint.yml`의 **다음 수용
     content**를 확정하는 trust ceremony를 수행하고, 그 위에서 PR #293을 재개한다
     (§3.2).
  2. **옵션 1(핀 전진)을 명시적으로 기각**한다 — 사유는 §3.1의 실측 두 가지다.
  3. **옵션 3(wontfix)을 채택하지 않는다** — 사유는 §3.3. 조용히 3을 고르지 않는다.
  4. **DEBT#554는 Open으로 유지**된다 — 본 문서는 `docs/DEBT_REGISTRY.md:263`과
     `data/debt_registry.json`을 수정하지 않는다.
- **경계 불변**: 본 문서의 수용은 워크플로·정책·스키마·핀·레지스트리 어느 것도 바꾸지
  않는다. ceremony와 그 착지는 본 ADR과 **독립된 break-glass + epoch rotation**이며,
  본 ADR의 착지는 fail-open을 고치지 않는다 — `:2272`·`:2286`의 `2>/dev/null`
  파이프라인은 본 문서 머지 후에도 그대로 live다(실측: §2.1). 본 문서 작성 PR은
  `docs/adr/**` 1파일 추가이고, 그 경로는 `config/policy/merge_admission.json`의
  trustSurface 39항목에 없고(같은 파일의 `docs/adr` 문자열은 `:4` description 산문에만
  등장), `config/policy/trust_surface_manifest.json` 18경로에 없고(0건),
  `config/trusted_checker_closure.json`의 `trustedCheckerTreeClosure` 891항목에
  0건이며, `src/cli/merge_cli.nim:1036`에서 회전 allowlist
  (`RotationAdrGlob = "docs/adr/**"`, `:228`)로 허용된다. 따라서 본 PR은 일반 lane이다.

## 0. 추적 (Tracking)

- **이슈 #384** — 본 결정의 정식 추적 이슈(Open). 본 문서는 이슈를 닫지 않는다.
- **DEBT#554** — `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`,
  **Open**). 이 드리프트의 결정 대기 상태 정식 추적 엔트리이며, 본 문서는 레지스트리를
  수정하지 않는다. 해소는 §0.1의 3번이 착지한 뒤 6번에서 기록된다.
- **결정 쌍**: 본 문서는 ADR-0049(`config/trusted_writer_set.json`의
  `trustedWriterJobs` 필드 수용 여부)와 같은 세션의 결정 쌍이다 — 두 대상 모두 18경로
  manifest의 구성원이므로 실행 레인 형태가 같다.
- 측정 기준: origin/main **5b14bbfc** (2026-11-23). 아래 모든 사실은 읽기 전용
  관측이며, 본 문서 작성 PR은 파일 1건(본 문서)만 추가한다.

### 0.1 미실행 실행 단계 (전수)

이 표가 이슈 #384를 작업 손실 없이 닫을 수 있게 하는 tracker다. **아래 단계 중
실행된 것은 하나도 없다.**

| # | 미실행 실행 단계 | 변경되는 아티팩트 | 레인 |
|---|---|---|---|
| 1 | App accepted manifest의 **소유자 지정** — ADM-01은 "이 저장소 어디에도 소유자가 기록돼 있지 않다"고 기록한다(`docs/evidence/trust_surface_ratification_366_2026-11-23.md:78-79`) | out-of-tree App(`axiom-admission-verifier`, 5795152) accepted manifest — 저장소 파일 아님 | **권한 결정** (break-glass도 rotation도 아닌 선행 조건) |
| 2 | **다음 수용 content 확정** — `certificate-mint.yml`이 수용될 정확한 bytes와 그에 대응하는 App accepted 상태를 한 쌍으로 고정 | `docs/evidence/` 신규 기록 1건 | 일반 PR (문서) |
| 3 | **DEBT#554 fail-closed 수정** — `:2272`·`:2286`에서 `2>/dev/null` 폐기, 출력 해석 전 `ledger-list` exit 0 요구(bounded retry, 소진 시 fail-closed), unreadable과 absent를 분기 조건에서 구분 | `.github/workflows/certificate-mint.yml` (bytes) | **break-glass + epoch rotation** |
| 4 | **epoch rotation 기록** — 2번에서 확정한 content를 새 epoch로 전진시키고 회전 사실을 기록 | App accepted manifest 전진 + `docs/evidence/` 회전 기록 | **epoch rotation** |
| 5 | **#293 재개** — 새 base로 rebase, 새 preflight, 새 landing-venue run(현 판정은 head `59640ca3`에 고정) | PR #293 | 착지 후 일반 lane |
| 6 | **DEBT#554 상태 갱신** | `docs/DEBT_REGISTRY.md:263` + `data/debt_registry.json` | 일반 PR (registry는 trust surface 구성원이 아니다) |
| 7 | **ADR-0049 실행과의 순서 결속** — 두 ceremony가 같은 epoch에 겹치면 3·4번과 ADR-0049 §0.1의 1번을 하나의 회전 기록으로 합친다 | 3·4번 아티팩트 + ADR-0049 §0.1 | **break-glass + epoch rotation** |

- **앵커 불변**: 이 회전은 `trustedWriterWorkflow`(경로)도
  `trustedAdmissionWorkflowSha`(`admission-check.yml` blob)도 바꾸지 않는다 —
  `certificate-mint.yml`은 그 두 앵커 필드의 대상이 아니고 경로도 그대로다. 따라서
  회전은 **수용 content 확정 + App accepted manifest 전진**이며 TWS 앵커 재기록이
  아니다. 이 구별은 ADR-0042의 값/경로 구분
  (`docs/adr/0042-trust-epoch-closure-split.md:109-111`)에 따라 회전 기록에 명시돼야
  한다.
- **3번 완료 전까지** `:263`은 Open이고 fail-open은 live다. 1·2번이 3번의 선행
  조건이므로, ceremony의 첫 blocker는 코드가 아니라 **소유자 지정**이다.

## 1. 질의 (Query)

`.github/workflows/certificate-mint.yml`은 다음 content로 전진할 수 있는가 — 전진이
허용된다면 어떤 레인으로, 어떤 순서로?

이 질의에는 코드 수정의 자유도가 없다. PR #293의 diff는 그 파일 **1건**(+40/−5)이며
(`touched=1`, §2.5), 이슈 #384의 split check는 "the whole PR is the protected file"로
음성 판정됐다. 따라서 "정책 결정과 분리 가능한 코드 수정"이라는 선택지가 존재하지
않는다.

## 2. 관련 사실 (Facts)

### 2.1 fail-open의 실측 위치

```
:2272  if ( cd "$B_CHECKOUT_DIR" && bin/ax cert ledger-list 2>/dev/null | grep -qx "$SUBJECT_ID" ); then
:2286  if ( cd "$B_CHECKOUT_DIR" && GITHUB_TOKEN="$GITHUB_TOKEN" bin/ax cert ledger-list 2>/dev/null | grep -qx "$SUBJECT_ID" \
```

- 파이프라인의 종료 상태는 `ledger-list`가 아니라 `grep`의 것이다. `2>/dev/null`이
  transport/auth/5xx 실패를 폐기하고, `grep`은 빈 입력에 exit 1을 낸다. 그 결과 else
  분기(`:2279-2280`)가 `bin/ax cert ledger-append`를 호출한다 — **읽기 실패가 "부재"와
  구별되지 않는다.**
- `:2286`은 append 실패 후의 reconciliation leg다. 같은 파이프라인 형태이므로 같은
  결함을 공유한다.
- 레지스트리 원문은 이 지점을 `:2263`으로 인용한다(`docs/DEBT_REGISTRY.md:263`).
  실측 현재 행은 `:2272`다 — 인용 행 번호가 +9 드리프트했고, 현재 `:2263`은
  `[ -x "$ax" ] || fail "B-built bin/ax missing at $ax"`다. 본 문서는 **실측 행
  번호**를 쓴다.

### 2.2 부채 추적 상태

- DEBT#554 = **Open**, `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`).
- 같은 행이 remediation 방향을 이미 명시한다: "run ledger-list without discarding
  stderr, require exit 0 before interpreting output (bounded retry on transient failure,
  fail-closed on exhaustion), and distinguish unreadable from absent in the branch
  condition." 본 ADR은 새 수정 방향을 발명하지 않는다 — §0.1의 3번은 이 문장의 실행이다.
- DEBT#553(첫 시도 유일성)은 PR #297로 수정됐다(`:263` 인용). 따라서 잔여 실패 모드는
  **영구 중복이 아니라 "혼란스러운 중복 append 시도 후 중단"**이다. 결함의 크기가
  줄었다는 사실은 결함이 사라졌다는 뜻이 아니다 — 조용한 오독은 그대로다.

### 2.3 보호 표면 — 세 목록 모두에서 확인

| 목록 | `certificate-mint.yml` |
|---|---|
| `config/policy/trust_surface_manifest.json` (18경로) | **`:12`** |
| `config/policy/merge_admission.json` trustSurface (39항목) | **`:82`** (index 3) |
| `config/trusted_checker_closure.json` (`trustedCheckerTreeClosure`, 891항목) | **0건** — 워크플로는 closure member가 아니다 |

세 목록 중 앞의 둘이 이 결정의 레인을 규정한다. 세 번째가 0건이라는 사실은 회전
allowlist 계산에만 영향을 준다(§Status 경계 불변).

### 2.4 manifest 계약 — 왜 "핀"이 아니라 "blob"인가

- `:3` — "Execution surface that must be byte-identical between a merge-group commit G
  and its base B_mg. **A PR that alters any listed path cannot receive the independent
  verifier's admission-check; such changes require the audited break-glass lane and an
  explicit epoch rotation.**"
- `:4` — `"comparison": "blob-based: every path's Git blob SHA at G must equal its blob
  SHA at B_mg"`
- `:5` — `"readFrom": "B_mg (merge_group.base_sha), never from G"`

계약의 비교 대상은 **manifest의 개정 번호가 아니라 경로별 blob**이며, 기준값은
G가 아니라 B_mg에서 읽는다.

### 2.5 App 실측 — #293 판정 원문

이슈 #384가 인용한 App verdict(원문):

```
venue=pull_request
head=59640ca354b3f6862c40412a634c1819e5987ed9
base=1ce9ac26d70ede9fcb1ba70c6fcdf47e81e463a5
evaluated_commit=59640ca354b3f6862c40412a634c1819e5987ed9
run=44900423461 attempt=1 conclusion=success
trust_surface=FAIL — venue=pull_request manifest_ref=e22f4eb touched=1 manifest_touched=1
  diff_base=05139b3
  reasons=mismatch:.github/workflows/certificate-mint.yml
ledger=not-required(preflight venue)
```

- **`manifest_touched=1`이 결정적이다**: App은 그 경로를 집행 대상으로 **실제
  포함**했다. 거부 사유는 핀 불일치가 아니라 그 경로의 **blob 미스매치**다.
- `touched=1` — PR의 diff는 그 파일 1건이다. 분리 가능한 두 번째 파일이 없다.
- ruleset 사실: `bypass_actors: []`, `current_user_can_bypass: "never"` (이슈 #384) —
  bypass는 존재하지 않는다.

### 2.6 App 집행 집합 ≠ in-repo 배열, 그리고 소유자 UNKNOWN

- `docs/evidence/trust_surface_ratification_366_2026-11-23.md:40-43`은
  `manifest_touched=0`인 trustSurface 착지 2건을 기록한다: "The App's enforced manifest
  and the in-repo 39-entry `merge_admission.trustSurface` array are **not the same
  set**: a change to a `trustSurface` member that is absent from the App manifest passes
  `admission-check`."
- 같은 문서 `:70-79`(ADM-01): "It needs a named owner for
  `axiom-admission-verifier`'s accepted manifest. No such owner is recorded anywhere in
  this repository, so the owner is **UNKNOWN** here."
- 함의 두 가지. (a) in-repo 계약(`:4`–`:5`)은 어떤 manifest 참조로도 우회되지 않는다.
  (b) App 쪽 레버는 이 저장소에 **소유자가 없다**.

## 3. 옵션 (Options)

### 3.1 옵션 1 — App의 `manifest_ref` 핀을 전진 (기각)

측정된 사실이 이 옵션을 제거한다.

1. **비교 대상은 핀이 아니라 blob이다.** `:4`는 `blob(G) == blob(B_mg)`를 요구하고
   `:5`는 기준을 B_mg에서 읽는다. PR #293의 diff는 그 경로 1건이므로(`touched=1`)
   `blob(G) ≠ blob(B_mg)`가 성립한다 — B_mg는 정의상 그 변경 **이전**의 base다.
   어떤 `manifest_ref` 값을 넣어도 이 등식은 참이 되지 않는다.
2. **계약이 in-band 경로를 원리적으로 배제한다.** `:3` — "A PR that alters any listed
   path cannot receive the independent verifier's admission-check." 목록 경로를 바꾸는
   PR은 *어떤 핀 상태에서도* admission-check을 받을 수 없다. 즉 옵션 1은 **파일이 이미
   B_mg에 착지한 뒤에만** 성립하는 순환 조건이다.
3. **옵션 1의 유일한 지렛대는 이 저장소 밖에 있다.** `manifest_ref`는 App verdict에만
   등장하는 out-of-tree 값이고, 이 저장소의 계약 파일에는 그 필드가 없다(부재). 그
   accepted manifest의 소유자는 UNKNOWN이다(ADM-01, `:78-79`). 실행자조차 지정되지
   않은 조작이다.
4. **`manifest_touched=1`이 "App이 이 파일을 모른다"는 해석을 반증한다.** 거부는
   인식 부재가 아니라 byte 불일치다.

이슈 #384는 옵션 1을 조건문으로 제시했다 — "If the `e22f4eb` pin is the only obstacle,
this is the whole fix." §2.5의 `manifest_touched=1`과 `:4`–`:5`는 그 조건이 **거짓**임을
측정한다.

### 3.2 옵션 2 — trust ceremony + #293 재개 (채택)

- **ceremony가 없으면 승인할 대상이 정의되지 않는다.** "다음 content"는 문서가 아니라
  **bytes와 그에 대응하는 App accepted 상태의 쌍**이고, 그 쌍을 확정하는 행위가
  ceremony다. 이 확정 없이 break-glass를 열면 무엇을 승인했는지 기록되지 않는다 —
  그것이 §0.9가 금지하는 형태(보장하는 척하는 착지)다.
- **수정 방향은 이미 등록돼 있다.** `:263`이 요구하는 세 항목(§2.2)이 곧 3번 실행
  단계다. 본 ADR은 수정 내용을 새로 정의하지 않고, 그 수정이 **착지 가능한 상태**를
  만드는 절차만 결정한다.
- **레인은 문서화돼 있다** —
  `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md:10`과 `:38-41`:
  병합 **전** MUST-T2a 위임 기록을 PR 코멘트로 등록, 두 ruleset(`27097366` `main`,
  `27525972` `main-admission`) 스냅샷, **두 ruleset 동시** bypass(하나만으로는 merge API
  405), REST native merge, 직후 원복과 `bypass_actors=[]` 재조회 확인. 본 ADR은 이
  형태를 새로 정의하지 않고 그대로 참조한다.
- **정직한 한계**: ceremony는 fail-open을 고치지 않는다. 고치는 것은 3번이다. ceremony는
  3번이 착지할 수 있는 상태를 만들 뿐이며, 그 구별이 §0.1의 표에 남아 있다.

### 3.3 옵션 3 — wontfix (채택하지 않음)

- `:263`은 **sole privileged publisher**에서 read-failure-as-absent 경로를 기록한다.
  이 경로가 열려 있으면 ledger read 장애가 "부재"로 해석되어 `ledger-append`로
  진입한다(`:2279-2280`). DEBT#553 수정 이후 잔여 모드는 "혼란스러운 중복 append 시도
  후 중단"이지만, 그 실패는 여전히 **조용한 오독**에서 시작한다.
- wontfix를 택하면 이 항목은 "pending work처럼 보이는 accepted risk"로 **재등록**되어야
  한다(이슈 #384 "What closing PR #293 does not decide"). 그 재등록은 별도 결정이며
  본 ADR은 하지 않는다.
- 또한 옵션 3은 fail-open을 **영구**로 만든다 — 파일이 frozen인 한 수정 경로가 없기
  때문이다. 그 거래는 명시적이어야 하고(이슈 #384), 본 ADR은 그 거래를 승인하지
  않는다. 따라서 3을 조용히 고르지 않는다.

## 4. 결정 (Decision)

**결정(한 문장)**: `.github/workflows/certificate-mint.yml`은 다음 content로 전진할 수
**있다** — 단 그 전진은 (i) 다음 수용 content를 확정하는 trust ceremony와 (ii) audited
break-glass + epoch rotation으로만 일어나며, 핀 전진(옵션 1)으로는 일어나지 않는다.

### 결과 (Consequences)

1. **DEBT#554는 Open으로 남는다.** 본 ADR은 fail-open을 고치지 않는다. 상태 갱신은
   §0.1의 6번이다.
2. **#293은 ceremony 전까지 도달 불가다.** ceremony 후에도 rebase가 필요하다 — 현 판정은
   head `59640ca3`에 고정돼 있고, 새 base는 새 preflight와 새 landing-venue run을
   요구한다(이슈 #384 "Reopen condition").
3. **옵션 1 기각은 재사용 가능한 판례다.** trust surface 목록 경로를 바꾸는 PR에 대해
   "핀을 전진하면 통과한다"는 형태의 요청은 이 ADR을 근거로 기각된다. 재론은 새 결정이다.
4. **미해결 선행 조건이 하나 남는다.** App accepted manifest의 소유자 UNKNOWN(ADM-01,
   `:78-79`). ceremony는 그 소유자 없이는 완결되지 않는다 — §0.1의 1번. 이 조건은
   코드로 해소되지 않는다.
5. **앵커는 움직이지 않는다.** 이 회전은 `trustedWriterWorkflow`(경로 불변)도
   `trustedAdmissionWorkflowSha`(`admission-check.yml` blob)도 바꾸지 않는다.
   `certificate-mint.yml`은 그 두 앵커 필드의 대상이 아니다. 회전 기록은 이 구별을
   명시해야 한다(ADR-0042의 값/경로 구분,
   `docs/adr/0042-trust-epoch-closure-split.md:109-111`).
6. **결정의 효력 범위는 레인 하나다.** 본 ADR은 "전진이 허용된다"와 "허용되는 레인은
   break-glass + epoch rotation이다"만 확정한다. 수정 내용·시점·실행자는 확정하지
   않는다.

## 5. 결정 권한·절차 (Decision authority and procedure)

- **판정 권한**: 저장소 단독 아키텍트. 본 문서는 그 승인의 기록이며 결정을 대리하지
  않는다.
- **근거**: AGENTS.md §0.10 결정 바인딩(변경은 커밋된 결정/정책에 구속, waiver 없는
  우회 금지); §2.3(merge-admission의 authority는 GitHub — required checks 0건은
  UNKNOWN/NOT READY로 해석하며 SUCCESS로 승격하지 않는다);
  `config/policy/trust_surface_manifest.json:3`(break-glass + epoch rotation 요구).
- **절차**: 본 ADR 착지 → §0.1의 1·2(소유자 지정, content 확정) → 3·4(break-glass +
  epoch rotation) → 5(rebase·재심사) → 6(registry 갱신). **어느 단계도 본 ADR 착지에
  포함되지 않는다.**
- **본 문서는 종결이 아니다**: DEBT#554는 Open, ceremony는 미실행, 이슈 #384는 Open으로
  남는다. 본 문서의 착지는 그 대기 상태의 정본화다.

## References

- 이슈 **#384** — "policy(trust-surface): decide whether certificate-mint.yml may
  advance (DEBT#554 fail-open path)" (Open)
- DEBT#554 — `docs/DEBT_REGISTRY.md:263` (Medium, `CI/Pipeline Health`, **Open**)
- `.github/workflows/certificate-mint.yml` — `:2272`, `:2279-2280`, `:2286`
- `config/policy/trust_surface_manifest.json` — `:3`, `:4`, `:5`, `:12` (18경로)
- `config/policy/merge_admission.json` — `:82` (trustSurface index 3, 39항목)
- `config/trusted_checker_closure.json` — `trustedCheckerTreeClosure` 891항목
  (`docs/adr` 0건)
- `src/cli/merge_cli.nim` — `:228` (`RotationAdrGlob`), `:1036` (allowlist 적용)
- ADR-0042 — `docs/adr/0042-trust-epoch-closure-split.md:109-111` (값/경로 구분)
- ADR-0049 — `docs/adr/0049-trusted-writer-jobs-field-decision.md` (결정 쌍)
- break-glass 레인 선례 — `docs/evidence/breakglass_trust_surface_landing_2026-11-19.md`
  `:10`, `:21`, `:38-41`
- ADM-01 / App 집행 집합 — `docs/evidence/trust_surface_ratification_366_2026-11-23.md`
  `:40-43`, `:70-79`