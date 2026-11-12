## P0.3.11 — C13 theater-kill contract tests for ChcBuildResult.
## Verifies the explicit success/failure classification that replaces the
## silent "" / none(string) VM→CHC contract (docs/spec/cfg_contract_specification.md §C12/C13).
## A canonical CHC build declined as NotApplicable must NEVER be mis-typed as
## Unsupported (semantics gap vs capability gap).

import std/unittest
import core/trusted/private/chc_build_result

suite "ChcBuildResult — C13 classification":
  test "success carries the program":
    let r = chcBuildSuccess("(check-sat)")
    check r.kind == cbSuccess
    check r.program == "(check-sat)"
    check chcBuildMessage(r) == ""

  test "not-applicable is distinct from unsupported":
    let na = chcBuildNotApplicable(cnaNoObligations)
    let un = chcBuildUnsupported(cusNotLoop)
    check na.kind == cbNotApplicable
    check un.kind == cbUnsupported
    # Semantics gap (vacuous) vs capability gap — MUST be distinguishable.
    check na.kind != un.kind
    check chcBuildMessage(na) == "not-applicable:cnaNoObligations"
    check chcBuildMessage(un) == "unsupported:cusNotLoop"

  test "invalid-model carries diagnostics":
    let r = chcBuildInvalidModel(["cimDegenerateStateArity"])
    check r.kind == cbInvalidModel
    check r.diagnostics == @["cimDegenerateStateArity"]

  test "internal-error separates from everything":
    let r = chcBuildInternalError("boom")
    check r.kind == cbInternalError
    check r.errorDiagnostics == @["boom"]
    check r.kind != cbSuccess and r.kind != cbNotApplicable and r.kind != cbUnsupported and r.kind != cbInvalidModel