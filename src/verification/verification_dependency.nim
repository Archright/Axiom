## verification_dependency.nim — Dependency Kind Classification Model
##
## Semantic classification of a runtime read (dependency kind).
## The verification-auditor verdict is a pure function of its
## semantic inputs; this module classifies every observable runtime
## read into one of five dependency categories so the pipeline can
## decide what feeds the query identity and what must be rejected.
##
## Dependency DAG (nodes/edges):
##   source → snapshot → IR → contract → verification query → result
##   plus global/context deps: policy, authorization, toolchain,
##   gate implementation, build configuration, provenance,
##   environment/filesystem state.
##
## Precedent: semantic_query_types.nim (QueryID digest components)
## and proof_typestate.nim (distinct types + function-only transitions).

import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, strutils, sugar]
import core/crypto/hash_kernel

# ---------------------------------------------------------------------------
# Dependency kind — the semantic classification of a runtime read
# ---------------------------------------------------------------------------

type
  VerificationDependencyKind* = enum
    ## Classification of a runtime read (dependency kind).
    dkSemantic      ## Content that changes the verdict: src/*.nim module
                    ## content, tests/gateway presence, @manual feature
                    ## presence, baseline, lock file.
    dkProvenance    ## Provenance metadata (e.g. commit id). Only used
                    ## by the optional P0 wrapper metadata — NOT by the
                    ## auditor itself.
    dkInternal      ## Self-generated / timestamped / history — does
                    ## NOT affect the verdict.
    dkOutput        ## Artifact the gate writes (not an input).
    dkUnclassified  ## A runtime read the model cannot yet prove semantic
                    ## or not — MUST fail-closed for any reuse.

func `$`*(k: VerificationDependencyKind): string {.raises: [].} =
  ## Human-readable name of a VerificationDependencyKind.
  case k
  of dkSemantic:   "SEMANTIC"
  of dkProvenance: "PROVENANCE"
  of dkInternal:   "INTERNAL"
  of dkOutput:     "OUTPUT"
  of dkUnclassified: "UNCLASSIFIED"

func `==`*(a, b: VerificationDependencyKind): bool {.raises: [].} =
  ## Equality for VerificationDependencyKind.
  $a == $b

# ---------------------------------------------------------------------------
# Read class — a named category of observable runtime read
# ---------------------------------------------------------------------------

type
  ReadClass* = enum
    ## Named category of an observable runtime read.
    rcModuleContent    ## Content of a source module (*.nim).
    rcModuleExistence  ## Existence check of a file/directory.
    rcTestGateway      ## Presence of tests/gateway fixtures.
    rcManualFeature    ## @manual feature presence.
    rcBaseline         ## Baseline data (data/verification_auditor_baseline.json).
    rcLockFile         ## Lock file (topology.lock).
    rcPolicy           ## Policy config (config/gates.json etc.).
    rcCommitId         ## Commit identifier (git HEAD).
    rcTimestamp        ## Timestamp / self-generated metadata.
    rcHistory          ## History / replay artifacts.
    rcGateOutput       ## Artifact the gate writes.
    rcEnvVar           ## Environment variable influence.
    rcCwd              ## Current working directory.
    rcCompilerSubprocess ## Compiler subprocess invocation.
    rcOther            ## Any other runtime read not in the list above.

func `$`*(rc: ReadClass): string {.raises: [].} =
  ## Human-readable name of a ReadClass.
  case rc
  of rcModuleContent:    "module_content"
  of rcModuleExistence:  "module_existence"
  of rcTestGateway:      "test_gateway"
  of rcManualFeature:    "manual_feature"
  of rcBaseline:         "baseline"
  of rcLockFile:         "lock_file"
  of rcPolicy:           "policy"
  of rcCommitId:         "commit_id"
  of rcTimestamp:        "timestamp"
  of rcHistory:          "history"
  of rcGateOutput:       "gate_output"
  of rcEnvVar:           "env_var"
  of rcCwd:              "cwd"
  of rcCompilerSubprocess: "compiler_subprocess"
  of rcOther:            "other"

