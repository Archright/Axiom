import std/[algorithm, os, osproc, strutils]
import core/crypto/hash_kernel
import core/results
import verification/judgment_cas
import verification/semantic_set_derivation
import gate/proof_unit_catalog

## Semantic-set derivation unit tests (judgment key ⑤ v3 —
## verification/semantic_set_derivation.nim, contract
## docs/spec/test_judgment_cas_contract.md v1.0.3 §4.1).
##
## S = TreeUniverse(R) − N over a REAL git object store. The tests never
## read the working directory through the derivation authority: the seed is
## `git archive HEAD` extracted into a throwaway repo, so every assertion
## below runs against committed bytes only (the same input face the
## admission workflow hands over).
##
##   T1  determinism + independent re-derivation + partition coverage
##   T2  p2 — an excluded-class byte change advances the tree OID but NOT
##       the key member (the probe OID never enters the key)
##   T3  a normative-carve-out mutation (docs/spec) advances the digest
##   T4  computed staticRead target mutations (config/templates,
##       config/policy) advance the digest — the k12 carve-out proof
##   T5  fail-closed: unresolvable probe (p1/p4), an excluded witness
##       (W ∩ N = ∅), a missing witness (W ⊆ S)
##   T6  k12 drift guard: every literal staticRead target in the seed tree
##       is a declared ComputedStaticReadTarget and every computed site is
##       a declared ComputedStaticReadSite (quote/comment-aware scan)
##   T7  data/ dual-class (redecision 2026-10-18 matrix case 3): every
##       data/*.json advances the digest — the 6 ComputedStaticReadTargets
##       data files are the k12 declared compile-input face, NOT exclusions
##   T8  normative-spelling drift guard: every seed-tree path that
##       case-insensitively matches a NormativePrefix/NormativeExactPath is
##       canonically spelled — the authority matches those case-SENSITIVELY
##       while the extension/root exclusions are case-INSENSITIVE, so a
##       case-variant normative path would fall into the .md N-class and a
##       real normative-face change would NOT advance the key
##   T9  dual-table lockstep: the judgment-key N tables
##       (NoEffect{Prefix,Extension,RootName}Rules) and proof_unit_catalog's
##       CertifiedNoEffect{Prefixes,Extensions,RootNames} carry the same
##       pattern SETS — the key face and the CI selector face move together
##       (sequence order is not asserted: both predicates are any-rule-wins)
##
## Run from the repository root (make test-fast-one T=tests/unit/
## test_judgment_set_derivation.nim). Without git+tar the suite skips
## honestly — there is no derivation to assert without an object store.

var failures = 0

proc expect(cond: bool; msg: string) =
  if cond:
    echo "  [PASS] " & msg
  else:
    inc failures
    echo "  FAIL: " & msg

proc expectErr[T](name: string; res: Result[T, string]; needle: string = "") =
  if res.isErr and (needle.len == 0 or res.error.contains(needle)):
    echo "  [PASS] " & name
  else:
    inc failures
    echo "  FAIL: " & name & "\n      got: " &
      (if res.isErr: "err(" & res.error & ")" else: "ok(<value>)") &
      (if needle.len > 0: "\n      expected err containing: " & needle else: "")

proc skip(name: string; reason: string) =
  echo "  [SKIP] " & name & " (" & reason & ")"

# ---------------------------------------------------------------------------
# Seed — a throwaway repo holding the exact HEAD tree bytes
# ---------------------------------------------------------------------------

type Seed = object
  dir: string    ## the throwaway repo root (its own git object store)
  tree: string   ## the current seed HEAD tree OID (advances per mutation)
  tarPath: string

proc commitAll(seedDir: string; msg: string): Result[string, string] =
  ## Stage everything, commit (hooks/identity/signing neutralized), return
  ## the new HEAD tree OID. `msg` must be a single argv token (no spaces):
  ## the derivation boundary spawns git WITHOUT a shell (Q-012 raw capture).
  ## `add -f`: the archive carries COMMITTED files that .gitignore also lists
  ## (e.g. proofs/proof_witness.json — committed AND generated); a plain
  ## `add -A` would silently drop them and the seed tree would diverge from
  ## the tested tree the derivation is supposed to see.
  let staged = runGitOrErr(seedDir, "add -A -f")
  if staged.isErr:
    return err("git add: " & staged.error)
  let c = runGitOrErr(seedDir, "-c user.name=vs2-test -c user.email=vs2@axiom.dev" &
    " -c commit.gpgsign=false -c core.hooksPath=/dev/null commit -q -m " & msg)
  if c.isErr:
    return err("git commit: " & c.error)
  let t = runGitOrErr(seedDir, "rev-parse HEAD^{tree}")
  if t.isErr:
    return err("rev-parse HEAD^{tree}: " & t.error)
  ok(t.get.strip())

