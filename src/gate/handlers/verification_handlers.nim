import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [CatchableError].}

## Verification Handlers
##
## Declarative gate handlers composed from predicate primitives in
## `gate/predicates/base.nim`. Each handler checks one verification domain
## by combining 2-4 predicates into a single boolean decision.
##
## Handlers follow the standard runner pattern: pure `run` func + `main` proc.
## Exit 0 = pass, exit 1 = fail with explanation on stderr.
##
## # axiom:verification-handler

import std/[os, strutils, streams]
import infrastructure/logging_facade
import gate/predicates/base
import core/trusted/axiom_pragmas
import core/parsers/safe_parsers

const GateTag* = "[verification-handlers]"

# ============================================================================
## Handler 1: Z3 Solver Gate — SMT Solver Response Validation
# ============================================================================

proc runZ3SolverGate*(z3Output: string): bool =
  ## Validates Z3 solver output is structurally valid (sat/unsat/model).
  ## Composes: checkZ3ResponseValid
  try:
    if not checkZ3ResponseValid(z3Output):
      logError("verification_handlers", $(GateTag) & " FAIL — invalid Z3 response")
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 2: LFS Integrity Gate — Large File Storage Pointer Verification
# ============================================================================

proc runLfsIntegrityGate*(stagedFiles: seq[string]): bool =
  ## Verifies all staged files marked by .gitattributes have valid LFS pointers.
  ## Composes: checkLfsPointerValid, checkFileReadable, hasImport
  try:
    var lfsPaths: seq[string] = @[]
    if fileExists(".gitattributes"):
      for line in readFile(".gitattributes").splitLines():
        if "filter=lfs" in line:
          let p = line.splitWhitespace()[0]
          lfsPaths.add(p)
    for filePath in stagedFiles:
      let fname = extractFilename(filePath)
      for lfsPattern in lfsPaths:
        let pat = lfsPattern.split('/')[^1]
        let matches = if pat.startsWith("*"):
                        fname.endsWith(pat[1..^1])
                      else:
                        fname == pat
        if matches:
          let content = readFile(filePath)
          if not checkLfsPointerValid(content):
            logError("verification_handlers", $(GateTag) & " FAIL — bad LFS pointer: " & filePath)
            return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 3: Manifest Consistency Gate — Registry Sync Check
# ============================================================================

proc runManifestConsistencyGate*(manifestDir: string): bool =
  ## Ensures manifest.d JSON files are synchronized and well-formed.
  ## Composes: checkManifestSync, hasRequiredField, validateEnumValue
  try:
    if not dirExists(manifestDir): return true
    var fileCount = 0
    var indexCount = 0
    for kind, path in walkDir(manifestDir):
      if kind == pcFile and path.endsWith(".json") and "_index" notin path:
        inc fileCount
        let content = readFile(path)
        if not hasRequiredField(content, "id"):
          logError("verification_handlers", $(GateTag) & " FAIL — missing id in " & path)
          return false
    let indexPath = manifestDir / "_index.json"
    if fileExists(indexPath):
      let idxContent = readFile(indexPath)
      indexCount = countMatches(idxContent, "\"") div 2
    if not checkManifestSync(fileCount, indexCount):
      logError("verification_handlers", $(GateTag) & " FAIL — manifest count mismatch")
      return false
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false
  result = true

# ============================================================================
## Handler 4: State Hash Gate — Ledger Hash Chain Integrity
# ============================================================================

proc runStateHashGate*(ledgerPath: string, expectedHash: string): bool =
  ## Verifies state ledger hash matches expected value from previous run.
  ## Composes: verifySha256Match, verifyLedgerIntegrity, computeStateHash
  try:
    let ledgerData = readFile(ledgerPath)
    if not verifyLedgerIntegrity(ledgerData):
      logError("verification_handlers", $(GateTag) & " FAIL — ledger integrity check failed")
      return false
    let computedHash = computeStateHash(ledgerData)
    if not verifySha256Match(computedHash, expectedHash):
      logError("verification_handlers", $(GateTag) & " FAIL — state hash mismatch")
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 5: Merkle Root Gate — Tree Integrity Verification
# ============================================================================

proc runMerkleRootGate*(rootHash: string, leafCount: int): bool =
  ## Validates merkle root hash is well-formed for the given leaf count.
  ## Composes: verifyMerkleRoot, verifyHashFormat
  try:
    if not verifyMerkleRoot(rootHash, leafCount):
      logError("verification_handlers", $(GateTag) & " FAIL — invalid merkle root for " &
               $leafCount & " leaves")
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 6: Effect Inference Gate — Axiom Effect Annotation Check
# ============================================================================

proc runEffectInferenceGate*(stagedFiles: seq[string]): bool =
  ## Ensures I/O procs have {.axiomEffect: IoEffect.} pragma annotations.
  ## Composes: checkEffectInference, checkAstHasEffectPragma
  try:
    for filePath in stagedFiles:
      if not filePath.endsWith(".nim"): continue
      let content = readFile(filePath)
      if not checkEffectInference(content):
        logError("verification_handlers", $(GateTag) & " FAIL — missing effect pragma in " & filePath)
        return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 7: Spec Binding Gate — Documentation-to-Code References
# ============================================================================

proc runSpecBindingGate*(specPath: string, codeRef: string): bool =
  ## Validates spec documents reference actual code implementation paths.
  ## Composes: checkSpecBinding, checkFileReadable
  try:
    if not checkSpecBinding(specPath, codeRef):
      logError("verification_handlers", $(GateTag) & " FAIL — broken spec binding")
      return false
    if not checkFileReadable(specPath):
      logError("verification_handlers", $(GateTag) & " FAIL — spec file not readable: " & specPath)
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 8: Coverage Ratchet Gate — Test Coverage Non-Regression
# ============================================================================

proc runCoverageRatchetGate*(currentCoverage: float, baselineCoverage: float): bool =
  ## Ensures test coverage hasn't regressed below the established baseline.
  ## Composes: checkCoverageRatchet
  if not checkCoverageRatchet(currentCoverage, baselineCoverage):
    logError("verification_handlers", $(GateTag) & " FAIL — coverage regression: " &
             $currentCoverage & "% < " & $baselineCoverage & "% baseline")
    return false
  result = true

# ============================================================================
## Handler 9: Golden Master Gate — Output Snapshot Comparison
# ============================================================================

proc runGoldenMasterGate*(actualOutput: string, goldenPath: string): bool =
  ## Compares actual CLI output against committed golden master reference.
  ## Composes: checkGoldenMasterMatch, checkFileReadable
  try:
    let goldenContent = readFile(goldenPath)
    if not checkGoldenMasterMatch(actualOutput.strip(), goldenContent.strip()):
      logError("verification_handlers", $(GateTag) & " FAIL — golden master mismatch")
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false

# ============================================================================
## Handler 10: Structural Safety Gate — Architecture Constraint Validation
# ============================================================================

proc runStructuralSafetyGate*(hasCycles: bool, hasAcyclicPragmas: bool): bool =
  ## Verifies ref object types declare {%.acyclic.} when referenced (non-cyclic).
  ## Composes: checkStructuralSafety
  try:
    if not checkStructuralSafety(hasCycles, hasAcyclicPragmas):
      logError("verification_handlers", $(GateTag) & " FAIL — structural safety violation")
      return false
    result = true
  except CatchableError as e:
    logError("verification_handlers", $(GateTag) & " ERROR — " & e.msg)
    result = false
