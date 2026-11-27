## test_setup_toolchain_skip_a_restore.nim — the skip-a-restore contract test.
##
## Subject: .github/actions/setup-axiom-toolchain/action.yml (parsed verbatim) +
## .github/workflows/certificate-mint.yml (the mint-publish call site).
##
## What this pins down:
##   1. The input exists and defaults to 'false' — every existing caller keeps
##      the restore path.
##   2. The input never leaks into the keygen key formula (a-key/a_fp/b-key are
##      unchanged).
##   3. Gating A-restore alone is a regression: cache-hit is then blank, so
##      '' != 'true' and every native installer/probe comes back to life. Every
##      step that reacts to that outcome must therefore be gated by the same
##      input (no step in the fail-closed chain may misread a skip as a
##      "verified hit").
##   4. The native installers are suppressed only when a verified B supply
##      exists — without a B exact hit the cold-build fallback needs nim, so the
##      install stays.
##   5. The mint-publish call site passes skip-a-restore='true' together with
##      provision-scope='full' (a scope change rotates a_fp -> b-key and forces
##      a structural B MISS).
##
## Fixtures are created only in temporary directories and never touch the
## working repository (the same policy as test_b_cache_anchor.nim).

import std/[os, strutils, unittest]

const
  ActionYml = ".github/actions/setup-axiom-toolchain/action.yml"
  MintWorkflow = ".github/workflows/certificate-mint.yml"

  ## The A-layer chain — steps that must never read as a "verified hit" on a
  ## skip. (4) is A-restore itself; the rest react to its outcome (a missing
  ## cache-hit).
  AChainRestore = "A-layer restore (toolchain"
  AChainObserve = "A-layer restore observation"
  AChainDiscard = "A-layer non-exact discard"
  AChainProbe = "Toolchain functional probes"
  AChainNim = "Install Nim (choosenim"
  AChainNimble = "Install project Nim dependencies"
  AChainLean = "Install Lean 4.33.0"
  AChainSaveAuth = "A-layer save authority"

  ## These steps depend only on the keygen result — a skip string leaking in
  ## here is a key rotation.
  KeygenStep = "Compute A/B cache identities"

proc repoRoot(): string =
  result = absolutePath(currentSourcePath())
  for _ in 0 ..< 3:
    result = result.parentDir()

proc loadAction(root: string): string =
  let p = root / ActionYml
  check fileExists(p)
  readFile(p)

proc stepBlocks(src, nameSubstring: string): seq[string] =
  ## Slice the source into `    - name:` blocks and keep those whose first
  ## line carries nameSubstring.
  var cur: seq[string]
  for line in src.splitLines():
    if line.startsWith("    - name:"):
      if cur.len > 0:
        let b = cur.join("\n")
        if nameSubstring in b.splitLines()[0]:
          result.add b
      cur = @[line]
    elif cur.len > 0:
      cur.add line
  if cur.len > 0:
    let b = cur.join("\n")
    if nameSubstring in b.splitLines()[0]:
      result.add b

proc stepBlock(src, nameSubstring: string): string =
  let all = stepBlocks(src, nameSubstring)
  check all.len == 1
  if all.len == 1: all[0] else: ""

proc stepIf(stepText: string): string =
  for line in stepText.splitLines():
    let t = line.strip()
    if t.startsWith("if:"):
      return t[3 .. ^1].strip()
  ""

proc inputBlock(src, name: string): string =
  ## The `  <name>:` block inside inputs:, up to the next 2-space key.
  let lines = src.splitLines()
  var i = -1
  for k, line in lines:
    if line == "inputs:":
      i = k
      break
  if i < 0: return ""
  inc i
  var cur: seq[string]
  var found = false
  while i < len(lines):
    let line = lines[i]
    if line.len > 0 and not line.startsWith(" "):
      break
    if line.startsWith("  ") and not line.startsWith("   ") and line.endsWith(":"):
      if found: break
      if line.strip() == name & ":":
        found = true
    if found: cur.add line
    inc i
  cur.join("\n")