proc buildSeed(repoRoot: string): Result[Seed, string] =
  ## `git archive HEAD` → tar → extract → fresh git repo → commit → tree OID.
  ## The seed bytes are the COMMITTED tree only — exactly the input face the
  ## derivation authority is allowed to see.
  let tarPath = getTempDir() / ("vs2-set-seed-" & $getCurrentProcessId() & ".tar")
  let seedDir = getTempDir() / ("vs2-set-seed-repo-" & $getCurrentProcessId())
  let arch = runGitOrErr(repoRoot,
    "archive HEAD --format=tar --output=" & quoteShell(tarPath))
  if arch.isErr:
    return err("git archive: " & arch.error)
  if not fileExists(tarPath):
    return err("git archive produced no tar at " & tarPath)
  createDir(seedDir)
  let ext = execCmdEx("tar -xf " & quoteShell(tarPath) & " -C " & quoteShell(seedDir),
    options = {poStdErrToStdOut, poUsePath})
  if ext.exitCode != 0:
    return err("tar extract: " & ext.output[0 ..< min(ext.output.len, 200)])
  let init = runGitOrErr(seedDir, "-c init.defaultBranch=main init -q")
  if init.isErr:
    return err("git init: " & init.error)
  let first = commitAll(seedDir, "vs2-semantic-set-seed")
  if first.isErr:
    return err(first.error)
  ok(Seed(dir: seedDir, tree: first.get, tarPath: tarPath))

proc commitAppend(seed: var Seed; relPath, text: string): Result[string, string] =
  ## Append bytes to a seed file, commit, return the new tree OID.
  let p = seed.dir / relPath
  if not fileExists(p):
    return err("seed file missing: " & relPath)
  try:
    let f = open(p, fmAppend)
    f.write(text)
    f.close()
  except CatchableError as e:
    return err("append failed: " & e.msg)
  commitAll(seed.dir, "vs2-mutation-" & relPath)

# ---------------------------------------------------------------------------
# Independent re-derivation (T1) — ls-tree → classify → sort → sha256,
# bypassing deriveSemanticSet/verifyPartition entirely
# ---------------------------------------------------------------------------

proc independentDigest(repo, tree: string): Result[tuple[digest: string;
    universe, semantic, excluded: int], string] =
  let uni = listTreeUniverse(repo, tree)
  if uni.isErr:
    return err(uni.error)
  var records: seq[string] = @[]
  var excluded = 0
  for e in uni.get:
    if classifyPath(e.path) == "excluded":
      inc excluded
    else:
      records.add(elementRecord(e))
  records.sort()
  var stream = ""
  for r in records:
    stream.add(r)
    stream.add('\0')
  ok((sha256Hex(stream), uni.get.len, records.len, excluded))

# ---------------------------------------------------------------------------
# T6 scanner — quote/comment-aware staticRead( census
# ---------------------------------------------------------------------------

type ScanState = enum ssCode, ssLineComment, ssBlockComment, ssStr,
  ssTripleStr, ssCharLit

const StaticReadCall = "staticRead("

proc suffixQuoteAt(s: string; i: int): bool =
  ## A `'` that is a type/numeric suffix rather than a char-literal opener:
  ## the previous significant char is an identifier char or closing delimiter
  ## (e.g. 1'f32, x'y) — never enters the char-literal state.
  var j = i - 1
  while j >= 0 and s[j] in {' ', '\t', '\n', '\r'}:
    dec j
  if j < 0:
    return false
  s[j] in {'a'..'z', 'A'..'Z', '0'..'9', '_', ')', ']', '}', '.', '"'}

