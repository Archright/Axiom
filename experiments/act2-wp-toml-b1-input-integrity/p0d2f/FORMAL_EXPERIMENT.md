# P0-D2-F — 정형검증 실험 기록 (S1 명세 하의 결함 커널 반증 + 대조 커널 Lean 검증)

Experiment: `act2-wp-toml-b1-input-integrity/p0d2f` · Date: 2026-10-17
명세: `SPEC.md` (정형명세 S1·커널 정의·비판 검증표·Amendment) · 재현: `replay_formal.sh`
증거: `evidence/` (41파일, README·SHA256SUMS 포함 — `SHA256SUMS`가 대응 보증)

## FACT SHEET

### Question

S1(UTF-8 바이트 길이 법칙 — `SPEC.md` §정형명세) 명세 하에서
`ax prove --project`가 **결함 커널은 반례로 반증**하고 **대조 커널은 통과**시키는가?
(Terminal: main 병합 후 `replay_formal.sh`로 재관측 — 끝의 「ACCEPTANCE 상태」 참조.)

### Context

| 항목 | 값 |
|---|---|
| subject | status-im/nim-toml-serialization @ `4aa8e2223649fc0837c490a4acfca7b8b1e756f9` (읽기전용 클론, `git status --porcelain` 비어있음 — 전 실험(`../p0d2/RT_EXPERIMENT.md` 포함)과 동일) |
| 변이 | `d2kernels.nim` 추가 단일 파일 (`variant.patch`; baseline 트리 대상 유일 delta), sha256 `d15f8a98bf2c32dcfa58a20fed6a3ed5f0f3dd65d4173e6e429c51aa76b26875` |
| Axiom | 본 브랜치 `followup/d2-formal-axprove` (커밋 `0c8225cc3` + 본 기록 커밋), `bin/ax` sha256 `36642c5453411c11906727afa9141767ef620430494ebe077b878468ec39baaf` |
| 툴체인 | Nim 2.2.10 [Linux: amd64] · z3 4.13.3 · Linux x86_64 |

### Scope

커널 2개만 — `d2HexEscapeAppendLen`(결함)·`d2Utf8AppendLen`(대조). 원본 함수 직접
추출, firstByte 바이트 값 법칙, 왕복 등가성 1급 명세, 인코더 출력 행 인증은
**범위 밖** (`SPEC.md` §범위 밖 1·2·3·4·6).

### Procedure

baseline(honest-zero) → 1차 실행(양 커널 exit 2 거부) → 동치 재표기(Amendment) →
P4b(재표기 후 결함/대조 런) → 콜드 재실행·경로 독립(env2 materialization)·cwd 축
(cwd=$EXP vs Axiom3 루트) → **커밋 후 재실행(defect6/control6, cwd=Axiom3 루트)**.
각 런의 명령·state·vault 대응은 `evidence/README.md`가 운반한다. 원시 산출물은
슬라이스 gitignore 디렉터리(`runs/`·`state_*/`·`vault_*/`·`env*/`)에 그대로 남는다.

### Result (모두 기계 관측)

1. **baseline** — exit 0, 344 후보 중 eligible 0, solver 0, vault 빈,
   digest `1b0455cc95f8668ff90e30abe839143dd3e8030a5ab2b29a6a0c8e1936789603`
   (honest-zero: 타깃 없는 빈 런도 결정적 digest를 낸다).
2. **1차 실행** — 양 커널 exit 2 거부. 후건의 if-표현식이 Canon 프론트엔드에서
   lossy 판정: `toCanonKind`의 `nkElifExpr`/`nkElseExpr` 매핑 부재 +
   `convertExprCanon`의 `ckIfStmt` 암 부재(`src/verification/ast_to_ir.nim:1046`).
   동치 재표기 `1+(code div 128)`로 해소 — **S1의 의미 불변, 표기만 변경**
   (`SPEC.md` §Amendment; Axiom 측 갭은 개선 후보로 기록, 본 슬라이스에서 수정 안 함).
3. **결함 커널** (`d2kernels.nim::d2HexEscapeAppendLen`) — exit 1,
   plannedNodeCount 1 · failedCount 1,
   `invariant does not imply postcondition` (`runs/defect6.err:27`),
   vault manifest `d2HexEscapeAppendLen` **certRed** 행 (irHash `4cbb02ff…9997`),
   claimOutcome **`clDisproved`**. 반례 모델 **code=128** (재생 하니스
   `echo $d2HexEscapeAppendLen(128)` — `replay_harness_code128.nim`로
   `evidence/defect/`에 보존). digest `55ac23c419fe2155bb4232511580eaf6f11c0e8d90f1353d2f6d066d5872e65c`
   — cold(state_v5)·경로(state_v7)·cwd(state_v9) 전부 동일, **커밋 후 defect6(state_v11)도 동일**
   (재생 불합치로 BUG_FOUND 페이로드가 런 결과에 진입하지 않아 구관측치가 그대로 핀 baseline).
