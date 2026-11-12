## test_b_cache_anchor.nim — J3 §3.3 B cache manifest 앵커링 계약 테스트
##
## 대상: .github/actions/setup-axiom-toolchain/action.yml의 두 실제 스텝 본문을
## 그대로 추출해 실행한다(프로덕션 코드 사본이 아닌 원문):
##   1. B-layer fingerprint verify — python heredoc + discard glue
##      (신뢰 입력 재유도 identity: tree OID + recipe 재계산 + a_fp)
##   2. B-layer semantic provenance probe — `git archive`로 신뢰 트리를
##      materialize하고 복원된 bin/ax의 자기 SourceCoherence를 그 트리에서 실행
##
## 시나리오:
##   (h)  healthy — 재유도 identity 일치 + 전 엔트리 digest 일치 → b-verify-ok=true, 폐기 없음
##   (i)  manifest identity가 재유도 기대와 불일치 → FAIL → 폐기
##   (a)  manifest-only files{} 변조 → per-entry digest 불일치 → FAIL → 폐기
##   (b)  payload-only 바이너리 변조 → per-entry digest 불일치 → FAIL → 폐기
##   (c)  payload+manifest 동시 변조 — digest 레이어는 자기일관이라 통과한다
##        (원형성 사실 고정 — 이 간을 probe가 닫는다) → probe 감지 → 폐기
##   (m)  manifest 누락 → 폐기
##   (v)  vacuous manifest(files{} 비었음) → 폐기 (극장 방지)
##   (r)  불완전 manifest(5파일 필수 집합 결손 — DEBT#502 부분 페이로드) → 폐기
##   (p1) probe healthy — 4종 stub 모두 exit 0 + ircheck 존재·실행가능 → OK, B 파일 보존
##   (p2) probe 감지(bin/ax) — stub exit 1(SourceCoherence FATAL 관측 계약) → 폐기
##   (p4) probe 감지(보조 바이너리) — bin/gate_hook만 exit 1 → 폐기 (§6 잔여 닫힘)
##   (p5) probe 감지(DEBT#502) — ircheck 결손/비실행 → 폐기 (부분 페이로드는
##        검증된 공급이 아니다 — 5번째 공급 멤버 강제)
##   (p3) probe content-equal 트리 — 같은 src 내용의 다른 트리도 수용(semantic identity)
##   (e)  probe exp-* 네임스페이스 → SKIP, 폐기 없음
##   (g)  probe 신뢰 트리 미존재(git archive 실패) → 폐기
##   (c2) 잔여 시나리오 종단간: 보조 바이너리 교체 + manifest 재작성 → digest 레이어
##        자기일관 통과(잔여 사실 고정) → probe 감지 → 폐기
##
## R3 B-cache 키 입력 폐쇄 스위트(keygen 실제 스텝 본문 — 2026-10-09):
##   (k1) 결정론 — 동일 커밋 2회 → 동일 identity/key/probe-tree
##   (k2) docs-only 커밋 → identity 불변 + probe-tree 전진 (무효화 소멸)
##   (k3) src 바이트 변경 → identity 변화 (다른 빌드 입력 ⇒ 다른 키)
##   (k4) spec_registry.json 바이트 → identity 변화
##   (k5) SPEC 필수 셀 제거 → 변화 / 무관 행 → 불변
##   (k6) AGENTS.md 비공백 교체 → 불변 / 비우기 → 변화 (술어 비트)
##   (k7) 클로저 파일 변경 → identity 변화
##   (k8) 클로저 파일 삭제 → keygen FAIL (fail-closed)
##   (k9) exp-* → identity 원문 + probe-tree 공백
##   (k10) 미커밋 오염 → identity 불변 (git 객체 유도)
##   (k11) src/generated 변경 → identity 불변
##   (k12) 정적 클로저 검증 — src staticRead/spec() 대상 전부 keygen 소화
##
## fixture는 임시 디렉터리(/tmp)에서 만들며 작업 저장소를 건드리지 않는다.

import std/[unittest, os, osproc, strutils, json, strtabs]

const
  ActionYml = ".github/actions/setup-axiom-toolchain/action.yml"
  ManifestRel = "build/.axiom-b-fingerprint.json"
  ## DEBT#502: 검증된 공급 = 정확히 5멤버(4 ci-compile 바이너리 + Lean 기준
  ## 추출기). b-verify의 필수 집합·publisher 양 경로 fingerprint·lane manifest가
  ## 이 5경로를 1:1 결속한다.
  BFiles = ["bin/ax", "bin/gate_hook", "bin/precompile_gates", "bin/install_ax_cas",
            "proofs/.lake/build/bin/ircheck"]
  ProbeBinNames = ["ax", "gate_hook", "precompile_gates", "install_ax_cas"]
  FakeAKey = "axiom-a-Linux-fakegccfp-fakeglibcfp-fakescripthash"
  GoodTree = "cf324cb08b9a56f08046b8706969e87b65615cec"

var fixtureCounter = 0

proc nextTag(): string =
  inc fixtureCounter
  result = $fixtureCounter

