# nimtry 옵션 A 범위 정정 — SAFETY-language-ban 36건의 기원 귀속·실효 감축 범위 erratum (2026-11-02)

> **종류**: erratum (정정 기록). **이 문서는 결정을 대리하지 않고, 유도하지도 않는다.**
> **정정 대상**: `docs/evidence/nimtry_ratchet_budget_request_2026-11-02.md` (PR #1190, GitHub native
> MERGE `7257d1209`) — §2("14 resolved" 관측), §4 옵션 A(기원 귀속·감축 수치 후보·consumer 미측정 고지).
> **원문 취급**: 원문은 **수정하지 않는다** — 정착 기록 불변·git 이력 보존. 본 문서는 참조로만 연결되며,
> 원문과 본 문서가 함께 1개의 기록 세트를 이룬다.
> **지위**: 계약·정책·게이트 변경이 아니다 — `docs/evidence/` 기록 문서이며 어떤 게이트도 본 문서를
> 소비하지 않는다(원문과 동일 지위, trust surface 무접촉).
> **범위**: 본 문서 1건 — `data/`·게이트 코드·Makefile·`.github/**`·원문 수정 0건.
> **D2 지위 불변**: 감축 예산(옵션 선택·목표 수치·시점)의 결정 권한은 여전히 **인간 전용**이다. 본 문서는
> 사실만을 정정하며 어느 옵션도 권고하지 않는다(§7).
> **Date**: 2026-11-02 · **Branch**: `work/d2-nimtry-option-a-erratum` (worktree off `origin/main` @ `291cb2f08`)
> **측정 기준선**: origin/main `data/nimtry_baseline.json` (version 2, total_violations 4263)

---

## §1. 정정 요약 (원문 기술 → 실측 → 판정)

| # | 원문 위치 | 원문 기술 | 실측 (2026-11-02 전수 조사) | 판정 |
|---|---|---|---|---|
| 1 | §4 옵션 A — "재앵커 신규 22건은 float_acceptance nimble fixture 14 · rust probe fixture 6(`.llbc` 2 + `.rs` 4) · workflow jq contract `.jsonl` 2 (PR #1178/#1179 기원, `90604006e` 본문)" | 22건의 착지 기원을 PR #1178/#1179로 귀속 | `.nimble` 14건은 어떤 PR·커밋에도 착지하지 않은 비tracked 로컬 생성물(`git log --all`에서 해당 경로 추가 커밋 **0건**). 실제 착지: rust 6 = PR **#1177**(`b6b085ff2`, u64 2건) + PR **#1174/#1176**(`3820bbe9d`, impl 4건), `.jsonl` 2 = PR **#1169**(`3220298e8`) | **기각** — #1178/#1179는 이 파일들의 착지 PR이 아니다 |
| 2 | §2 — "`baseline(4263) 대비 14건이 anchor 후 자연 해소`된 상태로 관측" | 해소 원인 미규명(관측 표기만 존재) | 위 14건이 origin/main 트리에 부재(`.gitignore:57` `tests/**` 하의 비tracked) → **재측정만으로 자동 소멸**. 재앵커가 실행된 워크트리에 존재한 파일의 지문이 anchor된 것 | **원인 규명** — 관측 자체는 정확, 해소는 조치 결과가 아닌 측정 대상 부재 |
| 3 | §4 옵션 A — "감축 수치 후보: **−36** (총량의 0.8%; error 384 중 9.4%)" | −36 단일 수치 제시 | **−22 지속**(consumer 있음 21건 + `.txt` 1건 무참조) + **−14 자동 소멸**(`.nimble`, 트리에 부재) | **수정** — 실효 감축 범위는 −36이 아니라 −22 지속분 기준 |
| 4 | §4 옵션 A — "(ii)는 fixture 경로에 의존하는 consumer의 존재 여부를 본 문서에서 측정하지 않았다" | 미측정 고지 | 전수 측정 완료 — 21건이 다층 경로로 고정(file:line 근거, §4), `.txt` 1건은 참조 0건 | **갱신** — 미측정 상태 해소 (판단은 여전히 인간) |
| 5 | §4 옵션 A — 확장자 분포의 "dir-level 1" | dir-level 1 | `src/generated/build_env.nim.default` — 디렉터가 아니라 **실존 파일** | **표기 정정** |

