## test_derive_checker_closure.nim — closure 유도자 fail-closed 계약 테스트
##
## Evidence [0b]: 미해소 의존성 fixture exit≠0 — silent skip = 미완료.
##
## 시나리오:
##   (a) hermetic happy path — 임시 git 저장소에서 workflow → make 타깃 → nim c
##       → import 그래프 → artifact 다운로드 별칭까지 전체 walk가 exit 0 +
##       시드 전부 포함 + git ls-tree 포맷.
##   (b) 실저장소 HEAD 검사 — ci/checker.mk가 트리에 있으면(커밋 후) full pass,
##       없으면(커밋 전) 시드 부재 fail-closed를 단언 (양쪽 다 진짜 단언 —
##       조용한 skip 없음).
##   (c) fail-closed fixture — `./generated-command "$MODE"` / `eval …` → exit≠0
##       + stderr에 UNRESOLVED.
##   (d) 미존재 ref → exit≠0.
##
## fixture는 격리 임시 git 저장소(/tmp)에서 만들며 작업 저장소를 건드리지 않는다.

import std/[unittest, os, osproc, strutils]

const
  SeedFiles = [
    "ci/checker.mk",
    "tools/ci/derive_checker_closure.nim",
    "tools/ci/impact_closure_selector.nim",
    "tools/ci/proof_reconcile_gate.nim",
    "tests/gateway/all_gateway_runner.nim",
    "nimble.lock",
    "config.nims",
    "config/effects.nims",
    "src/gate/config.nims",
  ]
  DeriverSource = "tools/ci/derive_checker_closure.nim"

var deriverBin: string = ""

proc gitRevParse(root: string): string =
  let (o, _) = execCmdEx("git -C " & quoteShell(root) & " ls-tree HEAD -- ci/checker.mk")
  result = o

proc compileDeriver(): string =
  ## deriver 1회 컴파일 (테스트 1회 캐시). 실패 = 테스트 인프라 오류.
  if deriverBin.len > 0 and fileExists(deriverBin):
    return deriverBin
  let bin = getTempDir() / "derive_cc_test_" & $getCurrentProcessId()
  let (outp, code) = execCmdEx(
    "nim c --hints:off --skipParentCfg --skipProjCfg --path:src " &
    "-o:" & bin & " " & DeriverSource)
  doAssert code == 0, "deriver 컴파일 실패:\n" & outp
  deriverBin = bin
  result = bin

proc runDeriver(repo: string, args: string): tuple[outp, errp: string, code: int] =
  ## stdout(closure 멤버십)과 stderr(진단)를 분리 수집한다.
  let bin = compileDeriver()
  let errPath = getTempDir() / "derive_cc_err_" & $getCurrentProcessId()
  let (outp, code) = execCmdEx(
    bin & " " & args & " --repo " & quoteShell(repo) & " 2>" & quoteShell(errPath))
  let errp = if fileExists(errPath): readFile(errPath) else: ""
  if fileExists(errPath):
    removeFile(errPath)
  result = (outp, errp, code)

proc writeFixture(repo: string, workflowTail: string) =
  createDir(repo)
  for seed in SeedFiles:
    let parent = parentDir(repo / seed)
    if parent.len > 0:
      createDir(parent)
    writeFile(repo / seed, "# fixture seed\n")
  createDir(repo / "tools")
  createDir(repo / "tests")
  createDir(repo / ".github" / "workflows")
  writeFile(repo / "tools/tools_src.nim", "# tools src\n")
  writeFile(repo / "tests/helper.nim", "# helper\n")
  writeFile(repo / "tests/helper_main.nim", "import ./helper\n")
  writeFile(repo / "ci/checker.mk",
    "NIM ?= nim\n" &
    "test-gateway:\n" &
    "\t@nim c --hints:off -o:bin/runner tests/helper_main.nim\n" &
    "\t@./bin/runner\n")
  writeFile(repo / ".github/workflows/runner-pool-acceptance.yml",
    "name: runner-pool-acceptance\n" &
    "on:\n  push:\n    branches: [main]\n" &
    "jobs:\n" &
    "  job1:\n    steps:\n" &
    "      - name: build+run\n" &
    "        run: |\n" &
    "          make test-gateway\n" &
    "          nim c --hints:off -o:bin/gate_tool tools/tools_src.nim\n" &
    "      - name: upload\n" &
    "        uses: actions/upload-artifact@v4\n" &
    "        with:\n" &
    "          name: verifier\n" &
    "          path: bin/gate_tool\n" &
    "      - name: download\n" &
    "        uses: actions/download-artifact@v4\n" &
    "        with:\n" &
    "          name: verifier\n" &
    "          path: verifier\n" &
    "      - name: exec\n" &
    "        run: |\n" &
    "          chmod +x verifier/gate_tool\n" &
    workflowTail)