proc repoRootOf(): string =
  ## tests/ci/ → 저장소 루트
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc stepBody(actionPath, namePrefix: string): string =
  ## action.yml에서 이름 접두어로 스텝을 찾아 run 본문(YAML 디던트 적용된
  ## 문자열)을 python yaml로 추출한다 — 원문 그대로.
  let py = getTempDir() / ("extract_step_" & nextTag() & ".py")
  writeFile(py, "import sys, yaml\n" &
    "d = yaml.safe_load(open(sys.argv[1]))\n" &
    "print(next(s['run'] for s in d['runs']['steps'] if s['name'].startswith(sys.argv[2])))\n")
  let (outp, code) = execCmdEx("python3 " & quoteShell(py) & " " &
    quoteShell(actionPath) & " " & quoteShell(namePrefix))
  removeFile(py)
  doAssert code == 0, "step extraction 실패 (" & namePrefix & "): " & outp
  result = outp.strip(trailing = true, leading = false)

proc pythonHeredoc(body: string): string =
  ## run 본문에서 `<<'PY'` … `PY` 사이 python 코드 추출
  let lines = body.splitLines()
  var i0 = -1
  var i1 = -1
  for i, l in lines:
    if i0 < 0 and l.endsWith("<<'PY'"):
      i0 = i
    elif i0 >= 0 and l.strip() == "PY":
      i1 = i
      break
  doAssert i0 >= 0 and i1 > i0, "python heredoc not found"
  result = lines[(i0+1) ..< i1].join("\n")

var ghCounter = 0

proc runStep(body, workdir: string, extraEnv: seq[(string, string)]): tuple[outp: string, code: int, ghOut: string] =
  ## 스텝 본문을 workdir에서 실행. GITHUB_OUTPUT은 임시 파일로 수집한다.
  inc ghCounter
  let ghOutPath = getTempDir() / ("gh_out_" & $getCurrentProcessId() & "_" & $ghCounter)
  writeFile(ghOutPath, "")
  let cmdEnv = newStringTable(modeCaseInsensitive)
  for k, v in envPairs():
    if k != "GITHUB_OUTPUT":
      cmdEnv[k] = v
  cmdEnv["GITHUB_OUTPUT"] = ghOutPath
  for (k, v) in extraEnv:
    cmdEnv[k] = v
  let script = getTempDir() / ("step_" & $getCurrentProcessId() & "_" & $ghCounter & ".sh")
  writeFile(script, body)
  let (outp, code) = execCmdEx("cd " & quoteShell(workdir) & " && bash " & quoteShell(script),
                               env = cmdEnv)
  removeFile(script)
  result.outp = outp
  result.code = code
  result.ghOut = readFile(ghOutPath)
  removeFile(ghOutPath)

proc ghOutputValue(ghOut, key: string): string =
  for line in ghOut.splitLines():
    if line.startsWith(key & "="):
      return line[(key.len+1) .. ^1]

proc bKeyOf(root, identity: string): string =
  ## keygen 공식 재현: axiom-b-<identity>-<recipe_hash><a_fp>
  ## identity = 입력 폐쇄 digest(40-hex, R3) 또는 exp-* 원문
  ## recipe_hash = sha256sum Makefile config.nims config/effects.nims
  ##               src/gate/config.nims | sha256sum (첫 32자)
  ## a_fp        = sha256(a-key)[:32] — verify 스텝 python과 동일 체인
  let (recipe, _) = execCmdEx("cd " & quoteShell(root) &
    " && sha256sum Makefile config.nims config/effects.nims src/gate/config.nims | sha256sum | cut -c1-32")
  doAssert recipe.strip().len == 32, "recipe_hash 재현 실패: " & recipe
  # a_fp = sha256(a-key)[:32] — keygen과 동일한 셸 체인
  let (aFp, _) = execCmdEx("printf '%s' " & quoteShell(FakeAKey) & " | sha256sum | cut -c1-32")
  doAssert aFp.strip().len == 32, "a_fp 재현 실패: " & aFp
  result = "axiom-b-" & identity & "-" & recipe.strip() & aFp.strip()

proc sha256Of(path: string): string =
  let (outp, code) = execCmdEx("sha256sum " & quoteShell(path))
  doAssert code == 0, "sha256sum 실패: " & outp
  result = outp.splitWhitespace()[0]

proc fixtureRecipeRoot(): string =
  ## recipe 파일 내용이 makeFixture와 동일한 고정 루트 — bKey 재계산용
  ## (makeFixture와 내용이 같으므로 recipe_hash도 동일)
  let r = getTempDir() / "j3_recipe_base"
  if not dirExists(r):
    createDir(r / "src/gate")
    createDir(r / "config")
    writeFile(r / "Makefile", "fixture-makefile\n")
    writeFile(r / "config.nims", "fixture-config\n")
    writeFile(r / "config/effects.nims", "fixture-effects\n")
    writeFile(r / "src/gate/config.nims", "fixture-gate-config\n")
  result = r

