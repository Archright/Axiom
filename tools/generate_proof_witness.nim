## tools/generate_proof_witness.nim — Phase 2 Proof Witness Infrastructure
##
## Collects Lean 4 build trace artifacts from proofs/.lake/build/ and
## generates proofs/proof_witness.json containing depHashes, olean hashes,
## and source file SHA-256 digests for compile-time cross-checking.
##
## Architecture:
##   proofs/.lake/build/**/*.trace  →  parse JSON
##   proofs/.lake/build/**/*.olean.hash  →  read content hash
##   proofs/GateInvariants/*.lean  →  SHA-256 source digest
##   →  proofs/proof_witness.json
##
## Run: nim c -o:bin/generate_proof_witness tools/generate_proof_witness.nim
##      bin/generate_proof_witness

import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, json, algorithm, sequtils, hashes]
import checksums/sha2

const
  ProofsDir = "proofs"
  BuildDir = ProofsDir / ".lake" / "build" / "lib" / "lean"
  GateInvariantsDir = ProofsDir / "GateInvariants"
  WitnessOutputPath = ProofsDir / "proof_witness.json"
  TraceExtension = ".trace"
  OleanHashExtension = ".olean.hash"
  LeanSourceExtension = ".lean"

# ─── Hash Helpers ─────────────────────────────────────────────────────────────
# SHA-256 via checksums/sha2 — project standard (see AGENTS.md §0.6).

proc sha256hex(content: string): string {.raises: [].} =
  ## Compute SHA-256 hex digest of content. Returns "" on error.
  try: $secureHash(Sha_256, content)
  except CatchableError: ""

# ─── Trace Parsing ────────────────────────────────────────────────────────────

proc extractLeanVersion(traceJson: JsonNode): string =
  ## Extract Lean version from trace inputs.
  ## Inputs contain: ["Lean 4.29.0, commit <hash>", "<hash>"]
  try:
    let inputs = traceJson{"inputs"}
    if inputs.isNil or inputs.kind != JArray: return ""
    for inputEntry in inputs:
      if inputEntry.kind == JArray and inputEntry.len >= 1:
        let candidate = inputEntry[0].getStr("")
        if candidate.startsWith("Lean "):
          # "Lean 4.29.0, commit 98dc76e3c0a9b856c9b98726b713fb04fab16740"
          let afterLean = candidate[5 .. ^1]
          let commaIdx = afterLean.find(',')
          if commaIdx > 0:
            return afterLean[0 ..< commaIdx]
          let spaceIdx = afterLean.find(' ')
          if spaceIdx > 0:
            return afterLean[0 ..< spaceIdx]
          return afterLean
  except CatchableError:
    discard  # axiom:best-effort(trace-json-parse-failure: missing or malformed inputs field)
  return ""

proc extractSourceFile(traceJson: JsonNode): string =
  ## Extract the source .lean file path from trace inputs.
  ## Inputs contain entries like:
  ##   ["/absolute/path/to/File.lean", "hash"]
  try:
    let inputs = traceJson{"inputs"}
    if inputs.isNil or inputs.kind != JArray: return ""
    for inputEntry in inputs:
      if inputEntry.kind == JArray and inputEntry.len >= 2:
        let candidate = inputEntry[0].getStr("")
        if candidate.endsWith(LeanSourceExtension):
          return candidate
  except CatchableError:
    discard  # axiom:best-effort(trace-json-parse-failure: inputs field not array-of-arrays)
  return ""

proc extractDepHash(traceJson: JsonNode): string =
  ## Extract the depHash field from trace JSON.
  try:
    return traceJson{"depHash"}.getStr("")
  except CatchableError:
    return ""

proc mapTraceToSource(tracePath: string): string =
  ## Derive the source .lean file path from a trace file path.
  ## Pattern: proofs/.lake/build/lib/lean/<Module>.trace
  ##      →  proofs/<Module>.lean
  ## Handles both flat (GateInvariants.trace) and nested (GateInvariants/DagAcyclicity.trace).
  let relPath = tracePath
  if not relPath.startsWith(BuildDir): return ""
  var sourceRel = relPath[BuildDir.len .. ^1]
  # Strip leading path separator
  if sourceRel.startsWith("/"):
    sourceRel = sourceRel[1 .. ^1]
  # Replace .trace with .lean
  if sourceRel.endsWith(TraceExtension):
    sourceRel = sourceRel[0 .. ^(TraceExtension.len + 1)] & LeanSourceExtension
  return ProofsDir / sourceRel

# ─── Olean Hash ───────────────────────────────────────────────────────────────

proc readOleanHash(oleanHashPath: string): string =
  ## Read the content hash from a .olean.hash file.
  ## File contains a single hex string (e.g., "523ed449bb88a7b9").
  if not fileExists(oleanHashPath): return ""
  try:
    return readFile(oleanHashPath).strip()
  except CatchableError:
    return ""

# ─── Source Hashing ───────────────────────────────────────────────────────────

proc collectLeanSourceFiles(baseDir: string): seq[string] =
  ## Collect all .lean files under baseDir, sorted for determinism.
  result = @[]
  if not dirExists(baseDir): return
  try:
    for entry in walkDirRec(baseDir):
      if entry.endsWith(LeanSourceExtension):
        result.add(entry)
  except CatchableError:
    discard  # axiom:best-effort(trace-directory-walk-failure: no traces collected, witness generation reports empty)
  result.sort()

