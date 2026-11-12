import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
import std/options
import core/trusted/axiom_pragmas
import core/trusted/verification_model_types

## C14 — Semantic ↔ CHC Identity Preservation.
##
## Identity is STRUCTURAL and explicit; never restored by name-string guessing
## or formula equality. Identity is SEPARATED from ordering (C14):
##   * `TransitionIdentity`   — canonical semantic edge key (WHAT a transition is)
##   * `TransitionOrdinal`    — serialization order only (WHERE it appears)
## Identity and ordering are NEVER fused into one value.

type
  TransitionIdentity* = object
    ## Canonical semantic edge key. Guard/update keys are the canonical SMT
    ## serialization so identity is stable across representations.
    sourceNode*: NodeId
    targetNode*: NodeId
    guardKey*: string
    updateKey*: string

  TransitionOrdinal* = distinct int
    ## Serialization order ONLY. Separate from identity per C14.

# ── Construction / accessors ────────────────────────────────────
func transitionIdentityOf*(tr: Transition; guardKey, updateKey: string): TransitionIdentity {.axiomDecision(
      id = "DECISION-0027",
      reason = "Build the canonical semantic edge key of a transition without any serialization ordinal (C14 identity != ordering)",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v35"), raises: [].} =
  ## Build the canonical identity of a transition WITHOUT any serialization
  ## ordinal — identity must not depend on insertion order (C14).
  TransitionIdentity(sourceNode: tr.source, targetNode: tr.target,
                     guardKey: guardKey, updateKey: updateKey)

func canonicalKey*(id: TransitionIdentity): string {.axiomDecision(
      id = "DECISION-0102",
      reason = "Structural serialization of a transition identity (identity, not a digest) for deterministic indexing (C14)",
      adr = "docs/spec/cfg_contract_specification.md",
      introduced = "v35"), raises: [].} =
  ## Structural serialization of the identity (identity, not a digest).
  "T(" & $uint32(id.sourceNode) & "->" & $uint32(id.targetNode) &
    " g=" & id.guardKey & " u=" & id.updateKey & ")"

{.pop.}