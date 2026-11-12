# nim-check: skip (include fragment — not an independent translation unit)
axiomLayer "trusted.core.pragmas-procs"

import core/macros/best_effort
import core/trusted/scope_version

import std/json

func isKernelScopeMember*(x: RuntimeAxiomEntry): bool {.axiomDecision(
  id = "DECISION-0410",
  reason = "Single SSOT predicate for kernel-scope membership — encapsulates the 4-condition filter (isKernel, non-opaque IR, Pure effect, non-BMC-skippable) used by countKernelFunctions and collectKernelSymbols",
  adr = "docs/spec/verification_density.md",
  introduced = "v35").} =
  x.isKernel and x.irSerialized != "__opaque__" and x.effectKind == Pure and not x.bmcSkippable

proc countKernelFunctions*(): int {.raises: [].} =
  for entry in runtimeAxiomRegistry:
    if entry.isKernelScopeMember:
      inc result

proc registerAxiom*(name, irStr, smtSrc, leanSrc, srcPath: string; isKern: bool = true; irHash: string = ""; effectKind: AxiomEffectKind = Pure; bmcSkippable: bool = false; origin: AxiomEntryOrigin = soAxiomSupport) {.raises: [].} =
  runtimeAxiomRegistry.add(RuntimeAxiomEntry(
    name: name, irSerialized: irStr,
    smtSource: smtSrc, leanSource: leanSrc,
    sourcePath: srcPath, isKernel: isKern, irHash: irHash,
    effectKind: effectKind, bmcSkippable: bmcSkippable,
    origin: origin))

