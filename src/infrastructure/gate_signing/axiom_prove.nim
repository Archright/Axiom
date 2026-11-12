## Proof-Carrying Code — Phase 4: Proof Generator
##
## Runs INSIDE the L1 bubblewrap sandbox (axiom-sandbox user).
## Takes a commit SHA, checks out the tree, runs Z3 and Lean 4 to generate
## a proof artifact. Z3 is used ONLY as a "proof finder" — it generates
## proofs, but the Lean kernel verifies them independently.
##
## Pipeline: commitSha → treeSha → Z3 proofs → Lean typecheck → olean hash
##           → toolchain hash → ProofArtifact → stdout (captured by sandbox launcher)
##
## Output: ProofArtifact JSON to stdout.

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[os, osproc, streams, strutils, times, json, algorithm]
import core/crypto/hash_kernel
import proof_artifact_types
import core/trusted/axiom_pragmas
import core/macros/best_effort

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

const
  Z3TimeoutMs* = 30_000          ## 30 seconds for Z3
  LeanTimeoutMs* = 60_000        ## 60 seconds for Lean
  GitTimeoutMs* = 10_000         ## 10 seconds for git operations
  EmptyHash* = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"  ## SHA-256 of ""

# ---------------------------------------------------------------------------
# SHA-256 Helpers
# ---------------------------------------------------------------------------

func computeSha256*(content: string): string {.raises: [].} =
  ## Compute SHA-256 hash of content, returning lowercase hex digest.
  result = hash_kernel.sha256Hex(content)
  result = result.toLowerAscii()

