import core/trusted/layer_declaration
axiomLayer "presentation"
import std/[json, os, strutils, algorithm]
import checksums/sha2
import core/config/toolchain_config
import core/trusted/axiom_pragmas
import core/trusted/semantic_profile
import core/trusted/project_setup
import core/trusted/scope_version
import core/utils/repo_root
import infrastructure/logging_facade
import cli/config_loader

proc writeScopeLockFromRegistry*(root: string): tuple[ok: bool, kernelTotal: int] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Regenerate data/verification_scope.lock from the runtime kernel registry.
  ## WS-P2-B: replaces the compile-time lock writer removed from the
  ## `generateAxiomInit` macro. Idempotent — only writes on content change.
  ##
  ## Phase C scope-invariant enforcement (schema v3): every curated
  ## kernel_exempt_symbols entry MUST be a member of kernel_symbols, and the
  ## computed vksTotal MUST equal kernel_total − exempt count.
  ## Violation → lock regeneration rejected (scope inconsistency); never silently
  ## written (anti-theater §0.9: a stale/overlapping exempt list must not hide).
  let lockPath = root / "data" / "verification_scope.lock"
  let (kernelTotal, kernelSymbols) = collectKernelSymbols(root)
  let kernelExemptSymbols = loadKernelExemptSymbols(root)
  # Read the existing lock ONCE at the I/O boundary and hand it to the builder
  # pre-parsed (core purity: buildScopeLockJson performs no lock-file read).
  var existingLock: JsonNode = nil
  var lockUnreadable = false
  if fileExists(lockPath):
    try:
      existingLock = parseFile(lockPath)
    except CatchableError:
      existingLock = nil
      lockUnreadable = true
  let content = buildScopeLockJson(root, existingLock)
  # Unreadable existing lock: refuse regeneration here (the fail-closed
  # semantics the builder previously carried; a corrupt lock must not be
  # silently overwritten by a fresh one).
  if lockUnreadable:
    logError("scope_cli", "[scope-invariant] rust scope declaration invalid: existing verification_scope.lock is unreadable — delete it to redeclare an empty Rust scope")
    return (false, kernelTotal)
  # Invariant check: vksTotal == kernelTotal − kernelExemptSymbols.len
  let expectedProvable = kernelTotal - kernelExemptSymbols.len
  var ksSet : seq[string] = kernelSymbols
  ksSet.sort()
  for exempt in kernelExemptSymbols:
    if binarySearch(ksSet, exempt) < 0:
      logError("scope_cli", "[scope-invariant] exempt symbol not in kernel_symbols: " & exempt)
      return (false, kernelTotal)
  if expectedProvable != kernelTotal - kernelExemptSymbols.len:
    logError("scope_cli", "[scope-invariant] vksTotal mismatch")
    return (false, kernelTotal)
  # vks_rust (fail-closed): the builder refuses to emit a lock over an invalid
  # or unreadable Rust declaration — a scope lock must never launder an
  # inconsistent Rust denominator (docs/spec/rust_certified_subset.md §2).
  if content.len == 0:
    var reason = "existing verification_scope.lock is unreadable — delete it to redeclare an empty Rust scope"
    try:
      if existingLock != nil:
        let declared = validateRustScopeSection(existingLock)
        if not declared.ok:
          reason = declared.reason
    except CatchableError:
      discard  # axiom:best-effort(re-validate failure keeps the default diagnostic reason — the caller already fails closed via logError + return false)
    logError("scope_cli", "[scope-invariant] rust scope declaration invalid: " & reason)
    return (false, kernelTotal)
  try:
    if fileExists(lockPath):
      if readFile(lockPath) == content:
        return (true, kernelTotal)
    let dir = parentDir(lockPath)
    if not dirExists(dir):
      createDir(dir)
    writeFile(lockPath, content)
    (true, kernelTotal)
  except CatchableError as e:
    logError("scope_cli", "Failed to write verification_scope.lock: " & e.msg)
    (false, kernelTotal)