suite "skip-a-restore: input contract":

  test "input exists with default 'false' (existing callers unchanged)":
    let src = loadAction(repoRoot())
    let blk = inputBlock(src, "skip-a-restore")
    check blk.len > 0
    check "required: false" in blk
    check "default: 'false'" in blk

  test "the input never enters the keygen step (key formula unchanged)":
    let src = loadAction(repoRoot())
    let keygen = stepBlock(src, KeygenStep)
    check keygen.len > 0
    check "skip-a-restore" notin keygen

  test "keygen still derives keys from script_hash and a_fp -> b_key":
    let src = loadAction(repoRoot())
    let keygen = stepBlock(src, KeygenStep)
    check "script_hash=" in keygen
    check "a_fp=" in keygen
    check "b_key=" in keygen


suite "skip-a-restore: A-layer chain gating":

  test "A-restore is gated on the input":
    let src = loadAction(repoRoot())
    check "skip-a-restore" in stepIf(stepBlock(src, AChainRestore))

  test "every step that reads a-restore.cache-hit is gated too":
    ## The regression this guards: skipping the restore alone leaves
    ## cache-hit='' , so ('' != 'true') makes every downstream step run — that
    ## is a regression, not an improvement.
    let src = loadAction(repoRoot())
    for name in [AChainObserve, AChainDiscard, AChainProbe, AChainSaveAuth]:
      let cond = stepIf(stepBlock(src, name))
      check cond.len > 0
      check "skip-a-restore" in cond

  test "native installers are suppressed only behind a verified B supply":
    ## The cold-build fallback (ci-compile-ax) needs nim — turning the install
    ## off while the B supply is unverified kills that path outright.
    let src = loadAction(repoRoot())
    for name in [AChainNim, AChainNimble, AChainLean]:
      let cond = stepIf(stepBlock(src, name))
      check cond.len > 0
      check "skip-a-restore" in cond
      check "b-verify-ok" in cond
      check "b-probe-ok" in cond

  test "A-layer save authority is never granted on a skipped restore":
    let src = loadAction(repoRoot())
    let cond = stepIf(stepBlock(src, AChainSaveAuth))
    check "skip-a-restore" in cond
    check "cache-hit != 'true'" in cond


suite "skip-a-restore: pins verification stays fail-closed":

  test "pins verify asserts z3/jq unconditionally and mirrors the B witness":
    let src = loadAction(repoRoot())
    let blk = stepBlock(src, "Verify toolchain pins")
    check blk.len > 0
    ## z3/jq are supplied on the skip path too, so they are always asserted.
    check "z3 --version | grep 4.13.3" in blk
    check "jq --version | grep 1.7.1" in blk
    ## Relaxing the nim/lean assertions must match the B supply witness exactly.
    check "skip-a-restore" in blk
    check "b-verify-ok" in blk
    check "b-probe-ok" in blk

  test "jq/z3 install steps are NOT gated (supply on every path)":
    let src = loadAction(repoRoot())
    for name in ["Install Z3 4.13.3", "Install jq 1.7.1"]:
      let cond = stepIf(stepBlock(src, name))
      check cond.len > 0
      check "skip-a-restore" notin cond


suite "skip-a-restore: mint-publish caller":

  test "mint-publish sets skip-a-restore='true' without changing scope":
    let root = repoRoot()
    let p = root / MintWorkflow
    check fileExists(p)
    let src = readFile(p)
    ## Only the publish job's toolchain call site matters (the prepare job runs
    ## at runtime scope).
    let lines = src.splitLines()
    var callSites: seq[string]
    var cur: seq[string]
    var inWith = false
    for line in lines:
      if line.contains("uses: ./.github/actions/setup-axiom-toolchain"):
        inWith = true
        cur = @[line]
        continue
      if inWith:
        if line.strip().len == 0:
          inWith = false
          callSites.add cur.join("\n")
          cur = @[]
        else:
          cur.add line
    if cur.len > 0: callSites.add cur.join("\n")
    ## At least two call sites (prepare/publish), and skip-a-restore on exactly
    ## one of them.
    check callSites.len >= 2
    var withSkip = 0
    for c in callSites:
      if "'true'" in c or "skip-a-restore" in c:
        if "skip-a-restore: 'true'" in c:
          inc withSkip
          ## scope must stay full — a scope change rotates b-key and forces a
          ## structural B MISS.
          check "provision-scope: 'full'" in c
    check withSkip == 1