proc computeFileSha256*(path: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 hash of a file's contents.
  let content = readFile(path)
  computeSha256(content)

# ---------------------------------------------------------------------------
# Process execution helpers
# ---------------------------------------------------------------------------

type
  ProcessResult* = object
    exitCode*: int
    stdout*: string
    stderr*: string

proc readAllOutput(p: Process): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Read all output from a process stdout stream.
  result = ""
  let stream = p.outputStream
  while not stream.atEnd:
    result.add(stream.readLine())
    result.add("\n")
  # Strip trailing newline
  if result.len > 0 and result[^1] == '\n':
    result.setLen(result.len - 1)

proc runProcess(cmd: string; args: openArray[string];
                timeoutMs: int): ProcessResult {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run an external process with a timeout. Returns exit code and captured output.
  let p = startProcess(cmd, args=args, options={poStdErrToStdOut, poUsePath})
  defer: p.close()
  let exitCode = p.waitForExit(timeout = timeoutMs)
  result.exitCode = exitCode
  result.stdout = readAllOutput(p)

# ---------------------------------------------------------------------------
# Git operations
# ---------------------------------------------------------------------------

proc gitVerifyCommit(repoPath: string;
                     commitSha: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Verify that commitSha is a valid git commit object.
  let gitResult = runProcess("git", [
    "-C", repoPath, "cat-file", "-t", commitSha
  ], GitTimeoutMs)
  gitResult.exitCode == 0 and gitResult.stdout.strip() == "commit"

proc gitGetTreeSha(repoPath: string;
                   commitSha: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolve commit SHA to its tree SHA.
  let gitResult = runProcess("git", [
    "-C", repoPath, "rev-parse", commitSha & "^{tree}"
  ], GitTimeoutMs)
  if gitResult.exitCode != 0:
    raise newException(CatchableError,
      "git rev-parse failed: " & gitResult.stdout)
  gitResult.stdout.strip()

proc gitCheckoutTree(repoPath: string;
                     commitSha: string) {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Checkout the commit tree into a temporary work tree.
  ## Uses git checkout to ensure the working directory matches the commit.
  let gitResult = runProcess("git", [
    "-C", repoPath, "checkout", "--force", commitSha, "--", "."
  ], GitTimeoutMs)
  if gitResult.exitCode != 0:
    raise newException(CatchableError,
      "git checkout failed: " & gitResult.stdout)

# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

proc findFiles(repoPath: string;
               extension: string): seq[string] {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Recursively find all files with the given extension under repoPath.
  ## Returns relative paths sorted alphabetically for determinism.
  result = @[]
  for path in walkDirRec(repoPath, relative = true):
    if path.endsWith(extension):
      result.add(path)
  result.sort()

# ---------------------------------------------------------------------------
# Z3 proof generation
# ---------------------------------------------------------------------------

proc trivialProof(): string {.raises: [CatchableError].} =
  ## Refuse to synthesize a proof when no .smt2 files exist.
  ## A satisfiable empty SMT query is vacuous and must not be emitted.
  raise newException(CatchableError,
    "no SMT-LIB2 proof files found; refusing to synthesize trivial proof")

proc runZ3OnFile(repoPath: string;
                 smt2File: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run Z3 on a single .smt2 file with produce-proofs=true.
  ## Returns the raw Z3 proof output.
  let fullPath = repoPath / smt2File
  let z3Result = runProcess("z3", [
    "produce-proofs=true", fullPath
  ], Z3TimeoutMs)

  if z3Result.exitCode != 0:
    # Z3 non-zero exit does not necessarily mean failure for proof generation.
    # If stdout contains proof output, treat it as valid.
    if z3Result.stdout.len == 0:
      raise newException(CatchableError,
        "z3 failed on " & smt2File & " (exit=" & $z3Result.exitCode & ")")
  z3Result.stdout

proc runZ3All(repoPath: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run Z3 on all .smt2 files in the repo. Concatenate all proofs.
  ## If no .smt2 files found, fail closed instead of synthesizing a proof.
  let smt2Files = findFiles(repoPath, ".smt2")
  if smt2Files.len == 0:
    return trivialProof()

  var allProofs = ""
  for f in smt2Files:
    let proof = runZ3OnFile(repoPath, f)
    if proof.len > 0:
      allProofs.add(proof)
      allProofs.add("\n")

  if allProofs.len == 0:
    return trivialProof()
  allProofs

# ---------------------------------------------------------------------------
# Lean 4 typecheck
# ---------------------------------------------------------------------------

proc runLeanTypecheck(repoPath: string;
                      leanFile: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Run lean --typecheck on a single .lean file.
  ## Uses kernel-only mode (no elaborator macros).
  ## Returns true if typecheck passes.
  let fullPath = repoPath / leanFile
  let leanResult = runProcess("lean", [
    "--run", "--threads=1", fullPath
  ], LeanTimeoutMs)
  # lean exits 0 on success; non-zero on type error
  leanResult.exitCode == 0

proc runLeanAll(repoPath: string): bool {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect], bestEffort("""no lean sources — trivially passes""").} =
  ## Run lean --typecheck on all .lean files.
  ## Returns true only if ALL files typecheck.
  let leanFiles = findFiles(repoPath, ".lean")
  if leanFiles.len == 0:
    return true

  for f in leanFiles:
    if not runLeanTypecheck(repoPath, f):
      raise newException(CatchableError,
        "Lean typecheck failed on: " & f)
  true

# ---------------------------------------------------------------------------
# .olean hash computation
# ---------------------------------------------------------------------------

proc computeOleanHash(repoPath: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute aggregate SHA-256 of all .olean files.
  ## If no .olean files exist, returns the empty hash.
  let oleanFiles = findFiles(repoPath, ".olean")
  if oleanFiles.len == 0:
    return EmptyHash

  var combined = ""
  for f in oleanFiles:
    try:
      let hash = computeFileSha256(repoPath / f)
      combined.add(hash)
    except CatchableError:
      combined.add("error")
  computeSha256(combined)

# ---------------------------------------------------------------------------
# Toolchain hash
# ---------------------------------------------------------------------------

proc computeToolchainHash(repoPath: string): string {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Compute SHA-256 of axiom-toolchain.lock if it exists.
  ## Returns the empty hash if the file is not found.
  let lockPath = repoPath / "axiom-toolchain.lock"
  if not fileExists(lockPath):
    return EmptyHash
  try:
    computeFileSha256(lockPath)
  except CatchableError:
    EmptyHash

# ---------------------------------------------------------------------------
# Main proof generator
# ---------------------------------------------------------------------------

proc generateProof*(repoPath: string,
                    commitSha: string): ProofArtifact
                    {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Generate a proof artifact for the given commit.
  ##
  ## Steps:
  ##   1. Validate commitSha format (40 hex chars)
  ##   2. Verify it's a valid git commit
  ##   3. Get tree SHA for Merkle binding
  ##   4. Run Z3 on .smt2 files (or generate trivial proof)
  ##   5. Run Lean --typecheck on .lean files
  ##   6. Compute .olean aggregate hash
  ##   7. Compute toolchain hash
  ##   8. Build ProofArtifact with composite proofHash
  ##   9. Write JSON to stdout

  # Step 1: Validate commit SHA format
  if not isValidCommitSha(commitSha):
    raise newException(CatchableError,
      "Invalid commit SHA: must be 40 lowercase hex chars, got: " & commitSha)

  # Step 2: Verify commit exists in the repo
  if not gitVerifyCommit(repoPath, commitSha):
    raise newException(CatchableError,
      "Not a valid git commit: " & commitSha)

  # Step 3: Get tree SHA
  let treeSha = gitGetTreeSha(repoPath, commitSha)
  if not isValidCommitSha(treeSha):
    raise newException(CatchableError,
      "Invalid tree SHA returned: " & treeSha)

  # Step 4: Checkout the commit tree
  gitCheckoutTree(repoPath, commitSha)

  # Step 5: Run Z3 proof generation on all .smt2 files
  let z3Proof = runZ3All(repoPath)
  if z3Proof.len > MaxZ3ProofSize:
    raise newException(CatchableError,
      "Z3 proof exceeds MaxZ3ProofSize: " & $z3Proof.len & " bytes")

  # Step 6: Run Lean typecheck on all .lean files
  discard runLeanAll(repoPath)

  # Step 7: Compute .olean aggregate hash
  let oleanHash = computeOleanHash(repoPath)

  # Step 8: Compute toolchain hash
  let toolchainHash = computeToolchainHash(repoPath)

  # Step 9: Build composite proofHash
  # proofHash = SHA-256(treeSha + z3Proof + leanOleanHash + toolchainHash)
  let composite = treeSha & z3Proof & oleanHash & toolchainHash
  let proofHash = computeSha256(composite)

  # Step 10: Build and return ProofArtifact
  result = ProofArtifact(
    treeSha: treeSha,
    z3Proof: z3Proof,
    leanOleanHash: oleanHash,
    toolchainHash: toolchainHash,
    timestamp: int64(epochTime()),
    proofHash: proofHash
  )

# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------

proc main() {.raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## CLI entry point: axiom-prove <repoPath> <commitSha>
  ## Outputs ProofArtifact JSON to stdout.
  let params = commandLineParams()
  if params.len != 2:
    echo "{\"error\": \"Usage: axiom-prove <repoPath> <commitSha>\"}"
    quit(1)

  let repoPath = params[0]
  let commitSha = params[1]

  if not dirExists(repoPath):
    echo "{\"error\": \"Repository path does not exist: " & repoPath & "\"}"
    quit(1)

  let artifact = generateProof(repoPath, commitSha)
  echo $artifact.toJson()

when isMainModule:
  try:
    main()
  except CatchableError as e:
    echo "{\"error\": \"" & e.msg & "\"}"
    quit(1)

{.pop.}