4. **대조 커널** (`d2kernels.nim::d2Utf8AppendLen`) — exit 0,
   **`certLeanVerified`** (SPEC 기대 `certZ3Candidate` **상회**). Lean 정리
   `∀ code, (0 ≤ code ≤ 255) → d2Utf8AppendLen code = 1 + code/128`을 `omega`로
   Lean 4 커널이 검증 (인증서 `leanSource` 필드에 정리 전문). 인증서
   `14006f9720c32db3a3fc8ac25450d1ffb8634920017e5c9b2b69aee44dad7ac2.json`,
   Ed25519 서명 저널 `journal_8deb….json` 수반, 경로·콜드에서 바이트 동일.
   digest `8549934738719edb3b5e55e03cfa489a8b006f5de742e60fb17e23226bab92fd`
   — cold(state_v6)·경로(state_v8)·cwd(state_v10)·**커밋 후 control6(state_v12)** 전부 동일.
5. **재생 2중 게이트** — Q1(cwd 상대 config.nims 부트스트랩)·Q2(porcelain 드리프트)
   (`docs/spec/replay_harness_config_quirks.md`). **커밋 후 재실행(defect6) 결과:
   재생 불합치 지속** — 결함 커널의 재생 판정은 여전히 fail-closed
   `cvUnresolved`이며, `replay_formal.sh`의 C1a(재생 합의 BUG_FOUND)는 미관측.
   상세는 아래 「재생 불합치 — 커밋 후 관측과 원인 정정」.

### 재생 불합치 — 커밋 후 관측과 원인 정정 (defect6, 2026-10-17)

Q2의 치유 가설(「Axiom3 트리 커밋 → porcelain 공백 → 재생 합의 관측 가능」)은
**기각되었다**. 클린 트리 + cwd=Axiom3 루트에서의 커밋 후 재실행(defect6:
state_v11·vault_defect6)에서 결함 커널 재생은 **동일 문구로 실패**했다:

```
runs/defect6.err:29
[INFO] ir_pipeline_runner: [ce-replay] d2HexEscapeAppendLen — replay rvUnavailable:subject tree drifted during replay (hash/porcelain mismatch); fail-closed cvUnresolved
runs/defect6.err:69
[Depth 1/1] Checking: d2kernels.nim::d2HexEscapeAppendLen... [FAILED]
```

**원인 (코드 수준 확정)** — 드리프트 게이트가 검사하는 porcelain은 **주체 저장소**의
것이다. `confirmPostRunIntegrity`는 `git -C <repoRoot> status --porcelain`을
요구하고(`src/verification/counterexample_replay.nim:519`), `repoRoot`는
`--project`의 sourceRoot에서 스레드된 주체 저장소 루트다
(`src/cli/axiom_engine.nim:2303` → `resolveSubjectRepoRoot`,
`src/verification/obligation/canonical_verification.nim:765`). 본 실험의 변이
materialization(`git clone` + `variant.patch` 적용)은 주체 저장소
`env/subject_variant`에 `d2kernels.nim`을 **스테이지된 추가(` A d2kernels.nim`)로
남기므로 주체 porcelain은 구조적으로 비어 있을 수 없다**. 즉 커밋이 비운 것은
Axiom3 쪽 porcelain이고, 게이트가 요구하는 것은 주체 쪽 porcelain이라
Q2 치유는 이 실험 형태에서 원리적으로 불가능했다.

`docs/spec/replay_harness_config_quirks.md` Q2의 defect5 귀속
(`?? experiments/…/p0d2f/` — Axiom3 쪽 dirt)은 관측 시점의 가설이었으며, defect6의
대조 관측(트리 커밋 후에도 동일 실패)이 **귀속을 주체 저장소 쪽으로 정정**한다.
퀴크 문서의 Cause 절은 위 코드 근거에 따라 정독되어야 한다 — Symptom·완화(cwd=$ROOT
고정)는 유효하나, 「커밋된 클린 트리에서만 관측 가능」의 주체는 Axiom3가 아니라
**주체 저장소**다. 재생 합의(BUG_FOUND → DISPROVED 승격)를 관측하려면 변이를
주체 저장소 안에서 커밋한 변이 커밋이 필요하다 — 개선 후보로 「다음 실험」에 기록.

**판정에 미치는 바**: 결함 커널의 반증 자체(SAT 반례·certRed·clDisproved)는
변함없이 관측되었으나, 재생 합의(C1a)가 없으므로 본 슬라이스의 ACCEPTANCE는
`replay_formal.sh` 기준 **INCOMPLETE (replay unavailable, refutation observed)**
에 머문다 — 승격은 main 병합 후 Phase 8 재생에서 판정된다.

### Evidence

