# CI 임계경로 보호 매트릭스 — "이 최적화는 불가능하다"의 증거

> **성격**: 관측 기록(evidence). 정책·config 파일은 하나도 수정하지 않는다. 본 문서는
> `main` @ `160e70cd` (2026-11-24T05:43:31Z 조회) 에서 계산한 결과를 기록한다.
> **목적**: admission 임계경로상의 각 파일을 어떤 통제 장치가 잠그는지 권위 있는
> 재현 가능한 표로 고정한다 — "불가능하다"를 가정이 아니라 증거로 말하기 위해서다.

## 0. 측정 환경과 재현 방법

| 항목 | 값 | 측정 명령 |
|---|---|---|
| 기준 커밋 | `160e70cda364e5745133d3f04d2e1295b4a026df` | `git rev-parse HEAD` |
| 조회 시각 (UTC) | `2026-11-24T05:43:31Z` | `date -u +%Y-%m-%dT%H:%M:%SZ` |
| `repository_surface.json` `policyVersion` | `108` | `python3 -c 'import json;print(json.load(open("config/repository_surface.json"))["policyVersion"])'` |
| 네 소스 규모 | manifest 18 / trustSurface 39 / closure 891 / surface FROZEN 12 | 아래 §1 |

판정 규칙은 손으로 세지 않고 `tools/surface_guard.nim`의 의미론을 그대로 옮긴
분류기로 계산했다 — `globMatch`(`tools/surface_guard.nim:186`, 세그먼트 단위,
`**`는 0개 이상의 세그먼트를 삼킨다)와 `resolveClass`(`tools/surface_guard.nim:245`,
PRODUCT → CONTROLLED → FROZEN first-match 후 `defaultClass`)를 1:1 이식했다.
재현 스크립트는 §7에 전문을 싣는다.

## 1. 네 개의 통제 장치 — 각각 무엇을 실제로 집행하는가

| # | 소스 | 규모 | 집행 주체 | 판정 의미 |
|---|---|---|---|---|
| A | `config/policy/trust_surface_manifest.json` `paths` | **18** | **외부** GitHub App `axiom-admission-verifier` (id `5795152`) | `blob(G) == blob(B_mg)` 아니면 `admission-check` **발급 거부** |
| B | `config/policy/merge_admission.json` `trustSurface` | **39** | `src/cli/merge_cli.nim` `trustSurfaceMatch` (`:954`) | 매칭 시 auto-merge 거부 → **수동 병합 레인** |
| C | `config/trusted_checker_closure.json` `trustedCheckerTreeClosure` | **891** | `.githooks/pre-push` rotation-pin 앵커 (`:565-646`) | 핀이 커밋을 앵커하지 못하면 **push 차단** (`rotation pin does not anchor pushed commit`) |
| D | `config/repository_surface.json` `classes.FROZEN` + `frozenExceptions` | FROZEN 12 패턴 / 예외 116 경로 / 8 그룹 | `tools/surface_guard.nim` (in-tree) + SL-20 step | `SURFACE_FORBIDDEN` → `admission-check` step FAIL |

