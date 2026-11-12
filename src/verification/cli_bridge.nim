import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
##
## DEBT#001 + DEBT#006: SoC violation import cleanup.
## controlled access point. Future phases should move shared types to src/core/

import core/pipeline_core_types
export pipeline_core_types

import core/vault/vault_index
export vault_index

import verification/proof_state_convergence
export proof_state_convergence

import verification/proof_state_builder
export proof_state_builder

import verification/lean_lsp
# axiomIoBoundary
export lean_lsp

import verification/integrity_ledger
export integrity_ledger

import verification/state_manager
export state_manager

import verification/global_symbol_graph
export global_symbol_graph

import verification/static_rules
export static_rules

import verification/semantic_graph
export semantic_graph

import verification/leanstral_gateway
export leanstral_gateway

import verification/contract_source_extractor
export contract_source_extractor

import verification/proof_linkage
export proof_linkage

import verification/certificate_manager
export certificate_manager

import verification/leanstral_prompt
export leanstral_prompt

import verification/discovery_error
export discovery_error

import verification/proof_summarizer
export proof_summarizer

import verification/integrity_guard
export integrity_guard

import verification/ast_extractor
export ast_extractor

import verification/fingerprint_engine
export fingerprint_engine

import verification/cert_writer
export cert_writer

import verification/reporter
export reporter

import verification/thought_dashboard
export thought_dashboard

import verification/proof_synthesis_engine
export proof_synthesis_engine

import verification/lean_skeleton
export lean_skeleton
{.pop.}
