import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

## Analyzer Shared Helpers
## Pure helper functions used across analyzer pipeline stages.

import std/options
import std/os
import std/sets
import std/strutils
import std/tables
import std/times
import core/domain_types
import core/domain_utils
import core/json/json_utils
import core/json/std_redirect
import ../../core/trusted/axiom_pragmas
# axiomIoBoundary


proc resolveSourcePath*(baseDir: string; modulePath: string): string {.raises: [], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if modulePath.len == 0:
    return ""
  if isAbsolute(modulePath):
    return modulePath
  var directCandidate = modulePath
  normalizePath(directCandidate)
  if fileExists(directCandidate):
    return directCandidate
  let repoRoot = parentDir(parentDir(parentDir(baseDir)))
  var candidate = joinPath(repoRoot, modulePath)
  normalizePath(candidate)
  if fileExists(candidate):
    return candidate
  var withSrc = joinPath(repoRoot, "src", modulePath)
  normalizePath(withSrc)
  if fileExists(withSrc):
    return withSrc
  return candidate


## axiom-smt: (assert (and (>= (str.len certificatePath) 0) (= (option.isNone rootOpt) true) (> (str.len rawStatus) 0) (> (str.len rawReason) 0) cert (=> (= (option.isNone rootOpt) true) (= result cert)) (>= cert 0)))
## axiom-lean: certificatePath.length ≥ 0 ∧ rootOpt.isNone = true ∧ rawStatus.length > 0 ∧ rawReason.length > 0 ∧ cert ∧ rootOpt.isNone = true → result = cert ∧ (cert ≥ 0)
proc buildLastNDaysUtc*(n: int): seq[string] {.axiom, axiomOpaque, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if n <= 0:
    return @[]
  let nowUtc = now().utc()
  for i in countdown(n - 1, 0):
    let day = (nowUtc - initDuration(days = i)).format("yyyy-MM-dd")
    result.add(day)


# @axiom-hint: lean="raw.length ≥ 0" smt="(assert (>= (str.len raw) 0))"
## axiom-smt: (assert (and (>= (str.len raw) 0) (>= (str.len stripped) 10) (>= (str.len raw) 0)))
## axiom-lean: raw.length ≥ 0 ∧ stripped.length ≥ 10 ∧ raw.length ≥ 0
proc parseDayFromTimestamp*(raw: string): string {.axiom, axiomImpl.} =
  let stripped = raw.strip()
  if stripped.len >= 10:
    stripped[0 .. 9]
  else:
    ""


# @axiom-hint: lean="content.length ≥ 0" smt="(assert (>= (str.len content) 0))"
proc parseJsonSafe*(content: string): Option[JsonNode] {.raises: [], axiom: ["(assert (and (>= (str.len content) 0) (>= result 0)))", "content.length ≥ 0 ∧ (result ≥ 0)"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  try:
    result = some(parseJsonOpt(content).get(newJObject()))
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)


func cumulativeDefectSum*(counts: seq[int]): int {.axiom, axiomImpl.} =
  ## Functional core: pure int-reduction (sum) over pre-extracted defect counts.
  ## Exported and carries the axiom macro. With the QF_AUFBV router, the
  ## `seq[int]` parameter is modelled as an array (slQfAufbv) and the
  ## `for n in counts` loop is handled by the Spacer/CHC route (vpInductiveLoop).
  ## This core now enters the kernel scope/denominator.
  for n in counts:
    result += n


## axiom-smt: (assert (and (>= (str.len logPath) 0) (and (>= days -9223372036854775808) (<= days 9223372036854775807) (= (str.len labels) 0) (= (option.isNone nodeOpt) true) (>= byDay 0) (>= labels 0)))
## axiom-lean: logPath.length ≥ 0 ∧ days ≥ -9223372036854775808 ∧ days ≤ 9223372036854775807 ∧ labels.length = 0 ∧ nodeOpt.isNone = true ∧ (byDay ≥ 0) ∧ (labels ≥ 0)
proc computeCumulativeDefectsHealed*(certificates: seq[FunctionCertificate]): int {.axiomOpaque.} =
  ## Opaque shell: pre-extracts the per-certificate `recoveredDefects.len`
  ## values then delegates to the verified core `cumulativeDefectSum`.
  ## Marked axiomOpaque — the shell itself is not verified; only the exported
  ## core carries the kernel proof obligations.
  var counts: seq[int] = @[]
  for cert in certificates:
    counts.add(cert.recoveredDefects.len)
  result = cumulativeDefectSum(counts)


## axiom-smt: (assert (and (>= (seq.len certificates) 0) (= (str.len certificates) 0) (= unstableTrustedCount 0) (>= certificates 0)))
## axiom-lean: certificates.size ≥ 0 ∧ certificates.length = 0 ∧ unstableTrustedCount = 0 ∧ (certificates ≥ 0)
proc computeAverageRetryCount*(certificates: seq[FunctionCertificate]): float {.axiom, axiomImpl.} =
  if certificates.len == 0:
    return 0.0
  var total = 0
  var unstableTrustedCount = 0
  for cert in certificates:
    if not cert.trusted or isCertificateVerified(cert.status):
      continue
    total += cert.retryCount
    inc unstableTrustedCount
  if unstableTrustedCount == 0:
    return 0.0
  result = total.float / unstableTrustedCount.float


## axiom-smt: (assert (and (>= (str.len certBaseDir) 0) (>= (str.len theoremName) 0) (= (str.len theoremName) 0) (= (str.len selectedStem) 0) (= selectedStem stem) (>= moduleByStem 0) (>= selectedStem 0)))
## axiom-lean: certBaseDir.length ≥ 0 ∧ theoremName.length ≥ 0 ∧ theoremName.length = 0 ∧ selectedStem.length = 0 ∧ selectedStem = stem ∧ (moduleByStem ≥ 0) ∧ (selectedStem ≥ 0)
proc inferModulePathFromTheorem*(certBaseDir: string; theoremName: string): string {.axiom, axiomOpaque, axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if theoremName.len == 0:
    return ""
  let repoRoot = parentDir(parentDir(parentDir(certBaseDir)))
  let coreRoot = joinPath(repoRoot, "src", "core")
  if not dirExists(coreRoot):
    return ""
  var moduleByStem = initTable[string, string]()
  for path in walkPattern(joinPath(coreRoot, "*.nim")):
    let stem = splitFile(path).name
    var relPath = relativePath(path, repoRoot)
    normalizePath(relPath)
    moduleByStem[stem] = relPath
  var selectedStem = ""
  for stem in moduleByStem.keys:
    if theoremName.startsWith(stem & "_") and stem.len > selectedStem.len:
      selectedStem = stem
  if selectedStem.len == 0:
    return ""
  moduleByStem[selectedStem]


## axiom-smt: (assert (and (>= (str.len theoremName) 0) (>= (str.len modulePath) 0) (or (= (str.len theoremName) 0) (= (str.len modulePath) 0))))
## axiom-lean: theoremName.length ≥ 0 ∧ modulePath.length ≥ 0 ∧ theoremName.length = 0 ∨ modulePath.length = 0
proc inferFunctionNameFromTheorem*(theoremName: string; modulePath: string): string {.axiom, axiomImpl.} =
  if theoremName.len == 0 or modulePath.len == 0:
    return ""
  let stem = splitFile(modulePath).name
  let prefix = stem & "_"
  if theoremName.startsWith(prefix) and theoremName.len > prefix.len:
    return theoremName[prefix.len .. ^1]
  ""


## axiom-smt: (assert (and (>= (seq.len certificates) 0) (>= certificates 0)))
## axiom-lean: certificates.size ≥ 0 ∧ (certificates ≥ 0)
proc collectKnownFunctions*(certificates: seq[FunctionCertificate]): HashSet[string] {.axiom, axiomImpl.} =
  for cert in certificates:
    if cert.functionName.len > 0:
      result.incl(cert.functionName)

# @axiom-hint: lean="certBaseDir.length ≥ 0 ∧ missingCertificates ≥ -9223372036854775808 ∧ missingCertificates ≤ 9223372036854775807 ∧ mismatchedFingerprints ≥ -9223372036854775808 ∧ mismatchedFingerprints ≤ 9223372036854775807 ∧ external_io_isolated" smt="(assert (and (>= (str.len certBaseDir) 0) (and (>= missingCertificates -9223372036854775808) (<= missingCertificates 9223372036854775807)) (and (>= mismatchedFingerprints -9223372036854775808) (<= mismatchedFingerprints 9223372036854775807)) external_io_isolated))"
# @axiom-hint: lean="ast_parse_failed_isolated" smt="(assert (and ast_parse_failed_isolated))"

{.pop.}

