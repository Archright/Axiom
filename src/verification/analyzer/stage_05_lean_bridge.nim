import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [CatchableError].}

import core/axiom_pragmas
import core/domain_types
import core/domain_utils
import core/json/json_utils
import core/json/std_redirect
import core/judge/the_judge_eval
import core/orchestrator/cfg_builder
import core/parsers/pnode_nav
import core/parser_utils
import core/symbolic/global_symbol_graph_types
import core/symbolic_types_expr
import core/type_system/liquid_inference
import core/utils/file_utils
import std/options
import std/os
import std/sequtils
import std/tables
import compiler/ast
import verification/abstract_provider
import verification/analyzer/analyzer_shared_json
import verification/certificate_applier
import verification/gate_rule_adapter
import verification/lean_lsp
import verification/loop_invariant_synthesis
import verification/solver/provers
import verification/state_manager
import verification/translation_validator
proc runSymbolicAnalysis*(result: var VerificationReportSummary;
    graph: GlobalSymbolGraph; certDir: string; repoRoot: string;
    enableSymbolic: bool) {.raises: [CatchableError].} =
  let auditPath = joinPath(repoRoot, "logs", "audit", "stream.jsonl")
  # Symbolic invariant analysis for certGreen functions with TranslationValidator
  var cfgResults = initTable[string, CfgAnalysisResult]()
  var semanticResults = initTable[string, TranslationValidationResult]()
  if enableSymbolic:
    var parsedFiles = initTable[string, PNode]() # modulePath -> AST cache
    var leanArtifactDir = joinPath(repoRoot, "logs", "lean_validation")
    discard existsOrCreateDir(leanArtifactDir)
    # Cache for Lean validation results to avoid re-compiling on subsequent runs
    var leanValidationCachePath = joinPath(repoRoot, "logs", "lean_validation_cache.json")
    var leanValidationCache = initTable[string, JsonNode]()
    if fileExists(leanValidationCachePath):
      let cacheOpt = readJsonFile(leanValidationCachePath)
      if cacheOpt.isSome:
        let cacheNode = cacheOpt.get()
        if cacheNode.kind == JObject:
          for k, v in cacheNode:
            leanValidationCache[k] = v

    for cert in result.certificates:
      if cert.status != certGreen:
        continue
      let qn = qualifiedName(cert)
      var cfgRes = CfgAnalysisResult(
        hasLoops: false,
        hasUnsupported: false,
        loopInvariants: initTable[int, SymSExpr](),
        unsupportedReason: ""
      )
      let moduleFile = string(cert.modulePath)
      if moduleFile.len == 0 or not fileExists(moduleFile):
        cfgResults[qn] = cfgRes
        continue
      try:
        var ast: PNode = nil
        if parsedFiles.hasKey(moduleFile):
          ast = parsedFiles[moduleFile]
        else:
          let src = readFileSafe(moduleFile)
          ast = parseStringAST(src)
          parsedFiles[moduleFile] = ast
        let fnOpt = findFunctionNodeP(ast, cert.functionName)
        if options.isSome(fnOpt):
          let fnNode = options.get(fnOpt)
          let liquidState = inferLiquidTypeEnvP(fnNode)
          let liquidCandidates = envToInvariantCandidates(liquidState)
          let liquidAsserts = envToLiquidSmtAsserts(liquidState)
          let cfg = buildCfgFromAstP(fnNode)
          let loopHeaders = findLoopHeaders(cfg)
          cfgRes.hasLoops = loopHeaders.len > 0
          if cfgRes.hasLoops:
            for headerId in loopHeaders:
              # Phase 5: Layer 1 — Abstract Context Analysis
              let intervals = analyzeVariableIntervalsAtLoopHeader(cfg, headerId)
              let loopCond = extractLoopConditionFromHeader(cfg, headerId)
              let indVars = detectInductionVariables(cfg, headerId)
              var abstractCtx = AbstractContext(
                intervals: intervals,
                loopCondition: loopCond,
                inductionVars: indVars,
                candidateInvariants: @[]
              )
              let layer1Candidates = deriveInvariantCandidates(abstractCtx)
              let initAsserts = buildInitiationAsserts(abstractCtx)
              let candidateInvariants = mergeInvariantCandidates(
                  layer1Candidates, liquidCandidates)
              let initiationContext = mergeStringEvidence(initAsserts, liquidAsserts)

              let invOpt = synthesizeLoopInvariant(
                cfg, headerId,
                proc(query: string): bool {.closure, gcsafe.} =
                if executeProof(Z3PoolProver(), query, 5000):
                  return true
                return executeProof(LeanProver(), query, 5000),
                candidateInvariants,
                initiationContext
              )
              if options.isSome(invOpt):
                let inv = options.get(invOpt)
                cfgRes.loopInvariants[headerId] = inv

                # Phase 5/6 Audit: context_injected_synthesis_success
                let isLayer1 = layer1Candidates.anyIt(sExprToString(it) ==
                    sExprToString(inv))
                let isLiquid = liquidCandidates.anyIt(sExprToString(it) ==
                    sExprToString(inv))
                let payload = %*{
                  "function": qn,
                  "headerId": headerId,
                  "layer": (if isLiquid: 6 elif isLayer1: 1 else: 2),
                  "invariant": sExprToString(inv),
                  "initAsserts": initiationContext,
                  "liquidTypes": envToJson(liquidState),
                  "liquidCandidateCount": liquidCandidates.len,
                  "abstractIntervals": (block:
                  var ivMap = newJObject()
                  for k, v in intervals:
                    ivMap[k] = %intervalToString(v)
                  ivMap
                )
                }
                discard appendGenericAuditEvent(auditPath,
                    "context_injected_synthesis_success", qn, payload)

                # Phase 4: TranslationValidator cross-verification
                # Lightweight Z3 semantic equivalence check (fast)
                var finalRes = TranslationValidationResult(
                  equivalent: false,
                  nimSmt2: "",
                  leanSmt2: "",
                  z3OutputFwd: "",
                  z3OutputBwd: "",
                  message: "semantic equivalence check bypassed",
                  verifiedByZ3: false,
                  verifiedByLean: false
                )

                # Lean 4 cross-validation (slower): use cache when available
                var leanVerified = false
                let cacheKey = qn & "_" & sExprToString(inv)
                if leanValidationCache.hasKey(cacheKey):
                  leanVerified = leanValidationCache[cacheKey].getOrDefault(
                      "verified").getBool()
                  let cachePayload = %*{"cacheHit": true,
                      "verified": leanVerified, "cacheKey": cacheKey,
                      "cacheFilePath": leanValidationCachePath}
                  discard appendGenericAuditEvent(auditPath,
                      "lean_validation_cache", qn, cachePayload)
                else:
                  let leanTheorem = buildLeanTheoremFromInvariant(cert.functionName, inv)
                  let leanPath = joinPath(leanArtifactDir, cert.functionName & "_inv.lean")
                  let negPath = joinPath(leanArtifactDir, cert.functionName & "_inv_neg.lean")
                  let leanResult = verifyGeneratedLeanSourceWithCompiler(
                    leanTheorem, leanPath,
                    buildLeanNegativeTest(cert.functionName, inv), negPath
                  )
                  leanVerified = leanResult.verified
                  # Update cache
                  leanValidationCache[cacheKey] = %*{"verified": leanVerified,
                      "leanSmt2": finalRes.leanSmt2}
                  let cachePayload = %*{"cacheHit": false,
                      "verified": leanVerified, "cacheKey": cacheKey,
                      "leanPath": leanPath, "negPath": negPath,
                      "cacheFilePath": leanValidationCachePath}
                  discard appendGenericAuditEvent(auditPath,
                      "lean_validation_cache", qn, cachePayload)

                finalRes.verifiedByLean = leanVerified
                semanticResults[qn] = finalRes

                # Audit log: semantic equivalence confirmed
                if finalRes.equivalent and leanVerified:
                  var payload2 = newJObject()
                  payload2["function"] = %qn
                  payload2["nimInvariant"] = %finalRes.nimSmt2
                  payload2["leanProposition"] = %finalRes.leanSmt2
                  payload2["z3Verified"] = %finalRes.verifiedByZ3
                  payload2["leanVerified"] = %finalRes.verifiedByLean
                  discard appendGenericAuditEvent(auditPath,
                      "semantic_equivalence_confirmed", qn, payload2)
      except CatchableError:
        cfgRes.hasUnsupported = true
        cfgRes.unsupportedReason = "parse-or-cfg-error"
      cfgResults[qn] = cfgRes

    # Persist Lean validation cache
    var cacheObj = newJObject()
    for k, v in leanValidationCache:
      cacheObj[k] = v
    discard writePrettyJsonFile(leanValidationCachePath, cacheObj)

  let bundle = applySymbolicInvariantGate(result.certificates, cfgResults)
  result.symbolicInvariantGate = bundle.gateResult
  applyDirectives(result.certificates, bundle.directives)

  # Apply Phase 4 Semantic Integrity through the OCP gate registry.
  # Non-symbolic runs keep this gate empty to avoid mass missing-validation warnings.
  result.semanticIntegrityGate = runSemanticIntegrityGate(
    result.certificates,
    semanticResults,
    enabled = enableSymbolic
  )




{.pop.}