# ---------------------------------------------------------------------------
# Per-gate classification contract (pure function)
# ---------------------------------------------------------------------------
## The verification-auditor reads module *content* + *existence* +
## *classification*; it does NOT depend on file size/mtime.
##
## Read classes the verification-auditor treats as:
##   SEMANTIC:  rcModuleContent, rcTestGateway, rcManualFeature,
##              rcBaseline, rcLockFile, rcPolicy
##   PROVENANCE: rcCommitId (only for optional P0 wrapper metadata,
##               NOT by the auditor itself)
##   INTERNAL:  rcTimestamp, rcHistory
##   OUTPUT:    rcGateOutput
##   UNCLASSIFIED: rcModuleExistence, rcEnvVar, rcCwd,
##               rcCompilerSubprocess, rcOther
##               (any VFS read or compiler-subprocess read that is not
##                proven to be a semantic input must be UNCLASSIFIED)

func classifyReadClass*(rc: ReadClass): VerificationDependencyKind {.raises: [].} =
  ## Return the VerificationDependencyKind for a ReadClass per the verification-
  ## auditor classification contract. Conservative: any read not
  ## explicitly listed as SEMANTIC is UNCLASSIFIED.
  case rc
  of rcModuleContent:   result = dkSemantic
  of rcModuleExistence: result = dkUnclassified
  of rcTestGateway:     result = dkSemantic
  of rcManualFeature:   result = dkSemantic
  of rcBaseline:        result = dkSemantic
  of rcLockFile:        result = dkSemantic
  of rcPolicy:          result = dkSemantic
  of rcCommitId:        result = dkProvenance
  of rcTimestamp:       result = dkInternal
  of rcHistory:         result = dkInternal
  of rcGateOutput:      result = dkOutput
  of rcEnvVar:          result = dkUnclassified
  of rcCwd:             result = dkUnclassified
  of rcCompilerSubprocess: result = dkUnclassified
  of rcOther:           result = dkUnclassified

func isSemantic*(rc: ReadClass): bool {.raises: [].} =
  ## True iff the read class is a declared SEMANTIC input for the
  ## verification-auditor gate.
  classifyReadClass(rc) == dkSemantic

func isProvenance*(rc: ReadClass): bool {.raises: [].} =
  ## True iff the read class is PROVENANCE (commit id for P0 wrapper).
  classifyReadClass(rc) == dkProvenance

func isInternal*(rc: ReadClass): bool {.raises: [].} =
  ## True iff the read class is INTERNAL (does not affect verdict).
  classifyReadClass(rc) == dkInternal

func isOutput*(rc: ReadClass): bool {.raises: [].} =
  ## True iff the read class is OUTPUT (artifact the gate writes).
  classifyReadClass(rc) == dkOutput

func isUnclassified*(rc: ReadClass): bool {.raises: [].} =
  ## True iff the read class is UNCLASSIFIED — must fail-closed.
  classifyReadClass(rc) == dkUnclassified

# ---------------------------------------------------------------------------
# Digest of the dependency kind set (for query identity / content hash)
# ---------------------------------------------------------------------------

type
  DependencyDigest* = distinct string
    ## SHA-256 hex digest of the canonical dependency kind set.

func newDependencyDigest*(hex: string): DependencyDigest =
  DependencyDigest(hex)

func `$`*(d: DependencyDigest): string {.raises: [].} = string(d)

## Compute a deterministic digest over all SEMANTIC dependency kinds
## present in the given read classes. Only SEMANTIC inputs contribute
## to the digest — PROVENANCE, INTERNAL, OUTPUT, UNCLASSIFIED are
## excluded (provenance is P0-wrapper-only; internal/output/unclassified
## do not affect the verdict).
func computeDependencyDigest*(reads: seq[ReadClass]): DependencyDigest {.raises: [].} =
  ## Sort the SEMANTIC read classes, concatenate, SHA-256, hex-encode.
  var semantic: seq[ReadClass] = @[]
  for r in reads:
    if isSemantic(r): semantic.add(r)
  semantic.sort(proc(a, b: ReadClass): int =
    if a.ord < b.ord: -1 elif a.ord > b.ord: 1 else: 0)
  var data = ""
  for i, r in semantic:
    if i > 0: data.add("|")
    data.add($r)
  if data.len == 0:
    DependencyDigest(hash_kernel.sha256Hex(""))
  else:
    DependencyDigest(hash_kernel.sha256Hex(data))

## Content digest of a single SEMANTIC read class (for per-dependency
## tracking in the observation pipeline).
func semanticContentDigest*(rc: ReadClass; content: string): string {.raises: [].} =
  ## SHA-256 of the read class name || content, only meaningful for
  ## SEMANTIC read classes.
  hash_kernel.sha256Hex($rc & ":" & content)

{.pop.}