import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## SOLID queries — Path-Aware DIP and OCP detection.
##
## Split from solid_queries.nim: contains DIP (forbidden concrete calls / pragmas)
## and OCP (registry violation detection).

import std/os
import std/strutils
import std/sets
import std/tables
import core/parsers/safe_parsers
import core/results
import gate/architecture_ast_facts
import core/gate/architecture_policy
import gate/rule_patterns
import core/boundary/file_utils_boundary
import core/trusted/axiom_pragmas

# ---------------------------------------------------------------------------
# Path-Aware DIP — forbidden call pattern loader
# ---------------------------------------------------------------------------

type
  ForbiddenCallPattern* = object
    callee*: string
    callerPattern*: string
    allowedCallers*: seq[string]

  OcpRegistryPolicy* = object
    modules*: seq[string]
    functions*: seq[string]

  OcpOverride* = object
    path*: string
    branchCount*: int
    reason*: string

proc loadForbiddenCallPatterns*(lockPath: string = architecturePolicyPath): seq[ForbiddenCallPattern] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read [forbidden_call_patterns] section from lock file.
  ## Simple string-based parsing to avoid modifying the policy parser.
  if not fileExists(lockPath):
    return @[]
  let content = try: readFileSafe(lockPath) except CatchableError: ""
  if content.len == 0:
    return @[]

  var inSection = false
  for rawLine in content.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.startsWith("[") and trimmed.endsWith("]"):
      let section = trimmed[1 .. ^2].strip()
      inSection = section == "forbidden_call_patterns"
      continue
    if not inSection or trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    # Parse: "callee" = { caller_pattern = "...", allowed_callers = ["...", "..."] }
    let eqIndex = trimmed.find('=')
    if eqIndex < 0:
      continue
    let calleeKey = trimmed[0 ..< eqIndex].strip().strip(chars = {'"'})
    if calleeKey.len == 0:
      continue

    let value = trimmed[eqIndex + 1 .. ^1].strip()
    let patternStart = value.find("caller_pattern = \"")
    let callersStart = value.find("allowed_callers = [")

    var callerPattern = ""
    var allowedCallers: seq[string] = @[]

    if patternStart >= 0:
      let quoteStart = patternStart + 18  # len("caller_pattern = \"")
      let quoteEnd = value.find("\"", quoteStart)
      if quoteEnd >= 0:
        callerPattern = value[quoteStart ..< quoteEnd]

    if callersStart >= 0:
      let bracketStart = callersStart + 19  # len("allowed_callers = [")
      let bracketEnd = value.find("]", bracketStart)
      if bracketEnd >= 0:
        let inside = value[bracketStart ..< bracketEnd]
        for item in inside.split(','):
          let trimmedItem = item.strip().strip(chars = {'"', '[', ']'}).strip()
          if trimmedItem.len > 0:
            allowedCallers.add(trimmedItem)

    if callerPattern.len > 0 and allowedCallers.len > 0:
      result.add(ForbiddenCallPattern(
        callee: calleeKey,
        callerPattern: callerPattern,
        allowedCallers: allowedCallers))

proc loadForbiddenPragmaPatterns*(lockPath: string = architecturePolicyPath): seq[ForbiddenPragmaPattern] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read [forbidden_pragmas] section from lock file.
  ## Mirrors loadForbiddenCallPatterns for pragma-based SoC enforcement.
  if not fileExists(lockPath):
    return @[]
  let content = try: readFileSafe(lockPath) except CatchableError: ""
  if content.len == 0:
    return @[]

  var inSection = false
  for rawLine in content.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.startsWith("[") and trimmed.endsWith("]"):
      let section = trimmed[1 .. ^2].strip()
      inSection = section == "forbidden_pragmas"
      continue
    if not inSection or trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    # Parse: "pragma" = { caller_pattern = "...", allowed_callers = ["...", "..."] }
    let eqIndex = trimmed.find('=')
    if eqIndex < 0:
      continue
    let pragmaKey = trimmed[0 ..< eqIndex].strip().strip(chars = {'"'})
    if pragmaKey.len == 0:
      continue

    let value = trimmed[eqIndex + 1 .. ^1].strip()
    let patternStart = value.find("caller_pattern = \"")
    let callersStart = value.find("allowed_callers = [")

    var callerPattern = ""
    var allowedCallers: seq[string] = @[]

    if patternStart >= 0:
      let quoteStart = patternStart + 18
      let quoteEnd = value.find("\"", quoteStart)
      if quoteEnd >= 0:
        callerPattern = value[quoteStart ..< quoteEnd]

    if callersStart >= 0:
      let bracketStart = callersStart + 19
      let bracketEnd = value.find("]", bracketStart)
      if bracketEnd >= 0:
        let inside = value[bracketStart ..< bracketEnd]
        for item in inside.split(','):
          let trimmedItem = item.strip().strip(chars = {'"', '[', ']'}).strip()
          if trimmedItem.len > 0:
            allowedCallers.add(trimmedItem)

    if callerPattern.len > 0 and allowedCallers.len > 0:
      result.add(ForbiddenPragmaPattern(
        pragmaName: pragmaKey,
        callerPattern: callerPattern,
        allowedCallers: allowedCallers))

