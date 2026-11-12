import core/trusted/layer_declaration
axiomLayer "domain"
import ../../core/trusted/axiom_pragmas
# axiomIoBoundary

## Build an SMT-LIB2 >= assertion for a variable.
func smtGteZero*(varName: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0)))", "varName.length ≥ 0"].} =
  "(assert (>= " & varName & " 0))"

## Build an SMT-LIB2 < len assertion.
func smtLtLen*(varName, container: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0) (>= (str.len container) 0)))", "varName.length ≥ 0 ∧ container.length ≥ 0"].} =
  "(assert (< " & varName & " (seq.len " & container & ")))"

## Build an SMT-LIB2 str.len < assertion.
func smtStrLtLen*(varName, container: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0) (>= (str.len container) 0)))", "varName.length ≥ 0 ∧ container.length ≥ 0"].} =
  "(assert (< " & varName & " (str.len " & container & ")))"

## Build an SMT-LIB2 non-zero assertion.
func smtNonZero*(varName: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0)))", "varName.length ≥ 0"].} =
  "(assert (not (= " & varName & " 0)))"

## Build an SMT-LIB2 str.len >= 0 assertion.
func smtStrLenPos*(varName: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0)))", "varName.length ≥ 0"].} =
  "(assert (>= (str.len " & varName & ") 0))"

## Build an SMT-LIB2 seq.len >= 0 assertion.
func smtSeqLenPos*(varName: string): string {.raises: [], axiom: ["(assert (and (>= (str.len varName) 0)))", "varName.length ≥ 0"].} =
  "(assert (>= (seq.len " & varName & ") 0))"