proc makeFixture(): string =
  ## 호출 워크스페이스 형태의 fixture: recipe 파일 4종 + 검증 공급 5멤버 +
  ## 정상 manifest.
  let root = getTempDir() / "j3_anchor_" & nextTag()
  createDir(root / "src/gate")
  createDir(root / "config")
  createDir(root / "bin")
  createDir(root / "build")
  createDir(root / "proofs/.lake/build/bin")  # DEBT#502 — ircheck 경로
  writeFile(root / ".axiom_root", "")
  writeFile(root / "Makefile", "fixture-makefile\n")
  writeFile(root / "config.nims", "fixture-config\n")
  writeFile(root / "config/effects.nims", "fixture-effects\n")
  writeFile(root / "src/gate/config.nims", "fixture-gate-config\n")
  for i, rel in BFiles:
    writeFile(root / rel, "fake binary " & $i & "\n")
  # manifest: publisher 형식 그대로 (schema/buildSha/bKey/files{})
  var filesObj = newJObject()
  for rel in BFiles:
    filesObj[rel] = %sha256Of(root / rel)
  var m = %*{"schema": "axiom-b-fingerprint-v1"}
  m["files"] = filesObj
  writeFile(root / ManifestRel, m.pretty)
  result = root

proc setIdentity(root, identity: string) =
  ## fixture manifest의 buildSha/bKey를 기대 identity로 기록 — save-side
  ## writer(publisher)가 파생 소스(identity)를 manifest에 싣는 것과 동일
  var m = parseJson(readFile(root / ManifestRel))
  m["buildSha"] = %identity
  m["bKey"] = %bKeyOf(root, identity)
  writeFile(root / ManifestRel, m.pretty)

proc bVerifyEnv(identity: string): seq[(string, string)] =
  ## verify 스텝 env — EXPECT_*는 keygen 산출물(신뢰 입력), A_KEY는 keygen a-key.
  ## EXPECT_B_KEY는 keygen 공식 전체(recipe+a_fp 포함)로 재현해야 action python의
  ## 재유도와 정확히 같은 체인을 통과한다 — 그래야 healthy가 성립한다.
  @[
    ("EXPECT_BUILD_SHA", identity),
    ("EXPECT_B_KEY", bKeyOf(fixtureRecipeRoot(), identity)),
    ("A_KEY", FakeAKey),
  ]

proc gitFixture(root: string): tuple[treeA, treeB: string] =
  ## root를 git 저장소로 만들고 src/a.nim 내용이 다른 트리 2개를 만든다
  let commit = " && git -c user.email=t@t -c user.name=t add -A" &
               " && git -c user.email=t@t -c user.name=t commit -qm w"
  discard execCmdEx("cd " & quoteShell(root) & " && git init -q" & commit)
  let (ta, _) = execCmdEx("cd " & quoteShell(root) & " && git rev-parse HEAD^{tree}")
  writeFile(root / "src/a.nim", "content B — differs\n")
  discard execCmdEx("cd " & quoteShell(root) & commit)
  let (tb, _) = execCmdEx("cd " & quoteShell(root) & " && git rev-parse HEAD^{tree}")
  result = (ta.strip(), tb.strip())

proc probeBody(): string =
  ## probe 스텝 본문 원문 — keygen 템플릿만 실행 가능한 형태로 치환
  ## (probe 앵커는 b-probe-tree — 클로저 digest 키 identity와 독립인 트리 OID)
  let raw = stepBody(repoRootOf() / ActionYml, "B-layer semantic provenance")
  result = raw.replace("${{ steps.keygen.outputs.b-probe-tree }}", "${AXIOM_PROBE_IDENTITY}")

proc probeEnv(probeTree: string): seq[(string, string)] =
  @[("AXIOM_PROBE_IDENTITY", probeTree)]

proc stubAllBinaries(root: string, exitCode: int) =
  ## 4종 전부를 지정 exit code의 실행 stub으로 교체 + ircheck를 실행가능 stub으로
  ## 준비 — probe는 정상 세계에서 4종 전부를 실행하고 ircheck 존재·실행비트를
  ## 단언한다(DEBT#502; 실바이너리 감지 실측은 evidence 기록 참조).
  for b in ProbeBinNames:
    writeFile(root / ("bin/" & b), "#!/bin/sh\nexit " & $exitCode & "\n")
    discard execCmdEx("chmod +x " & quoteShell(root / ("bin/" & b)))
  createDir(root / "proofs/.lake/build/bin")
  writeFile(root / "proofs/.lake/build/bin/ircheck", "#!/bin/sh\nexit " & $exitCode & "\n")
  discard execCmdEx("chmod +x " & quoteShell(root / "proofs/.lake/build/bin/ircheck"))