proc findStaticReadCalls(content: string): seq[string] =
  ## The raw balanced argument text of every staticRead( call in CODE
  ## position. String literals, triple strings, char literals, line and
  ## block comments are never code — "staticRead(" inside them is skipped.
  result = @[]
  var i = 0
  var state = ssCode
  var depth = 0
  let n = content.len
  while i < n:
    let c = content[i]
    case state
    of ssCode:
      if c == '#':
        if i + 1 < n and content[i + 1] == '[':
          state = ssBlockComment
          depth = 1
          inc i, 2
        else:
          state = ssLineComment
          inc i
      elif c == '"':
        if i + 2 < n and content[i + 1] == '"' and content[i + 2] == '"':
          state = ssTripleStr
          inc i, 3
        else:
          state = ssStr
          inc i
      elif c == '\'' and not suffixQuoteAt(content, i):
        state = ssCharLit
        inc i
      elif c == 's' and i + StaticReadCall.len <= n and
          content[i ..< i + StaticReadCall.len] == StaticReadCall and
          (i == 0 or content[i - 1] notin {'a'..'z', 'A'..'Z', '0'..'9', '_'}):
        var j = i + StaticReadCall.len
        var arg = ""
        var inner = 0     # 0 code, 1 string, 2 char literal
        var balance = 1
        while j < n and balance > 0:
          let d = content[j]
          case inner
          of 0:
            if d == '"':
              inner = 1
              arg.add(d)
              inc j
            elif d == '\'' and not suffixQuoteAt(content, j):
              inner = 2
              arg.add(d)
              inc j
            elif d == '(':
              inc balance
              arg.add(d)
              inc j
            elif d == ')':
              dec balance
              if balance > 0:
                arg.add(d)
              inc j
            else:
              arg.add(d)
              inc j
          of 1:
            if d == '\\' and j + 1 < n:
              arg.add(d)
              arg.add(content[j + 1])
              inc j, 2
            elif d == '"':
              inner = 0
              arg.add(d)
              inc j
            else:
              arg.add(d)
              inc j
          else:
            if d == '\\' and j + 1 < n:
              arg.add(d)
              arg.add(content[j + 1])
              inc j, 2
            elif d == '\'':
              inner = 0
              arg.add(d)
              inc j
            else:
              arg.add(d)
              inc j
        result.add(arg)
        i = j
      else:
        inc i
    of ssLineComment:
      if c == '\n':
        state = ssCode
      inc i
    of ssBlockComment:
      if c == '#' and i + 1 < n and content[i + 1] == '[':
        inc depth
        inc i, 2
      elif c == ']' and i + 1 < n and content[i + 1] == '#':
        dec depth
        inc i, 2
        if depth == 0:
          state = ssCode
      else:
        inc i
    of ssStr:
      if c == '\\' and i + 1 < n:
        inc i, 2
      elif c == '"':
        state = ssCode
        inc i
      else:
        inc i
    of ssTripleStr:
      if c == '"' and i + 2 < n and content[i + 1] == '"' and content[i + 2] == '"':
        state = ssCode
        inc i, 3
      else:
        inc i
    of ssCharLit:
      if c == '\\' and i + 1 < n:
        inc i, 2
      elif c == '\'':
        state = ssCode
        inc i
      else:
        inc i

proc plainStringLit(arg: string): string =
  ## The literal content when the argument is exactly one quoted string
  ## literal (no concatenation, no escapes), else "".
  let t = arg.strip()
  if t.len >= 2 and t[0] == '"' and t[^1] == '"':
    let inner = t[1 ..< t.len - 1]
    if inner.contains('"') or inner.contains('\\'):
      return ""
    return inner
  ""

proc resolveLiteralTarget(lit, moduleDir: string; treePaths: seq[string]): string =
  ## Repo-relative target when the literal resolves to a seed tree member,
  ## else "" (lenient skip — an unresolvable literal cannot be asserted).
  var candidates: seq[string] = @[]
  if lit.startsWith("."):
    candidates.add(joinPath(moduleDir, lit).normalizedPath())
  else:
    candidates.add(lit)
    candidates.add(joinPath(moduleDir, lit).normalizedPath())
  for c in candidates:
    for t in treePaths:
      if t == c:
        return t
  ""

proc declaredTarget(t: string): bool =
  for x in ComputedStaticReadTargets:
    if x == t:
      return true
  false

