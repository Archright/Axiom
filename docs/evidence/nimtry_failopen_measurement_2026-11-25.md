# `nimtry_violations` fail-open 측정 — `debt_engine --validate` Part D

> **Status**: 측정·증거 문서. **프로덕션 코드 변경 없음** — `tools/debt_engine.nim` 무수정. 본 문서는 후속 수정 PR의 결정 입력이다.
> **Created**: 2026-11-25
> **Measured at**: 2026-11-25T05:13Z–05:40Z (UTC)
> **Base**: `57f2067b58560d39236ce34f1e14f45d662652f0` (`origin/main`, PR #478 merge). 로컬 worktree `ci/vsb-nimtry-failopen-measurement`.
> **Worktree**: `/home/wintr/wt-vsb` (`git worktree add`, 메인 클론의 미커밋 작업과 격리).

## §0. 판정 요약

| 질문 | 판정 | 결정 증거 |
|---|---|---|
| ① 분기 도달 경로 | `--validate` (그리고 `--close`) — **`--converge`는 존재하지 않는다** | §1 |
| ② `evalNimtryViolations()` 부재 시 동작 | 예외 없음. `[skip]` 출력 후 **센티넬 `-1` 반환** | §2 |
| ③ CI required context에서 도달하는가 | **예** — `debt-registry-gate`의 `bin/debt_engine --validate` 스텝 | §3 |
| ④ 로컬 재현 | **성공** — `[warn] nimtry_violations: evaluator error` + exit 0 | §4 |
| ⑤ fail-closed로 바꾸면 안전한가 | **아니오 — 지금 그대로면 게이트가 상시 red가 된다** | §5 |

**VERDICT — `debt-registry-gate` required context에서 `nimtry_violations`는 fail-open이다: YES.**

단, "silently skipped on every single CI run"이라는 가설은 **부분적으로만 참**이다. `bin/nimtry`는 같은
job에서 **단 2초 뒤에 실제로 빌드된다**(§3.3). 즉 nimtry는 그 job에 *구조적으로* 없는 것이 아니라
**`--validate`보다 늦게** provisioning된다. 이 구분이 §5의 결론을 바꾼다:
수정 비용은 "provisioning 결정"이 아니라 **스텝 순서 결정**이다.

---

## §1. ① 분기가 도달하는 subcommand

### §1.1 `--converge`는 존재하지 않는다

```console
$ cd /home/wintr/wt-vsb && grep -n "converge" tools/debt_engine.nim
1475:    echo "  \u274c " & $driftCount & " metric(s) not converged (DRIFT or no committed ledger record)" &
```

유일한 매치는 문구("not converged")다. `--converge` subcommand는 없다.

### §1.2 실제 dispatch (main, `tools/debt_engine.nim:3759-3778`)

```nim
proc main() {.raises: [CatchableError].} =
  let args = commandLineParams()
  if args.len == 0 or args[0] == "--help":
    usage()
    quit(0)
  case args[0]
  of "--codegen": cmdCodegen()
  of "--validate": cmdValidate()
  ...
  of "--sync-budget": cmdSyncBudget(args.len > 1 and args[1] == "--dry-run")
  of "--close": cmdClose(args[1 .. ^1])
```

### §1.3 분기를 감싸는 함수는 `runValidateCore`

`tools/debt_engine.nim:1459-1461` — 인용:

```nim
1456:         else:
1457:           echo "  [skip] " & metricName & ": no evaluator registered (source: none — plan needed)"
1458:           continue
1459:         if liveValue < 0:
1460:           echo "  [warn] " & metricName & ": evaluator error"
1461:           continue
1462:         if ledgerCurrent < 0:
```

`continue`는 `passCount`도 `driftCount`도 증가시키지 않는다. 따라서 이 metric은
`370/370 PASS`와 `3 PASS, 0 DRIFT` 집계 어디에도 흔적을 남기지 않는다 (§4.2).

enclosing proc은 `tools/debt_engine.nim:1341`:

```nim
1341: proc runValidateCore(): ValidateOutcome {.raises: [CatchableError].} =
```

`runValidateCore` 호출 지점은 세 곳뿐이다:

```console
$ grep -n "runValidateCore" tools/debt_engine.nim
1341:proc runValidateCore(): ValidateOutcome {.raises: [CatchableError].} =
1616:  let outcome = runValidateCore()
2125:  if runValidateCore() != voPass:          # --close [close/1] 사전검증
2199:    let verdict = runValidateCore()        # --close [close/5] 사후검증
```

| 호출자 | subcommand | CI 사용 |
|---|---|---|
| `cmdValidate` (`:1613`) | **`--validate`** | **예** (§3) |
| `cmdClose` (`:2125`, `:2199`) | `--close` | 아니오 (로컬 mutation 전용) |

### §1.4 `--sync-budget`은 이 분기를 지나지 않는다 — 별도 fail-closed 경로를 이미 갖는다

`cmdSyncBudget` → `syncBudgetCore`는 자체 skip 회계를 하고 `:2031`에서 fail-closed한다:

```nim
2031:    echo "  Sync INCOMPLETE: " & $res.skipped.len & " of " & $res.recordsProcessed &
2032:      " BUDGET record(s) unmeasured (evaluator error or no evaluator registered)."
```

이것이 DEBT#543(`data/debt_registry.json`, status `closed`)이 이미 고친 경로다. 그 수정은
**`--sync-budget`만** 대상으로 했고 `--validate`의 동일 클래스는 남았다 (§5.1).

---

## §2. ② `evalNimtryViolations()`의 부재 시 동작

`tools/debt_engine.nim:1702-1736`. 셸아웃 **전에** `fileExists`로 조기 반환한다:

```nim
1702: proc evalNimtryViolations(): int {.raises: [CatchableError].} =
...
1713:   ## Unmeasured (binary or sidecar absent) → -1, so the ledger keeps its last
1714:   ## verified value instead of a fabricated one (DEBT#543 fail-closed).
1715:   let tool = "bin/nimtry"
1716:   if not fileExists(tool):
1717:     echo "  [skip] nimtry_violations: evaluator binary unavailable (" & tool & ")"
1718:     return -1
1719:   let livePath = "data/nimtry_live_count.json"
...
1728:   removeFile(livePath)
1729:   discard execCmdEx(tool & " src/")   # refreshes the live-count sidecar
1730:   if not fileExists(livePath):
1731:     echo "  [skip] nimtry_violations: live-count sidecar unavailable (" & livePath & ")"
1732:     return -1
1733:   try:
1734:     result = parseJson(readFile(livePath)){"total_violations"}.getInt(-1)
1735:   except CatchableError:
1736:     result = -1
```

**센티넬 값: `-1`.** 세 경로 모두 `-1`이다 — (a) 바이너리 부재, (b) sidecar 부재, (c) sidecar 파싱 실패.
예외를 **던지지 않고**, `raise`도 하지 않는다(`{.raises: [CatchableError].}`는 `removeFile`용으로만 쓰인다).

즉 `-1`은 **"측정 불가"를 뜻하도록 설계된 값**이다. docstring이 그 의도를 명시한다:

```nim
1729:  ## Unmeasured (binary or sidecar absent) → -1, so the ledger keeps its last
1730:  ## verified value instead of a fabricated one (DEBT#543 fail-closed).
```

`-1`을 없앨 필요가 없다. **센티넬 자체는 올바르다.** 결함은 `-1`을 *어떻게 처분하느냐*에 있다:
`--sync-budget`은 `-1`을 INCOMPLETE로 승격하지만(`:2031`), `--validate`는 `continue`로 버린다(`:1461`).

### §2.1 형제 evaluator도 동일한 fail-open 계약을 공유한다

| evaluator | 부재 시 | 위치 |
|---|---|---|
| `evalNimtryViolations` | `-1` | `:1720-1722` |
| `evalLayerViolations` | `-1` | `:1676-1681` |
| `evalEffectViolations` | `-1` | `:1793-1804` |
| `evalImportLintViolations` | `-1` (단, `tools/`는 CI에 항상 존재 → 실질 도달 불가) | `:1767-1770` |

즉 결함은 `nimtry_violations` 단독이 아니라 **evaluator 4종 공통의 처분 규칙**이다.

---

## §3. ③ CI required context에서의 도달

### §3.1 `debt-registry-gate`는 required validation이다

`config/policy/merge_admission.json` `requiredValidations`:

```json
{
  "workflowPath": ".github/workflows/debt-registry-gate.yml",
  "job": "debt-registry-gate",
  "acceptableConclusion": "success",
  "workflowIdObservation": { "value": 414023986, "observedAt": "2026-11-11T01:01:50Z" }
}
```

### §3.2 워크플로 스텝 (`.github/workflows/debt-registry-gate.yml:45-48`)

```yaml
45:      - name: Build canonical debt validator
46:        run: make bin/debt_engine
47:      - name: Enforce Theater registry contract (unconditional)
48:        run: bin/debt_engine --validate
```

`:48`이 정확히 §1.3의 분기를 실행한다. 이 스텝 이름의 "(unconditional)"이 아이러니다 —
스텝은 무조건 실행되지만, 그 안의 metric 하나는 무조건 건너뛰어진다.

### §3.3 워크플로 자신이 이 사실을 이미 적어 두었다

`.github/workflows/debt-registry-gate.yml:24-31`:

```yaml
24:          # nim scope — this job's toolchain uses are `make bin/debt_engine`
25:          # + `bin/debt_engine --validate`, `make check-nim-theater`
...
28:          # binding, VS-2). The gate is compiled -d:release so the reduction
29:          # ratchet cannot downgrade to WARN, and runs without bin/nimtry,
30:          # so its nimtry active-violation metric reports "unmeasured" here
31:          # while marker binding is enforced unconditionally.
```

"reports 'unmeasured'"는 **낙관적 서술**이다. 실제로는 "unmeasured"가 아니라 아무것도
보고되지 않는다 — 집계(`1879 total, 1879 passed, 0 failed` / `3 PASS, 0 DRIFT`)에
`unmeasured` 항목이 존재하지 않는다. 관측된 사실은 "보고되지 않음"이다 (§4.2).

### §3.4 실측: 실제 merge_group 런의 로그 (가장 강한 증거)

```console
$ gh run view 45553393942 --log | grep "Enforce Theater registry contract" \
    | sed -E 's/^[^\t]+\t[^\t]+\t[0-9T:.Z-]+ ?//' | sed -n '/Part D:/,/Part D.1:/p'
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  [skip] layer_violations: evaluator binary unavailable (bin/layer_enforcement_gate)
  [warn] layer_violations: evaluator error
  [skip] effect_violations: evaluator binary unavailable (bin/effect_contract_projection)
  [warn] effect_violations: evaluator error
  [skip] nimtry_violations: evaluator binary unavailable (bin/nimtry)
  [warn] nimtry_violations: evaluator error
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)

=== Part D.1: Policy disposition resolution ===
```

런 메타데이터: `conclusion=success`, `event=merge_group`,
`headSha=963c8ae8a0c8be4bf709073ac61349ed67a208ed`, `createdAt=2026-11-25T05:24:49Z`,
`https://github.com/Archright/Axiom/actions/runs/45553393942`.

요약 줄도 함께 인용한다:

```console
$ gh run view 45553393942 --log | grep "Metric evaluation"
...Z   Metric evaluation: 3 PASS, 0 DRIFT
```

**6개 metric 중 3개가 skip됐는데 집계는 "3 PASS, 0 DRIFT"다.** skip된 3개는 문구상
존재하지 않는다. `[warn]` 줄이 남아 있으므로 **완전히 침묵하지는 않지만**, 판정(exit code)에는
아무 영향이 없다 — 로그를 읽는 사람이 없으면 아무도 모른다.

### §3.5 핵심 정정: `bin/nimtry`는 그 job에서 실제로 빌드된다 — 단, `--validate` **이후**에

가설("nimtry is NEVER provisioned in that job")은 **거짓**이다. 같은 런의 후속 스텝
`Build bidirectional debt binding gate`가 `nimtry-measure`를 끌어와 `bin/nimtry`를 컴파일한다:

```console
$ gh run view 45553393942 --log | grep -E "\-o:bin/nimtry|Part D: Budget"
Enforce Theater registry contract (unconditional)  2026-11-25T05:25:19.7125400Z  === Part D: Budget metric evaluation ===
Build bidirectional debt binding gate             2026-11-25T05:25:21.8209887Z  nim c ... -d:release -o:bin/nimtry src/gate/nimtry.nim
Build bidirectional debt binding gate             2026-11-25T05:25:30.8525201Z  [nimtry-baseline-check] OK: 4375 fingerprints, version 2
Build bidirectional debt binding gate             2026-11-25T05:25:33.5499437Z  [nimtry-measure] sidecar produced; ...
```

**`--validate` 05:25:19.712 → nimtry 빌드 05:25:21.821. 격차 약 2.1초.**

근본 원인은 `Makefile:277-278`의 의존성 누락이다:

```make
274: DEBT_AUDIT_SRCS := tools/debt_engine.nim $(wildcard src/core/debt/*.nim) \
275:                    $(wildcard src/infrastructure/debt_audit/*.nim)
276:
277: bin/debt_engine: $(DEBT_AUDIT_SRCS)
278: 	$(NIM) c $(NIM_TOOL_FLAGS) -o:$@ $<
```

`bin/debt_engine`은 evaluator 바이너리를 prerequisite으로 갖지 않는다. 반면
`bin/debt_integrity_gate`는 `| nimtry-measure` order-only prerequisite을 갖는다(`Makefile:292-295`).
즉 **같은 job 안에 두 개의 서로 다른 provisioning 계약**이 공존한다.

CI 스텝 순서 (실측):

```console
$ gh run view 45553393942 --log | cut -f2 | uniq
Set up job
Run actions/checkout@...
Run ./.github/actions/setup-axiom-toolchain
Ensure Draft 2020-12 validator
Build canonical debt validator
Enforce Theater registry contract (unconditional)      ← --validate: nimtry 부재
Theater five-field negative fixture
Enforce Nim theater static scan (unconditional)
Build bidirectional debt binding gate                  ← 여기서 bin/nimtry 생성
Enforce bidirectional debt registry↔code binding (unconditional)
...
```

`bin/`는 gitignore이므로 클론에 포함되지 않는다 — `bin/nimtry`가 로컬 main 클론에 존재한다는
사실(1,504,536 bytes, Nov 23 10:49)은 CI에 대해 아무것도 증명하지 않는다:

```console
$ git check-ignore -v bin/nimtry
.gitignore:288:bin/nimtry	bin/nimtry
$ git ls-files bin/nimtry
              # (빈 출력 = 미추적)
$ head -2 .gitignore
bin/*
!bin/.gitkeep
```

---

## §4. ④ 로컬 재현

### §4.1 빌드 (저장소 문서화 경로 사용)

```console
$ cd /home/wintr/wt-vsb && make bin/debt_engine
nim c --hints:off --skipParentCfg --skipProjCfg --path:$HOME/.choosenim/toolchains/nim-2.2.10 \
  --path:. --path:src --path:tools --nimcache:build/nimcache/tools -o:bin/debt_engine tools/debt_engine.nim
real	0m6.331s

$ make bin/nimtry        # Makefile:202-203, -d:release
nim c ... -d:release -o:bin/nimtry src/gate/nimtry.nim
real	0m8.496s
```

`bin/nimtry`는 `nimble`이 아니라 **Makefile 타깃**으로 빌드된다 (`Makefile:202`).
`src/gate/nimtry.nim`이 엔트리포인트다.

### §4.2 재현 A — nimtry를 rename (제거와 동등) 후 `--validate`

```console
$ cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved
$ ./bin/debt_engine --validate; echo "VALIDATE EXIT=$?"
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  [skip] layer_violations: evaluator binary unavailable (bin/layer_enforcement_gate)
  [warn] layer_violations: evaluator error
  [skip] effect_violations: evaluator binary unavailable (bin/effect_contract_projection)
  [warn] effect_violations: evaluator error
  [skip] nimtry_violations: evaluator binary unavailable (bin/nimtry)
  [warn] nimtry_violations: evaluator error
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)

=== Part D.1: Policy disposition resolution ===
  Checks: 1879 total, 1879 passed, 0 failed
  Metric evaluation: 3 PASS, 0 DRIFT
  All debt validation checks passed.
VALIDATE EXIT=0
```

**핵심 실측**: `bin/nimtry`가 없는데도 **exit 0**이다.
`nimtry_violations`가 집계에서 **사라진다**(`3 PASS`, 6개 중 3개).

**rename 방식을 택한 이유**: `tools/debt_engine.nim`도, 평가 대상 데이터도 건드리지 않는다.
`mv`는 같은 파일시스템 내 원자적 연산이고 `mv` 로 복원하면 바이트 단위로 동일하다.
플래그·환경변수 우회는 존재하지 않는다 — evaluator는 `bin/nimtry` **상대 경로**를 직접
`fileExists`로 검사하므로(`:1719-1720`) PATH 조작으로는 재현할 수 없다.

### §4.3 재현 B — nimtry 존재 시 (대조군)

```console
$ cd /home/wintr/wt-vsb && mv /tmp/nimtry.saved bin/nimtry
$ ./bin/debt_engine --validate; echo "EXIT=$?"
=== Part D: Budget metric evaluation ===
  ✅ import_lint_violations PASS (projection=0 == ledger 0)
  ...
  ✅ nimtry_violations PASS (projection=4371 == ledger 4371)
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)
  Metric evaluation: 4 PASS, 0 DRIFT
EXIT=0
```

**A vs B 차이는 `3 PASS` vs `4 PASS` 단 하나다.** exit code는 양쪽 모두 0 —
즉 nimtry의 유무가 **판정을 바꾸지 않는다**.

### §4.4 재현 C — DRIFT가 실제로 exit 1을 만드는지 확인 (fail-closed 비용 측정)

`data/debt_ledger.json`의 `nimtry_violations.current`를 `4371 → 1`로 일시 변경:

```console
$ ./bin/debt_engine --validate; echo "EXIT=$?"
=== Part D: Budget metric evaluation ===
  ...
  ⚠️  nimtry_violations DRIFT (projection=4371 vs ledger 1)
  ✅ debt_registry_open PASS (projection=40 == ledger 40)
  ✅ debt_registry_closed PASS (projection=261 == ledger 261)
  ❌ 1 metric(s) not converged (DRIFT or no committed ledger record) — run: bin/debt_engine --sync-budget
  Metric evaluation: 3 PASS, 1 DRIFT
  Validation FAILED (ERROR disposition or fail-closed condition).
EXIT=1
VALIDATE EXIT=1
```

복원:

```console
$ git checkout -- data/debt_ledger.json && git status --short data/debt_ledger.json
              # (빈 출력 = 복원 완료)
```

**이 실측이 §5의 비용 계산 근거다**: `driftCount > 0` → `hasErrorDisposition = true`
(`:1474-1477`) → `voErrorDisposition` (`:1609`) → `quit(1)` (`:1621-1624`).
따라서 skip을 DRIFT로 승격하면 **곧바로 exit 1**이다.

### §4.5 재현 D — `--sync-budget`과의 비대칭 (같은 결함 클래스, 다른 처분)

```console
$ cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved
$ ./bin/debt_engine --sync-budget --dry-run; echo "SYNC EXIT=$?"
  [DRY-RUN] No changes detected — fully synced.
  Sync INCOMPLETE: 3 of 6 BUDGET record(s) unmeasured (evaluator error or no evaluator registered).
  Unmeasured records keep their last verified value; exiting 1 (fail-closed).
  Build the missing evaluator dependencies (see [skip]/[warn] lines above) and re-run.
SYNC EXIT=1
$ mv /tmp/nimtry.saved bin/nimtry
```

| subcommand | nimtry 부재 시 | exit |
|---|---|---|
| `--sync-budget` | `Sync INCOMPLETE: 3 of 6 ... unmeasured` | **1** |
| `--validate` | `[warn] ... evaluator error` (무시) | **0** |

동일한 `-1` 센티넬, 동일한 evaluator, **정반대 처분**. `--validate`는 DEBT#543 수정의
범위에서 빠져 있었다.

---

## §5. ⑤ fail-closed가 안전한가 — "무료 레인"이 아니라 **provisioning 순서 결정**

### §5.1 편집 권한은 무료 레인이다 (편집 자체는 자유)

| 대상 | surface class | trust-surface manifest | 판정 |
|---|---|---|---|
| `tools/debt_engine.nim` | **CONTROLLED** | **미포함** | 수정 가능 |
| `Makefile` | CONTROLLED | 미포함 | 수정 가능 |
| `.github/workflows/debt-registry-gate.yml` | — | **포함** (`:13`) | 수정 시 break-glass 필요 |
| `config/policy/trust_surface_manifest.json` | — | **포함** (`:20`) | 자기참조 |

근거:

```console
$ grep -n "debt_engine" config/policy/trust_surface_manifest.json
              # (빈 출력 = NOT in manifest)
$ python3 -c '...'   # classes 순회 결과
CONTROLLED -> tools/debt_engine.nim
CONTROLLED -> Makefile
```

`config/repository_surface.json`의 `rules`:

```json
"PRODUCT":    { "ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS" },
"CONTROLLED": { "ADD": "PASS", "MODIFY": "PASS", "DELETE": "PASS" },
"FROZEN":     { "ADD": "FAIL", "MODIFY": "FAIL", "DELETE": "FAIL" }
```
(`"defaultClass": "PRODUCT"`, `"resolutionOrder": ["PRODUCT","CONTROLLED","FROZEN"]`)

`CONTROLLED`는 `PRODUCT`와 동일하게 MODIFY `PASS`다. 표면 분류상 **자유 편집**이 맞다.
그러나 §0.9(극장 금지)·§2.6(변경 불변조건)상 **의미 변경**은 별개 심사 대상이다.

### §5.2 의미론적 결론: **지금 그대로 fail-closed로 바꾸면 게이트가 상시 red가 된다**

`bin/nimtry`는 `--validate` 시점에 **없고**, 같은 job에서 **2초 뒤에 생성된다** (§3.5).
따라서 `continue` → `inc driftCount`로 바꾸는 순간:

- `driftCount >= 1` (`nimtry_violations`, 그리고 `layer_violations`·`effect_violations`도 동일하게 부재)
- → `hasErrorDisposition = true` (`:1474-1477`)
- → `voErrorDisposition` → `quit(1)` (`:1621-1624`)
- → **required check `debt-registry-gate`가 모든 PR에서 실패** → 머지 큐 전면 차단

`layer_violations`(`bin/layer_enforcement_gate`)와 `effect_violations`
(`bin/effect_contract_projection`)도 같은 job에서 build되지 않으므로, 최소 **3개 metric**이
동시에 red가 된다. 즉 이 변경은 "정확해지는" 것이 아니라 **게이트를 죽이는** 변경이 된다.

§4.4는 이 인과를 실측으로 고정했다 — DRIFT 1건이 정확히 exit 1을 만든다.

### §5.3 그래서 남는 선택지 (구현하지 않음 — 결정 항목)

| 안 | 내용 | 비용 | 위험 |
|---|---|---|---|
| **A** | `bin/debt_engine`의 prerequisite에 evaluator 바이너리 추가 (`Makefile`) | 낮음 (2초 빌드, 툴체인 이미 존재) | 없음 — 이미 job 안에서 빌드되는 바이너리를 앞당길 뿐 |
| **B** | `--validate` 스텝을 `bin/nimtry` 빌드 **뒤로** 이동 | 낮음 (YAML 스텝 순서) | **trust-surface 파일 수정** → break-glass 레인 필요 |
| **C** | `--validate`에 "이 metric은 필수" 선언 도입 (evaluator별 required/optional 구분) | 중간 | 계약 신설 — §0.12상 제품 계약 근거 필요 |
| **D** | `--validate`에 `--allow-unmeasured` 같은 탈출구 추가 | 중간 | **극장 위험** (§0.9) — 상시 사용되면 게이트 무력화 |

A안이 §0.2(Ideal/Elegant/Fundamental)에 가장 부합한다: 새 계약·새 플래그 없이
`bin/debt_integrity_gate`가 **이미 쓰는** `| nimtry-measure` 패턴을 `bin/debt_engine`에
동일하게 적용하는 것이다. 즉 "예외 없음"이며 provisioning 계약이 하나로 통일된다.

**B안의 함정**: 워크플로는 trust-surface manifest에 있으므로, 스텝 순서만 바꿔도
`admission-check`의 독립 검증 대상에서 빠져 break-glass가 필요하다. 반면 A안은
`Makefile`(manifest 미포함)만 건드리므로 **일반 레인**이다. 이 비대칭이 A안을 선호할
결정적 이유다.

### §5.4 후속 PR이 반드시 함께 결정해야 하는 것

1. **어느 metric이 required인가?** 4개 evaluator 전부인가, `nimtry_violations`만인가.
   `import_lint_violations`는 `tools/`만 스캔하므로 CI에서 항상 측정 가능하다 — 나머지 3개와
   성격이 다르다.
2. **`-1`(측정 불가)과 `!= ledger`(실제 DRIFT)를 구분해 보고할 것인가?** 현재 집계는
   `N PASS, M DRIFT` 2-튜플이라 "측정 불가"를 표현할 자리가 없다. fail-closed로 만들면
   최소한 세 번째 카운터(`UNMEASURED`)가 필요하다 — 그렇지 않으면 "측정 불가"가
   "DRIFT"로 위장된다(이번 결함의 거울상).
3. **`--close` 경로도 같이 고칠 것인가?** `cmdClose`는 `runValidateCore`를 사전·사후로
   두 번 호출한다(`:2125`, `:2199`). fail-closed가 되면 nimtry 없는 체크아웃에서
   **`--close`가 불가능**해진다. 로컬 워크플로에 미치는 영향은 별도 판단이 필요하다.
4. **DEBT#543의 회귀 테스트를 확장할 것인가?** `tests/unit/test_debt_engine_sync_budget.nim`은
   `--sync-budget`만 덮는다. `--validate`의 동일 클래스를 고정하는 케이스가 없다.

---

## §6. 재현 명령 (복사-붙여넣기)

WSL 경유 (Git Bash에서 실행):

```bash
wsl.exe -e bash -lc 'cd /home/wintr/develop/Axiom && git worktree add /home/wintr/wt-vsb -b ci/vsb-nimtry-failopen-measurement origin/main'
wsl.exe -e bash -lc 'cd /home/wintr/develop/Axiom && cp bin/ax bin/build_all_gates bin/nim_check_gate /home/wintr/wt-vsb/bin/'
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && make bin/debt_engine && make bin/nimtry'

# 재현 A: nimtry 제거
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved && ./bin/debt_engine --validate; echo "EXIT=$?"'

# 재현 B: 대조군
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv /tmp/nimtry.saved bin/nimtry && ./bin/debt_engine --validate'

# 재현 D: --sync-budget 비대칭
wsl.exe -e bash -lc 'cd /home/wintr/wt-vsb && mv bin/nimtry /tmp/nimtry.saved && ./bin/debt_engine --sync-budget --dry-run; echo "EXIT=$?"; mv /tmp/nimtry.saved bin/nimtry'

# CI 실측 (§3.4, §3.5)
GH="/c/Program Files/GitHub CLI/gh.exe"
"$GH" run view 45553393942 --log | grep -E "Part D:|nimtry_violations|-o:bin/nimtry"
```

---

## §7. 측정 환경·한계

- **측정 SHA**: `57f2067b58560d39236ce34f1e14f45d662652f0` (`origin/main`, 2026-11-25 04:50:37Z).
- **로컬 바이너리**: `bin/debt_engine`, `bin/nimtry` 모두 본 측정에서 새로 빌드했다.
  메인 클론의 `bin/nimtry`(1,504,536 bytes, Nov 23)는 **사용하지 않았다**.
- **부수 산출물**: `data/nimtry_live_count.json` (gitignore `:422`)이 재현 B에서 생성됐다.
  이는 `--validate`가 실제로 nimtry를 실행했다는 증거이며, 커밋 대상이 아니다.
- **복원 확인**: `data/debt_ledger.json`은 `git checkout --`로 복원했고 `git status`가 clean이다.
  `tools/debt_engine.nim`은 **무수정**이다.
- **한계**: CI 로그 표본은 `merge_group` 런 1건(`45553393942`)이다. 코드 경로(§1)와
  워크플로 정의(§3.2)가 결정적이므로 표본을 늘려도 판정은 바뀌지 않는다. 다만
  "nimtry가 `--validate` 이후에 빌드된다"는 사실은 그 런의 스텝 순서에 근거하며,
  스텝 순서는 워크플로 파일에 고정되어 있으므로 재현 가능하다.

---

## §8. 한 줄 결론

`nimtry_violations`는 required `debt-registry-gate`에서 **fail-open이다(YES)** — nimtry 부재가
`-1` 센티넬 → `continue` → `3 PASS, 0 DRIFT` → **exit 0**으로 흘러 판정에 흔적을 남기지 않는다.
그러나 `bin/nimtry`는 그 job에 *구조적으로 없는* 것이 아니라 **`--validate` 2.1초 뒤에 빌드**되므로,
수정은 "게이트를 영구히 red로 만드는" 변경이 아니라 **provisioning 순서를 정렬하는** 변경이다 —
`Makefile`만 건드리는 A안이면 일반 레인이고, `--validate`에 UNMEASURED 처분을 함께 도입해야
비로소 fail-closed가 의미를 갖는다.
