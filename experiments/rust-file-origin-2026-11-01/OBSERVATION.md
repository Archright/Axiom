# OBSERVATION — §6d ① LLBC files-table 절대경로 출처 분류 `embeddedContentAttested` (사전병합 기준선)

- EXPERIMENT_ID: rust-file-origin-2026-11-01
- Written: 2026-11-01, branch `work/rust-file-origin-2026-11-01` (미커밋 working tree). 관측 사실만 기록 — 기계 출력은 verbatim 또는 sha256.
- Governing contract: `docs/spec/productization_contract.md` §6d (동일 working tree)
- Subject: `<workspace>/json` @ `8c535a260ce561eaab4111aafc29038eb9f77ff3` (실행 내내 clean)
- Target: `serde_json::error::parse_line_col`
- Charon pinned==measured `0.1.281 (798016509139eb51f0d764645f76d068d34ba5f6)` ok=true (런 stdout verbatim)
- State lock seed: `experiments/serde-json-claim-2026-10-31/state_d1/data/verification_scope.lock` byte copy — sha `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` (④ 프로토콜)
- Cargo.lock 프로토콜: `experiments/serde-json-claim-2026-10-31/inputs/Cargo.lock` sha `1bc62b1a4645e18c7856073376f0601348f874d47a854e55261955381061b2e4` place→run→out sha 동일→remove (양 런 모두)
- Env: `CARGO_NET_OFFLINE=true`, `GITHUB_TOKEN` via `gh auth token`(값 미출력), fresh `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR` (/tmp 하위)

## §1 Fresh-state LLBC 재추출 (실측)

Fresh state → 레인 재추출: rust-lane dir `1398235db249fc8b`, files 테이블 151 엔트리, 주체 15 = 상대경로 소스 14 + 절대경로 `…/charon-target/…/out/private.rs` (index 1, contents string) — d1과 동일 형상(차이는 run-relative prefix와 빌드 해시뿐: `b579eb18e836c66a` vs d1 `211aa9d180883da9`). d1 보존 LLBC sha `17113512a770a39e0614254f4bbd09211a955f9dde1b00bd8354552985ce5784`, fresh `e9abf8f4abf068f7910feadf67999a0ba7e1703c123e0329e1f8feb03e6998f3`.

## §2 Run 1 — 결함 관측 (엔진 BuildSourceHash 8909617506688019767)

- exit 0, 서브젝트 불변. Sidecar identity: `rejection: null` — §6c v2 `path_absolute` 거절이 **소멸** (파일테이블 층이 해당 항목을 수용) — 그러나 `embeddedContentAttested` 키 부재(null).
- 원인(코드 추적으로 국소화): `rustSubjectOutcome`의 계약 실패 조기 반환이 `contract.embeddedFiles`(§6d **측정값**)를 폐기 — 파일테이블 하위검사는 통과했고 계약 레벨 결과는 그대로 갖고 있었음(단위 masquerade 테스트가 `c.embeddedFiles.len == 1`을 이미 검증). ④가 rejection을 실패 경로에서 sidecar에 기록한 것과 비대칭.
- 수정: 조기 반환 **앞**으로 측정 전파 이동(1줄) + 타입/필드 doc 정합화 + 단위 회귀 "§6d outcome wiring: embeddedFiles survive a later contract sub-check refusal". 판정·reason 변경 없음(측정 전파일 뿐).
- 결함 런 산출물 verbatim 보존: `artifacts/defect-run/` (sidecar·payload·stdout).

## §3 Run 2 — 수정 엔진 (BuildSourceHash 9090236443785619195) — ① 기능 증거

- `bin/ax prove --project … --target 'serde_json::error::parse_line_col'` exit 0 (~14s)
- Sidecar sha256 `c3ccb339789bdd9d8a78f8f484e95b70aff2dc5b2675f06581f3e31e34c9eca2`; canonical payload(`jq -S .extra`) sha `9ca83701e057e05e69b91c6b4ebe68fd74fc64e305a59741ff162a55b9c1b539`
- `identity.embeddedContentAttested = [{index: 1, crateName: "serde_json", contentSha256: "30c7e046bfa6c6cf17498e5dac35232b89cb62a2116ba976bfd749bdc763c143"}]` — content sha는 ④에서 3회 콜드 실측한 `30c7e046…`와 동일
- 생산시점 결속 체인 기계 재검증 (비교기 self-pair, 동일 산출물 양측): verdict **equal** (identity/structure/reason 3축), notes "left/right re-measurement — all 4 anchors match the recorded declarations" (subject.commit·moduleSha256·sourceFingerprint·scope.rustTargetsSha256). 기록: `artifacts/compare_selfpair.json`
- 서브젝트 불변: pre/post find+sha256 manifest 동일 (양쪽 sha `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4`)
- 판정 (verbatim — 실측이 권위, 사전 고정 안 함): `status: unknown`, reason `producer: rust subject input contract FAILED (LLBC not current with the subject source — fail-closed): subject file(s) missing from the LLBC local table: [58 파일 — build.rs, fuzz/fuzz_targets/from_slice.rs, src/io/{core,mod}.rs, src/lexical/* 21, src/macros.rs, src/raw.rs, tests/* 31]` (전체 목록 `artifacts/payload.pre.json`)