proc commitFixture(repo: string) =
  discard execCmdEx("git -C " & quoteShell(repo) & " init -q")
  discard execCmdEx("git -C " & quoteShell(repo) & " add -A")
  let (o, c) = execCmdEx("git -C " & quoteShell(repo) &
    " -c user.email=t@t -c user.name=t commit -qm init")
  doAssert c == 0, "fixture commit 실패: " & o

proc repoRootOf(): string =
  ## 테스트가 놓인 저장소 루트 (tests/ci/ → 저장소 루트).
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

suite "derive_checker_closure fail-closed 계약":

  test "hermetic happy path — walk 전체(import/artifact) 성공 + 시드 포함":
    let repo = getTempDir() / "cc_ok_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./verifier/gate_tool\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--ref HEAD")
    if r.code != 0:
      echo r.errp
    check r.code == 0
    for seed in SeedFiles:
      check seed in r.outp
    check ".github/workflows/" notin r.outp
    # import 그래프 (tests/helper_main.nim → ./helper) 멤버십
    check "tests/helper_main.nim" in r.outp
    check "tests/helper.nim" in r.outp
    # artifact 다운로드 별칭 (verifier/gate_tool → tools/tools_src.nim)
    check "tools/tools_src.nim" in r.outp
    # git ls-tree 포맷 엄격 검사
    var badFormat = 0
    for line in r.outp.splitLines():
      if line.len == 0:
        continue
      let tab = line.find('\t')
      if tab < 0:
        badFormat.inc
        continue
      let meta = line[0 ..< tab].split(' ')
      if meta.len != 3 or meta[1] != "blob" or
         meta[0].len != 6 or meta[2].len != 40:
        badFormat.inc
    check badFormat == 0

  test "실저장소 HEAD — ci/checker.mk 커밋 여부에 따른 양쪽 단언":
    let root = repoRootOf()
    let r = runDeriver(root, "--ref HEAD")
    if "ci/checker.mk" in gitRevParse(root):
      check r.code == 0
      check "ci/checker.mk" in r.outp
      check "nimble.lock" in r.outp
    else:
      # 커밋 전 상태 — 시드 부재가 UNRESOLVED로 거부되어야 한다 (조용한 축소 금지)
      check r.code != 0
      check "UNRESOLVED" in r.errp
      check "시드" in r.errp

  test "fail-closed fixture — 생성 바이너리 변수 경로는 exit≠0":
    let repo = getTempDir() / "cc_gen_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./generated-command \"$MODE\"\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--ref HEAD")
    check r.code != 0
    check "UNRESOLVED" in r.errp
    check "generated-command" in r.errp

  test "fail-closed fixture — eval은 항상 거부":
    let repo = getTempDir() / "cc_eval_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          eval \"$CMD\"\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--ref HEAD")
    check r.code != 0
    check "UNRESOLVED" in r.errp
    check "eval" in r.errp

  test "--tree 모드 (Amendment F 제3각) — --ref HEAD와 바이트 동일 산출":
    # 같은 커밋의 트리 OID를 --tree로 주면 --ref와 완전히 같은 closure이
    # 나와야 한다 — 산출은 트리의 순수 함수 (결정론).
    let repo = getTempDir() / "cc_tree_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./verifier/gate_tool\n")
    commitFixture(repo)
    let (treeOut, treeCode) = execCmdEx(
      "git -C " & quoteShell(repo) & " rev-parse HEAD^{tree}")
    doAssert treeCode == 0, treeOut
    let rTree = runDeriver(repo, "--tree " & treeOut.strip())
    if rTree.code != 0:
      echo rTree.errp
    check rTree.code == 0
    let rRef = runDeriver(repo, "--ref HEAD")
    check rRef.code == 0
    check rTree.outp == rRef.outp

  test "--tree 미존재 OID — exit≠0 (fail-closed)":
    let repo = getTempDir() / "cc_treebad_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./verifier/gate_tool\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--tree deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    check r.code != 0
    check "트리 아님" in r.errp or "존재하지 않음" in r.errp

  test "--ref와 --tree 동시 지정 — 상호 배타 위반 exit≠0":
    let repo = getTempDir() / "cc_treeboth_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./verifier/gate_tool\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--ref HEAD --tree deadbeefdeadbeefdeadbeefdeadbeefdeadbeef")
    check r.code != 0
    check "상호 배타" in r.errp

  test "미존재 ref — exit≠0":
    let repo = getTempDir() / "cc_noref_" & $getCurrentProcessId()
    defer: removeDir(repo)
    writeFixture(repo, "          ./verifier/gate_tool\n")
    commitFixture(repo)
    let r = runDeriver(repo, "--ref DOES-NOT-EXIST")
    check r.code != 0
    check "DOES-NOT-EXIST" in r.errp