## VS-2 P0-1 fixture subject module (REGISTRY_SPEC.md §4).
##
## NOT A REAL DEFECT ADOPTION: this module is a grammar exercise for the
## external-subject binding registry's constructed-gate capability. It is
## structurally isomorphic to a four-member equality gate; it is NOT a copy
## of any governed subject, carries no repository/commit provenance of a
## real tree, and no adoption record references it. The only consumer is
## tests/unit/test_external_subject_registry.nim, which drives the generic
## registry loader with specDir pointed at tests/fixtures/spec_overlays/.
##
## The directory layout (fixture_gate_subject/fixture_gate_subject.nim)
## mirrors the subject-module shape the constructed-gate replay-import
## derivation requires (a module inside a package directory:
## <dir>/<name>.nim → import <dir>).

proc gateAccept*(c: int): bool {.raises: [].} =
  ## Four-member equality gate over {2, 9, 11, 127}-shaped values — the
  ## fixture defect model the synthesized carrier states.
  c == 2 or c == 9 or c == 11 or c == 127

proc gateLetVariant*(c: int): bool {.raises: [].} =
  ## Let-binding-carrying variant: the adapter-level pure-expression scope
  ## rejection (the one real let-binding guard in the PR-0 engine — the
  ## body-carry family's "carries let-bindings outside the pure-expression
  ## scope" rule) is exercised against this shape by the test.
  let doubled = c * 2
  doubled == 18 or c == 127