proc lookupAxiomIR*(name: string): Option[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for entry in runtimeAxiomRegistry:
    if entry.name == name:
      return some(entry.irSerialized)
  none(string)

proc lookupAxiomLeanSource*(name: string): Option[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  for entry in runtimeAxiomRegistry:
    if entry.name == name and entry.leanSource.len > 0:
      return some(entry.leanSource)
  none(string)

proc initRegistryLookup*() {.axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  registryLookup = initTable[string, RuntimeAxiomEntry](runtimeAxiomRegistry.len)
  for entry in runtimeAxiomRegistry:
    registryLookup[entry.name] = entry

# ─── WS-P2-B: Kernel scope lock derivation (runtime) ─────────────────────────
# Replaces the compile-time `writeFile` previously performed by the
# `generateAxiomInit` macro (Hermetic violation). The kernel scope JSON is now
# derived deterministically at runtime from `runtimeAxiomRegistry` — the same
# data the macro previously serialized — and written by `ax scope lock`.

func scopeJsonEscape(s: string): string {.raises: [].} =
  ## Minimal JSON string escaping for scope symbol names (runtime twin of the
  ## compile-time jsonEscape in axiom_pragmas_macros.nim).
  result = "\""
  for c in s:
    case c
    of '"': result.add("\\\"")
    of '\\': result.add("\\\\")
    of '\n': result.add("\\n")
    of '\r': result.add("\\r")
    of '\t': result.add("\\t")
    else: result.add(c)
  result.add("\"")

proc collectKernelSymbols*(projectRoot: string): tuple[kernelTotal: int, kernelSymbols: seq[string]] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Mirrors the legacy macro kernel-scope filter via isKernelScopeMember predicate.
  var count = 0
  var symbols: seq[string] = @[]
  for entry in runtimeAxiomRegistry:
    if entry.isKernelScopeMember:
      inc count
      var modulePath = entry.sourcePath
      if modulePath.startsWith("src/"):
        discard
      elif modulePath.startsWith("/"):
        try:
          let rel = relativePath(modulePath, projectRoot, '/')
          modulePath = if rel.startsWith("src/"): rel else: ""
        except CatchableError:
          modulePath = ""
      elif modulePath.find('/') >= 0:
        discard
      else:
        modulePath = ""
      if modulePath.len > 0:
        symbols.add(modulePath & "::" & entry.name)
      else:
        symbols.add(entry.name)
  (count, symbols)

proc loadKernelExemptSymbols*(projectRoot: string): seq[string] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""read kernel_exempt_symbols.json — empty exempt set on missing/corrupt file (fail-closed, schema v3)""").} =
  ## Curated proof-exempt kernel symbols (schema v3). Read-only SSOT from
  ## `data/kernel_exempt_symbols.json`; missing/invalid file → empty (no exemptions).
  var exempt: seq[string] = @[]
  let p = projectRoot / "data" / "kernel_exempt_symbols.json"
  if not fileExists(p):
    return exempt
  try:
    let node = parseJson(readFile(p))
    if node.kind == JArray:
      for s in node:
        if s.kind == JString and s.getStr.len > 0:
          exempt.add(s.getStr)
    elif node.kind == JObject:
      let arr = node.getOrDefault("kernel_exempt_symbols")
      if arr.kind == JArray:
        for s in arr:
          if s.kind == JString and s.getStr.len > 0:
            exempt.add(s.getStr)
  except CatchableError:
    discard  # axiom:best-effort(kernel exempt symbols read — empty on missing/corrupt file, fail-closed)
  exempt

# ─── vks_rust — Rust subject scope declaration (schema v3, additive) ─────────
# The Rust counterpart of the Nim kernel denominator (docs/spec/
# rust_certified_subset.md §2): `rust_targets` declares the Rust scope entries
# and `vksRust` the Rust denominator. It is NOT added to the Nim `vksTotal`
# (docs/spec/verification_density.md:168-169) — the two denominators stay
# separate. The declaration lives IN the lock (no separate registry exists for
# Rust in v1) and is carried forward verbatim by the lock builder; the checker
# validates it fail-closed.

const rustTargetFields* = ["commit", "module", "symbol", "signatureHash",
                           "specRef", "conditions"]
  ## Required rust_targets entry fields. A missing field (e.g. specRef) is a
  ## fail-closed schema violation.

type
  RustScopeCheck* = object
    ## Result of validating the rust_targets / vksRust section of a
    ## verification_scope.lock. `checked` is false for a legacy Nim-only lock
    ## declaring neither field — the Nim invariants are unaffected by it.
    checked*: bool
    ok*: bool
    reason*: string
    computedVksRust*: int
      ## Independently derived from the rust_targets ENTRIES themselves
      ## (structural validation walk + uniqueness). The ok verdict requires
      ## computedVksRust == the DECLARED `vksRust` integer — two different
      ## JSON members derived separately, so editing one side without the
      ## other fails closed (a real comparison, not a tautology).

func isLowerHexOfLen(s: string; n: int): bool {.raises: [].} =
  if s.len != n:
    return false
  for c in s:
    if c notin {'0'..'9', 'a'..'f'}:
      return false
  true

func validateRustTargetEntry(entry: JsonNode; idx: int): string {.raises: [].} =
  ## "" when the entry is well-formed; otherwise the fail-closed reason.
  ## All accessors are nil-safe (getOrDefault/getStr) so the verdict is total.
  if entry.kind != JObject:
    return "rust_targets[" & $idx & "] is not an object"
  for field in rustTargetFields:
    if entry.getOrDefault(field).isNil:
      return "rust_targets[" & $idx & "] missing required field: " & field
  for strField in ["commit", "module", "symbol", "signatureHash", "specRef"]:
    let v = entry.getOrDefault(strField)
    if v.kind != JString or v.getStr().len == 0:
      return "rust_targets[" & $idx & "]." & strField & " must be a non-empty string"
  let commit = entry.getOrDefault("commit").getStr()
  if not isLowerHexOfLen(commit, 40) and not isLowerHexOfLen(commit, 64):
    return "rust_targets[" & $idx & "].commit must be 40/64-char lowercase hex (git commit-or-tree)"
  if not isLowerHexOfLen(entry.getOrDefault("signatureHash").getStr(), 64):
    return "rust_targets[" & $idx & "].signatureHash must be 64-char lowercase hex (sha256)"
  let conds = entry.getOrDefault("conditions")
  if conds.kind != JArray:
    return "rust_targets[" & $idx & "].conditions must be an array"
  for i in 0 ..< conds.len:
    if conds[i].kind != JString or conds[i].getStr().len == 0:
      return "rust_targets[" & $idx & "].conditions[" & $i & "] must be a non-empty string"
  ""

func validateRustScopeSection*(lockData: JsonNode): RustScopeCheck {.raises: [].} =
  ## Validate the additive vks_rust section of a verification_scope.lock:
  ## every rust_targets entry must be present and well-formed, (module, symbol)
  ## pairs unique, and the DECLARED `vksRust` integer must equal the count
  ## derived from the entries. A lock with neither field is a legacy Nim-only
  ## lock (checked=false, ok=true). Any violation is fail-closed.
  let hasTargets = not lockData.getOrDefault("rust_targets").isNil
  let hasDeclared = not lockData.getOrDefault("vksRust").isNil
  if not hasTargets and not hasDeclared:
    return RustScopeCheck(checked: false, ok: true, computedVksRust: 0)
  if hasTargets != hasDeclared:
    return RustScopeCheck(checked: true, ok: false, computedVksRust: 0,
      reason: "partial rust scope declaration: rust_targets and vksRust must both be present")
  let targets = lockData.getOrDefault("rust_targets")
  if targets.kind != JArray:
    return RustScopeCheck(checked: true, ok: false,
      reason: "rust_targets must be an array")
  var seen: seq[string] = @[]
  for i in 0 ..< targets.len:
    let reason = validateRustTargetEntry(targets[i], i)
    if reason.len > 0:
      return RustScopeCheck(checked: true, ok: false, reason: reason)
    let key = targets[i].getOrDefault("module").getStr() & "::" &
              targets[i].getOrDefault("symbol").getStr()
    if key in seen:
      return RustScopeCheck(checked: true, ok: false,
        reason: "duplicate rust target: " & key)
    seen.add(key)
  let declared = lockData.getOrDefault("vksRust")
  if declared.kind != JInt or declared.getInt() < 0:
    return RustScopeCheck(checked: true, ok: false, computedVksRust: 0,
      reason: "vksRust must be a non-negative integer")
  let computed = targets.len
  if declared.getInt() != computed:
    return RustScopeCheck(checked: true, ok: false, computedVksRust: computed,
      reason: "vksRust mismatch: declared " & $declared.getInt() &
              " vs computed " & $computed & " from rust_targets")
  RustScopeCheck(checked: true, ok: true, computedVksRust: computed)

func buildRustScopeJson*(targets: JsonNode; vksRust: int): string {.raises: [].} =
  ## Canonical lock members for a VALIDATED rust_targets array: fields are
  ## re-emitted in a fixed order (commit, module, symbol, signatureHash,
  ## specRef, conditions) so the lock bytes stay deterministic regardless of
  ## the declaration's key order. Callers must validateRustScopeSection first.
  var arr = "["
  for i in 0 ..< targets.len:
    if i > 0: arr.add(",")
    let t = targets[i]
    let commit = t.getOrDefault("commit").getStr()
    let module = t.getOrDefault("module").getStr()
    let symbol = t.getOrDefault("symbol").getStr()
    let signatureHash = t.getOrDefault("signatureHash").getStr()
    let specRef = t.getOrDefault("specRef").getStr()
    let conds = t.getOrDefault("conditions")
    arr.add("{\"commit\":" & scopeJsonEscape(commit) &
      ",\"module\":" & scopeJsonEscape(module) &
      ",\"symbol\":" & scopeJsonEscape(symbol) &
      ",\"signatureHash\":" & scopeJsonEscape(signatureHash) &
      ",\"specRef\":" & scopeJsonEscape(specRef) &
      ",\"conditions\":[")
    for j in 0 ..< conds.len:
      if j > 0: arr.add(",")
      arr.add(scopeJsonEscape(conds[j].getStr()))
    arr.add("]}")
  arr.add("]")
  "\"rust_targets\":" & arr & ",\"vksRust\":" & $vksRust

proc buildScopeLockJson*(projectRoot: string; existingLock: JsonNode = nil): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic verification_scope.lock JSON (schema v3, additively extended
  ## with the vks_rust members `rust_targets` + `vksRust`) derived from the
  ## runtime kernel registry. Must be called after `generateAxiomInit()` so the
  ## registry is populated.
  ## The existing-lock Rust declaration is passed in pre-parsed by the caller
  ## (I/O stays at the CLI boundary — core purity: this proc reads no lock file
  ## itself; the only anchored readFile in this file belongs to
  ## loadKernelExemptSymbols). An invalid Rust declaration in `existingLock`
  ## returns "" (regeneration refused) instead of writing a lock that would
  ## launder an inconsistent Rust denominator.
  let kernelExemptSymbols = loadKernelExemptSymbols(projectRoot)
  let (kernelTotal, kernelSymbols) = collectKernelSymbols(projectRoot)
  var rustCheck = RustScopeCheck(checked: false, ok: true, computedVksRust: 0)
  var rustTargets = newJArray()
  if existingLock != nil:
    rustCheck = validateRustScopeSection(existingLock)
    if rustCheck.checked and rustCheck.ok:
      rustTargets = existingLock.getOrDefault("rust_targets")
  if not rustCheck.ok:
    return ""
  var symJson = "["
  for i, s in kernelSymbols:
    if i > 0: symJson.add(",")
    symJson.add(scopeJsonEscape(s))
  symJson.add("]")
  var exemptJson = "["
  for i, s in kernelExemptSymbols:
    if i > 0: exemptJson.add(",")
    exemptJson.add(scopeJsonEscape(s))
  exemptJson.add("]")
  let rustJson = if rustCheck.checked:
      buildRustScopeJson(rustTargets, rustCheck.computedVksRust)
    else:
      "\"rust_targets\":[],\"vksRust\":0"
  "{\"schema_version\":" & $VERIFICATION_SCOPE_SCHEMA_VERSION & ",\"kernel_total\":" & $kernelTotal &
    ",\"kernel_symbols\":" & symJson &
    ",\"vksTotal\":" & $(kernelTotal - kernelExemptSymbols.len) &
    ",\"kernel_exempt_symbols\":" & exemptJson &
    "," & rustJson &
    ",\"last_updated\":\"runtime-auto\",\"updated_by\":\"ax scope lock\"}"