suite "J3 §3.3 B cache manifest 앵커링 (action.yml 실제 스텝 본문)":

  test "python heredoc은 컴파일 가능한 python이다 (원문 무결성)":
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let py = pythonHeredoc(body)
    let pyf = getTempDir() / ("bverify_" & nextTag() & ".py")
    writeFile(pyf, py)
    let (outp, code) = execCmdEx("python3 -c " &
      quoteShell("import sys; compile(open(sys.argv[1]).read(), 'bverify.py', 'exec'); print('COMPILED')") &
      " " & quoteShell(pyf))
    removeFile(pyf)
    check code == 0
    check "COMPILED" in outp
    check "expect = os.environ[\"EXPECT_B_KEY\"]" in py  # 신뢰 입력 기대값이 블록 안에 존재

  test "(h) healthy — 재유도 identity + 전 엔트리 일치 → b-verify-ok=true, 폐기 없음":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check r.code == 0
    check ghOutputValue(r.ghOut, "b-verify-ok") == "true"
    check "RESULT OK — 5/5 entries digest-verified" in r.outp  # DEBT#502: 5/5 = 완전 페이로드 마커
    check "anchor — derivation source" in r.outp  # 파생 소스 명시 기록(로그)
    check "DISCARDED" notin r.outp
    check fileExists(root / "bin/ax")

  test "(r) 불완전 manifest — 5파일 필수 집합 결손(ircheck) → 폐기 (DEBT#502: 부분 페이로드는 검증된 공급이 아니다)":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    var m = parseJson(readFile(root / ManifestRel))
    m["files"].delete("proofs/.lake/build/bin/ircheck")  # 구세대 lane 부분 엔트리 형태
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check r.code == 0
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "manifest files map incomplete" in r.outp
    check "never a verified supply" in r.outp
    check not fileExists(root / "bin/ax")
    check not fileExists(root / "proofs/.lake/build/bin/ircheck")

  test "(i) manifest identity가 재유도 기대와 불일치 → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    var m = parseJson(readFile(root / ManifestRel))
    m["bKey"] = %"axiom-b-0000000000000000000000000000000000000000-forged0000000000000000"
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check r.code == 0  # fail-closed: 폐기 후 정상 진행
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "not an anchor" in r.outp
    check not fileExists(root / "bin/ax")

  test "(a) manifest-only files{} 변조 → digest 불일치 → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    var m = parseJson(readFile(root / ManifestRel))
    m["files"]["bin/ax"] = %"0000000000000000000000000000000000000000000000000000000000000000"
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "sha256 mismatch" in r.outp
    check not fileExists(root / "bin/ax")

  test "(b) payload-only 바이너리 변조 → digest 불일치 → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    writeFile(root / "bin/ax", "TAMPERED binary\n")
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "sha256 mismatch" in r.outp
    check not fileExists(root / "bin/ax")

  test "(c) 동시 변조 — digest 레이어는 자기일관 통과(원형성 사실 고정 — probe가 닫는 간)":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    # 동시 변조: 바이너리 교체 + manifest files{}를 그에 맞게 재작성(identity
    # 필드는 그대로 — 오염이 identity를 유지하는 최악의 자기일관 시나리오)
    writeFile(root / "bin/ax", "STALE binary from another tree\n")
    var m = parseJson(readFile(root / ManifestRel))
    m["files"]["bin/ax"] = %sha256Of(root / "bin/ax")
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check r.code == 0
    check ghOutputValue(r.ghOut, "b-verify-ok") == "true"  # digest 레이어만으론 미검출
    check fileExists(root / "bin/ax")

  test "(c2) 잔여 시나리오 종단간 — 보조 바이너리 교체+manifest 재작성: digest 레이어 자기일관 통과 → probe 감지 → 폐기":
    # PR #566 증거 §6 잔여의 정확한 재현: bin/ax는 정상 유지, 보조 바이너리만
    # 교체 + manifest files{} 재작성 — probe가 bin/ax만 검증하던 세계에서는
    # 통과했지만, 4종 전부 자기검증으로 확장된 probe가 이 간을 닫는다.
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    let (treeA, _) = gitFixture(root)
    # stub 교체로 모든 엔트리 재계산 — 자기일관 정상 페이로드에서 출발
    var m = parseJson(readFile(root / ManifestRel))
    for rel in BFiles:
      m["files"][rel] = %sha256Of(root / rel)
    writeFile(root / ManifestRel, m.pretty)
    setIdentity(root, treeA)
    writeFile(root / "bin/gate_hook", "STALE gate_hook from another tree\n")
    m = parseJson(readFile(root / ManifestRel))
    m["files"]["bin/gate_hook"] = %sha256Of(root / "bin/gate_hook")
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(treeA))
    check r.code == 0
    check ghOutputValue(r.ghOut, "b-verify-ok") == "true"  # digest 레이어만으론 미검출 (잔여 사실 고정)
    check fileExists(root / "bin/gate_hook")
    # probe가 이 간을 닫는다: gate_hook stub exit 1 = 신뢰 트리와 불일치하는
    # 바이너리의 SourceCoherence FATAL 관측 계약
    writeFile(root / "bin/gate_hook", "#!/bin/sh\nexit 1\n")
    discard execCmdEx("chmod +x " & quoteShell(root / "bin/gate_hook"))
    let rp = runStep(probeBody(), root, probeEnv(treeA))
    check "AXIOM_CACHE_B_PROBE: FAIL — restored bin/gate_hook" in rp.outp
    check "AXIOM_CACHE_B_PROBE: DISCARDED" in rp.outp
    check not fileExists(root / "bin/gate_hook")
    check not fileExists(root / "bin/ax")

  test "(m) manifest 누락 → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    removeFile(root / ManifestRel)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "manifest missing from restored payload" in r.outp
    check not fileExists(root / "bin/ax")

  test "(v) vacuous manifest(files{} 비었음) → 폐기 (극장 방지)":
    let root = makeFixture()
    defer: removeDir(root)
    setIdentity(root, GoodTree)
    var m = parseJson(readFile(root / ManifestRel))
    m["files"] = newJObject()
    writeFile(root / ManifestRel, m.pretty)
    let body = stepBody(repoRootOf() / ActionYml, "B-layer fingerprint verify")
    let r = runStep(body, root, bVerifyEnv(GoodTree))
    check ghOutputValue(r.ghOut, "b-verify-ok") == "false"
    check "files map is empty" in r.outp
    check not fileExists(root / "bin/ax")