원문 §4의 **확장자 분포 자체(`.nimble` 14, `.rs` 6, `.llbc` 4, `.yml` 7, `.jsonl` 2, `.py` 1, `.txt` 1, 나머지 1)는 전수 재계산에서 그대로 확인됐다** — 정정되는 것은 기원 귀속과 실효 범위 해석이다.

## §2. 정정 사실 1 — 기원 귀속 기각 (파일 단위 실측)

기준선(origin/main baseline 4263건)에서 `rule=SAFETY-language-ban` 36건(전부 error)을 추출하고,
36개 경로 전수에 대해 `git log --all`로 경로별 추가(착지) 커밋을 추적했다.

**재앵커 신규 22건의 실제 소속**:

- **`.nimble` 14건 — 미착지(비tracked 로컬 생성물)**: `tests/golden/float_acceptance_subject_{sem,tplwrap,varparam,witness,recvraise}/minifloat.nimble` + 각 `textio/textio.nimble` (10건), `tests/negative/float_acceptance_{tpl_no_raise,varparam_mismatch}_subject/minifloat.nimble` + 각 `textio/textio.nimble` (4건). `git log --all`에서 해당 경로의 추가 커밋 **0건** — 어느 PR·커밋에도 착지하지 않았다. 재앵커(`90604006e`)가 실행된 워크트리에 비tracked로 존재하던 파일이 스캔 대상(`src/gate/nimtry/safety_queries.nim:506`의 스캔 루트 `src/`·`tests/`는 파일시스템 walk이므로 비tracked 파일도 포함)에 들어가 그 지문이 anchor됐다.
- **rust 6건 — 착지 확인**: u64 2건(`axiom_u64_probe/src/lib.rs`, `axiom_u64_probe/axiom_u64_probe.llbc`) = PR **#1177** (`b6b085ff2`); impl 4건(`axiom_impl_probe/src/{lib,m1,m2}.rs`, `axiom_impl_probe/axiom_impl_probe.llbc`) = PR **#1174/#1176** (`3820bbe9d`).
- **`.jsonl` 2건 — 착지 확인**: PR **#1169** (`3220298e8`).

즉 **PR #1178/#1179는 이 22건의 착지 PR이 아니다**(일부는 해당 파일들의 조상 병합일 뿐). 원문 §4 및
재앵커 커밋 `90604006e` 본문의 기원 귀속은 파일 단위 실측과 불일치한다.

**재앵커 이전 원 anchor 소속(36 − 22 = 14건)**:

| 항목 | 건수 | 소속 | 커밋 |
|---|---|---|---|
| guard | 2 | #919/920 시기 | `c43e77faa` |
| rust_probe | 2 | feat/rust-subject-v1 | `5444b3b3c` |
| `.py` | 1 | PR #957 | `c579af063` |
| `.txt` | 1 | act2-external-verification | `9e4f3b2a9` |
| `.yml` | 7 | 각 workflow self-test 시리즈 | (시리즈별) |
| `.default` | 1 | 빌드 부트스트랩 시리즈 | (시리즈별) |

## §3. 정정 사실 2 — 옵션 A 실효 감축 범위

원문의 "감축 수치 후보 −36"은 다음과 같이 정정된다: **−22 지속 + −14 자동 소멸**.

| 분류 | 건수 | 항목 |
|---|---|---|
| **consumer 있음** | **21** | `.rs` 6 · `.llbc` 4 · `.yml` 7 · `.jsonl` 2 · `.py` 1 · `.default` 1 — §4의 다층 경로로 고정 |
| **consumer 없음** | **15** | `.nimble` 14(origin/main 트리에 파일 자체가 없음 — 재측정 시 소멸, 조치 불요) · `.txt` 1(`tests/fixtures/add_comm_test_log.txt`, 참조 0건) |

- **−14 자동 소멸**: `.nimble` 14건은 트리에 부재하므로 어떤 감축 작업도 필요하지 않다 — baseline 재측정
  (`--update-baseline`) 시 자동으로 소멸한다. 원문 §2의 "14 resolved" 관측(4249)이 정확히 이것이다.
- **−22 지속**: consumer 있는 21건 + 무참조 `.txt` 1건. 이 22건만이 현실적인 감축 대상이며, 그중 21건은
  §4의 다층 경로 고정 하에 있다.
