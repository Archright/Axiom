import core/trusted/layer_declaration
axiomLayer "domain"
# src/core/solver/interfaces.nim — Compile-time interface contracts
#
# Nim concept types that enforce SOLID/LSP/DIP at compile time.
# Violations become compiler errors, not gate warnings.
#
# Context7 reference: /nim-lang/nim "Nim Generics: Procs, Types, and Concepts"

{.push raises: [].}
# axiomIoBoundary

import core/types/results

type
  ProverInterface* = concept x
    x.prove("", 0) is bool
    x.name() is string

  ProverOutputInterface* = concept x
    ## Extended prover concept that exposes the raw solver output.
    ## Used by the constructive witness path to extract unsat cores.
    x.proveWithOutput("", 0) is Result[string, string]
    x.name() is string

  GateInterface* = concept x
    x.inspect("") is bool
    x.ruleName() is string

{.pop.}