proc loadOcpOverrides*(lockPath: string = architecturePolicyPath): seq[OcpOverride] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read [ocp_overrides] section from lock file.
  if not fileExists(lockPath):
    return @[]
  let content = try: readFileSafe(lockPath) except CatchableError: ""
  if content.len == 0:
    return @[]

  var inSection = false
  for rawLine in content.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.startsWith("[") and trimmed.endsWith("]"):
      let section = trimmed[1 .. ^2].strip()
      inSection = section == "ocp_overrides"
      continue
    if not inSection or trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    # Parse: "path" = { branchCount = N, reason = "..." }
    let eqIndex = trimmed.find('=')
    if eqIndex < 0:
      continue
    let modPath = trimmed[0 ..< eqIndex].strip().strip(chars = {'"'}).strip()
    if modPath.len == 0:
      continue

    let value = trimmed[eqIndex + 1 .. ^1].strip()
    let bcStart = value.find("branchCount = ")
    let reasonStart = value.find("reason = \"")

    var branchCount = 0
    var reason = ""

    if bcStart >= 0:
      let numStart = bcStart + 14  # len("branchCount = ")
      var numStr = ""
      for i in numStart ..< value.len:
        if value[i] in {'0'..'9'}:
          numStr.add(value[i])
        elif value[i] notin {' ', ',', '}'}:
          break
        else:
          break
      if numStr.len > 0:
        let parsed = safeParseInt(numStr)
        if parsed.isOk:
          branchCount = parsed.get

    if reasonStart >= 0:
      let quoteStart = reasonStart + 10  # len("reason = \"")
      let quoteEnd = value.find("\"", quoteStart)
      if quoteEnd >= 0:
        reason = value[quoteStart ..< quoteEnd]

    result.add(OcpOverride(
      path: modPath,
      branchCount: branchCount,
      reason: reason))