## §4 판정의 의미 (정직한 범위 경계)

- ①이 완결한 것은 **파일테이블 층**: 절대경로+문자열 contents 항목 수용·내용 결속, null contents의 `path_absolute` byte 불변, 중복 `embedded_path_duplicate` 거절, 위장(masquerade)은 여전히 missingInLlbc로 fail-closed.
- 서브젝트는 **여전히 입력 계약을 통과하지 못한다**: 파일집합 동치 하위검사(① 이전부터 존재, ①이 변경하지 않음)는 디스크 `.rs` 집합 == LLBC local table를 요구 — serde_json은 58개 디스크 파일이 테이블 밖(기능게이트 lib 모듈 io/lexical/macros/raw + tests/ + fuzz/ + build.rs — lib-target LLBC가 결코 포함할 수 없는 것들). 이는 다음 신뢰경계 질문(실세계 서브젝트에 대해 D1 디스크 집합이 무엇을 비교해야 하는가 — 별도 계약 결정)이며 **명시적으로 ① 범위 밖**이다.
- `parse_line_col`은 증명되지 않았다 — 이 슬라이스는 입력 수용 확장이지 인증된 Rust 의미 확장이 아니다(문법 추가 없음).

## §5 검증 체인 (사전커밋, 동일 working tree)

