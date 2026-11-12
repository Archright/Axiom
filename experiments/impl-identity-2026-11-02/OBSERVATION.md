# OBSERVATION — ② Impl 메서드 주소가능성: `llbcFunctionToCanonical` identity 계약 (사전병합 기준선 + 병합 후 cold acceptance)

- EXPERIMENT_ID: impl-identity-2026-11-02
- Written: 2026-11-02, branch `work/impl-identity-2026-11-02` (폐쇄 증거 커밋). 관측 사실만 기록 — 기계 출력은 verbatim 또는 sha256 (artifacts/acceptance/).
- MERGE_SHA: `a24b8b82bd16ddb7f62c6804594e16fa847efd8a` (PR #1174 MERGED, mergedAt 2026-11-01T19:02:21Z — gh pr view 재확인; admission-gate merge_group run 41338597724 conclusion=success; `tools/ci/landing_observe.sh 1174` VERDICT=TERMINAL_SUCCESS)
- Subject fixture: `tests/fixtures/rust/axiom_impl_probe` — `src/lib.rs` + `src/m1.rs`(`Dog::speak`, `add_u8`) + `src/m2.rs`(`Cat::speak`, `add_u8`) + 사전 추출 `axiom_impl_probe.llbc`. **중복 이름이 계약의 시험대**: `speak`·`add_u8`은 각각 2개 impl에 존재.
- Charon pinned==measured `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` ok=true (전 런 stderr verbatim)
- Env: `GITHUB_TOKEN` via `gh auth token`(값 미출력), fresh `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR` (/tmp 하위), state seed = repo `data/verification_scope.lock` byte copy
- DEBT#510 → **closed** (resolution FIXED, resolvedBy `workstream_impl_identity_2026-11-02`, resolvedAt 2026-11-02) — 본 슬라이스가 폐쇄 주체. 병합 registry 최종: 242 entries, closed=195(510·511 모두 closed), open=29, deferred=18

## §1 계약·구현 요약 (PR #1174 본체)

- `llbcFunctionToCanonical`: 구조화 fullName(예: `axiom_impl_probe::m1::Dog::speak`) **정확 일치**만 대상 선택. bare last-segment(예: `speak`)는 유일할 때만 선택, 복수 시 `rceMalformed` **Ambiguous 명시적 거부** — 후보 구조화 이름 전체 나열 + DEBT#510 문구(안내). 0 matches = NotFound. 어느 쪽이든 "암묵적 1개 선택 후 검증" 없이 fail-closed.
- Impl 소유자 해석: `translated.item_names` **전용 수집 owner-map**(`LlbcDeclCtx.ownerTypes: Table[int, JsonNode]`, `collectInterns(jField(translated,"item_names"), ownerInterns)`). 일반 인턴 테이블은 `Adt.generics.trait_refs`의 트레잇 공간 Value 쌍이 Adt id를 그림자화하는 실측 충돌(`fun_decls[1]/body/Structured/locals/locals[5]/ty/Value[1]/Adt/generics/trait_refs[0]/Value` + Q12 layout id 충돌)로 owner 판별에 쓸 수 없음 — 별도 수집이 근본 수정.
- CLI(`--target`): 로컬 lastSegment 재유도 삭제 — 사용자 입력 문자열을 그대로 파이프라인에 전달(identity는 기계가 결정).
- 열거 SSOT: `llbcFunDeclNamePaths` export (테스트·문서 동일 소스).

## §2 사전병합 검증 체인 (병합 트리 기준, 게이트 PASS)

- `make build` ✅
- `tests/unit/test_llbc_to_canonical.nim` **20/20** (impl suite 포함 — Ambiguous 후보 나열·NotFound·정확 일치·owner-map 그림자화 회귀)
- `tests/gateway/rust_lane_cli_acceptance_test.nim` **20/20** (신규 suite 7 포함; `materializeTrackedCrate`의 `splitFile().name` 확장자 제거 버그(`lib.rs`→`lib`)는 `extractFilename(path)`로 수정)
- `tests/gateway/rust_subject_three_cases_test.nim` **10/10** · `test_rust_guard_attempt` **34/34** · `test_rust_input_contract` **39/39** · `test_rust_obligation_render` **11/11**
- 문서: README·`rust_certified_subset`에 monomorphic 게이트가 파라미터 디코딩보다 **선행**함을 기술(Dog::speak의 honest reason은 `Ref`가 아니라 `generic parameter 'regions'` — `&self` 무명 라이프타임)
- 커밋 체인(전부 게이트 PASS, dry-run 후 push): `3820bbe9d`(본체) → `73aa7b191`(pin reanchor) → `537b8f89c`(투영 sync) → merge #1173(`9ef2ca255`) → merge #1175(`d8afabf03`, PR head)
- main 이동 2회 대응: #1173(그들의 DEBT#510→511 재번호화)·#1175(#511 FIXED) — registry는 자동 병합으로 의미 정확, 충돌은 생성 투영 3종만 → 정본 경로 `bin/debt_engine --codegen` + `--sync-budget` 재생성으로 해소(BUDGET#005/006 동기화). 빈 pin 커밋 1건은 `git reset --hard`로 드롭.

## §3 사전병합 기준선 실측 (working tree @ `d8afabf03`, state `/tmp/ax_impl_state_*`)

- B `--target axiom_impl_probe::m1::Dog::speak`: exit 0, lane `done: verified=0/1 failed=0 unknown=1 error=0`, name=`axiom_impl_probe::m1::Dog::speak`(**fullName 그대로**), status=unknown, reason=`out-of-subset grammar (fail-closed): out-of-scope subject grammar — fail-closed UNKNOWN (not verified, not an internal error): generic parameter 'regions' outside the closed v1 grammar (monomorphic only)`
- C `m2::Cat::speak`: 동일 형상
- E `m1::add_u8`: exit 0, status=unknown, reason=`guard attempt: 1 goal(s); guard goal '4:boLt(5:boAdd(var(1:a,BV64),var(1:b,BV64)),lit(3:256))' declined by kernel; Z3 confirms a refuting candidate exists (script digest f32b31343521fd973ac5479e123a16a6d80a59d68845b60b645656d7f18519f1); counterexample confirmation unavailable (overflow-discretion class, out-of-subset per §3)`
- 트리(d8afabf03) == 트리(a24b8b82): a24b8b82는 3befe0315(main) ⊂ d8afabf03(자손)의 merge이므로 content 동일 — 사전병합 엔진과 merge SHA 엔진의 소스 정체성 일치.

## §4 병합 후 cold acceptance (고정 MERGE_SHA `a24b8b82`, worktree `/tmp/cold2_main`)

엔진: `git worktree add /tmp/cold2_main a24b8b82bd…`(detached, clean) → `make build` exit 0 → `bin/ax --check-provenance` **OK** — `AXIOM_PROVENANCE: OK — embedded BuildSourceHash == live src tree (4584204844708207837)`. 러너 verbatim: `artifacts/acceptance/runner_verbatim.txt`.

| 케이스 | --target | exit | 실측 (기계 출력이 권위) |
|---|---|---|---|
| A | `speak` (bare, 2개 충돌) | **3** | `resolved to more than one extraction target (Ambiguous): axiom_impl_probe::m1::Dog::speak, axiom_impl_probe::m2::Cat::speak. The rust lane requires exactly one match.` — **양쪽 fullName 나열** |
| B | `axiom_impl_probe::m1::Dog::speak` | **0** | lane done unknown=1/1; name=fullName; reason = §3 B reason — **사전병합과 byte 동일** |
| C | `axiom_impl_probe::m2::Cat::speak` | **0** | 동일 — **byte 동일** |
| NEG | `axiom_impl_probe::m1::Cat::speak` (잘못된 소유자) | **3** | `resolved to no extraction targets (NotFound or Ambiguous). … 0 matches = NotFound, >1 = Ambiguous. Refusing an implicit verification run on an unresolved target.` |
| D | `add_u8` (bare, 2개 충돌) | **3** | Ambiguous: `axiom_impl_probe::m1::add_u8, axiom_impl_probe::m2::add_u8` 나열 |
| E | `axiom_impl_probe::m1::add_u8` | **0** | 최초 런: Lean 참조추출기 `unknown module prefix 'IR'` — **환경 전제 결함(아래)** |
| EM | 동일 대상, 서브젝트를 `/tmp/cold2_impl_subject`(자체 git)로 복제 | **0** | 동일 'IR' 오류 → **경로 의존성 아님** 입증 |
| E2 | E 재실행 (`lake build` 후) | **0** | guard-attempt reason **사전병합 실측과 byte 동일**; stderr에 guard 상세: `goal[0/1] proved=false declinedByKernel=true z3Sat=true scriptDigest=f32b31…`, Z3 모델 `a=0xff, b=0xff` |

- **E/EM 'IR' 오류의 근거**: Rust 레인 참조추출기는 `lake env lean --run IR/RustReferenceExtractor.lean`(rust_extraction_agreement.nim:364, 인터프리티드, cwd=proofs)로 실행 — 신규 cold worktree엔 `.lake` 빌드 산출물(미추적)이 없어 `import IR` 실패(검색경로 `/tmp/cold2_main/proofs/.lake/build/lib/lean`). **코드 회귀가 아니라 재현 환경 전제**이며, EM(외부 경로 복제)이 동일 실패로 경로 의존성을 배제, `lake build`(21 jobs, exit 0) 후 E2가 기준선 재현으로 확정. 추후 cold 재현 절차에 Lean 빌드 프로비저닝이 필수 전제로 기록됨.
- **결정론 (기계 비교, `report_extract.txt`)**: B·C·E2의 name/status/reason이 사전병합 기준선과 **전부 byte-identical** (python 직접 비교 `==`). Ambiguous/NotFound 거부문도 사전병합 테스트 기대치와 동일 문구.
- 서브젝트 불변: pre(make build 직후)·post(전 런 후) sha256 동일 — `lib.rs ce67bd418246c87f…`, `m1.rs 9c5024ad6c489bc3…`, `m2.rs 785a0442d617f386…`, `axiom_impl_probe.llbc b591592865d5d9ca…` (전체값 `subject_sha256_post.txt`).
- vault 인증서: 0개 (검증 승인 없음 — honest).
- 부수 관측: 레인 실행이 `src/generated/build_metadata.json` 갱신(worktree porcelain 1 M) — 레인 자체 bookkeeping, 서브젝트 아님.

## §5 판정의 의미 (정직한 범위 경계)

- ②가 완결한 것은 **함수 identity 계약**: bare 이름 다중 정의 → 후보 나열하며 Ambiguous 거부, 구조화 fullName → 의도한 함수만 정확 선택, 잘못된 소유자 → NotFound, 암묵적 선택·전역 재유도 없음. DEBT#510 폐쇄.
- B/C(`Dog::speak`/`Cat::speak`)는 **증명되지 않았다** — reason은 out-of-subset grammar `generic parameter 'regions'`(`&self` 무명 라이프타임; monomorphic 게이트가 파라미터 디코딩보다 선행). Ref를 포함한 인증 문법 확장은 **③의 범위**.
- E(`add_u8`)는 unconfirmed counterexample(overflow-discretion class) — guard replay harness가 `src/lib.rs`만 바인딩(`rust_lane_cli.nim` `guardModulePath = projectAbs/"src"/"lib.rs"`)하는데 `add_u8`은 `m1`에 있어 재현 harness 컴파일 불가 → 정직한 overflow-discretion fallback. **사전존재 동작이며 ②와 무관**(②가 변경한 것은 대상 선택이지 guard 경로 아님).
- ②는 identity 계약 슬라이스이지 Rust 의미론 확장이 아니다 — Terminal state: **VERIFICATION_COMPLETE**(②의 판정 대상 = 대상 식별 계약의 기계 판정·재현·증거).

## §6 트리 정리

- 폐쇄 증거는 본 문서+artifacts로 별도 PR 랜딩 — main 직접 mutation 아님. cold worktree·state·vault는 /tmp(gitignored 영역 밖 실행 산출물), 주 저장소 tree clean(선존 미추적 `gh_env.txt` 미손대).
