# 1d S2 — 캠페인 ② 증거 미해결 근원 2건의 기록 근원 조사 (erratum 근거 착지) (2026-11-09)

> **Status**: 기록 근원 조사(provenance investigation) 관측 기록 — 1d 증거 문서 §9에 남은 두 Non-Conclusion(상한 1,795 측정 원천·캡슐 inputs 75파일 차이)의 근원 확정·검증. **판정·acceptance 변경이 아니다** — 본 조사의 산출은 근원 판정과 계약 §7 표기 정정(단위 "1,795 .ltar" → "1,795")의 근거다. 조사 자체는 읽기 전용(서브젝트·원본 캐시·elan 무접촉 — 읽기만·실험 재실행 아님)으로 2026-11-09 수행됐고, 본 문서 + 기계 원본 산출물 7종(`docs/evidence/b2m_1d_s2_provenance_2026-11-09/`)로 착지한다.
> **Created**: 2026-11-09
> **Written at**: branch `workstream/1d-s2-erratum`, branch base = main `d6d7625b9d91c0415535346e7418c8f51ad6c962` (1d 증거 MERGE #22)
> **Governing docs**:
> - [docs/spec/capsule_minimal_materialization.md](../spec/capsule_minimal_materialization.md) (1d materialization 사전계약 — §7 폐쇄 상한 대조 [본 erratum으로 표기 정정])
> - [docs/evidence/b2m_1d_minimal_capsule_materialization_2026-11-08.md](b2m_1d_minimal_capsule_materialization_2026-11-08.md) (1d 증거 문서 — §9 Non-Conclusions [본 조사로 두 항목 dated addendum 갱신]·§4.3 상한 대조 판정)
> - [docs/evidence/b2_hermetic_proof_capsule_2026-11-04.md](b2_hermetic_proof_capsule_2026-11-04.md) (원본 B-2 capsule — §5.3 run 로그·§5.2 generation.json 정본)
> - [docs/evidence/b1_gate_a_minimal_proof_2026-11-04.md](b1_gate_a_minimal_proof_2026-11-04.md) (B-1 Gate A — §4.6 최종 빌드 기록)
>
> **원칙**: 관측 원문(기계 수치 JSON·로그·스냅샷)은 바이트 그대로 착지하고 본 문서는 그 인용·종합이다. 모든 결론은 근거 인용 전제 — 근거 없는 항목은 UNKNOWN으로 기록한다.

---

## 1. Question

캠페인 ②(1d 최소 캡슐 materialization M) 증거에 남은 두 미해결 근원 —

1. **폐쇄 상한 1,795의 측정 원천**: 계약 §7은 "사전 측정(capsule_min_measure, 2026-11-08 — 등록) 폐쇄 상한은 1,795 .ltar"로 등록했으나 그 측정 방법론이 저장소 어디에도 문서화돼 있지 않다(1d 증거 문서 §9 — "상한 1,795의 측정 방법 원천 미확보"). 1,795는 어디서·누가·어떻게 측정했는가?
2. **캡슐 inputs 75파일 차이의 실체**: 원본 캡슐 inputs 153,082파일 vs M 153,006파일(+심볼릭 1) — 75파일·4,779,252B 차이의 원인 가설(b1 post-build 상태)이 미검증이다(1d 증거 문서 §9). 차이는 어떤 성분에 걸려 있는가?

## 2. Context

- **조사 시점**: 2026-11-09 (기록 근원 조사 — 읽기 전용, 실험 재실행 아님)
- **조사 대상 기록**: 계약 `docs/spec/capsule_minimal_materialization.md` §7(폐쇄 상한 대조 — 커밋 `66c7a47`·2026-11-08 등록)·증거 문서 `docs/evidence/b2m_1d_minimal_capsule_materialization_2026-11-08.md` §9(두 Non-Conclusion)
- **정정 대상이 아닌 관측 수치**: 1d 실험의 상한 대조 판정 — S = 1,478 .ltar ≤ 상한 1,795 미초과 PASS(증거 문서 §4.3). 본 조사는 이 판정의 유효성에 영향을 주지 않는다.
- **원본 계열 기록**: B-2 증거 문서 §5.2(generation.json — inputs per_dir·subtree digest 3종)·§5.3(run1 로그 — 빌드 플랜 관측)·B-1 증거 문서 §4.6(최종 빌드)

## 3. Scope

- **포함**: 두 조사 항목의 근원 확정·검증 — (1) 상한 1,795의 측정 주체·시점·방법·전달 경로 추적, (2) inputs 차이의 성분별(subtree digest) 기계 대조·동일 기준 재측정, 관련 기록 전수 검색(Axiom4·아카이브).
- **제외**: 실험 재실행(Stage A′·B′ 어느 스테이지도 재실행하지 않음)·캠페인 후속 ③⑤ 설계(계약 경로 — 본 문서 범위 밖)·판정·acceptance 재평가.

## 4. Procedure

조사 전문은 캠페인 워크스페이스의 S2 보고서(`b2m_1d/provenance/report.md`)이고, 본 절은 그 절차 요약이다 —

1. **세션 이벤트 로그 원문 발굴**: 세션 로그 `followup_investigations_2026-11-05/` 내에서 capsule_min_measure 측정 보고서 원문·기계 수치 JSON(summary_numbers)·패키지 센서스를 발견 — 원본 산출 위치(`/tmp/capsule_min_measure/`)는 소실(tmpfs)됐으나 세션 디렉터리 내구 사본이 생존.
2. **스냅샷 내구 보존**: 측정 보고서·기계 수치·패키지 센서스·원본 인벤토리 생성 로그·b1 빌드 반복 관측·아카이브 검색 결과를 캠페인 워크스페이스(`b2m_1d/provenance/`)에 스냅샷 — 본 PR이 그 7종을 바이트 정확 착지한다(§6 Evidence).
3. **원본 인벤토리 생성 스크립트 복원·동일 알고리즘 재적용**: 세션 로그(agent-115 wire — Write tool.call 원문)에서 인벤토리 생성 스크립트를 복원하고(알고리즘: `find -type f` → `sorted(paths)` 바이트 순서 → `'<sha256>  inputs/leanproj/<rel>\n'` 직렬화의 sha256), 동일 알고리즘을 M(`b2m_1d/stageA/leanproj`)에 재적용해 subtree digest를 재계산·원본 기록값과 대조(§5 조사 2).
4. **Axiom4 전수 검색**: 저장소 grep·`git log -S --all`로 `capsule_min_measure` 등장 전수 추적.
5. **Axiom-archive 음성 대조**: private 아카이브(Archright/Axiom-archive — 재생성 전 히스토리) blobless clone에서 코드 서치·pickaxe(`-S`) 검색, 알려진 문자열로 양성 대조(메커니즘 검증).

## 5. Result

### 5.1 조사 1 — 상한 1,795의 측정 원천: 확정

**1,795의 정체** — `.ltar` 개수가 아니라 **원본 B-2 run 로그(총 1,801 jobs)의 빌드 플랜 관측치**에서 유도된 상한이다:

- 원본 B-2 run 로그 원문(B-2 증거 문서 §5.3 — `✔ [1796/1801] Built AsBool.TypesExternal (5.5s)` 이후 루트 5종 Built·`Build completed successfully (1801 jobs)`): **1,801 총작업 = 1,795(첫 루트 Built 이전에 완료된 up-to-date·silent 작업) + 5(루트 컴파일) + 1(trailing)** — 즉 **1,795 = 1,801 − 5 − 1**.
- **기계 수치 원문**(착지본 `capsule_min_measure_summary_numbers.json`): `build_plan_observed: {jobs: 1801, root_built: 5, dep_jobs_before_first_root: 1795, trailing: 1}`·`needed_ltar_upper_bound.count: 1795` — "각 작업 ≥ 1 모듈" 가정 하 유도한 느슨한 상한(측정 보고서 스스로 aeneas 사전빌드 모듈·집계 작업을 의도적으로 미차감했음을 명시).
- **측정 시점·주체**: 2026-11-05 10:59 — 세션 `followup_investigations_2026-11-05`의 capsule_min_measure(백그라운드 서브에이전트 agent-119 수행). 캡슐 본체는 당시 이미 소실 → 문서 결속 관측치(B-2 run 로그)·잔존 캐시 전수·상류 공개 저장소 기반 읽기 전용 정적 분석(lake/lean/aeneas 실행 0회).
- **전달 사슬**: followup 측정 보고서(2026-11-05 — 세션 로컬·미커밋) → 캠페인 PLAN.md 기준값 대조표 → 계약 §7(커밋 `66c7a47`·2026-11-08 등록 — 측정일 11-05와 등록일 11-08이 다른데 계약 문구는 등록일만 표기) → 1d 증거 문서 §9. 캠페인이 원천을 찾지 못한 이유: 측정 보고서가 저장소 외부(세션 디렉터리·/tmp)에만 존재했고 커밋 기록에는 값만 등록됐다.
- **317(= 1,795 − 1,478) 차이의 성격**: 상한의 설계상 여유 — `.ltar` 외 항목(aeneas-lean 사전빌드 prebuilt 모듈 — 측정 보고서 기록 249·1d 폐쇄 도달 기준 266[서로 다른 측정, 통합하지 않음]·비모듈 집계 작업 ~51 추정)을 포함한다. 전체 정확 분해는 UNKNOWN. 1,478 < 1,795는 설계상 예상된 결과이며 상한 미초과 판정(증거 문서 §4.3)에 무영향.
- **전수 검색·음성 대조**: Axiom4 grep — 계약 §7·증거 문서 §9(+캠페인 dir 미커밋 파일)뿐. `git log -S --all` — `66c7a47`(계약 도입)·`3b397a1`(증거) 2건뿐. `experiments/serde-json-claim-2026-10-31/`(B-1 시대) 0건. Axiom-archive(blobless clone·커밋 3,992) — tip 코드 서치 0건·pickaxe 0건, **대조 양성 검증**: 알려진 문자열 `b2_hermetic_proof_capsule` → `1acd5c47` 검출(검색 메커니즘 정상 — 음성 결과 유의미). 상세: 착지본 `archive_search_result.md`.

### 5.2 조사 2 — inputs 75파일 차이: 부분 확정 + 신규 발견 2건

**(a) `deps/aeneas-lean` subtree digest — MATCH (신규 입증)**: 원본 기록값 `1d5bd051b63b3af0e75810de372e8bdf36ab62354878bc9e8145a7f50175f567`(인벤토리 생성 로그 원문·B-2 문서 172-174행과 일치)과 M 실측(4,673파일·504,319,893B)이 동일 — **deps는 차이의 원인이 아님을 신규 입증**(양쪽 모두 aeneas 번들 내장 사본 — prebuilt `.lake/build` 포함).

**(b) `.lake/packages` subtree digest — MISMATCH (신규 발견)**: 원본 기록 `11509afcd86ac32000ffe4c9d77143175f801a69bafdd2534513d27c4c885f9d` vs M 실측 `c52d67f07be99d465fc7ede49e064d8164a36d3bfc9a11e7c917a7d99266b5bc`(148,316파일·7,248,549,946B — `.git` 2,234파일 51,049,693B + 작업트리 146,082파일 7,197,500,253B). 캠페인의 총계 비교(9,031 `.ltar`·bytes 대조)만으로는 잡히지 않던 불일치다. M의 9패키지는 전부 manifest 핀 리비전의 클린 체크아웃(실측: `git status --porcelain` 0행 전원 — mathlib `56a005855ea1`·batteries `66e469188fe0`·aesop `4a174c490d87`·Qq `dce0ad79c486`·plausible `dfa4f38190d0`·importGraph `a41f0e9a4dea`·proofwidgets `df72b022e556`·LeanSearchClient `d6b4c7be5be7`·Cli `c24fe6078c63` — capsule_min_measure 패키지 센서스 핀과 전부 일치)이므로 작업트리 소스는 구성상 동일 — **최유력 원인은 `.git` 내부의 클론 시점 상태**(reflog 타임스탬프·`FETCH_HEAD`·pack 구성 등 — 원본 fetch 2026-11-04 vs M fetch 2026-11-08). 확정 아님(§9).

**(c) 동일 find 기준 실측 차이 — 76파일·4,779,264B**: 기록값 75파일·4,779,252B는 계상 기준 혼합(원본 find 기준·심볼릭 제외 vs M walk 기준·심볼릭 1개 계상)이었다. 동일 기준(`find -type f`) 차이는 76파일·4,779,264B(양쪽 심볼릭 포함 계상에서도 76).

**(d) "b1 post-build 상태" 가설 — 지지되나 수정 필요**: 원본 inputs에 루트 `.lake/build`가 존재했음은 **문서 결속**(B-2 증거 문서 573행 — 캡슐 inputs은 b1 최종 상태 그대로 봉입·stage_b.sh [2]가 빌드 전 삭제·컴파일에 소비된 것은 unpack 캡슐 cache 9,031 `.ltar`)·b1 빌드 기록(B-1 §4.6 최종 빌드 exit 0·"Build completed successfully (1801 jobs)")·b1 실패 빌드 12회 관측 원문(착지본 `b1_build_attempt_observations.txt` — `lake_build_exit=1` 12회를 포함한 점진적 빌드의 최종 상태)이다. 그러나 **차이 전체가 루트 빌드 잔존물은 아니다** — (b)의 packages subtree 불일치가 관측됐으므로 `.git` 상태를 포함한 복합 차이다. b1 잔존물의 정확한 구성은 기록 없음(참고 실측: 클린 빌드 루트 `.lake/build`는 80파일·4,745,083B).

**(e) "작동상 무관" — 실험적 지지**: stage_b.sh [2] `rm -rf /workspace/leanproj/.lake/build`(byte-exact 재구성본 — 14행·sha `9197a0f0…54e39`)이 빌드 직전 루트 빌드 산출물을 삭제 + M이 원본과 다른 초기 상태(다른 `.git` 상태·pristine 루트 빌드)에서 acceptance 4축 전부 PASS(증거 문서 §4·§10 Deviations 2 — 원본은 [2]가 실재 삭제, M은 no-op, 어느 쪽이든 빌드 시작 시점 "루트 빌드 산출물 부재"로 동일). 관측된 판정축 어느 것도 inputs 초기 상태 차이에 민감하지 않았다.

## 6. Evidence

**착지 기계 원본 7종** — `docs/evidence/b2m_1d_s2_provenance_2026-11-09/`(캠페인 워크스페이스 내구 사본에서 `cp -a` — byte-identical, `cmp` 전수 대조):

| 파일 | bytes | sha256 | 내용 |
|---|---:|---|---|
| `capsule_min_measure_summary_numbers.json` | 715 | `256511217e53fdae7ce7d5fb1490b16d8327d61c8b10ff786822163a56c2e804` | 기계 수치 원문 — jobs 1801·`dep_jobs_before_first_root: 1795`·`needed_ltar_upper_bound.count: 1795` |
| `capsule_min_measure_package_census.json` | 296 | `59af34301d81119fa29ad66c01d54175f10746d2c3df694365b2fd22d95d1afc` | 캐시 패키지 센서스(패키지별 .ltar 수·bytes·핀 리비전) |
| `subtree_digest_recheck.json` | 607 | `b83c5c2f057af7f49825d58e8225a5b2a49ab2dc4770387a532053b5dbb33037` | 본 조사 신규 실측 — M subtree digest 재계산·원본 기록값 대조(MATCH/MISMATCH) |
| `b2_inventory_generation_log.txt` | 1,935 | `1acf9e1d74e6c0b7295338f42a0681df8116aed1c613e23bcd2b246fcf5f3fe9` | 원본 인벤토리 생성 로그 원문 — per_dir 4종·subtree digest 3종 |
| `b1_build_attempt_observations.txt` | 2,671 | `8781a4e455b7547b7f0f8c045155ef5a5c7a316f4d5dfbbc1a8b777ac041959c` | b1 빌드 반복 관측(exit=1 12회·오류 원문)·B-1 §4.6·B-2 run1 [2][4] 원문 |
| `capsule_min_measure_report_snapshot.md` | 23,398 | `9c4f458f0be5439bfd923be2ffb845de65878435651cb98062e8a4d82ecd3533` | 측정 보고서 전문 스냅샷(§0 fail-closed 선언·§2.4 상·하한 표·§8 보관 파일) |
| `archive_search_result.md` | 2,041 | `c0525c296f64c27db048824a7cff3da53abf4c7d3ee0e5ec3ab7a25e23e78399` | 아카이브 검색 방법·결과(0건)·음성 대조 검증·한계 |

**미착지 결속**: `subtree_digest_recheck.py`(계산 스크립트 — bytes 2,205·sha256 `689348dd2848c6d33ab4238705ef4fa56c280168e55cacf5b5db5016e8fe5e50`)은 **착지하지 않았다** — 스크립트 본문에 호스트 절대경로가 포함되어 본 문서의 착지 규칙(호스트 절대경로 기입 금지)과 충돌. 알고리즘·절차는 §4에 서술했고 계산 결과(`subtree_digest_recheck.json`)를 착지했다.

**인용 계보**: 세션 이벤트 로그 원본(세션 로그 `followup_investigations_2026-11-05/`·agent wire — 원본 산출 `/tmp`는 소실) → 캠페인 워크스페이스 내구 사본(`b2m_1d/provenance/` — 저장소 외부) → 본 브랜치 착지본(위 표). 본 문서·착지 산출물에 호스트 절대경로·세션 절대경로는 기입하지 않는다(상대 서술만).

## 7. Classification

기록 근원 조사(관측) — 판정·acceptance 변경 아님. 본 조사의 지위는 (1) 1d 증거 문서 §9 두 Non-Conclusion의 근원 확정·해소, (2) 계약 §7 상한 표기 정정("1,795 .ltar" 단위 → 1,795[빌드 작업 수 관측에서 유도된 상한])의 근거다. 결과 분류: 조사 1 확정(원천·방법·전달 경로 관측)·조사 2 부분 확정(성분별 MATCH/MISMATCH·동일 기준 수치) + 신규 발견 2건.

## 8. Interpretation

**확립한 것** —

- 상한 1,795의 측정 원천(원본 B-2 run 로그 빌드 플랜 관측)·측정 방법(1,801 − 5 − 1 유도·느슨한 상한 설계)·측정 시점(2026-11-05)·전달 경로(followup 보고서 → PLAN.md → 계약 §7 → 증거 문서 §9) — 전부 기계 수치 원문·문서 결속으로 관측.
- inputs 차이의 성분별 판정: `deps/aeneas-lean` MATCH(차이의 원인 아님)·`.lake/packages` MISMATCH(신규 발견 — 최유력 원인 `.git` 클론 시점 상태).
- 동일 기준 정확 차이: 76파일·4,779,264B(기록값 75파일·4,779,252B는 계상 기준 혼합).
- 상한 미초과 판정(1,478 ≤ 1,795)의 유효성은 무영향 — 판정 술어·fail-closed 문구는 변동 없음.

**확립 안 한 것** — §9 Non-Conclusions 참조.

## 9. Non-Conclusions

- **317(1,795 − 1,478)의 전체 정확 분해는 UNKNOWN** — aeneas-lean 모듈 수(249 vs 266)의 측정 차이 포함, 문서화돼 있지 않다.
- **76파일 차이의 파일별 목록·루트/packages 배분은 UNKNOWN** — 원본 인벤토리의 파일 전수 목록은 소실(세션 wire에도 미보존), 본 조사는 영역 수준(subtree digest·전수 열거·산술)까지만 특정했다.
- **`.lake/packages` MISMATCH의 원인은 최유력 가설(`.git` 클론 시점 상태)이지 확정이 아니다** — 원본 직접 대조 불가(원본 소실), 작업트리 동일성은 구성 논증(동일 manifest 핀·클린 체크아웃)+M 실측으로 지지될 뿐이다.
- **본 조사는 기록 근원 조사이지 실험 재실행이 아니다** — 관측 원문은 착지 산출물(§6 표)·원문 digest 결속으로 보존하며, Stage A′·B′·측정 스크립트를 재실행하지 않았다(subtree 재계산은 살아있는 자산 M에 대한 신규 실측이지 원본 재실행이 아니다).

## 10. Next Experiment

없음 — 캠페인 후속 ③⑤는 계약 경로에 있으며 본 문서의 범위 밖이다(본 조사는 두 Non-Conclusion의 근원 확정과 erratum 근거 착지로 종결).
