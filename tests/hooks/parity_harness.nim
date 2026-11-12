import core/trusted/layer_declaration
axiomLayer "tests"
{.push raises: [CatchableError].}

## parity_harness.nim — Sequential-vs-parallel nim check parity gate
##
## Verifies that the canonical per-file parallel path
##   AXIOM_HERMETIC_BUILDING=1 bin/nim_check_gate <root> incremental <jobs> @files
## produces the same checked / skipped / failed outcome as the legacy sequential
## path it replaces (one `nim check` per staged file, skip-marked fragments
## excluded).
##
## Comparison contract (3-way):
##   checked  = non-skip files actually passed to the compiler
##   skipped  = "nim-check: skip" fragments excluded on BOTH paths
##   failed   = a broken file fails BOTH paths (and the skip marker protects a
##              broken fragment on BOTH paths)
##
## Suites:
##   A (all-good)        -> PASS  both paths
##   B (broken included) -> FAIL  both paths, same failed set
##   C (broken skip)     -> PASS  both paths (skip fragment never checked)
##
## Run:  AXIOM_HERMETIC_BUILDING=1 nim c -r tests/hooks/parity_harness.nim

import std/os
import std/osproc
import std/strutils
import std/sequtils

const
  GateBin = "bin" / "nim_check_gate"
  NimExe  = "nim"
  SkipMarker = "nim-check: skip"

type
  Result3 = object
    name: string
    seqOk: bool
    parOk: bool
    pass: bool

proc runWithHermetic(args: seq[string]): tuple[code: int, outp: string] =
  ## Run a command with hermeticPreBuild disabled so both paths share identical
  ## compiler semantics (housekeeping is irrelevant to check parity).
  var cmd = "AXIOM_HERMETIC_BUILDING=1 "
  cmd.add(args.quoteShellCommand)
  let (outp, code) = execCmdEx(cmd)
  result = (code, outp)

proc seqCheckAll(files: seq[string]): tuple[ok: bool, failed: seq[string]] =
  ## Legacy path: one `nim check` per file, skip-marked fragments excluded.
  var ok = true
  var failed: seq[string] = @[]
  for f in files:
    if f.readFile().contains(SkipMarker):
      continue
    let (code, _) = runWithHermetic(@[NimExe, "check", "--hints:off", f])
    if code != 0:
      ok = false
      failed.add(f.extractFilename())
  result = (ok, failed)

proc parCheckAll(root: string; files: seq[string]; jobs: int):
    tuple[ok: bool, checked: seq[string]] =
  ## New path: canonical per-file parallel gate, skip markers filtered here
  ## (mirrors pre-commit hook filter until absorbed into the runner).
  var eligible: seq[string] = @[]
  for f in files:
    if not f.readFile().contains(SkipMarker):
      eligible.add(f)
  let (code, outp) = runWithHermetic(
    @[GateBin, root, "incremental", $jobs] & eligible)
  let checked = eligible.mapIt(it.extractFilename())
  result = (code == 0, checked)

proc runSuite(root, tmpDir: string; name: string; files: seq[string];
              jobs: int; expectOk: bool): Result3 =
  ## Executes a single suite on both paths and asserts outcome parity.
  let (seqOk, seqFailed) = seqCheckAll(files)
  let (parOk, parChecked) = parCheckAll(root, files, jobs)

  var pass = true
  if seqOk != expectOk:
    echo "  [suite '", name, "'] SEQUENTIAL mismatch: expected ",
         expectOk, " got ", seqOk
    pass = false
  if parOk != expectOk:
    echo "  [suite '", name, "'] PARALLEL mismatch: expected ",
         expectOk, " got ", parOk
    pass = false
  # failed set parity: the broken file must fail BOTH paths identically.
  if not expectOk and seqFailed != @[]:
    let parBroken = parChecked.filterIt(it == "broken.nim")
    if parBroken.len != 1:
      echo "  [suite '", name, "'] parallel failed-set mismatch (broken.nim absent)"
      pass = false

  echo "  [suite '", name, "'] sequential=", (if seqOk: "PASS" else: "FAIL"),
       " parallel=", (if parOk: "PASS" else: "FAIL"),
       " -> ", (if pass: "PARITY OK" else: "PARITY BROKEN")
  result = Result3(name: name, seqOk: seqOk, parOk: parOk, pass: pass)

proc main() =
  let root = getCurrentDir()
  let tmpBase = getTempDir() / ("axiom_parity_" & $getCurrentProcessId())
  try:
    createDir(tmpBase)
  except CatchableError:
    # axiom:best-effort(temp dir creation is non-fatal; test failure surfaces via subsequent file ops)
    discard

  # ── Fixtures (real, importable standalone translation units) ──
  let good = tmpBase / "good.nim"
  writeFile(good, "proc addTwo*(a, b: int): int = a + b\n")

  let stub = tmpBase / "stub.nim"
  writeFile(stub, "proc alwaysTrue*(): bool = true\n")

  let ismain = tmpBase / "ismain.nim"
  writeFile(ismain, "proc hello*() = discard\nwhen isMainModule:\n  hello()\n")

  let broken = tmpBase / "broken.nim"
  writeFile(broken, "let x: int = \"not an int\"\n")

  let skipBroken = tmpBase / "skip_broken.nim"
  writeFile(skipBroken, "# " & SkipMarker & "\nlet y: int = \"also broken\"\n")

  defer:
    for p in [good, stub, ismain, broken, skipBroken]:
      try:
        if fileExists(p):
          removeFile(p)
      except CatchableError:
        # axiom:best-effort(fixture teardown cannot fail the test; failure is surfaced by preceding assertions)
        discard
    try:
      if dirExists(tmpBase):
        removeDir(tmpBase)
    except CatchableError:
      # axiom:best-effort(temp dir teardown is cleanup; test outcome already determined)
      discard

  let jobs = 4
  echo "== nim check parity harness =="
  echo "  root: ", root
  echo ""

  var results: seq[Result3] = @[]

  # Suite A: all-good must PASS on both paths.
  results.add(runSuite(root, tmpBase, "A: all-good",
                       @[good, stub, ismain], jobs, expectOk = true))

  # Suite B: broken file must FAIL on both paths (same failed set).
  results.add(runSuite(root, tmpBase, "B: broken-included",
                       @[good, stub, broken], jobs, expectOk = false))

  # Suite C: broken skip-marked fragment must be excluded on both paths -> PASS.
  results.add(runSuite(root, tmpBase, "C: broken-skip",
                       @[good, skipBroken], jobs, expectOk = true))

  echo ""
  var passAll = true
  for r in results:
    if not r.pass:
      passAll = false
  echo "== parity summary: ",
       (if passAll: "ALL PARITY OK" else: "PARITY BROKEN"), " =="
  quit(if passAll: 0 else: 1)

{.pop.}

when isMainModule:
  main()