proc loadOcpRegistryPolicy*(lockPath: string = architecturePolicyPath): OcpRegistryPolicy {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read [ocp_registries] section from lock file.
  if not fileExists(lockPath):
    return OcpRegistryPolicy()
  let content = try: readFileSafe(lockPath) except CatchableError: ""
  if content.len == 0:
    return OcpRegistryPolicy()

  var inSection = false
  var modules: seq[string] = @[]
  var functions: seq[string] = @[]

  for rawLine in content.splitLines():
    let trimmed = rawLine.strip()
    if trimmed.startsWith("[") and trimmed.endsWith("]"):
      let section = trimmed[1 .. ^2].strip()
      inSection = section == "ocp_registries"
      continue
    if not inSection or trimmed.len == 0 or trimmed.startsWith("#"):
      continue

    let eqIndex = trimmed.find('=')
    if eqIndex < 0:
      continue
    let key = trimmed[0 ..< eqIndex].strip()
    let value = trimmed[eqIndex + 1 .. ^1].strip()

    if key == "modules":
      let bracketStart = value.find('[')
      let bracketEnd = value.find(']')
      if bracketStart >= 0 and bracketEnd > bracketStart:
        let inside = value[bracketStart + 1 ..< bracketEnd]
        for item in inside.split(','):
          let trimmedItem = item.strip().strip(chars = {'"'}).strip()
          if trimmedItem.len > 0:
            modules.add(trimmedItem)
    elif key == "functions":
      let bracketStart = value.find('[')
      let bracketEnd = value.find(']')
      if bracketStart >= 0 and bracketEnd > bracketStart:
        let inside = value[bracketStart + 1 ..< bracketEnd]
        for item in inside.split(','):
          let trimmedItem = item.strip().strip(chars = {'"'}).strip()
          if trimmedItem.len > 0:
            functions.add(trimmedItem)

  result = OcpRegistryPolicy(modules: modules, functions: functions)

# ---------------------------------------------------------------------------
# Query: Path-Aware DIP — Forbidden concrete calls
# ---------------------------------------------------------------------------

proc checkForbiddenCallsWrapper*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Path-Aware DIP check: if a module calls a forbidden callee, verify
  ## the caller's path matches allowed_callers patterns.
  ##
  ## Uses the new forbiddenCallPatterns (path-pattern-based from lock file).

  let patterns = loadForbiddenCallPatterns()

  for facts in allFacts:
    # --- Check: forbidden_calls table (legacy, layer-based) ---
    for call in facts.calls:
      let allowedCallers = policy.forbiddenCalls.getOrDefault(call.callee, @[])
      if allowedCallers.len > 0:
        var allowed = false
        for ac in allowedCallers:
          if pathMatchesGlob(facts.path, ac):
            allowed = true
            break
          # Also try directory prefix match
          if facts.path.startsWith(ac & "/"):
            allowed = true
            break
        if not allowed:
          result.add(ArchitectureViolationArtifact(
            rule: "SOLID",
            detail: facts.path & ":" & $call.location.line & ":" & $call.location.column &
              " calls concrete backend " & call.callee & "; allowed only from " & allowedCallers.join(", "),
            files: @[facts.path],
            severity: "error"))

    # --- Check: forbidden_call_patterns section (path-pattern-based) ---
    for pat in patterns:
      for call in facts.calls:
        if pat.callee != call.callee:
          continue
        # Check if caller matches the pattern that would trigger this rule
        if not pathMatchesGlob(facts.path, pat.callerPattern):
          continue
        # Check if caller is in the allowed list
        var allowed = false
        for ac in pat.allowedCallers:
          if pathMatchesGlob(facts.path, ac):
            allowed = true
            break
          if facts.path.startsWith(ac & "/"):
            allowed = true
            break
        if not allowed:
          result.add(ArchitectureViolationArtifact(
            rule: "SOLID",
            detail: facts.path & ":" & $call.location.line & ":" & $call.location.column &
              " calls concrete backend " & call.callee &
              " from " & facts.path &
              "; allowed only from " & pat.allowedCallers.join(", "),
            files: @[facts.path],
            severity: "error"))

proc checkForbiddenPragmas*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Path-Aware SoC check: if a module uses a forbidden pragma, verify
  ## the caller's path matches allowed_callers patterns.
  ##
  ## Uses the [forbidden_pragmas] section from the lock file.

  let patterns = loadForbiddenPragmaPatterns()
  if patterns.len == 0:
    return

  for facts in allFacts:
    for pat in patterns:
      for pragma in facts.pragmas:
        if pat.pragmaName != pragma.pragmaName:
          continue
        # Check if caller matches the pattern that would trigger this rule
        if not pathMatchesGlob(facts.path, pat.callerPattern):
          continue
        # Check if caller is in the allowed list
        var allowed = false
        for ac in pat.allowedCallers:
          if pathMatchesGlob(facts.path, ac):
            allowed = true
            break
          if facts.path.startsWith(ac & "/"):
            allowed = true
            break
        if not allowed:
          result.add(ArchitectureViolationArtifact(
            rule: "SOLID",
            detail: facts.path & ":" & $pragma.location.line & ":" & $pragma.location.column &
              " uses pragma {." & pragma.pragmaName & ".} on " & pragma.targetName &
              " from " & facts.path &
              "; allowed only from " & pat.allowedCallers.join(", "),
            files: @[facts.path],
            severity: "error"))

# ---------------------------------------------------------------------------
# Query: OCP Registry violation detection
# ---------------------------------------------------------------------------

const ocpBranchThreshold = 3
  ## Files with ≤3 runtime case branches are too small for dispatch tables.

proc isVisitorModule*(facts: ModuleFacts): bool {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Detect visitor/walker patterns: a module with self-recursive functions
  ## where case branches are part of recursive AST walking, not
  ## extensibility points.  Pattern: proc walk(n) = case n.kind of ... walk(child)
  for edge in facts.callEdges:
    if edge.callerFunction == edge.calleeFunction:
      return true

proc checkOcpViolation*(
  allFacts: seq[ModuleFacts];
  policy: ArchitecturePolicy
): seq[ArchitectureViolationArtifact] {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Static OCP detection: modules with excessive case branches but no
  ## registry calls are flagged as potential OCP violations.
  ##
  ## A proper OCP module should use registries/dispatch tables instead
  ## of long case/switch chains.
  ##
  ## Three exemptions reduce false positives:
  ## 1. Object variant type definitions (nkTypeSection branches) are
  ##    type-level constructs, not runtime dispatch.
  ## 2. Visitor/walker patterns (self-recursive functions) use case
  ##    branches for AST traversal — inherently case-based.
  ## 3. Small case counts (≤4 branches) are too few for dispatch
  ##    table benefit.

  let ocpPolicy = loadOcpRegistryPolicy()
  if ocpPolicy.functions.len == 0:
    return

  let ocpOverrides = loadOcpOverrides()

  # Build a set of paths that are overridden
  var overridePaths = initHashSet[string]()
  for o in ocpOverrides:
    overridePaths.incl(o.path)

  for facts in allFacts:
    # Determine effective branch count:
    # If --base-ref was provided (addedLineRanges non-empty), only count
    # branches whose location falls within the git diff added line ranges.
    # Otherwise, count all case branches (existing behavior).
    var addedBranchCount = 0
    if facts.addedLineRanges.len > 0:
      for loc in facts.caseBranchLocations:
        for (startLine, endLine) in facts.addedLineRanges:
          if loc.line >= startLine and loc.line <= endLine:
            addedBranchCount += 1
            break

    # Temporal OCP: flag if new branches were added AND total exceeds threshold.
    # Static mode (no --base-ref): use total caseBranchCount as before.
    let effectiveBranchCount = if facts.addedLineRanges.len > 0:
                                 (if addedBranchCount > 0: facts.caseBranchCount else: 0)
                               else: facts.caseBranchCount

    # Exemption: Subtract type-definition branches (object variants are
    # type-level constructs, not runtime dispatch).  Use conditional to
    # avoid std/math import for max().
    let runtimeBranchCount = if effectiveBranchCount > facts.typeCaseBranchCount:
                               effectiveBranchCount - facts.typeCaseBranchCount
                             else: 0

    if runtimeBranchCount <= ocpBranchThreshold:
      continue  # below threshold or all branches are type definitions

    # Skip if module is in the override list
    if facts.path in overridePaths:
      continue

    # Exemption: Visitor/walker pattern — self-recursive functions indicate
    # case branches are part of recursive AST walking, not extensibility
    # points that should use registries.
    if facts.isVisitorModule():
      continue

    # Count calls to registry functions
    var registryCallCount = 0
    for call in facts.calls:
      if call.callee in ocpPolicy.functions:
        registryCallCount += 1

    if registryCallCount == 0:
      # Check if this module path is in the registry modules list
      var isRegistryModule = false
      for rm in ocpPolicy.modules:
        if rm == facts.path:
          isRegistryModule = true
          break
        if facts.path.endsWith("/" & rm):
          isRegistryModule = true
          break

      if not isRegistryModule:
        result.add(ArchitectureViolationArtifact(
          rule: "SOLID",
          detail: facts.path & " has " & $runtimeBranchCount &
            " case branches but 0 calls to registry functions [" &
            ocpPolicy.functions.join(", ") & "]; " &
            "consider using registry/dispatch pattern for OCP compliance",
          files: @[facts.path],
          severity: "warning"))

{.pop.}