- 위 수치는 "해소 시 총량 감소분"의 산술 구분이며 달성 보장이 아니다 — 원문 §4의 전제를 계승한다.
  옵션 선택·목표 수치·시점의 결정은 인간이다(§7).

## §4. 정정 사실 3 — consumer 다층 경로 고정 (file:line)

원문이 미측정으로 남긴 "(ii) fixture 위치·형식·확장자 변경"의 consumer 의존을 전수 측정한 결과다.
**이동·형식 변경이 자유롭지 않은 근거(file:line, 기준 커밋 `291cb2f08`에서 재검증)**:

**rust 10건** (`.rs` 6 + `.llbc` 4 — crate 디렉터명·crate명·`<crate>.llbc` 명명규약까지 하중-bearing):

- `tests/gateway/rust_lane_cli_acceptance_test.nim:107,108,250,953` — 4 crate 디렉터를 CLI 프로젝트 인자로 실행
- `tests/unit/test_llbc_to_canonical.nim:1109,29` — impl/rust_probe llbc 경로
- `src/cli/merge_cli.nim:295-300,313-317` — rust/guard probe 파일 단위 rotation allowlist / `tests/cli/test_merge_cli.nim:876-881,903`
- `data/verification_scope.lock:69-86,98-112` — `src/lib.rs` 모듈 경로·specRef 바인딩(CONTROLLED 락 — 이동 시 재생성 + 증거 무효화)
- `src/gate/runners/language_ban_gate.nim:77` — `.rs` 허용 접두어(`src/frontend/rust/`, `tests/fixtures/rust/`): **`tests/fixtures/rust/` 밖 이동 시 nimtry와 별개 게이트(language_ban_gate)의 신규 위반**
- `.gitignore:81` 화이트리스트 — 디렉터 밖 이동 시 비tracked화
- 문서 고정: `docs/spec/rust_certified_subset.md:81,116,141-142,160`

**`.yml` 7건** — 2개 셀프테스트 하니스가 파일명 수준으로 소비(이동·이름·형식 변경 시 fail-closed):

- poison 5건: `tools/ci/test_workflow_poison_lint.sh:30`(디렉터), `:40`(파일명 리스트), `:10-14`(파일별 설계 판정) + `Makefile:1106-1113`
- lane_guard 2건: `tools/ci/test_workflow_lane_guard.sh:40`, `:59-65`(파일명별 PASS/FAIL grep 단언) + `Makefile:1122-1129`
- `.gitignore:69-73` 경로 고정 화이트리스트 (CI/.github 직접 참조 없음 — 로컬 make target 경계)

**`.jsonl` 2건**: `tools/ci/test_workflow_jq_contracts.sh:146-149`(파일명 존재검사, 부재 시 config_error exit 2), `:360-364`(golden byte-일치 비교) + `Makefile:1145-1152` + `.gitignore:77-78`

**`.py` 1건**: `.github/workflows/debt-registry-gate.yml:36` `run: python3 tests/ci/test_debt_schema_theater_rule.py` — **CI required check가 직접 실행**(경로 변경 시 required check 자체가 깨짐)

**`.default` 1건** — 가장 강한 결합(빌드 부트스트랩 + CI 클로저 축):

- `config.nims:477`(`.default` → `build_env.nim` copyFile), `:414`(env-hash 멤버), `config/vendors.nims:37`
- `.github/workflows/admission-check.yml:424`(CI cp 폴백), `.github/workflows/runner-pool-acceptance.yml:500,532`(**envHashInputs 클로저 축 멤버** — 경로 변경 시 클로저 판정 변동)
- `.gitignore:49`

**측정된 사실 귀결(권고 아님)**: 위 표면 변경 없이 원문 경로 (ii)만으로 36건 전체 소멸은 불가능하다 —
21건은 다층 경로 고정, 14건(`.nimble`)은 애초에 조치 대상이 아니다(자동 소멸).

## §5. 정정 사실 4 — 지문 메커니즘과 위반 소멸 조건

- **지문은 경로를 포함한 detail의 SHA256이다**: 위반 생성 시 detail에 `path`가 포함된다
  (`src/gate/nimtry/safety_queries.nim:534` — `detail: path & " has disallowed extension …"`), 지문은
  detail의 SHA256이며 line:col만 제거되고 경로는 유지된다(`src/gate/nimtry/nimtry_cli.nim:88`
  normalizeDetail). baseline 항목의 `id`가 이 지문이다.
