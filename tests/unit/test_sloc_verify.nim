import unittest
import sloc_verify
import core/results
import core/ast_kernel
import core/sloc_policy
import std/[json, sets, strutils, options]

suite "sloc_verify negative cases":

  test "case 1 - fixture hash mismatch returns err":
    let result = step1FixtureIntegrity("proc f() =\n  result = 1", "0000000000000000000000000000000000000000000000000000000000000000")
    check result.isErr

  test "case 2 - unknown semantic pattern (missing SLOC-WHEN-UNKNOWN in registry) returns err":
    let registry = %*{"schema_version": 1, "policy_version": "effective-sloc-policy-v1", "rules": [{"rule_id": "SLOC-PROC-DECL", "semantic_category": "declaration"}]}
    let policyRefs = @["SLOC-WHEN-UNKNOWN"]
    let registryRules = getRegistryRules(registry)
    let result = step4PolicyCoverage(policyRefs, registryRules, "effectiveSloc", "err:urMissingSemanticContext", "proc f() = discard", registry)
    check result.isErr

  test "case 3 - unknown rule in policy_refs returns err":
    let registry = %*{"schema_version": 1, "policy_version": "effective-sloc-policy-v1", "rules": [{"rule_id": "SLOC-PROC-DECL", "semantic_category": "declaration"}]}
    let policyRefs = @["SLOC-NONEXISTENT-RULE"]
    let registryRules = getRegistryRules(registry)
    let result = step4PolicyCoverage(policyRefs, registryRules, "sourceSloc", "3", "proc f() = discard", registry)
    check result.isErr

  test "case 8 - unratified semantic category (import not in registry) returns err":
    let registry = %*{"schema_version": 1, "policy_version": "effective-sloc-policy-v1", "rules": [{"rule_id": "SLOC-PROC-DECL", "semantic_category": "declaration"}]}
    let policyRefs = @["SLOC-PROC-DECL"]
    let registryRules = getRegistryRules(registry)
    let result = step4PolicyCoverage(policyRefs, registryRules, "sourceSloc", "2", "import os\nproc f() = discard", registry)
    check result.isErr

  test "case 9 - ratified semantic category passes coverage check":
    let registry = %*{"schema_version": 1, "policy_version": "effective-sloc-policy-v1", "rules": [{"rule_id": "SLOC-PROC-DECL", "semantic_category": "declaration"}, {"rule_id": "SLOC-COMMENT-EXCLUDED", "semantic_category": "comment"}]}
    let policyRefs = @["SLOC-PROC-DECL"]
    let registryRules = getRegistryRules(registry)
    let result = step4PolicyCoverage(policyRefs, registryRules, "sourceSloc", "2", "proc f() =\n  # comment\n  discard", registry)
    check result.isOk

  test "case 4 - missing evidence (nil expected_result) returns err":
    let result = step5EvidenceMatch("3", nil)
    check result.isErr

  test "case 5 - context mismatch returns err":
    var knownCtx: HashSet[string]
    knownCtx.incl("posix")
    let currentCtx = some(WhenContext(defines: DefineContext(knownDefined: knownCtx, knownUndefined: initHashSet[string]())))
    let evContext = %*{"defines": {"knownDefined": ["windows"], "knownUndefined": []}}
    let result = step2EvidenceIdentity("effectiveSloc", evContext, "effectiveSloc", currentCtx)
    check result.isErr

  test "case 6 - expected result mismatch returns err":
    let result = step5EvidenceMatch("3", %*4)
    check result.isErr

  test "case 7 - policy version mismatch returns err":
    let result = step6PolicyVersion("effective-sloc-policy-v1", "different-policy-version")
    check result.isErr