**A의 규모 정정**: `trust_surface_manifest.json`의 `paths`는 **18개**다(파일 자체
`:7-24`). 이 저장소의 여러 문서는 여전히 "15-path"/"17-path"로 적고 있다
(`.github/workflows/admission-check.yml:37`, `docs/agents/axiom_admission_verifier_ops.md:90`,
`data/debt_registry.json` DEBT#558의 "17 paths"). 이는 **문서 드리프트**이며, 본
문서는 파일에 적힌 실제 값을 쓴다.

**B는 glob을 포함한다** — `.github/actions/setup-axiom-toolchain/**`(39개 중 5번째).
exact 문자열 비교로만 검사하면 이 항목을 **조용히 놓친다**. 최초 계산에서 실제로
놓쳤고, glob 매칭으로 고친 뒤 재계산했다. 이것이 "눈으로 세지 말 것"의 실증이다.

## 2. 14개 파일 보호 매트릭스

범례: A = App byte-identity(manifest), B = trustSurface(수동 병합), C = checker
closure(891), D = repository surface 클래스. `—` = 해당 없음.

| # | 경로 | A | B | C | D (해석된 클래스 / 매칭 패턴) | 판정 (전부 나열) |
|---|---|---|---|---|---|---|
| 1 | `.github/workflows/axiom-operational-slice.yml` | **Y** | **Y** | — | **FROZEN** / `.github/**` | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_FROZEN` |
| 2 | `.github/workflows/admission-gate-v2.yml` | **Y** | — | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `SURFACE_EXCEPTION(admission-mint-pin-rotation)` |
| 3 | `.github/workflows/admission-check.yml` | **Y** | **Y** | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(epoch-rotation)` |
| 4 | `.github/workflows/certificate-mint.yml` | **Y** | **Y** | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(admission-mint-pin-rotation)` |
| 5 | `.github/workflows/runner-pool-acceptance.yml` | **Y** | **Y** | — | **FROZEN** / `.github/**` | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_FROZEN` |
| 6 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** (glob `**`) | — | CONTROLLED / exact | `APP_BYTE_IDENTITY`, `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(trust-supply-path)` |
| 7 | `src/gate/runners/readiness_start_gate.nim` | — | **Y** | — | CONTROLLED / exact (FROZEN glob `src/gate/**`와 교차) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_EXCEPTION(gate-infra)` |
| 8 | `tools/readiness_evaluator.nim` | — | **Y** | — | PRODUCT (미등록) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 9 | `tools/ci/readiness_collect_ci.nim` | — | **Y** | — | PRODUCT (미등록) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 10 | `config/readiness_policy.json` | — | **Y** | — | PRODUCT (미등록) | `ADMISSION_MANUAL_AUDIT`, `SURFACE_PRODUCT` |
| 11 | `tools/ci/ci_admission_observe.nim` | — | — | — | PRODUCT (미등록) | `SURFACE_PRODUCT` |
| 12 | `tests/ci/test_ci_admission_observe.nim` | — | — | — | PRODUCT (미등록) | `SURFACE_PRODUCT` |
| 13 | `docs/spec/ci_critical_path_metric.md` | — | — | — | PRODUCT (미등록) | `SURFACE_PRODUCT` |
| 14 | `config/repository_surface.json` | **Y** | — | — | **FROZEN** / exact | `APP_BYTE_IDENTITY`, `SURFACE_FROZEN` |

**C가 전부 `—`인 이유**: 891개 항목은 `src/` 879 + `tools/` 7 + 루트 2 + `ci/`
1 + `config/` 1 + `tests/` 1 로 구성되며, 14개 중 어느 것도 포함되지 않는다.
`tools/` 7개는 `derive_checker_closure.nim`, `impact_closure_selector.nim`,
`proof_reconcile_gate.nim`, `hermetic_build.nim`, `safe_move.nim`, `setup_hooks.nim`,
`sha256_native.nim` 이다. 즉 **C는 이 14개 경로에 대해 아무것도 잠그지 않는다.**

**핵심 대비**: 같은 임계경로 위의 두 파일이 서로 다른 등급이다 —
`tools/readiness_evaluator.nim`(B만, `SURFACE_PRODUCT`) vs
`src/gate/runners/readiness_start_gate.nim`(B + `gate-infra` 예외). 전자는
surface guard가 `MODIFY=PASS`로 통과시키고, 후자도 예외 등재 덕에 통과한다(§3).
그러나 **둘 다 B에 걸려 자동 병합은 거부된다** — 이것이 두 장치가 독립임을 보이는
한 쌍이다.

## 3. 질문: `frozenExceptions` 등재는 App의 byte-identity를 열어주는가?

**아니다. 오직 repository surface guard만 연다.** 근거는 세 층이다.

### 3.1 surface 쪽 — 코드로 확인한 집행

| 사실 | 증거 |
|---|---|
| `classify()`는 `frozenExceptions`를 **한 번도 읽지 않는다** | `tools/surface_guard.nim:491` `classify()` → `:519` `resolveClass(policy, p)` → `:520` `ruleValue(...)` 뿐. 예외 레지스트리 조회 없음 |
| `frozenExceptionPaths()`의 유일한 호출자는 **테스트** | `grep -rn frozenExceptionPaths tests/ src/ tools/` → 정의(`tools/surface_guard.nim:273`) + `tests/unit/test_surface_guard.nim:766` 뿐 |
| 예외는 **정책 유효성** 장치다 | `tools/surface_guard.nim:445-466`: exact CONTROLLED/PRODUCT 등재가 FROZEN glob과 교차하면(`:445-460`) 등재를 **요구**하고(`:461-463` — 미등재 충돌은 `POLICY_INVALID`), 등재됐지만 교차하지 않으면 **거부**한다(`:464-466`, DEBT#545 dead exception) |
| 예외가 실제로 바꾸는 것 | 그 경로가 first-match에서 `CONTROLLED`로 해석되게 만드는 **클래스 등재 자체**다. 116개 중 115개가 `classes.CONTROLLED`에 그대로 있고, 나머지 1개는 `classes.PRODUCT`에 있다 |

실측 확인 — 같은 정책·같은 가드 바이너리(`bin/surface_guard`, policyVersion 108):

```text
$ printf 'M\t.github/workflows/admission-gate-v2.yml\n' > /tmp/d.txt
$ ./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt
verdict=PASS reasonCode=OK                   # 예외 그룹 등재 경로
exit=0

$ printf 'M\t.github/workflows/axiom-operational-slice.yml\n' > /tmp/d.txt
$ ./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt
verdict=FAIL reasonCode=SURFACE_FORBIDDEN    # 예외 미등재 → FROZEN
  changeClass=FROZEN op=MODIFY
exit=1
```

정본 문서도 같은 말을 한다 — `docs/spec/repository_surface_contract.md:700-702`
(v108 부록): "등재는 런타임 carve-out이 아니라 선언이며, 분류는 `resolutionOrder`의
first-match를 따른다."

### 3.2 App 쪽 — **외부**이므로 문서화된 것과 추론한 것을 구분한다

| 구분 | 내용 | 출처 성격 |
|---|---|---|
| **문서화됨** | App `5795152`가 `blob(G) == blob(B_mg)`를 비교한다; `readFrom`은 `B_mg`이며 `G`가 아니다 | `config/policy/trust_surface_manifest.json:2-5` (`"purpose"`, `"comparison"`, `"readFrom"`) — 정책 파일 자신의 선언 |
| **문서화됨** | 불일치 시 `conclusion=failure`, 임계경로 17/18개 비교 | `data/debt_registry.json` DEBT#558 `:6057` (`worker/src/index.js:309-338`, `:180-185` 인용) |
| **추론** | App 코드가 `frozenExceptions`를 **모른다** | App 소스가 이 저장소 밖(`worker/src/index.js`)이라 직접 읽을 수 없다. 다만 App이 읽는 유일한 입력이 `trust_surface_manifest.json`(`:5` `readFrom: B_mg`)이고 그 파일에는 `frozenExceptions` 키가 **없다** — 최상위 키는 `schema`·`purpose`·`comparison`·`readFrom`·`paths` 5개뿐이다 |

**추론의 강도**: App이 설령 `repository_surface.json`을 읽는다 해도, 그 파일의
`frozenExceptions`는 §3.1에 의해 **분류 결과를 바꾸지 않는 선언**이다. 따라서
어느 쪽이든 "예외 등재 → App 통과"라는 경로는 존재하지 않는다.

**여섯 경로가 두 장치에 동시에 걸려 있다** — 예외 그룹에 있으면서 App manifest에도 있다:

| 경로 | 예외 그룹 | App manifest |
|---|---|---|
| `.github/actions/setup-axiom-toolchain/action.yml` | `trust-supply-path` | Y |
| `.github/workflows/admission-check.yml` | `epoch-rotation` | Y |
| `config/policy/epoch_manifest.json` | `epoch-rotation` | Y |
| `.github/workflows/admission-gate-v2.yml` | `admission-mint-pin-rotation` | Y |
| `.github/workflows/certificate-mint.yml` | `admission-mint-pin-rotation` | Y |
| `.github/workflows/publication-integrity.yml` | `publication-venue-split` | Y |

이 여섯은 **surface guard는 통과하지만 App byte-identity는 통과하지 못한다.** 죽은
예외(dead exception)와 살아있는 예외를 구분해야 하는 이유가 여기 있다 — surface
관점에서 예외는 유효하지만, 그 경로를 실제로 잠그는 것은 B(App)다.

## 4. 임계경로 wall의 분해 — 어느 초가 보호된 파일 안에 있는가

측정된 wall: `.github/workflows/axiom-operational-slice.yml` **591 s** (job1 283 s
+ gap 4 s + job2 302 s). 두 잡은 `readiness-verdict` → `needs: [axiom-operational-slice]`
(`.github/workflows/axiom-operational-slice.yml:319-320`)로 직렬이므로 wall은 합이다.

> **산술 정정**: 283 + 4 + 302 = **589**, 591이 아니다. 아래 표는 브리프의 591을
> 그대로 두되, 합계 행에 589를 병기한다. 2초 차이는 미해소로 남긴다(추정하지 않는다).

| 단계 | 초 | 그 단계를 실제로 수행하는 파일 | A | B | C | D | 보호 상태 |
|---|---:|---|---|---|---|---|---|
| job1 setup | 28 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** | — | CONTROLLED(`trust-supply-path`) | **A 차단** |
| job1 build release verifier | 129 | `Makefile`, `ci/checker.mk`, `config.nims` | — | — | checker.mk **Y**, config.nims **Y** | CONTROLLED | **C 차단** |
| job1 prove/replay | 77 | `Makefile` (`make verify-contract-release-e2e-full`, `:1170`) | — | — | — | CONTROLLED | **잠금 없음** |
| job1 determinism ratchet | 12 | `tests/gateway/deterministic_parallel_proof_test.nim` | — | — | — | **PRODUCT** | **잠금 없음** |
| job1 R3 | 10 | `tools/ci/wp5_relocation_measure.nim` | — | — | — | **PRODUCT** | **잠금 없음** |
| job1 소계 | **256** | | | | | | |
| job2 setup | 64 | `.github/actions/setup-axiom-toolchain/action.yml` | **Y** | **Y** | — | CONTROLLED(`trust-supply-path`) | **A 차단** |
| job2 supply verification | 92 | `Makefile` (+ `logs/run-manifest.json`, `logs/r3_relocation.json` 아티팩트) | — | — | — | CONTROLLED | **잠금 없음** |
| job2 readiness decision test suite | 79 | `tests/ci/test_readiness_verdict_mapping.nim` 외 4종 | — | — | — | **PRODUCT** | **잠금 없음** |
| job2 readiness gate | 29 | `src/gate/runners/readiness_start_gate.nim` | — | **Y** | — | CONTROLLED(`gate-infra`) | **B 차단** |
| job2 collect R1–R8 | 26 | `tools/ci/readiness_collect_ci.nim` | — | **Y** | — | **PRODUCT** | **B 차단** |
| job2 소계 | **290** | | | | | | |
| 합계(알려진 단계) | **546** | | | | | | |
| wall (job1+gap+job2) | 589 / (591) | | | | | | |
| 미배분 | 43 | gap 4 + 업로드/다운로드 아티팩트 + checkout 등 | | | | | |

### 4.1 결론 — 보호 등급별 초

| 등급 | 초 | 비중(546 기준) | 해당 단계 |
|---|---:|---:|---|
| **A 차단** (App byte-identity) — break-glass 없이는 후보가 통과 불가 | **92** | 16.8% | job1 setup 28, job2 setup 64 |
| **C 차단** (checker closure 회전 핀) | **129** | 23.6% | build verifier 129 (`ci/checker.mk`, `config.nims`) |
| **B만** (trustSurface — 자동 병합 거부, 수동 병합 가능) | **55** | 10.1% | readiness gate 29, collect R1–R8 26 |
| **잠금 없음** (A·B·C 전부 미등재 — surface도 PRODUCT/CONTROLLED) | **270** | 49.5% | prove/replay 77, supply verification 92, readiness test suite 79, determinism ratchet 12, R3 10 |
| 합계 | **546** | 100% | |

> `Makefile`은 A도 B도 C도 아니고 surface CONTROLLED(MODIFY=PASS)이므로 prove/replay
> 77 s와 supply verification 92 s는 **잠금 없음**으로 분류했다. 반면 build verifier
> 129 s의 입력인 `ci/checker.mk`·`config.nims`는 C에 있어 회전 핀 대상이다 — 같은
> "Makefile 단계"라도 **어느 파일이 그 초를 결정하는지**에 따라 등급이 갈린다.
> 이 구분 자체가 이 문서의 결론이다.

### 4.2 "불가능"의 정확한 범위

- **정말 불가능 (92 s, 16.8%)**: job1+job2 setup. `action.yml`이 A(byte-identity)에
  있으므로 후보 PR은 이 파일을 바꾼 채 `admission-check`를 받을 수 없다 — App이
  발급을 거부하고 break-glass(MUST-T2a) 수동 레인만 남는다.
- **C로 잠김 (129 s, 23.6%)**: build release verifier. `ci/checker.mk`·`config.nims`가
  891 closure에 있어 `.githooks/pre-push` rotation-pin 재앵커가 필요하다. 불가능은
  아니지만 모든 PR이 핀 회전 동반 커밋을 강제받는다.
- **B로 잠김 (55 s, 10.1%)**: collect 26 + readiness gate 29. 자동 병합은 거부되나
  1회성 수동 병합 레인으로 착지 가능하다 — **최적화 자체는 가능하다.**
- **잠금 없음 (270 s, 49.5%)**: prove/replay 77, supply verification 92, readiness
  test suite 79, determinism ratchet 12, R3 10. 이 다섯 단계의 수행 파일은 surface
  PRODUCT 또는 CONTROLLED이고 A·B·C 어디에도 없다. 여기에는 **어떤 기계적 잠금도
  없다** — 최적화가 "불가능"한 것이 아니라 **아직 아무도 안 한 것**이다.

즉 임계경로 546 s 중 **기계적으로 막힌 것은 92 s(16.8%)뿐**이고, 나머지 454 s는
정책 PR·핀 회전·수동 병합 또는 아무 제약 없이 손댈 수 있다. "이 최적화는 불가능하다"는
주장은 **setup 92 s에만** 성립한다.

## 5. 문서화된 것 vs 추론한 것 (명시)

| 주장 | 근거 | 신뢰 등급 |
|---|---|---|
| 14개 파일의 A/B/C/D 소속 | §7 스크립트 실행 출력 | **측정** |
| `frozenExceptions`가 surface 분류를 바꾸지 않음 | `classify()`/`resolveClass` 코드 + 가드 바이너리 실측 | **측정** |
| App이 `frozenExceptions`를 모름 | App 소스가 out-of-tree(`worker/src/index.js`); manifest에 키 없음 | **추론** (§3.2) |
| App comparator 라인 번호 `:309-338` | `data/debt_registry.json:6057`의 인용 | **문서 인용**(원본 미검증) |
| wall 591 s / 단계별 초 | 브리프 제공값 | **미재측정** — 재측정하지 않았다 |
| "17/15 paths" | 문서 서술 | **드리프트** — 파일 실제값은 18 |

## 6. 발견 사항 (브리프와 어긋나는 것)

1. **A 규모는 18**이며 문서의 "15-path"(admission-check.yml:37, verifier ops:90)와
   DEBT#558의 "17 paths"는 **스테일**이다. 18개 경로를 비교한다고 적어야 맞다.
2. **B에 glob이 있다** — `.github/actions/setup-axiom-toolchain/**`. exact 비교로는
   `action.yml`이 B에서 누락된다. 이 문서의 최초 계산이 실제로 틀렸고 수정했다.
3. **wall 산술**: 283+4+302 = **589**, 브리프의 591과 2초 차이. 미해소로 기록한다.
4. **알려진 단계 합은 546**이다(28+129+77+12+10+64+92+79+29+26). 미배분은 589−546 =
   43 s며 그 중 4 s가 gap이다.
5. **`tests/unit/test_surface_guard.nim`이 현재 실패한다** — 이 파일은 본 작업 범위
   밖이며 수정하지 않았다. 상세는 §8.

## 7. 재현 스크립트

`tools/surface_guard.nim`의 `globMatch`/`resolveClass`를 이식한 분류기. 저장소 루트에서
`python3`로 실행한다.

```python
import json, re
REPO = "."
def seg(p, s): return re.fullmatch(re.escape(p).replace(r"\*", "[^/]*"), s) is not None
def glob_match(pat, path):
    ps = [s for s in pat.split("/") if s]; xs = [s for s in path.split("/") if s]
    pi = si = 0; sp = -1; ss = 0
    while si < len(xs):
        if pi < len(ps) and ps[pi] == "**": sp, ss, pi = pi, si, pi + 1
        elif pi < len(ps) and seg(ps[pi], xs[si]): pi, si = pi + 1, si + 1
        elif sp >= 0: pi = sp + 1; ss += 1; si = ss
        else: return False
    while pi < len(ps) and ps[pi] == "**": pi += 1
    return pi == len(ps)

rs  = json.load(open(f"{REPO}/config/repository_surface.json"))
cl  = json.load(open(f"{REPO}/config/trusted_checker_closure.json"))["trustedCheckerTreeClosure"]
man = json.load(open(f"{REPO}/config/policy/trust_surface_manifest.json"))["paths"]
adm = json.load(open(f"{REPO}/config/policy/merge_admission.json"))["trustSurface"]

for p in ["<경로>"]:
    cls = next((c for c in ["PRODUCT","CONTROLLED","FROZEN"]
                if any(glob_match(x, p) for x in rs["classes"][c])), rs["defaultClass"])
    print(p, "A=", p in man, "B=", [x for x in adm if glob_match(x, p)],
          "C=", p in cl, "D=", cls, "exc=", rs["frozenExceptions"]["paths"].get(p))
```

가드 실측(§3.1) 재현:

```bash
printf 'M\t.github/workflows/admission-gate-v2.yml\n' > /tmp/d.txt
./bin/surface_guard --policy config/repository_surface.json --diff /tmp/d.txt; echo "exit=$?"
```

## 8. 범위 밖 관측 (수정하지 않음)

`nim c -r --hints:off tests/unit/test_surface_guard.nim` 실행 결과 **60건 중 59건 OK,
1건 실패**:

```text
tests/unit/test_surface_guard.nim(766, 48): Check failed: frozenExceptionPaths(loaded.node).len == 109
  frozenExceptionPaths(loaded.node).len was 116
tests/unit/test_surface_guard.nim(769, 38): Check failed: v["policyVersion"].getInt() == 102
  v["policyVersion"].getInt() was 108
[FAILED] shipped policy v102 is valid and registers 109 exceptions
Error: execution of an external program failed
```

테스트 이름("shipped policy **v102**")과 기대값(109/102)이 모두 shipped 정책(108/116)보다
뒤처져 있다 — v105~v108 개정에서 이 테스트만 갱신되지 않은 것으로 보인다. **본 작업의
파일이 아니므로 고치지 않았다.** 정책 유효성 자체는 `isValidPolicy`를 통과하며
(`classify()`가 `POLICY_INVALID`를 내지 않음 — §3.1 실측), 나머지 테스트는 전부 `[OK]`다.
