import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Gate Rule Adapter — Consolidates verification→gate coupling to ONE file.
##
## AGENTS.md §1.2: Domain never imports Gate.
## This adapter lives in Infrastructure (verification/) and is the SINGLE point
## where gate rule functions are called. All analyzer stages import from here
## instead of importing gate/ directly.
##
## CONSTRAINT: This file MUST contain ONLY import/export statements.
## No business logic, no type definitions, no proc implementations.
## Violation = SoC breach.
##
## Future migration: Move pure apply*Gate functions to core/gate_evaluators.nim
## since they operate only on Domain types (FunctionCertificate, GateDirectiveBundle).

import core/domain_types
export domain_types

import gate/gate_rules
# axiomIoBoundary
export gate_rules

import gate/gate_registry
export gate_registry

import gate/gate_rules_normalization
export gate_rules_normalization

import core/gate/gate_evaluators
export gate_evaluators
{.pop.}