proc computeSourceHash(leanFiles: seq[string]): string =
  ## Compute SHA-256 of all .lean source files concatenated (sorted order).
  var combined = ""
  for f in leanFiles:
    try:
      combined &= readFile(f)
    except CatchableError:
      discard  # axiom:best-effort(source-file-read-failure: skip unreadable file, hash remaining files)
  sha256hex(combined)

# ─── Trace Collection ─────────────────────────────────────────────────────────

proc collectTraceFiles(buildDir: string): seq[string] =
  ## Collect all .trace files under buildDir, sorted for determinism.
  result = @[]
  if not dirExists(buildDir): return
  try:
    for entry in walkDirRec(buildDir):
      if entry.endsWith(TraceExtension):
        result.add(entry)
  except CatchableError:
    discard  # axiom:best-effort(trace-directory-walk-failure: no traces collected, witness generation reports empty)
  result.sort()

# ─── Witness Generation ───────────────────────────────────────────────────────

proc generateWitness*(): bool =
  ## Generate proofs/proof_witness.json from build trace artifacts.
  ## Returns true on success, false on failure.
  echo "Phase 2: Generating proof witness..."

  # 1. Collect trace files
  let traceFiles = collectTraceFiles(BuildDir)
  if traceFiles.len == 0:
    echo "  ⚠️  No .trace files found in ", BuildDir
    echo "     Run `lake build` in proofs/ first."
    return false

  echo "  Found ", $traceFiles.len, " trace file(s)"

  # 2. Parse each trace and build witness entries
  var tracesJson = newJObject()
  var allDepHashes: seq[string] = @[]
  var leanVersion = ""

  for tracePath in traceFiles:
    let traceContent =
      try: readFile(tracePath)
      except CatchableError:
        echo "  ⚠️  Cannot read: ", tracePath
        continue

    let traceJson =
      try: parseJson(traceContent)
      except CatchableError:
        echo "  ⚠️  Invalid JSON: ", tracePath
        continue

    let depHash = extractDepHash(traceJson)
    if depHash.len == 0:
      echo "  ⚠️  No depHash in: ", tracePath
      continue

    # Extract Lean version from first trace that has it
    if leanVersion.len == 0:
      leanVersion = extractLeanVersion(traceJson)

    # Resolve source file — prefer trace inputs, fall back to path mapping
    var sourceFile = extractSourceFile(traceJson)
    if sourceFile.len == 0:
      sourceFile = mapTraceToSource(tracePath)

    # Read olean hash — sibling .olean.hash file
    let oleanHashPath = tracePath.replace(TraceExtension, OleanHashExtension)
    let oleanHash = readOleanHash(oleanHashPath)

    # Build trace entry key: just the filename relative to build
    var traceKey = tracePath
    if traceKey.startsWith(BuildDir):
      traceKey = traceKey[BuildDir.len .. ^1]
      if traceKey.startsWith("/"):
        traceKey = traceKey[1 .. ^1]

    let traceEntry = %*{
      "depHash": depHash,
      "oleanHash": oleanHash,
      "sourceFile": sourceFile
    }
    tracesJson[traceKey] = traceEntry
    allDepHashes.add(depHash)

    echo "  ✓ ", traceKey, " → depHash=", depHash

  if tracesJson.len == 0:
    echo "  ❌ No valid traces parsed"
    return false

  # 3. Compute source hash from all GateInvariants .lean files
  let leanSourceFiles = collectLeanSourceFiles(GateInvariantsDir)
  # Also include the top-level GateInvariants.lean if it exists
  let topLevelLean = ProofsDir / "GateInvariants" & LeanSourceExtension
  var allLeanFiles = leanSourceFiles
  if fileExists(topLevelLean) and topLevelLean notin allLeanFiles:
    allLeanFiles.add(topLevelLean)
  allLeanFiles.sort()

  let sourceHash = computeSourceHash(allLeanFiles)
  echo "  Source hash: ", sourceHash, " (", $allLeanFiles.len, " files)"

  # 4. Compute overall hash from all depHashes (sorted for determinism)
  allDepHashes.sort()
  var depHashCombined = ""
  for h in allDepHashes:
    depHashCombined &= h
  let overallHash = sha256hex(depHashCombined)
  echo "  Overall hash: ", overallHash

  # 5. Assemble final witness JSON
  let witness = %*{
    "lean_version": leanVersion,
    "traces": tracesJson,
    "source_hash": sourceHash,
    "overall_hash": overallHash
  }

  # 6. Write output
  let outputDir = WitnessOutputPath.parentDir()
  if not dirExists(outputDir):
    try: createDir(outputDir)
    except CatchableError:
      echo "  ❌ Cannot create directory: ", outputDir
      return false

  let outputJson = witness.pretty() & "\n"
  try:
    writeFile(WitnessOutputPath, outputJson)
  except CatchableError:
    echo "  ❌ Cannot write: ", WitnessOutputPath
    return false

  echo "  ✓ Witness written to ", WitnessOutputPath
  echo "  ✓ ", $tracesJson.len, " trace(s), lean ", leanVersion
  return true

# ─── Entry Point ──────────────────────────────────────────────────────────────

when isMainModule:
  let ok = generateWitness()
  if not ok:
    quit(1)
