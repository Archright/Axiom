# Canonical Repository Hygiene — MUST Restoration 사전 증거 (2026-11-03)

- **기준 커밋**: `679eb49db` (origin/main = Merge PR #1247, 2026-11-03 fetch 후 불변 확인)
- **증거 종류**: 사전 증거 — 본 문서는 PR 생성 시점까지 관측된 사실만 기록한다. 병합 사실(MERGE SHA·checks green·merge queue 결과)의 권위는 GitHub PR/merge 커밋이다(AGENTS.md §2.3). 병합 후 관측은 별도 보고로 종결하며, 결함이 발견된 경우에만 정정 커밋이 후속된다(`docs/spec/evidence_manifest_gitignore_quirk.md` §3 관례).
- **조사 방법**: 로컬 클론에서 `git ls-tree -r -z --full-tree origin/main`·`git cat-file --batch-check`·`git grep` 전수. blob SHA 동일 = 바이트 동일의 기계 판정. 백그라운드 전수조사 2건(agent-90: §0.6 게이트 predicate·바이너리 재고 / agent-89: 중복 13쌍 정본·참조·레지스트리)의 산출과 교차 검증 완료.

## 1. 변경 내용 (11 경로)

| 작업 | 대상 |
|---|---|
| 중복 사본 삭제 8 (정본 보존) | `docs/evidence/evidence.txt`, `evidence_add_doc_first_principle.txt`, `feature_restoration_evidence.txt`, `gate_self_check_evidence.txt`, `git_notes_evidence.txt`, `module_overrides_cleanup.txt`, `override_removal_evidence.txt`, `phase0_completion_evidence.txt` |
| 우발 커밋 ELF 제거 1 (소스·레시피 보존) | `tools/ci/check_perf` (302,024B, ELF magic `7f454c46`) |
| 재발 방지 (보조) | `.gitignore` +1행 `tools/ci/check_perf` — §0.6b Source-First 선례(`tools/ax_hygiene_fix`)와 동일 형식 |
| 사전 증거 문서 1 | 본 문서 |

## 2. docs/ 바이트 동일 중복 13쌍 — 3계층 분류

>10,240B 무관·docs/ 전체 blob SHA 그룹화 결과 13그룹(26파일). 전원 2-멤버.

| # | blob | 경로쌍 | 계층 | 처리 |
|---|---|---|---|---|
| G1 | `0b2859c2` | `evidence/ci/21954da7.json` ≡ `evidence/ci/latest.json` | B — 역할 문서화(ci/index.md:7-14: 롤링 게이트 입력 vs 커밋별 스냅샷) | 제외(부실 상태로 별도 기록) |
| G2 | `09f5d2a2` | `evidence/evidence.txt` ≡ `verifications/` 동명 | A | **삭제(루트)** |
| G3 | `2044c3d8` | `evidence/evidence_add_doc_first_principle.txt` ≡ 동명 | A | **삭제(루트)** |
| G4 | `0d3e097b` | `evidence/feature_restoration_evidence.txt` ≡ 동명 | A | **삭제(루트)** |
| G5 | `95af08a5` | `evidence/gate_self_check_evidence.txt` ≡ 동명 | A | **삭제(루트)** |
| G6 | `4176da20` | `evidence/git_notes_evidence.txt` ≡ 동명 | A | **삭제(루트)** |
| G7 | `50a3fa98` | `evidence/module_overrides_cleanup.txt` ≡ 동명 | A | **삭제(루트)** |
| G8 | `be85ab6c` | `evidence/override_removal_evidence.txt` ≡ 동명 | A | **삭제(루트)** |
| G9 | `c27f759a` | `evidence/phase0_completion_evidence.txt` ≡ 동명 | A | **삭제(루트)** |
| G10 | `b1aeada1` | `verifications/evidence_precommit_timeout.txt` ≡ `history/` 동명 | C — 층위 상이(evidence vs history), 병존 사유 무문서 | 격리(인간) |
| G11 | `b28ce891` | `verifications/gate_infrastructure_debt_audit.txt` ≡ `history/audits/` 동명 | C — R100 이동(1acf4cb) vs verifications 병존 | 격리(인간) |
| G12 | `b5ca9dd9` | `verifications/official_docs_cross_check.txt` ≡ `history/audits/` 동명 | C — 동 G11 | 격리(인간) |
| G13 | `f4bcc9c8` | `verifications/parallelization_performance_audit.txt` ≡ `history/reports/` 동명 | C — 동 G11(원본 docs/reports/ 출신) | 격리(인간) |

**A계층 정본 = `docs/evidence/verifications/`인 근거**: (i) 6개 규범 문서가 verifications/를 위임 증거 SSOT로 명시(`docs/agents/evidence-based-deterministic-convergence.md:13`·`rules_workflow.md:65`·`report-guardrails.md:21` 등); (ii) 이력 — 루트 8파일 `73c2fa66`(2026-06-01) → verifications/ 26파일 일괄 통합 `d898af00`(2026-06-03), 루트 사본은 통합 후 무문서 잔존; (iii) 존재하는 참조 전부(G4·G6·G11)가 verifications 쪽, 루트 사본 참조 0; (iv) 관련 5개 커밋 메시지에 사본 유지 사유 기술 없음.

**전수 무결성**: 26경로 모두 전체경로 참조자 0건(코드·Makefile·workflow·data/·config/ 포함 전 트리 grep, 양성 대조군 3파일 적중으로 기제 검증). `data/debt_registry.json` 미포함(레지스트리 755 경로와의 comm 교집합 = 공집합).

## 3. `tools/ci/check_perf` ELF — 우발 커밋 판정 근거 4건

1. **소비자 0**: 워크플로 0힛(27 워크플로·45 checkout 스텝 전수)·make 타깃 `check-perf`는 고아(`make test`는 별개 `perf-check` 사용)·docs는 소스(.nim)만 서술·레지스트리는 과거 재고 기록만.
2. **빌드 산물 경로 일치**: `Makefile:1313` `@nim c -r tools/ci/check_perf.nim` — nim 기본 출력 경로 = ELF 위치와 동일.
3. **.gitignore 비커버**(변경 전) — 우발 커밋 경로가 개방돼 있었음.
4. **반입 경로**: 커밋 `6fe14fbe0` — 58커밋 스쿼시에서 소스와 바이너리가 동시 반입.

→ 처리: §0.6b Source-First 선례(`tools/ax_hygiene_fix`, .gitignore 주석 "pre-built ELF binaries removed from git tracking (§0.6b Source-First)")와 동일 — 트리에서 제거하고 소스 `tools/ci/check_perf.nim`·`Makefile` 레시피는 보존(요구 시 `nim c -r tools/ci/check_perf.nim`로 동일 경로 재생성, 소비자 0이므로 바이트 재현 불요). `.gitignore` 등록으로 `git add` 실수 재발 차단(`git add -f` 우회는 막지 못함 — 강제 장치가 아니라 보조 실수방지).

## 4. §0.6 바이너리 전수 재고 — 신규 발견 gzip 5건 (인간 격리)

>10,240B blob 1,361경로(고유 1,331 oid) 전수에 대해 선두 8,000바이트 NUL 스니프·매직 확인. **바이너리 6건, 전부 비LFS 실체**(LFS 포인터는 공식 스펙상 텍스트 <1024B — `git-lfs` docs/spec.md):

| 분류 | 크기(B) | 경로 | 처리 |
|---|---|---|---|
| ELF | 302,024 | `tools/ci/check_perf` | **본 PR 제거** |
| gzip | 307,669 | `experiments/act2-wp-toml-b1-input-integrity/bsec/evidence/raw.tar.gz` | 격리 |
| gzip | 128,779 | `…/bsec/offline/deps.tar.gz` | 격리 |
| gzip | 11,804 | `…/followup/contract/raw.tar.gz` | 격리 |
| gzip | 46,291 | `…/followup/valuemodel/raw.tar.gz` | 격리 |
| gzip | 27,302 | `…/followup/writer_table/raw.tar.gz` | 격리 |

**gzip 5건 판정**: 의도성 — MANIFEST가 SHA-256으로 archive/member 해시를 고정하고 `JUDGMENT.md:220`이 deps.tar.gz를 "번들 vendor"로 사용을 명시하는 **의도적 증거 아카이브**. 그러나 `.gitattributes`의 LFS 패턴은 `*.pdf *.so *.bin *.png` 4종뿐(`*.gz` 무패턴) → §0.6b 「`.gitattributes`에 패턴이 없는 바이너리 형식은 추가 금지」 기준 **위반 소지**(2026-10-11 `4255ec7de` 착지). 본 PR은 AGENTS.md §2.2(범위 닫힘·발견≠권한)에 따라 이 5건을 변경하지 않는다. **인간 결정 필요**: (a) LFS 전환 + `.gitattributes` 패턴 추가, (b) 게이트 baseline 갱신, (c) 명시적 면제 결정 중 택1.

## 5. 게이트 관측 (참고 — 본 PR 변경 아님)

- `asset_hygiene_gate.nim`(§0.6 집행 구현): 확장자 31종(LfsRequiredExtensions :87–94) + 매직 24종(:25–49)의 **부분 근사** — NUL 스니프 없음·VFS 경로(`scanAssetsVfs`)는 확장자 경로만 존재. ratchet baseline `data/asset_hygiene_baseline.json` = 2026-08-26 갱신(gzip 착지 이전).
- `binary_artifact_gate.nim`: pre-commit·staged 파일 ELF/PE/Mach-O 하드블록(크기 무관) — 본 PR은 삭제만 staged하므로 통과.
- **DEBT#493(passFilenames 극장) = closed** (2026-10-07, executor.nim 수정·`docs/evidence/debt493_passfilenames_closure_2026-10-07.md`).
- 잔존 관측: 두 게이트 모두 `stages=skManual`(`src/gate/topology_spec.nim:53–74`) — `.github/workflows`·`ci/`·`.githooks`에 실행 흔적 없음. gzip 5건이 게이트를 통과한 원인으로 추정. 라이브 배선 여부는 별도 인간 판정 사항(본 PR 범위 밖).

## 6. Completion Evidence (§2.2-10 — 명령·기대 결과)

변경 전(기준 `679eb49db`) 관측: duplicate_groups 13·바이너리 6(ELF 1+gzip 5)·삭제 9경로 전체경로 참조 0·레지스트리 0·ELF 소비자 0(소스 참조 `Makefile:1313`·`docs/spec/vc_pipeline_architecture.md:417`만 존재).

사전 검증(브랜치 HEAD) 및 병합 후 수용(origin/main + MERGE)에 동일 fail-closed 판정을 적용한다 — 전 check가 exit code로 판정되며, 위반 시 즉시 중단(우회 금지):

1. **중복 그룹 정체성** — `git ls-tree -r -z --full-tree <ref>` 후 docs/ blob SHA 그룹화: `duplicate_groups == 5`이고 잔존 그룹이 G1·G10·G11·G12·G13의 OID·경로쌍과 완전 일치. (개수만 5인 상태 — 예: G2 잔존 + 신규 그룹 소멸 — 는 FAIL)
2. **삭제 9 부재 + 정본 8 존재** — `tools/ci/check_perf`·루트 8 `.txt`가 트리에 부재, `docs/evidence/verifications/` 동명 8파일 존재.
3. **바이너리 재고** — >10KiB blob NUL 스니프 결과가 gzip 5건 OID 집합과 완전 일치(ELF 소멸·신규 바이너리 0).
4. **.gitignore** — `tools/ci/check_perf` 행 정확히 1행.
5. **소비자 참조** — `git grep -F <경로> <ref> -- ':(exclude)docs/evidence/canonical_hygiene_must_restore_*.md'`: 8 문서경로 0건; `tools/ci/check_perf`(공백 없는 문자열 — 인용 형태 전부 포획)는 허용집합(`Makefile` 소스 레시피·`docs/spec/vc_pipeline_architecture.md` 소스 서술·`.gitignore`·본 문서) 외 0건. 본 문서가 삭제 경로를 기록하는 것은 역사적 감사 기록이지 소비자 참조가 아니다 — pathspec 제외로 분리된다.
6. **무변경 경계** — `git diff --exit-code <MERGE>^1 <MERGE> -- .github/ config/policy/ data/debt_registry.json`이 빈 출력(첫-parent diff — 병합 자체의 변경만 격리, 타 PR 변경 배제). 사전 검증은 base..HEAD로 동일 경로 적용.
7. **MERGE 착지** — `git cat-file -p <MERGE>` parent 정확히 2개·`gh pr view --json state,mergeCommit` state=MERGED·mergeCommit.oid=<MERGE>·`git rev-parse origin/main` == <MERGE>.

## 7. 격리 명단 (인간 아키텍트 결정 대기 — 본 PR 완료 조건 아님)

| 항목 | 내용 |
|---|---|
| G1 | `ci/latest.json` ≡ `21954da7.json` — 중복 아닌 부실 상태(소비 게이트 2026-09-20 RETIRED). 폴러 부산물 정리 여부 |
| G10–G13 | verifications ↔ history 4쌍 — 층위·이동·§5 감사 매핑의 3방향 충돌. 정본 확정 필요 |
| gzip 5건 | §4 표 — LFS 전환/.gitattributes 확장/baseline 갱신/면제 중 결정 |
| 게이트 배선 | asset_hygiene·binary_artifact의 skManual 라이브 배선 여부 |
| 기존 부채 결정 | ADR-0038·nimtry 감축 예산·STALE 10·WARN/ERROR 승격·waiver 통합(기존 인간 대기 항목, 본 PR과 무관) |

## 8. 비용·범위 서약

- 신규 CI 잡·스텝·트리거·워크플로·게이트 0 / LFS 대역폭·저장 증가 0 / 신규 측정 시스템 0.
- 본 PR은 모든 PR과 동일한 통상 필수검사 기준선 1회분을 소비한다(신규 자동화 구조로 인한 추가 비용 0과 별개로, 작업 자체의 CI 실행 비용은 발생).
- B/C계층 5쌍·gzip 5건·레지스트리·`config/policy/`·`.github/workflows/`·nimtry baseline 일체 무변경.