- **금지 확장자인 채의 이동·개명은 감축이 아니라 신규 위반이다**: 경로가 바뀌면 detail이 바뀌고 따라서
  지문이 새로워진다 → baseline 미등재 지문 = ratchet FAIL = **재앵커(`--update-baseline`) 수반**
  (원문 §6의 "갱신은 감축이 아니다" 원칙과 동일하게, 이동 후 재앵커도 감축으로 계수되지 않는다).
- **위반이 소멸하는 조건은 두 가지뿐이다**: (a) 파일을 허용 확장자(`safety_queries.nim:505` —
  `.nim`·`.lean`·`.md`·`.toml`·`.nims`·`.lock`·`.feature`·`.json`)로 변경하거나, (b) 면제 경로
  (`safety_queries.nim:507` — `vendor/`, `tests/generated_code_dump/`) 또는 스캔 루트
  (`:506` — `src/`, `tests/`) 밖으로 이동할 때.
- **이중 게이트 주의(사실)**: `.rs`는 nimtry(본 스캐너)와 `language_ban_gate`
  (`src/gate/runners/language_ban_gate.nim:77` — `rs` → `src/frontend/rust/`, `tests/fixtures/rust/`)
  양쪽의 대상이다. nimtry 측 소멸 조건을 만족하는 이동이 language_ban_gate 측 신규 위반이 될 수 있다.
- 본 문서의 file:line은 착지 기준 커밋 `291cb2f08`에서 재검증된 값이다.

## §6. 실측 방법 (원문 §8 형식 계승 — command → observation)

1. **기준선 확정**: origin/main 기준 `data/nimtry_baseline.json`(4263건)에서
   `rule=SAFETY-language-ban` 추출 → **36건, 전부 error** — 확장자 분포는 원문 §4와 정확히 일치
   (`.nimble` 14 / `.rs` 6 / `.llbc` 4 / `.yml` 7 / `.jsonl` 2 / `.py` 1 / `.txt` 1 / `.default` 1).
   로컬 체크아웃 일부는 이전 anchor(4222, 2026-10-21)를 유지하므로 전수 분석은 origin/main
   baseline으로 수행했다(기준선 불일치 시 36건 중 22건만 관측되는 착시 방지).
2. **기원 추적**: 36개 경로 전수에 대해 `git log --all` 경로별 추가 커밋 추적 → `.nimble` 14경로는
   추가 커밋 0건(미착지), 나머지는 §2 표의 PR/커밋에 귀속 확인.
3. **consumer 전수 조사**: 36 경로(+crate명·fixture 파일명)를 `src/`·`tests/`·`tools/`·`Makefile`·
   `config*`·`.github/`·`data/*.lock`·`docs/` 대상 전수 Grep → 참조 지점 file:line 기록(§4).
4. **메커니즘 검증**: `src/gate/nimtry/safety_queries.nim`(허용 확장자·스캔 루트·면제 경로·위반
   detail 생성)·`src/gate/nimtry/nimtry_cli.nim`(normalizeDetail) 코드 확인 + baseline 항목 구조
   (`id`=SHA256 지문, detail에 경로 포함) 실측.
5. **재검증**: 본 문서 착지 기준 커밋 `291cb2f08`에서 §4·§5의 file:line 전수 재확인 완료.

## §7. 원문과의 관계 — 결정 비유도 선언

- 원문(PR #1190, MERGE `7257d1209`)은 수정되지 않으며, 본 문서는 그 §2·§4의 사실 기술 중 기원 귀속과
  실효 범위 해석을 정정한다. 원문의 관측치("14 resolved", 확장자 분포 36건)는 실측으로 그대로 확인됐다.
- **D2(감축 예산 — 옵션 선택·목표 수치·시점)의 결정 권한은 인간(제품·아키텍처 책임자) 전용으로 변함없다.**
  본 문서는 정정된 사실만을 기록하며, 어느 옵션(A/B/C·조합)·경로·수치도 권고하거나 유도하지 않는다.
  원문 §7("결정 기록의 방법·시점은 인간이 정한다")은 그대로 유효하다.
- 본 문서는 원문과 동일하게 어떤 게이트도 소비하지 않는 기록 문서다 — 이 정정이 계약·정책·게이트
  동작을 변경하지 않는다.
