import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].}

import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/trusted/axiom_ir
import core/trusted/evidence_calculus
import core/trusted/evidence_capture
import core/trusted/solver_invocation
import core/trusted/specification_artifact
import core/types/z3_solver_config
import std/locks
import std/os

## Solver Invocation Provenance — the I/O half of the invocation record.
##
## `core/trusted/solver_invocation` owns the pure side: the pinned option set,
## its digest, and the verdict grammar. This module owns the parts that can
## only be answered by touching the filesystem: which executable was actually
## run, and what its content hashes to.
##
## The solver binary is an EXTERNAL authority. Axiom's responsibility is not to
## trust it but to record exactly which binary, which version and which options
## received the problem — so every path here refuses rather than degrades.

type
  SolverBinaryIdentity* = object
    resolvedPath*: string   ## path resolveZ3Path() selected, not a bare name
    binaryDigest*: string   ## sha256Hex of the executable's bytes

proc solverBinaryDigestAt*(path: string): Result[string, string] {.axiomDecision(
    id = "DECISION-0820",
    reason = "Refuse to record a solver binary identity that was not observed; an unresolvable path or unreadable executable must fail closed instead of degrading to an empty digest",
    adr = "docs/adr/0001-fail-closed-result-type.md",
    introduced = "v33"), raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Content digest of a solver executable, computed from the RESOLVED path.
  ##
  ## resolveZ3Path() falls back to the bare name "z3" when nothing on the
  ## priority chain exists. That name is not a readable file, so this proc
  ## refuses it — recording `""` would read as "the digest of the empty
  ## executable", which is a stronger and false claim than "not established".
  if path.len == 0:
    return err("solver executable path is unresolved")
  if not fileExists(path):
    return err("solver executable not found: " & path)
  let content = readFile(path)
  if content.len == 0:
    return err("solver executable is empty: " & path)
  let digest = sha256Hex(content)
  if digest.len == 0:
    return err("solver executable digest could not be computed: " & path)
  ok(digest)

var
  binaryIdentityLock: Lock
  cachedBinaryPath: string
  cachedBinaryDigest: string

proc resolveSolverBinaryIdentity*(): Result[SolverBinaryIdentity, string] {.axiomDecision(
    id = "DECISION-0821",
    reason = "Resolve the canonical solver executable and memoize its content digest so the digest cannot drift between invocations in one run",
    adr = "docs/adr/0001-fail-closed-result-type.md",
    introduced = "v33"), raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Resolver-canonical identity of the solver binary, computed once and reused.
  ##
  ## The cache is keyed on the resolved path, not on the answer: if the
  ## executable is swapped under a live process, the new path misses and is
  ## rehashed rather than served from a stale entry.
  let resolved = resolveZ3Path()
  binaryIdentityLock.withLock:
    if cachedBinaryDigest.len > 0 and cachedBinaryPath == resolved:
      return ok(SolverBinaryIdentity(resolvedPath: cachedBinaryPath,
                                     binaryDigest: cachedBinaryDigest))
  let digest = solverBinaryDigestAt(resolved)
  if digest.isErr:
    return err(digest.error())
  binaryIdentityLock.withLock:
    cachedBinaryPath = resolved
    cachedBinaryDigest = digest.get()
  ok(SolverBinaryIdentity(resolvedPath: resolved, binaryDigest: digest.get()))

proc captureEvidenceWithSolverIdentity*(
    funcDef: IRFuncDef;
    origin: SpecOrigin = soCanonicalDerived;
    ruleVersion: string = "v1";
    dependencies: seq[string] = @[];
    sourceScope: string = ""
): Result[EvidenceBundle, string] {.axiomDecision(
    id = "DECISION-0822",
    reason = "Evidence capture is fail-closed on solver identity: a bundle whose SolverInvocation cannot name the executable that received the problem is a false-authority record, so it is refused rather than written with an empty binary digest",
    adr = "docs/adr/0001-fail-closed-result-type.md",
    introduced = "v33"), raises: [CatchableError], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Capture evidence with the solver binary identity established at the
  ## filesystem boundary. The pure captureEvidence remains available for
  ## callers that deliberately record an invocation without binary identity;
  ## this entry point is the one that makes the record self-describing.
  let identity = resolveSolverBinaryIdentity()
  if identity.isErr:
    return err("solver binary identity not established: " & identity.error())
  ok(captureEvidence(funcDef, origin, ruleVersion, dependencies, sourceScope,
                     identity.get().binaryDigest))

{.pop.}