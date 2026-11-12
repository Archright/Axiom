import core/trusted/layer_declaration
axiomLayer "trusted"
{.push raises: [].}

import std/sequtils
import core/crypto/hash_kernel
import generated/build_env
import core/trusted/axiom_ir
import core/trusted/specification_artifact
import core/trusted/evidence_calculus
import core/trusted/ir_to_smt
import core/trusted/semantic_profile
import core/trusted/dependency_snapshot
import core/trusted/solver_invocation

## Phase-2 Evidence Capture — the FIRST vertical slicing commitment.
##
## This is a PURE collector: it captures artifacts that were ALREADY generated
## (never reconstructing/synthesizing again — capture must be reference-preserving),
## and it does NOT decide PROVED/assurance/certificate/VKD (that is Claim Authority,
## a later phase). The evidence bundle accumulated here is internal-only and is NOT
## serialized into certificates in this phase.

func captureSpecification*(
  funcDef: IRFuncDef;
  origin: SpecOrigin = soCanonicalDerived;
  ruleVersion: string = "v1"
): SpecificationArtifact {.raises: [].} =
  ## Build a SpecificationArtifact from the IR func's pre/post conditions,
  ## preserving the raw IRExpr (no reconstruction) AND a canonical identity.
  result.rawPreConditions = funcDef.preConditions
  result.rawPostConditions = funcDef.postConditions
  result.canonicalSpecIR = (funcDef.preConditions & funcDef.postConditions).mapIt(
    serializeIRExpr(it))
  result.origin = origin
  result.ruleId = "synthesizeContracts"
  result.ruleVersion = ruleVersion
  # specId is derived from the CANONICAL form (not the rendering) — stable identity.

func captureEvidence*(
  funcDef: IRFuncDef;
  origin: SpecOrigin = soCanonicalDerived;
  ruleVersion: string = "v1";
  dependencies: seq[string] = @[];
  sourceScope: string = "";
  solverBinaryDigest: string = ""
): EvidenceBundle {.raises: [].} =
  ## Minimum 3-artifact capture: SpecificationArtifact + DependencySnapshot +
  ## (minimal SolverEvidence — identity/version/outcome/outputDigest, no proof
  ## object which would imply P5/T2). Cert/Claim/VKD untouched.
  ##
  ## The recorded option digest is the digest of the option set this product
  ## pins (core/trusted/solver_invocation), not a placeholder: a declared field
  ## that is never populated is false authority. `solverBinaryDigest` is
  ## injected at the filesystem boundary by
  ## verification/solver/solver_invocation_provenance — this module is pure and
  ## cannot resolve an executable path itself.
  let spec = captureSpecification(funcDef, origin, ruleVersion)
  let smtScript = irToSmtScript(funcDef)
  result.specificationArtifact = spec
  result.dependencySnapshot = captureDependencySnapshot(dependencies, sourceScope)
  # minimal solver evidence (replay-level T0; proof object NOT required)
  result.facts.solver.solverIdentity = "z3"
  result.facts.solver.smtHash = ""
  result.facts.solver.proofFormat = ""
  result.facts.solver.proofDigest = ""     # optional: only a T2/kernel check fills this
  result.facts.solver.replayResult = ""    # "ACCEPTED"/"REJECTED" in Replay phase only
  # Phase-6: persist the T0 replay identity (canonical SMT input + solver identity/options).
  result.solverInvocation = SolverInvocation(
    scriptDigest: sha256Hex(serializeIRFuncDef(funcDef)),
    solverIdentity: "z3",
    solverVersion: BuildEnvZ3Version,
    solverOptionsDigest: deterministicSolverOptionsDigest(),
    solverBinaryDigest: solverBinaryDigest,
    semanticProfileId: SemanticProfileV1Hash,
    encodingIdentity: "axiom-ir-smt-v1",
    env: "",
    canonicalSourceIdentity: sha256Hex(funcDef.name),
    specificationIdentity: spec.specIdentity,
    translationIdentityHash: "axiom-ir-smt-v1",
    smtScriptDigest: sha256Hex(smtScript),
    smtScript: smtScript
  )
  result.facts.provenanceComplete = false  # Phase 3 fills provenance

{.pop.}
