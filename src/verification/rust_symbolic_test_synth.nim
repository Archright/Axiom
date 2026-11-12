import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Rust Symbolic Test Synthesis — model binding → Rust source literal
## projection + exact-input gate (S4 exact-input discipline).
##
## This module is the Rust-side counterpart of
## `verification/symbolic_test_synth.nim` (bindingToNimLiteral /
## modelToTestInputs, :170-223). The Nim path stays byte-stable; this module
## adds the language-partitioned projection for the Rust replay adapter
## (`verification/rust_replay_adapter.nim`) without touching it.
##
## Literal vocabulary (the certified replay subset — ConcreteValue is
## ckInt | ckBool, so only these are expressible end to end):
##   - BitVec64 → decimal integer literal ("42", "-7")
##   - Bool     → "true" / "false"
##   - List/String/Enum/Variant → "" (NOT expressible as a Rust literal in
##     the certified subset — fail-closed empty literal, never a guessed
##     placeholder; the adapter refuses to replay it)
##
## Exact-input gate: `modelToTestInputs` fills type-default literals for
## unbound parameters, which the Nim replay entry gates BEFORE mapping
## (counterexample_replay.nim:734-747 — "fail closed unless the model binds
## every subject parameter"). The Rust side keeps the same discipline but
## makes the gate explicit and pure here: `unboundParameters` names every
## parameter the model did not bind, and `modelToRustTestInputs` projects ""
## (never a default) for unbound parameters, so a partially bound model can
## never masquerade as a solver counterexample.

import std/strutils

import core/trusted/axiom_ir
import core/types/obligation_evidence  # ModelBinding
import verification/symbolic_test_synth  # z3BvHexToI64 — bit-exact bv64 hex decode (shared, language-neutral)

# ---------------------------------------------------------------------------
# Model binding → Rust source literal
# ---------------------------------------------------------------------------

func bindingToRustLiteral*(binding: ModelBinding; paramType: IRType): string {.raises: [].} =
  ## Convert a Z3 model binding to a Rust source literal string.
  ##
  ## - BitVec64 → UNSIGNED decimal string (e.g. ``"42"``,
  ##   ``"18446744073709551615"``) — the Rust lane's canonical types are
  ##   rsgUnsigned-only, so a bit63-set model value must print as its
  ##   unsigned decimal; the signed ``-1`` a raw int64 reinterpretation
  ##   would print neither compiles at a ``u64`` call site nor observes
  ##   exactly. Values below 2^63 print identically either way.
  ## - Bool     → ``"true"`` / ``"false"``
  ## - List/String/Enum/Variant → ``""`` (fail-closed: no Rust literal in the
  ##   certified subset; the adapter treats the empty literal as unplayable)
  case paramType.kind
  of irtBitVec64:
    # Value may be ``#x...`` hex or plain decimal (same shapes as the Nim path)
    if binding.value.len >= 18 and binding.value[0] == '#' and
       binding.value[1] == 'x':
      $cast[uint64](z3BvHexToI64(binding.value))
    else:
      binding.value.strip()
  of irtBool:
    if binding.value == "true": "true"
    else: "false"
  of irtList, irtString, irtEnum, irtVariant:
    ""  # fail-closed: outside the certified Rust-literal subset

# ---------------------------------------------------------------------------
# Exact-input gate (pure)
# ---------------------------------------------------------------------------

func unboundParameters*(bindings: seq[ModelBinding];
                        params: seq[IRFuncParam]): seq[string] {.raises: [].} =
  ## Names of subject parameters with NO model binding, in positional order.
  ## Empty result ⇔ the model binds every subject parameter — the only state
  ## the Rust replay adapter may replay (exact-input discipline;
  ## counterexample_replay.nim:734-747).
  result = @[]
  for p in params:
    var bound = false
    for b in bindings:
      if b.name == p.name:
        bound = true
        break
    if not bound:
      result.add(p.name)

# ---------------------------------------------------------------------------
# Model bindings → seq of Rust test-input literals
# ---------------------------------------------------------------------------

func modelToRustTestInputs*(bindings: seq[ModelBinding];
                            params: seq[IRFuncParam]): seq[string] {.raises: [].} =
  ## Match Z3 model bindings to IR function parameters by name and convert
  ## each to a Rust source literal, positional order.
  ##
  ## Unbound parameters project "" — NO type-default fill. The caller must
  ## run `unboundParameters` first and fail closed; the empty literal here is
  ## the honest projection of "nothing bound", never a usable replay input.
  result = newSeq[string](params.len)
  for pi, param in params:
    var found = false
    for b in bindings:
      if b.name == param.name:
        result[pi] = bindingToRustLiteral(b, param.ty)
        found = true
        break
    if not found:
      result[pi] = ""

{.pop.}