suite "J3 §3.3 semantic provenance probe (action.yml 실제 스텝 본문)":

  test "(p1) probe healthy — 4종 stub 모두 exit 0 → OK, B 파일 보존":
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    let (treeA, _) = gitFixture(root)
    let r = runStep(probeBody(), root, probeEnv(treeA))
    check r.code == 0
    check "AXIOM_CACHE_B_PROBE: OK" in r.outp
    check "restored proofs/.lake/build/bin/ircheck present+executable" in r.outp  # DEBT#502 5번째 멤버
    check "DISCARDED" notin r.outp
    check fileExists(root / "bin/ax")

  test "(p2) probe 감지(bin/ax) — binary provenance 불일치(exit 1 = SourceCoherence FATAL 관측 계약) → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    # foreign bin/ax: provenance 불일치 바이너리의 관측 가능 계약(exit 1)을
    # 재현 — 실바이너리 + 실제 트리 감지는 docs/evidence 실측 기록 참조
    writeFile(root / "bin/ax", "#!/bin/sh\nexit 1\n")
    discard execCmdEx("chmod +x " & quoteShell(root / "bin/ax"))
    let (_, treeB) = gitFixture(root)
    let r = runStep(probeBody(), root, probeEnv(treeB))
    check r.code == 0  # fail-closed: 폐기 후 정상 진행(잡 실패 아님)
    check "AXIOM_CACHE_B_PROBE: FAIL" in r.outp
    check "simultaneous payload+manifest contamination detected" in r.outp
    check "AXIOM_CACHE_B_PROBE: DISCARDED" in r.outp
    check not fileExists(root / "bin/ax")
    check not fileExists(root / "bin/gate_hook")

  test "(p4) probe 감지(보조 바이너리) — bin/gate_hook만 provenance 불일치 → 폐기 (bin/ax 외 3종 커버 — §6 잔여 닫힘)":
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    # 보조 바이너리 단독 교체 + bin/ax 정상 유지 — 직전까지 미검출이던 클래스
    writeFile(root / "bin/gate_hook", "#!/bin/sh\nexit 1\n")
    discard execCmdEx("chmod +x " & quoteShell(root / "bin/gate_hook"))
    let (treeA, _) = gitFixture(root)
    let r = runStep(probeBody(), root, probeEnv(treeA))
    check r.code == 0  # fail-closed: 폐기 후 정상 진행(잡 실패 아님)
    check "AXIOM_CACHE_B_PROBE: OK — restored bin/ax" in r.outp  # 정상 bin/ax는 통과
    check "AXIOM_CACHE_B_PROBE: FAIL — restored bin/gate_hook" in r.outp
    check "AXIOM_CACHE_B_PROBE: DISCARDED" in r.outp
    check not fileExists(root / "bin/gate_hook")
    check not fileExists(root / "bin/precompile_gates")

  test "(p5) probe 감지(DEBT#502) — ircheck 결손 → 폐기 (5번째 공급 멤버 — 부분 페이로드는 재사용 금지)":
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    let (treeA, _) = gitFixture(root)
    removeFile(root / "proofs/.lake/build/bin/ircheck")  # DEBT#502 부분 페이로드 형태
    let r = runStep(probeBody(), root, probeEnv(treeA))
    check r.code == 0  # fail-closed: 폐기 후 정상 진행(잡 실패 아님)
    check "AXIOM_CACHE_B_PROBE: OK — restored bin/ax" in r.outp  # 4종 Nim probe는 전부 통과
    check "proofs/.lake/build/bin/ircheck missing or not executable" in r.outp
    check "partial payload is not a verified supply" in r.outp
    check "AXIOM_CACHE_B_PROBE: DISCARDED" in r.outp
    check not fileExists(root / "bin/ax")
    check not fileExists(root / "proofs/.lake/build/bin/ircheck")

  test "(p3) probe content-equal 트리 — 같은 src 내용이면 다른 커밋 트리도 수용 (semantic identity)":
    let root = makeFixture()
    defer: removeDir(root)
    stubAllBinaries(root, 0)
    let (treeA, _) = gitFixture(root)
    # src 내용을 다시 content A로 복원 + src 밖 파일 추가 → 다른 트리 OID,
    # 동일한 src 서브트리 내용 (바이트 동일성이 아닌 semantic identity 수용)
    writeFile(root / "src/a.nim", "content A\n")
    writeFile(root / "notes-unrelated.md", "docs change only\n")
    discard execCmdEx("cd " & quoteShell(root) &
      " && git -c user.email=t@t -c user.name=t add -A" &
      " && git -c user.email=t@t -c user.name=t commit -qm c")
    let (treeC, _) = execCmdEx("cd " & quoteShell(root) & " && git rev-parse HEAD^{tree}")
    check treeC.strip() != treeA  # 다른 트리 OID
    let r = runStep(probeBody(), root, probeEnv(treeC.strip()))
    check "AXIOM_CACHE_B_PROBE: OK" in r.outp
    check fileExists(root / "bin/ax")

  test "(e) probe exp-* 네임스페이스 → SKIP, 폐기 없음":
    let root = makeFixture()
    defer: removeDir(root)
    let r = runStep(probeBody(), root, probeEnv("exp-measurement-ref"))
    check r.code == 0
    check "AXIOM_CACHE_B_PROBE: SKIP" in r.outp
    check fileExists(root / "bin/ax")

  test "(g) probe 신뢰 트리 미존재(git archive 실패) → 폐기":
    let root = makeFixture()
    defer: removeDir(root)
    # 존재하지 않는 40-hex 트리 — keygen이 보장하는 객체 부재 상태의 fail-closed
    let r = runStep(probeBody(), root, probeEnv("1111111111111111111111111111111111111111"))
    check r.code == 0
    check "AXIOM_CACHE_B_PROBE: FAIL" in r.outp
    check "not materializable" in r.outp
    check "AXIOM_CACHE_B_PROBE: DISCARDED" in r.outp
    check not fileExists(root / "bin/ax")