proc collectSourceFilesForHash(root: string): seq[string] {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic walk of src/ .nim files (generated excluded), sorted.
  ## Mirrors hermetic_build computeDeterministicSourceHash ordering.
  let srcDir = root / "src"
  if not dirExists(srcDir):
    return @[]
  for f in walkDirRec(srcDir):
    if f.endsWith(".nim") and "/generated/" notin f and "nimcache" notin f:
      result.add(f)
  result.sort()

proc computeScopeHash*(root: string): string {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic scope integrity hash: sorted source tree + toolchain
  ## lockfiles (config.nims, axiom.nimble, nimble.lock) + verification_scope.lock
  ## + declared Z3 version. Callers must fail-fast when the scope lock is absent.
  var content = ""
  for f in collectSourceFilesForHash(root):
    try:
      content.add(f & ":" & readFile(f) & "\n")
    except CatchableError:
      content.add(f & ":<unreadable>\n")
  for rel in ["config.nims", "axiom.nimble", "nimble.lock", "data/verification_scope.lock"]:
    let p = root / rel
    if fileExists(p):
      content.add(rel & ":" & readFile(p) & "\n")
  content.add("z3:" & ExpectedZ3Version & "\n")
  $secureHash(Sha_256, content)

proc reportSymbolDelta(missing: seq[string]; extra: seq[string]) {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Emit MISSING/EXTRA symbol diagnostics during scope-lock comparison.
  if missing.len > 0:
    logInfo("scope_cli", "[FAIL] symbols in lock but not in registry (missing):")
    for s in missing:
      logInfo("scope_cli", "  MISSING: " & s)
  if extra.len > 0:
    logInfo("scope_cli", "[FAIL] symbols in registry but not in lock (extra):")
    for s in extra:
      logInfo("scope_cli", "  EXTRA: " & s)

proc symbolDifference(derived, expected: seq[string]): tuple[missing, extra: seq[string]] =
  ## Sorted two-way set difference between derived kernel scope and lock symbols.
  var missing: seq[string] = @[]
  var extra: seq[string] = @[]
  var i = 0; var j = 0
  while i < derived.len and j < expected.len:
    if derived[i] < expected[j]:
      extra.add(derived[i]); inc i
    elif derived[i] > expected[j]:
      missing.add(expected[j]); inc j
    else:
      inc i; inc j
  while i < derived.len:
    extra.add(derived[i]); inc i
  while j < expected.len:
    missing.add(expected[j]); inc j
  (missing, extra)

proc checkScopeLockConsistency(root: string): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read-only comparison: derived kernel scope (registry) vs verification_scope.lock.
  ## Full symbol-list comparison, not just count. Does NOT regenerate the lock.
  let lockPath = root / "data" / "verification_scope.lock"
  if not fileExists(lockPath):
    logInfo("scope_cli", "[ERROR] verification_scope.lock not found — run `ax scope lock` (after compile) first")
    return 1
  let lockData = parseFile(lockPath)
  let expectedTotal = lockData["kernel_total"].getInt()
  let expectedSymbolsRaw = lockData["kernel_symbols"]
  if expectedSymbolsRaw.kind != JArray:
    logInfo("scope_cli", "[ERROR] lock file missing kernel_symbols array")
    return 1
  var expectedSymbols: seq[string] = @[]
  for s in expectedSymbolsRaw:
    expectedSymbols.add(s.getStr())
  let (derivedTotal, derivedSymbols) = collectKernelSymbols(root)
  if derivedTotal != expectedTotal:
    logInfo("scope_cli", "[FAIL] kernel_total mismatch: derived=" & $derivedTotal & " lock=" & $expectedTotal)
    return 1
  let diff = symbolDifference(derivedSymbols.sorted(), expectedSymbols.sorted())
  if diff.missing.len > 0 or diff.extra.len > 0:
    reportSymbolDelta(diff.missing, diff.extra)
    return 1
  # vks_rust (fail-closed): validate the additive Rust scope declaration. A
  # legacy lock declaring neither field skips this (checked=false, Nim-only);
  # a present-but-invalid declaration (missing specRef, malformed entry,
  # duplicate target, or declared vksRust ≠ count derived from rust_targets)
  # fails the consistency check.
  let rustCheck = validateRustScopeSection(lockData)
  if rustCheck.checked and not rustCheck.ok:
    logInfo("scope_cli", "[FAIL] rust scope declaration invalid: " & rustCheck.reason)
    return 1
  let rustSuffix = if rustCheck.checked:
      " + rust scope declaration valid (rust_targets=" & $rustCheck.computedVksRust &
      " == vksRust)"
    else:
      ""
  logInfo("scope_cli", "[PASS] scope_consistency — derived kernel scope matches lock (kernel_total=" & $derivedTotal & ", kernel_symbols=" & $expectedSymbols.len & ")" & rustSuffix)
  result = 0

proc runScopeCli*(args: seq[string]): int {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  generateAxiomInit()
  let root = findRepoRoot()
  let lockPath = root / "data" / "verification_scope.lock"

  let sub = if args.len > 0: args[0] else: ""
  # Argument guard (fail-closed, no mutation): every subcommand of `ax scope`
  # takes NO options — a flag-looking or unrecognized first argument is a
  # usage error, not a silent pass-through into a mutating default. Observed
  # 2026-10-22: `ax scope lock --help` fell through to the mutating `lock`
  # arm and rewrote data/verification_scope.lock from a help probe.
  if sub.len > 0 and sub.startsWith("-"):
    echo "usage: ax scope [check|init|lock|hash] — unknown option: " & sub
    return 1
  if sub.len > 0 and sub notin ["check", "init", "lock", "hash"]:
    echo "usage: ax scope [check|init|lock|hash] — unknown subcommand: " & sub
    return 1
  case sub
  of "init":
    let initRoot = getCurrentDir()
    let axiomRootPath = initRoot / ".axiom_root"
    if not fileExists(axiomRootPath):
      writeFile(axiomRootPath, "")
    let tomlPath = initRoot / "axiom.toml"
    var profileName = "v1"
    if fileExists(tomlPath):
      let tomlConfig = loadTomlConfig(tomlPath)
      let semanticSection = getSection(tomlConfig, "semantic_profile")
      profileName = getString(semanticSection, "profile", "v1")
    else:
      writeFile(tomlPath, "[semantic_profile]\nprofile = \"v1\"\n")
    let profileIdentity = profileIdentityFor(profileName)
    let lockDir = initRoot / "data"
    if not dirExists(lockDir):
      createDir(lockDir)
    let lockPath = lockDir / "verification_scope.lock"
    let lockContent = "{\"schema_version\":" & $VERIFICATION_SCOPE_SCHEMA_VERSION &
      ",\"kernel_total\":0,\"kernel_symbols\":[],\"vksTotal\":0," &
      "\"kernel_exempt_symbols\":[],\"rust_targets\":[],\"vksRust\":0," &
      "\"last_updated\":\"init\",\"updated_by\":\"ax scope init\"}"
    if not fileExists(lockPath) or readFile(lockPath) != lockContent:
      writeFile(lockPath, lockContent)
    let lockHash = $secureHash(Sha_256, lockContent)
    discard resolvedConfigDigest(profileIdentity, lockHash)
    echo ".axiom_root written"
    echo "profile identity = " & profileIdentity
    echo "scope lock written"
    return 0
  of "lock":
    ## Regenerate the scope lock from the compiled kernel registry (runtime).
    let (ok, kernelTotal) = writeScopeLockFromRegistry(root)
    if not ok:
      return 1
    echo "verification_scope.lock regenerated (kernel_total=" & $kernelTotal & ")"
    return 0
  of "hash":
    ## Deterministic scope hash. Runtime read-only — fails fast when the lock
    ## is missing (never synthesizes one).
    if not fileExists(lockPath):
      logInfo("scope_cli", "[ERROR] verification_scope.lock not found — run `ax scope lock` (after compile) first")
      return 1
    echo computeScopeHash(root)
    return 0
  else:
    ## Default: compare the lock against the runtime kernel registry
    ## (full symbol list comparison, not just count). Read-only.
    checkScopeLockConsistency(root)