`evidence/` 41파일(README·SHA256SUMS 포함; baseline 5·defect 16·control 12·
first_attempt_refusal 5) — `evidence/SHA256SUMS`가 파일 대응을 보증한다. 원본 raw는
이동시키지 않고 슬라이스 gitignore 디렉터리(`runs/`·`state_*/`·`vault_*/`·`env*/`)에
그대로 두었으며, 커밋 후 재실행 원본도 동일 위치(`runs/defect6.*`·`runs/control6.*`·
`state_v11/`·`state_v12/`·`vault_defect6/`·`vault_control6/`)에 남는다. 전체 런의
재생성은 `replay_formal.sh`가 담당한다.

### Classification

- **결함 커널 = 반증(refutation)** — SAT 반례(code=128)·certRed·claimOutcome
  `clDisproved`. 재생 합의는 **불합치(cvUnresolved)** — 위 관측대로 명시한다.
  즉 슬라이스 verdict는 DISPROVED로 승격되지 않고 **반증 관측 + 재생 불가**로 분류된다.
- **대조 커널 = certLeanVerified** — 제한 아님: Lean 4 커널 검증(최상위 등급).
  (SPEC 기대 `certZ3Candidate`를 상회한 관측.)
- **전체 슬라이스 분류**: "실제 결함에서 추출한 커널을 이용한 정형검증 파이프라인 실증"
  — 동일 명세 S1에 대한 판별력(differential) + 결정론 4축 + 재생 게이트 2중 실측.

### Interpretation

- **파이프라인 판별력 실증**: 동일 명세 S1을 양 커널에 적용했을 때 결함 커널만
  반례(SAT)로 반증되고 대조 커널은 Lean 커널 검증까지 통과 — 음성 대조군이
  파이프라인·명세 주입의 결함을 배제한다(SPEC §커널 정의 차동 설계).
- **결정론 4축 확증**: 결함 digest `55ac23c4…`·대조 digest `85499347…`가
  cold(state_v5/v6)·경로(state_v7/v8)·cwd(state_v9/v10)·재실행(state_v11/v12,
  커밋 후) 전축에서 동일. 대조 인증서는 경로·콜드에서 바이트 동일.
- **외부 주체 경로(§10) 실동작 확인**: `ax prove --project <외부 트리>`가 읽기전용
  외부 클론 위 변이에서 정상 파이프라인(수집→Z3/Lean→인증서 발행)을 수행했다.
- 커널↔원본 대응은 최소 diff(`lexer.nim:428-429` 1행 추출)+출처 주석+p0d2 런타임
  바이트(E9 vs C3 A9)로 뒷받침되나 **정형 검증 아니다** — 우발적(accidental)
  근거 체인까지만 허용된다(SPEC §범위 밖 6).

### Non-Conclusions

- 원본 `scanHexEscape`의 **직접** 정형 반증이 아니다 — SAT의 대상은 추출 커널이다.
- 대조 커널의 `certLeanVerified`는 라이브러리 전체의 정확성을 증명하지 않는다 —
  담보는 "대조 커널이 S1을 [0,255] 전 도메인에서 만족한다"까지만이다.
- firstByte 바이트 값 법칙·왕복 등가성·인코더 인증은 포함되지 않는다.
- 대조 UNSAT/검증의 "원본 정합성 증명"으로의 확대는 금지된다(SPEC 비판 검증표 5).

### Next Experiment (후보)

1. **Canon 프론트엔드 if-표현식 커버리지** — `toCanonKind`의 `nkElifExpr`/`nkElseExpr`
   매핑과 `convertExprCanon`의 `ckIfStmt` 암 추가(Axiom 개선; 1차 거부의 원인).
2. **원본 함수 직접 IR 추출** — 제네릭·예외·플래그 경로를 포함한 원본
   `scanHexEscape` 통째 추출(SPEC 범위 밖 3의 해소).
3. **변이 커밋 변이 커널** — variant를 주체 저장소 안에서 커밋한 변이 커밋으로
   materialization하여 Q2(주체 porcelain)를 통과시키고 재생 합의(BUG_FOUND →
   DISPROVED 승격)를 관측한다(위 원인 정정의 직접 후속).
4. 바이너리 실행 타깃 — §10.4 후속 Act.

---

## ACCEPTANCE 상태

최종 판정은 `replay_formal.sh`가 낸다 — 조건 C1(결함 반증)·C1a(재생 합의)·
C2(대조 검증)·C3(cold 결정론, 핀 digest `55ac23c4…`/`85499347…` 고정 비교)·
C4(경로 독립)·C5(증거 완전성)의 6조건 판정표와 ACCEPTANCE verdict.
**main 병합 후 Phase 8에서 실행**이 예정되어 있으며, 현재 관측(C1a 미관측 — 위
재생 불합치) 하의 예상 종료는 `INCOMPLETE (replay unavailable, refutation observed)`
이다. 본 문서는 그 판정을 대신하지 않는다.