# ─────────────────────────────────────────────────────────────────────────────
# R3 B-cache 키 입력 폐쇄 (keygen 실제 스텝 본문)
#
# b-identity = 컴파일 참여 입력 폐쇄 digest (2026-10-09, R3 등록 슬라이스):
#   src 전수(generated 제외) + staticRead 컴파일 입력 바이트 + 정책문서
#   비공백 술어 비트 + SPEC 셀 존재 비트 — cache-build-source 커밋의 git
#   객체에서 유도(작업 트리 오염 무시). probe-tree(트리 OID)는 별도 출력.
# ─────────────────────────────────────────────────────────────────────────────

const KeygenClosureFiles = [
  "axiom.nimble", "lean-toolchain",
  "proofs/proof_witness.json", "proofs/lean-toolchain",
  "config/gates.manifest.toml", "config/gates.waiver.toml",
  "config/templates/good_plan.md",
  "config/templates/bad_plan_missing_stage.md",
  "config/templates/bad_plan_no_tasks.md",
  "data/axiom_catalog.json", "data/command_policy.json",
  "data/stateless_whitelist.json", "data/policy_manifest.json",
  "data/feature_manifest.json", "data/i18n/ko.json",
  "docs/spec/spec_registry.json", "tools/ci/smoke_test.nim"]

proc keygenBody(): string =
  ## keygen 스텝 본문 원문 — inputs 템플릿만 실행 가능한 형태로 치환
  stepBody(repoRootOf() / ActionYml, "Compute A/B cache identities")
    .replace("${{ inputs.cache-build-source }}", "${KEYGEN_SRC}")
    .replace("${{ inputs.provision-scope }}", "full")

proc keygenEnv(src: string): seq[(string, string)] =
  @[("KEYGEN_SRC", src), ("RUNNER_OS", "Linux")]

proc commitAll(root: string): string =
  ## 전체를 커밋하고 새 HEAD sha 반환
  discard execCmdEx("cd " & quoteShell(root) &
    " && git -c user.email=t@t -c user.name=t add -A" &
    " && git -c user.email=t@t -c user.name=t commit -qm w")
  let (outp, _) = execCmdEx("cd " & quoteShell(root) & " && git rev-parse HEAD")
  result = outp.strip()

proc keygenFixture(): string =
  ## 클로저 요구 파일 전체 + 레시피 + script_hash 입력을 갖춘 git fixture
  let root = getTempDir() / "j3_keygen_" & nextTag()
  createDir(root / ".github/actions/setup-axiom-toolchain")
  createDir(root / "src/gate")
  createDir(root / "src/core")
  createDir(root / "src/generated")
  createDir(root / "config/templates")
  createDir(root / "data/i18n")
  createDir(root / "docs/spec")
  createDir(root / "docs/agents")
  createDir(root / "proofs")
  createDir(root / "tools/ci")
  writeFile(root / ".github/actions/setup-axiom-toolchain/action.yml", "fixture-action\n")
  writeFile(root / "nimble.lock", "fixture-lock\n")
  writeFile(root / "Makefile", "fixture-makefile\n")
  writeFile(root / "config.nims", "fixture-config\n")
  writeFile(root / "config/effects.nims", "fixture-effects\n")
  writeFile(root / "src/gate/config.nims", "fixture-gate-config\n")
  writeFile(root / "src/core/a.nim", "content A\n")
  writeFile(root / "src/generated/build_env.nim", "generated\n")
  for f in KeygenClosureFiles:
    writeFile(root / f, "closure-bytes: " & f & "\n")
  writeFile(root / "docs/spec/three_tier_contract_architecture.md",
    "| Spec | Value |\n|---|---|\n" &
    "| SPEC-T1-ASIRATIO | 0.0 |\n| SPEC-T1-DURATION | 0 |\n" &
    "| SPEC-T1-VKDRATIO | 0 |\n| SPEC-UNRELATED-ROW | x |\n")
  writeFile(root / "AGENTS.md", "policy bytes v1\n")
  writeFile(root / "docs/agents/architecture.md", "arch bytes\n")
  writeFile(root / "docs/agents/rules_workflow.md", "rules bytes\n")
  writeFile(root / "docs/other.md", "docs-only prose\n")
  discard execCmdEx("cd " & quoteShell(root) & " && git init -q")
  result = root