proc declaredSite(s: string): bool =
  for x in ComputedStaticReadSites:
    if x == s:
      return true
  false

# ---------------------------------------------------------------------------
# Suite
# ---------------------------------------------------------------------------

let moduleDir = currentSourcePath().parentDir          # .../tests/unit
let repoRootGuess =
  if moduleDir.isAbsolute:
    moduleDir.parentDir.parentDir
  else:
    moduleDir.parentDir.parentDir
let repoRoot =
  if repoRootGuess.len == 0:
    getCurrentDir()
  elif repoRootGuess.isAbsolute:
    repoRootGuess
  else:
    getCurrentDir() / repoRootGuess.normalizedPath()

if not fileExists(repoRoot / "axiom.nimble"):
  echo "FAIL: the test must run against the Axiom repository root " &
    "(make test-fast-one from the repo root); resolved: " & repoRoot
  inc failures

var seed: Seed
var seedReady = false

if findExe("git").len == 0 or findExe("tar").len == 0:
  skip("T1..T9", "git/tar unavailable — the derivation needs a real git object store")
else:
  let built = buildSeed(repoRoot)
  if built.isErr:
    inc failures
    echo "  FAIL: seed construction: " & built.error
  else:
    seed = built.get
    seedReady = true

if seedReady:
  block:
    let W = judgmentWitnessPaths(jsS1aGolden)

    # ------------------------------------------------------------------
    echo "T1 — determinism, independent re-derivation, partition coverage"
    let d1 = deriveSemanticSet(seed.dir, seed.tree, W)
    let d2 = deriveSemanticSet(seed.dir, seed.tree, W)
    expect(d1.isOk and d2.isOk, "the derivation succeeds over the seed tree")
    if d1.isOk and d2.isOk:
      expect(d1.get == d2.get,
        "identical inputs derive the identical outcome (determinism)")
      expect(isHexLen(d1.get.semanticDigest, 64),
        "the semantic digest is 64 lowercase hex")
      expect(d1.get.probeTreeOid == seed.tree,
        "the derivation records the probe anchor (out-of-key)")
      expect(d1.get.universeCount == d1.get.semanticCount + d1.get.excludedCount,
        "the partition covers the universe (S + N == universe)")
      expect(d1.get.excludedCount > 0 and d1.get.semanticCount > 0,
        "both partition sides are non-empty over the seed tree")
    expect(validateExclusionTable() == "",
      "the exclusion + declaration tables are self-consistent")
    let rec = "100644 blob " & sha256Hex("vs2-rec")[0 ..< 40] & "\tdocs/a.md"
    let parsed = parseLsTreeZ(rec & "\0")
    expect(parsed.isOk and parsed.get.len == 1 and
      elementRecord(parsed.get[0]) == rec,
      "a ls-tree record round-trips losslessly (mode+type+oid+path)")
    expect(parseLsTreeZ("100644 blob zz\tx\0").isErr,
      "a non-hex ls-tree oid is refused (fail-closed)")
    let indep = independentDigest(seed.dir, seed.tree)
    expect(indep.isOk, "the independent re-derivation lists the universe")
    if indep.isOk and d1.isOk:
      expect(indep.get.digest == d1.get.semanticDigest,
        "the digest matches an independent ls-tree→classify→sort→sha256 pipeline")
      expect(indep.get.universe == d1.get.universeCount and
        indep.get.semantic == d1.get.semanticCount and
        indep.get.excluded == d1.get.excludedCount,
        "the partition counts match the independent pipeline")
    let baseDigest =
      if d1.isOk: d1.get.semanticDigest
      else: ""

    # ------------------------------------------------------------------
    echo "T2 — p2: an excluded-class byte change advances the tree, not the key"
    let m2 = commitAppend(seed, "docs/evidence/go_critical_test_cost_2026-10-08.md",
      "\n<!-- vs2 p2 probe: excluded-class byte change -->\n")
    expect(m2.isOk, "the excluded-class mutation commits")
    if m2.isOk:
      expect(m2.get != seed.tree, "the tree OID advances")
      seed.tree = m2.get
      let after = deriveSemanticSet(seed.dir, seed.tree, W)
      expect(after.isOk, "the derivation succeeds over the mutated tree")
      if after.isOk:
        expect(after.get.semanticDigest == baseDigest,
          "an excluded-class byte change does NOT advance the digest (p2)")

    # ------------------------------------------------------------------
    echo "T3 — normative face mutation (docs/spec) advances the digest"
    let m3 = commitAppend(seed, "docs/spec/test_judgment_cas_contract.md",
      "\n<!-- vs2 T3 normative mutation -->\n")
    expect(m3.isOk, "the docs/spec mutation commits")
    if m3.isOk:
      seed.tree = m3.get
      let after = deriveSemanticSet(seed.dir, seed.tree, W)
      expect(after.isOk, "the derivation succeeds over the mutated tree")
      if after.isOk:
        expect(after.get.semanticDigest != baseDigest,
          "a normative-carve-out byte change advances the digest")

    # ------------------------------------------------------------------
    echo "T4 — computed staticRead target mutations advance the digest (k12)"
    let m4a = commitAppend(seed, "config/templates/good_plan.md",
      "\n<!-- vs2 T4 computed-target mutation -->\n")
    expect(m4a.isOk, "the config/templates mutation commits")
    if m4a.isOk:
      seed.tree = m4a.get
      let after = deriveSemanticSet(seed.dir, seed.tree, W)
      expect(after.isOk, "the derivation succeeds over the mutated tree")
      if after.isOk:
        expect(after.get.semanticDigest != baseDigest,
          "a computed staticRead target change (config/templates) advances the digest")
    let m4b = commitAppend(seed, "config/policy/merge_admission.json", "\n")
    expect(m4b.isOk, "the config/policy mutation commits")
    if m4b.isOk:
      seed.tree = m4b.get
      let after = deriveSemanticSet(seed.dir, seed.tree, W)
      expect(after.isOk, "the derivation succeeds over the mutated tree")
      if after.isOk:
        expect(after.get.semanticDigest != baseDigest,
          "a policy-face byte change (config/policy) advances the digest")

    # ------------------------------------------------------------------
    echo "T7 — data/ is dual-class: every data/*.json advances the digest (key moves → MISS)"
    ## Verified nuance for the redecision 2026-10-18 test matrix (case 3) —
    ## measured correction of the report's phrasing: NO data/*.json is in the
    ## exclusion table N (NoEffectPrefixRules covers .github/.githooks/
    ## .opencode/.axiom/.config/.cursorrules + license/copying/readme — no
    ## data face). The 6 data files (command_policy·debt_budgets·
    ## feature_manifest·i18n/ko·policy_manifest·stateless_whitelist —
    ## semantic_set_derivation.nim ComputedStaticReadTargets) are the k12
    ## DECLARED compile-input face, not exclusions. Both classes are semantic
    ## members: a byte change in EITHER advances the digest → the judgment key
    ## moves → MISS (a fresh EXECUTED, never a reuse across the mutation).
    let afterT4 = deriveSemanticSet(seed.dir, seed.tree, W)
    expect(afterT4.isOk, "the pre-T7 derivation succeeds")
    if afterT4.isOk:
      let curDigest = afterT4.get.semanticDigest
      # (a) a DECLARED computed staticRead target data file:
      #     data/command_policy.json ∈ ComputedStaticReadTargets (k12 face)
      expect(ComputedStaticReadTargets.contains("data/command_policy.json") and
        not ComputedStaticReadTargets.contains("data/baseline.json"),
        "the k12 declaration face distinguishes command_policy.json from baseline.json (compile-input declaration, not exclusion)")
      let m7a = commitAppend(seed, "data/command_policy.json", "\n")
      expect(m7a.isOk, "the declared staticRead data file mutation commits")
      if m7a.isOk:
        expect(m7a.get != seed.tree, "the tree OID advances")
        seed.tree = m7a.get
        let after = deriveSemanticSet(seed.dir, seed.tree, W)
        expect(after.isOk, "the derivation succeeds over the declared-target data mutation")
        if after.isOk:
          expect(after.get.semanticDigest != curDigest,
            "a declared computed-staticRead data/*.json byte change ADVANCES the digest (compile-input member — T4's class, not excluded)")
      # (b) a PLAIN semantic data file: data/baseline.json — no declaration,
      #     not excluded: default-include member of S
      let m7b = commitAppend(seed, "data/baseline.json", "\n")
      expect(m7b.isOk, "the plain semantic data file mutation commits")
      if m7b.isOk:
        seed.tree = m7b.get
        let after = deriveSemanticSet(seed.dir, seed.tree, W)
        expect(after.isOk, "the derivation succeeds over the plain data mutation")
        if after.isOk:
          expect(after.get.semanticDigest != curDigest,
            "a plain data/*.json byte change advances the digest (key moves → MISS, redecision 2026-10-18 matrix case 3)")
      # neither class reaches N: no data/*.json is a certified-no-effect path
      expect(not isCertifiedNoEffectPath("data/command_policy.json") and
        not isCertifiedNoEffectPath("data/baseline.json"),
        "no data/*.json is in the exclusion table N (the report's 'excluded' phrasing corrected by measurement)")

    # ------------------------------------------------------------------
    echo "T5 — fail-closed: probe resolution, excluded witness, missing witness"
    let zeroOid = "0000000000000000000000000000000000000000"
    expectErr("a 40-zero probe OID is refused (p4 — 검증 불가 → EXECUTED 폴백)",
      deriveSemanticSet(seed.dir, zeroOid, W))
    expectErr("a non-hex probe is refused (p1)",
      deriveSemanticSet(seed.dir, "not-a-tree-oid", W))
    let p1ok = probeTreeResolvable(seed.dir, seed.tree)
    expect(p1ok.isOk and p1ok.get,
      "the real probe tree resolves in the seed object store (p1)")
    expectErr("the 40-zero probe does not resolve (p1)",
      probeTreeResolvable(seed.dir, zeroOid))
    let uni = listTreeUniverse(seed.dir, seed.tree)
    var excludedPath = ""
    if uni.isOk:
      for e in uni.get:
        if classifyPath(e.path) == "excluded":
          excludedPath = e.path
          break
    expect(excludedPath.len > 0, "the universe contains an excluded-class path")
    if excludedPath.len > 0:
      var wExcl = W
      wExcl.add(excludedPath)
      expectErr(
        "an excluded witness refuses the derivation (W ∩ N = ∅) — '" &
        excludedPath & "'",
        deriveSemanticSet(seed.dir, seed.tree, wExcl), "excluded")
    var removed = false
    try:
      if fileExists(seed.dir / "nimble.lock"):
        removeFile(seed.dir / "nimble.lock")
        removed = true
    except CatchableError:
      discard # axiom:best-effort(removal failure is reported by the expect() guard below — never silent)
    expect(removed, "nimble.lock (recipe ⑦) removed from the seed")
    if removed:
      let m5 = commitAll(seed.dir, "vs2-T5-witness-removal")
      expect(m5.isOk, "the witness removal commits")
      if m5.isOk:
        seed.tree = m5.get
        expectErr("a missing known input refuses the derivation (W ⊆ S)",
          deriveSemanticSet(seed.dir, seed.tree, W),
          "missing from the tested tree")

    # ------------------------------------------------------------------
    echo "T6 — k12 drift guard: the tree's staticRead population is declared"
    block:
      var nimFiles: seq[string] = @[]
      proc walkNimFiles(dir: string) =
        for entry in walkDir(dir):
          case entry.kind
          of pcFile:
            if entry.path.endsWith(".nim"):
              nimFiles.add(entry.path)
          of pcDir:
            walkNimFiles(entry.path)
          else:
            discard
      walkNimFiles(seed.dir)
      var treePaths: seq[string] = @[]
      let uniT6 = listTreeUniverse(seed.dir, seed.tree)
      if uniT6.isOk:
        for e in uniT6.get:
          treePaths.add(e.path)
      expect(uniT6.isOk and treePaths.len > 0,
        "the seed universe is listed for the census")
      var literalChecked = 0
      var siteChecked = 0
      var lenientSkips = 0
      for f in nimFiles:
        let rel = f.substr(seed.dir.len + 1).replace('\\', '/')
        let modDir = rel.parentDir
        let content =
          try: readFile(f)
          except CatchableError: ""
        for arg in findStaticReadCalls(content):
          let lit = plainStringLit(arg)
          if lit.len > 0:
            let target = resolveLiteralTarget(lit, modDir, treePaths)
            if target.len == 0:
              inc lenientSkips
            else:
              inc literalChecked
              expect(declaredTarget(target),
                "literal staticRead target is declared: " & target &
                " (at " & rel & ")")
          else:
            inc siteChecked
            expect(declaredSite(rel),
              "computed staticRead site is declared: " & rel)
      expect(nimFiles.len > 1000,
        "the census scanned a full source tree (got " & $nimFiles.len & " .nim files)")
      echo "    census: " & $nimFiles.len & " files, " & $literalChecked &
        " literal target(s), " & $siteChecked & " computed site(s), " &
        $lenientSkips & " unresolvable literal skip(s)"

    # ------------------------------------------------------------------
    echo "T8 — normative-spelling drift guard: no case-variant normative " &
      "path in the tree"
    block:
      func normativeSpellingViolation(paths: openArray[string]): string =
        ## "" = clean; otherwise the case-variant normative spellings found.
        ## The classification authority matches normative prefixes/exact
        ## paths case-SENSITIVELY (normativeGround: startsWith / ==) while
        ## the extension (.md) and root-name exclusions are case-INSENSITIVE
        ## (toLowerAscii). A case-variant normative path (e.g. DOCS/agents/
        ## x.md) would NOT be recognized as normative, would fall into the
        ## .md N-class, and a real normative-face change would NOT advance
        ## the judgment key — fail-closed drift guard: the tree may carry
        ## canonical spellings only.
        var violations: seq[string] = @[]
        for p in paths:
          let lo = p.toLowerAscii()
          for pfx in NormativePrefixes:
            if lo.startsWith(pfx.toLowerAscii()) and not p.startsWith(pfx):
              violations.add(p & " (case-matches prefix '" & pfx & "')")
          for ex in NormativeExactPaths:
            if lo == ex.toLowerAscii() and p != ex:
              violations.add(p & " (case-matches exact path '" & ex & "')")
        violations.join("; ")
      var spellPaths: seq[string] = @[]
      let uniT8 = listTreeUniverse(seed.dir, seed.tree)
      if uniT8.isOk:
        for e in uniT8.get:
          spellPaths.add(e.path)
      expect(uniT8.isOk and spellPaths.len > 0,
        "the seed universe is listed for the spelling census")
      spellPaths.sort()
      let spelling = normativeSpellingViolation(spellPaths)
      expect(spelling.len == 0,
        "every normative-class tree path is canonically spelled (" &
        $spellPaths.len & " paths censused)" &
        (if spelling.len > 0: " — violations: " & spelling else: ""))
      # failure-mode demonstration (synthetic inputs — no repo mutation):
      # the detector fires on case-variant normative spellings …
      let demo = normativeSpellingViolation(@[
        "DOCS/agents/core_rules.md", "docs/Spec/contract.md", "agents.md",
        "docs/debt_registry.md", "nimble.LOCK"])
      expect(demo.len > 0 and demo.contains("case-matches"),
        "the guard FIRES on synthetic case-variant normative spellings — " &
        demo)
      expect(demo.contains("DOCS/agents/core_rules.md") and
        demo.contains("docs/Spec/contract.md") and
        demo.contains("agents.md") and
        demo.contains("docs/debt_registry.md") and
        demo.contains("nimble.LOCK"),
        "each synthetic case-variant (prefix and exact faces) is detected")
      # … and stays silent on canonical spellings + ordinary N-class paths
      expect(normativeSpellingViolation(@[
        "docs/spec/c.md", "docs/agents/r.md", "config/policy/p.json",
        "config/templates/t.md", "AGENTS.md", "docs/DEBT_REGISTRY.md",
        "nimble.lock", "docs/evidence/e.md", "README.md"]) == "",
        "canonical spellings and ordinary paths raise no violation")

    # ------------------------------------------------------------------
    echo "T9 — dual-table lockstep: the N table's pattern sets equal " &
      "proof_unit_catalog's certified no-effect tables"
    block:
      proc lockstepDrift(prefixes, extensions, roots: openArray[string]): string =
        ## "" = the judgment-key N tables in verification/
        ## semantic_set_derivation.nim (NoEffectPrefixRules /
        ## NoEffectExtensionRules / NoEffectRootNameRules) carry the SAME
        ## pattern SETS as proof_unit_catalog's CertifiedNoEffect{Prefixes,
        ## Extensions,RootNames}; otherwise the first divergence. SET (not
        ## sequence) equality is the contract: both consumers classify with
        ## any-rule-wins loops, so element order has no semantic effect —
        ## the live tables already differ in sequence (.editorconfig/.envrc
        ## transposed, audit F2 follow-up measurement). The N table computes
        ## the judgment key's semantic set while proof_unit_catalog drives
        ## the CI selector (tools/ci/impact_closure_selector.nim) — a
        ## one-sided CONTENT edit of either table silently diverges
        ## key-advance from CI selection, so the two must move in lockstep.
        ## Drift detector only: the single-table consolidation is a
        ## separate structural change.
        proc axisDrift(name: string; want, got: seq[string]): string =
          if want.len != got.len:
            return name & " table SIZE drift: semantic_set_derivation=" &
              $want.len & " proof_unit_catalog=" & $got.len
          for i in 0 ..< want.len:
            if want[i] != got[i]:
              return name & " pattern drift: '" & want[i] & "' != '" &
                got[i] & "'"
          ""
        var wantP: seq[string] = @[]
        for r in NoEffectPrefixRules: wantP.add(r.pattern)
        var wantE: seq[string] = @[]
        for r in NoEffectExtensionRules: wantE.add(r.pattern)
        var wantR: seq[string] = @[]
        for r in NoEffectRootNameRules: wantR.add(r.pattern)
        var gotP: seq[string] = @[]
        for p in prefixes: gotP.add(p)
        var gotE: seq[string] = @[]
        for p in extensions: gotE.add(p)
        var gotR: seq[string] = @[]
        for p in roots: gotR.add(p)
        wantP.sort(); gotP.sort()
        wantE.sort(); gotE.sort()
        wantR.sort(); gotR.sort()
        let pDrift = axisDrift("prefix", wantP, gotP)
        if pDrift.len > 0: return pDrift
        let eDrift = axisDrift("extension", wantE, gotE)
        if eDrift.len > 0: return eDrift
        axisDrift("root-name", wantR, gotR)
      let live = lockstepDrift(CertifiedNoEffectPrefixes,
        CertifiedNoEffectExtensions, CertifiedNoEffectRootNames)
      expect(live.len == 0,
        "the two certified no-effect tables carry equal pattern sets " &
        "(lockstep)" & (if live.len > 0: " — drift: " & live else: ""))
      echo "    lockstep: " & $NoEffectPrefixRules.len & " prefixes, " &
        $NoEffectExtensionRules.len & " extensions, " &
        $NoEffectRootNameRules.len & " root names, set-equal on both faces"
      # failure-mode demonstration (synthetic copies — no repo mutation):
      # the detector fires on size and content divergence …
      var synthSize = CertifiedNoEffectPrefixes
      synthSize.setLen(synthSize.len - 1)
      expect(lockstepDrift(synthSize, CertifiedNoEffectExtensions,
          CertifiedNoEffectRootNames).contains("prefix table SIZE drift"),
        "the detector FIRES on a table-size drift")
      var synthPattern = CertifiedNoEffectExtensions
      synthPattern[0] = ".markdown"
      expect(lockstepDrift(CertifiedNoEffectPrefixes, synthPattern,
          CertifiedNoEffectRootNames).contains("extension pattern drift"),
        "the detector FIRES on a one-element pattern edit")
      # … and, by contract, an order-only divergence is NOT a violation:
      # both predicates are any-rule-wins loops, so element order is
      # semantically inert (the live tables are already transposed at
      # .editorconfig/.envrc — measured, not assumed)
      var synthOrder = CertifiedNoEffectExtensions
      swap(synthOrder[0], synthOrder[1])
      expect(lockstepDrift(CertifiedNoEffectPrefixes, synthOrder,
          CertifiedNoEffectRootNames) == "",
        "an order-only divergence is not a violation (any-rule-wins loops)")

  # cleanup
  try:
    removeDir(seed.dir)
    removeFile(seed.tarPath)
  except CatchableError:
    discard # axiom:best-effort(temp seed cleanup after all assertions — a leftover temp dir is not a test outcome)

echo ""
if failures == 0:
  echo "=== All judgment semantic-set derivation tests PASSED ==="
else:
  echo "=== " & $failures &
    " judgment semantic-set derivation test assertion(s) FAILED ==="
  quit(1)