- `make build` ✅; `bin/ax --check-provenance` OK (BuildSourceHash `9090236443785619195`)
- `make verify-contract-release-e2e-full` → **PASSED** (exit 0; G7 pass tier=dual-verified status=verified; cert `data/trusted/certificates/e57ee9394d16b8dcb8a859eb205f59a55dc3926227dc2250a21448c8d5ebf200.json`) — ④가 기록한 honest residual "e2e-full never run" 폐쇄
- `tests/unit/test_rust_input_contract.nim` → **39 [OK] / 0 [FAILED]** (rule 5a-1/2/3, masquerade, §6d propagation + 신규 실패경로 wiring 회귀 포함; real-probe 스위트는 env-gate로 부재)
- gateway 스위트 12/13 — 유일 실패 `run_gate_feature_test`는 **사전존재** (순수 base aa155017 /tmp/base_run_gate worktree에서 동일 2 nimtry 위반 재현 — ④ #1162의 zombie-runner 포함; 별도 debt-hygiene 작업)
- bare `bin/ax prove`(커널 전체) exit 1 — **사전존재**: 순수 base aa155017 detached worktree(fresh `make build` ✅, provenance OK `1581309748423241377`)에서 exit 1 + **동일 psFail 집합**(calcDynamicTimeoutCore smNone/pkNone, safeSpeedupRatioCore smBMC/pkNone, cold에선 proximityScore 추가) + `contestedCount=2 ⇒ GateVerdict=FAIL (fail-closed)` 재현 — 기계 관측: ①은 커널을 회귀시키지 않았다.

## §6 병합 후 (계획 — 랜딩 시 기록)

고정 mergeCommit.oid에서 cold acceptance: A(원본)/B(/tmp 사본) + C(source 음성)/D(scope 음성) + 서브젝트 manifest 불변. 기대: A/B 3축 **직접 equal**(missingInLlbc reason은 서브젝트-상대 파일 목록으로 위치 비의존 — run 경로 span 없음, ④식 경로 span 승격 불요), embedded 재현, C/D not_equal.

## §7 병합 후 cold acceptance (실측 — 2026-11-02, 고정 MERGE_SHA)

- MERGE_SHA `743e7222036b182609d5e7f1a06434bd8774412a` (PR #1170 MERGE, mergedAt 2026-11-01T15:45:46Z). 착지 관측 3축 일치: GitHub graphql↔rest(`state=MERGED ∧ mergedAt ∧ mergeCommit.oid ∧ parents=2`) + 로컬 git(`parents: 73140f84fac4db607f7b27bc9403384ce496115b`=#1169 merge, `1ba6257c968e9e315a4b94c86ccd2e9c94de3643`=PR head; origin/main tip·containment 확인). admission-gate merge_group run 41321805126 conclusion=success.
- 엔진: MERGE_SHA 체크아웃(`repro/rust-file-origin-1`) → `make build` exit 0 (37.98s) → `bin/ax --check-provenance` OK — BuildSourceHash `9090236443785619195` (§3 기준선 엔진과 동일 — 병합 전 working tree 기준선 ↔ 병합 후 고정 SHA의 엔진 정체성 일치). 비교기 `build/skreport_compare_tool` 빌드 exit 0.
- 4런(공통: `CARGO_NET_OFFLINE=true`, GITHUB_TOKEN=`gh auth token`(값 미출력), fresh `AXIOM_STATE_DIR`/`AXIOM_PROVE_VAULT_DIR`, lock seed byte copy sha `0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e` — D만 `jq -S .` 재직렬화 sha `ea0d86dd00f5b9d4259490011a3bb75e74818a58fa996e40acf86c773bcd8eec`, Cargo.lock `1bc62b1a…` place→run→remove, 러너 `artifacts/acceptance/run_acceptance.sh.txt`):
  - A 원본 `<workspace>/json` · B `/tmp/axiom-accept1/json_b`(cp -a) · C `json_c`(src/error.rs +1 코멘트) · D=json_b+lock 재직렬화. 러너 wall 61.23s.
  - 전 런 exit 0, stdout 판정 `done: verified=0/1 failed=0 unknown=1 error=0`(기준선 §3과 동일 — §4 범위 경계 유지), charon pinned==measured ok=true.
- 서브젝트 불변: pre/post find+sha256 manifest 전 런 동일 — A/B/D `8045f3b1ce56398fe506aeec9f9344405e32cd7dffda64ddaff4dbd0db6c7cd4`, C `ce881efd4ae0c33c879edd8082a893dacbef6f8be2f2c427423c659ba5ee9b4f`(C 고유 identity도 실행 내내 불변).
- 비교(`build/skreport_compare_tool` 8인수 앵커 재측정 형태, 판정 기록 `cmp_{ab,ca,da}.json`):
  - **A vs B: `equal`** — identity/structure/reason 3축 전부 equal. §6 기대대로 직접 equal(경로 span 승격 불요). 양측 재측정 앵커 "all 4 anchors match the recorded declarations"(subject.commit·moduleSha256·sourceFingerprint·scope.rustTargetsSha256).
  - **C vs A: `not_equal`**(identity축) — moduleSha256 `d0522b19dbd0b40006aa10c11c80426961568e156097bec1a8257275e19173f1`↔`a13add05a63adf53d89e37effa03221d897a60486cfe360a5a958c0dd2a7e90d`, sourceFingerprint `03193e47bda322ef5d57a02b8c9dc4598c4670e2336452c95437620e1ef97284`↔`f03e32dc7effa2b39cc692bfbc8639aa0eb7a26207d0aafd4777f9f44c0378a0` — 코멘트 1줄 차이 포착. structure/reason equal(파일집합 동일).
  - **D vs A: `not_equal`**(identity축) — scope.rustTargetsSha256 `ea0d86dd…`(재직렬화)↔`0c1f4abca316f8c26a247731cadc1eacc93ace2b49c2f3b55f4eb43909b6004e`(byte copy). 의미 동일 lock이라도 바이트가 다르면 동일로 판정하지 않음(정직한 fail-closed).
- 결정론 교차검증: payload A=B=기준선 §3 `9ca83701e057e05e69b91c6b4ebe68fd74fc64e305a59741ff162a55b9c1b539` **byte 동일**; sidecar A=B=기준선 `c3ccb339789bdd9d8a78f8f484e95b70aff2dc5b2675f06581f3e31e34c9eca2` **byte 동일**(lane id는 서브젝트 절대경로별 상이: A `1398235db249fc8b`, B/D `1b86d759ac29eecb`, C `30b0a152c2555e17` — sidecar/payload 내용은 경로 비의존). C payload `07e3021d…`, D payload `3246e911…`, sidecar C `4cb99fc1…`, D `57cb0c0a…`(의도적 차이).
- embedded 재현: 전 런 `embeddedContentAttested = [{index:1, crateName:"serde_json", contentSha256:"30c7e046bfa6c6cf17498e5dac35232b89cb62a2116ba976bfd749bdc763c143"}]` — ④ 3회 콜드 실측·§3 기준선과 동일(C의 embedded content sha 동일은 생성물 private.rs가 error.rs 코멘트의 영향을 받지 않는다는 관측 — C 음성 판정은 moduleSha256/sourceFingerprint 앵커가 담당).
- §6 기대 판정 **전부 실측 달성** → ① 슬라이스 Terminal state: `VERIFICATION_COMPLETE`(①의 판정 대상 = 파일테이블 층 입력 수용 확장 — §4 명시 범위). serde_json 서브젝트 전체의 판정은 여전히 `unknown`(missingInLlbc 58파일 — ① 범위 밖 다음 신뢰경계 질문, 별도 계약 필요).
- 산출물: `artifacts/acceptance/`(payload×4·sidecar×4·cmp JSON×3+stderr×3·run stdout×4·provenance·summary·러너 — `*.log`는 gitignore되어 `.txt`로 보존).

### §7.1 트리 정리

- 폐쇄 증거는 본 §7+artifacts로 별도 PR(`work/rust-file-origin-acceptance-2026-11-02`) 랜딩 — main 직접 mutation 아님. 체크아웃·빌드 산출물은 gitignored, tree clean(선존 미추적 `gh_env.txt` 미손대).