proc keyOutputs(ghOut: string): tuple[ident, key, probeTree: string] =
  result.ident = ghOutputValue(ghOut, "b-identity")
  result.key = ghOutputValue(ghOut, "b-key")
  result.probeTree = ghOutputValue(ghOut, "b-probe-tree")

suite "R3 B-cache 키 입력 폐쇄 (keygen 실제 스텝 본문)":

  test "(k1) 결정론 — 같은 커밋 2회 → 동일 identity·key·probe-tree (상호검증: 동일 입력 ⇒ 동일 키)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c = commitAll(root)
    let body = keygenBody()
    let r1 = runStep(body, root, keygenEnv(c))
    let r2 = runStep(body, root, keygenEnv(c))
    check r1.code == 0
    check r2.code == 0
    let o1 = keyOutputs(r1.ghOut)
    let o2 = keyOutputs(r2.ghOut)
    check o1.ident.len == 40
    check o1.ident == o2.ident
    check o1.key == o2.key
    check o1.probeTree == o2.probeTree
    check o1.probeTree.len == 40
    check o1.key.startsWith("axiom-b-" & o1.ident & "-")

  test "(k2) docs-only 커밋 → identity 불변 + probe-tree 전진 (트리-OID 무효화 소멸 — R3 핵심 이점)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "docs/other.md", "docs-only prose EDITED\n")
    let c2 = commitAll(root)
    check c1 != c2
    let body = keygenBody()
    let r1 = runStep(body, root, keygenEnv(c1))
    let r2 = runStep(body, root, keygenEnv(c2))
    check r1.code == 0
    check r2.code == 0
    let o1 = keyOutputs(r1.ghOut)
    let o2 = keyOutputs(r2.ghOut)
    check o1.ident == o2.ident           # 키 불변 (구 트리-OID 단위라면 전진했을 지점)
    check o1.probeTree != o2.probeTree   # 트리 OID는 전진 — probe 앵커로만 존재

  test "(k3) src/.nim 바이트 변경(커밋) → identity 변화 (상호검증: 다른 빌드 입력 ⇒ 다른 키)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "src/core/a.nim", "content B — differs\n")
    let c2 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    check o1.ident != o2.ident

  test "(k4) spec_registry.json 바이트 변경 → identity 변화 (staticRead 각인 입력)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "docs/spec/spec_registry.json", "closure-bytes: EDITED\n")
    let c2 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    check o1.ident != o2.ident

  test "(k5) SPEC 셀 — 필수 셀 제거 → identity 변화 / 무관 행 편집 → 불변 (셀 매칭 술어)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "docs/spec/three_tier_contract_architecture.md",
      "| Spec | Value |\n|---|---|\n" &
      "| SPEC-T1-ASIRATIO | 0.0 |\n| SPEC-T1-DURATION | 0 |\n" &
      "| SPEC-T1-VKDRATIO | 0 |\n| SPEC-UNRELATED-ROW | EDITED |\n")
    let c2 = commitAll(root)
    writeFile(root / "docs/spec/three_tier_contract_architecture.md",
      "| Spec | Value |\n|---|---|\n" &
      "| SPEC-T1-ASIRATIO | 0.0 |\n| SPEC-T1-DURATION | 0 |\n" &
      "| SPEC-UNRELATED-ROW | EDITED |\n")
    let c3 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    let o3 = keyOutputs(runStep(body, root, keygenEnv(c3)).ghOut)
    check o1.ident == o2.ident           # 매크로가 요구하지 않는 행 — 키 무관
    check o1.ident != o3.ident           # 필수 셀(SPEC-T1-VKDRATIO) 소멸 — 키 전진

  test "(k6) AGENTS.md — 비공백 바이트 교체 → 불변 / 비우기 → 변화 (비공백 술어 비트)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "AGENTS.md", "policy bytes v2 — different bytes\n")
    let c2 = commitAll(root)
    writeFile(root / "AGENTS.md", "")
    let c3 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    let o3 = keyOutputs(runStep(body, root, keygenEnv(c3)).ghOut)
    check o1.ident == o2.ident           # 바이트 각인 아님 — 비공백이면 무관
    check o1.ident != o3.ident           # 빈 파일 = 컴파일 성공 술어 반전 → 키 전진

  test "(k7) 클로저 파일(data/axiom_catalog.json) 바이트 변경 → identity 변화":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "data/axiom_catalog.json", "closure-bytes: EDITED\n")
    let c2 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    check o1.ident != o2.ident

  test "(k8) 클로저 파일 삭제 → keygen FAIL (fail-closed — divergence 없음)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    removeFile(root / "data/command_policy.json")
    let c2 = commitAll(root)
    let body = keygenBody()
    let r = runStep(body, root, keygenEnv(c2))
    check r.code != 0
    check "fail-closed" in r.outp
    let baseline = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    check baseline.ident.len == 40       # 정상 트리는 여전히 키 생성

  test "(k9) exp-* 네임스페이스 → identity 원문 전달 + probe-tree 공백":
    let root = keygenFixture()
    defer: removeDir(root)
    let base = commitAll(root)
    check base.len == 40
    let r = runStep(keygenBody(), root, keygenEnv("exp-measurement-ref"))
    check r.code == 0
    let o = keyOutputs(r.ghOut)
    check o.ident == "exp-measurement-ref"
    check o.probeTree == ""
    check o.key.startsWith("axiom-b-exp-measurement-ref-")

  test "(k10) 미커밋 작업파일 오염 → identity 불변 (git 객체 유도 — 체크아웃 오염 차단)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c = commitAll(root)
    let baseline = keyOutputs(runStep(keygenBody(), root, keygenEnv(c)).ghOut)
    writeFile(root / "src/core/a.nim", "UNCOMMITTED dirt\n")
    writeFile(root / "docs/spec/spec_registry.json", "UNCOMMITTED registry\n")
    let after = keyOutputs(runStep(keygenBody(), root, keygenEnv(c)).ghOut)
    check baseline.ident == after.ident
    check baseline.probeTree == after.probeTree

  test "(k11) src/generated 변경 → identity 불변 (BuildSourceHash 우주 제외 — 순환성 차단)":
    let root = keygenFixture()
    defer: removeDir(root)
    let c1 = commitAll(root)
    writeFile(root / "src/generated/build_env.nim", "REGENERATED\n")
    let c2 = commitAll(root)
    let body = keygenBody()
    let o1 = keyOutputs(runStep(body, root, keygenEnv(c1)).ghOut)
    let o2 = keyOutputs(runStep(body, root, keygenEnv(c2)).ghOut)
    check o1.ident == o2.ident

  test "(k12) 정적 클로저 검증 — src literal staticRead 대상(src 밖)·spec() ID 전부가 keygen 폐쇄에 존재":
    ## 클로저 표류 가드: src의 literal staticRead 대상이 src 밖으로 나가면
    ## keygen 목록에 없어야 키가 그 입력을 소화한다 — 신규 staticRead 추가 시
    ## 이 테스트가 keygen 갱신을 강제한다 (미배선 모듈까지 보수적으로 포함).
    let body = keygenBody()
    for f in KeygenClosureFiles:
      check body.contains(f)
    for f in ["AGENTS.md", "docs/agents/architecture.md",
              "docs/agents/rules_workflow.md",
              "docs/spec/three_tier_contract_architecture.md"]:
      check body.contains(f)
    for id in ["SPEC-T1-ASIRATIO", "SPEC-T1-DURATION", "SPEC-T1-VKDRATIO"]:
      check body.contains(id)
    # 동적 스캔 1 — literal staticRead 대상(src 밖)
    let repoRoot = repoRootOf()
    var outsideTargets = 0
    for f in walkDirRec(repoRoot / "src"):
      if not f.endsWith(".nim") or "/generated/" in f:
        continue
      let content = readFile(f)
      var i = 0
      while true:
        i = content.find("staticRead(", i)
        if i < 0:
          break
        var j = i + "staticRead(".len
        while j < content.len and content[j] in {' ', '\t'}:
          inc j
        if j >= content.len or content[j] != '"':
          i = i + "staticRead(".len
          continue
        let open = j
        let close = content.find("\"", open + 1)
        if close < 0:
          break
        let lit = content[open + 1 ..< close]
        let rel = normalizedPath(f.splitFile().dir / lit).substr(repoRoot.len + 1)
        if not rel.startsWith("src/"):
          check body.contains(rel)
          inc outsideTargets
        i = close + 1
    check outsideTargets >= 1  # 스캔 유효성 — literal 대상이 실제 발견됨
    # 동적 스캔 2 — src의 spec("...") 사용 ID는 keygen 셀 비트와 일치해야 한다
    var usedIds: seq[string]
    for f in walkDirRec(repoRoot / "src"):
      if not f.endsWith(".nim") or "/generated/" in f:
        continue
      let content = readFile(f)
      var i = 0
      while true:
        i = content.find("{.spec(\"", i)
        if i < 0:
          break
        let open = i + "{.spec(\"".len
        let close = content.find("\"", open)
        if close < 0:
          break
        let id = content[open ..< close]
        if id.startsWith("SPEC-") and id notin usedIds:
          usedIds.add(id)
        i = close + 1
    check usedIds.len >= 3
    for id in usedIds:
      check body.contains(id)
