import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Contract Source Extractor — Source-level contract extraction using AST.
## Moved from src/core/contract_extractor.nim to resolve Domain->Infrastructure
## import violation (verification/ast_extractor).

import std/strutils
import std/os
import std/tables
import core/utils/io_utils
import core/results
import core/contract/contract_types as ct
import core/contract/contract_param_util as cparam
import core/contract/contract_ast_extractor as castex
import core/encoding/smtlib2_util as su
import core/results as res
import verification/ast_extractor as astex
import ../core/trusted/axiom_pragmas
# axiomIoBoundary

export ct.ExtractedContract

## Extract contract from source file for a given function.
proc extractContractFromSource*(modulePath, functionName: string): ct.ExtractedContract {.raises: [], axiom: ["(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0)))", "modulePath.length ≥ 0 ∧ functionName.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(modulePath):
    return ct.ExtractedContract()
  try:
    let readRes = readFileOpt(modulePath)
    if readRes.isErr: return
    let source = readRes.get
    ## Extract parameters up-front for Type-Driven Contract Synthesis.
    var params: seq[(string, string)] = @[]
    let extractedRes = astex.extractFunctionBody(source, functionName)
    if extractedRes.isOk:
      let data = res.get(extractedRes)
      if data.found and data.body.len > 0:
        let firstLine = data.body.splitLines()[0]
        params = cparam.detectParams(firstLine)
    if su.isCertifiedExemptFunctionSource(source, functionName):
      return ct.ExtractedContract()
    ## Phase 0.5: AST-based structural impossibility heuristic.
    try:
      let indexRes = astex.getCachedFunctionNodeIndex(source)
      if indexRes.isOk:
        let index = res.get(indexRes)
        if index.hasKey(functionName):
          let fnNode = index.getOrDefault(functionName)
          if castex.scanAstForCertifiedExemptionP(fnNode, functionName):
            return ct.ExtractedContract()
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    ## Phase 0: @axiom-hint annotation takes precedence.
    let hintSmt = su.extractAxiomHintForFunction(source, functionName)
    if hintSmt.len > 0:
      result.preconditions.add(hintSmt)
      for tc in cparam.generateTypeDrivenContracts(params):
        result.preconditions.add(tc)
      return result
    ## Phase 1: AST-based extraction from cached function node.
    let indexRes = astex.getCachedFunctionNodeIndex(source)
    if indexRes.isOk:
      let index = res.get(indexRes)
      if index.hasKey(functionName):
        let fnNode = index.getOrDefault(functionName)
        let contract = castex.extractContractFromAstP(functionName, fnNode, params)
        result = contract
        for tc in cparam.generateTypeDrivenContracts(params):
          result.preconditions.add(tc)
        return result
    ## Phase 2: Type-Driven Contract Synthesis fallback when AST yields nothing.
    for tc in cparam.generateTypeDrivenContracts(params):
      result.preconditions.add(tc)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  return result

## Extract contract and parameters from source file.
proc extractContractAndParams*(modulePath, functionName: string): (ct.ExtractedContract, seq[(string, string)]) {.raises: [], axiom: ["(assert (and (>= (str.len modulePath) 0) (>= (str.len functionName) 0)))", "modulePath.length ≥ 0 ∧ functionName.length ≥ 0"], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  if not fileExists(modulePath):
    return (ct.ExtractedContract(), @[])
  try:
    let readRes = readFileOpt(modulePath)
    if readRes.isErr: return
    let source = readRes.get
    ## Extract parameters up-front for Type-Driven Contract Synthesis.
    var params: seq[(string, string)] = @[]
    let extractedRes = astex.extractFunctionBody(source, functionName)
    if extractedRes.isOk:
      let data = res.get(extractedRes)
      if data.found and data.body.len > 0:
        let firstLine = data.body.splitLines()[0]
        params = cparam.detectParams(firstLine)
    if su.isCertifiedExemptFunctionSource(source, functionName):
      return (ct.ExtractedContract(), params)
    ## Phase 0.5: AST-based structural impossibility heuristic.
    try:
      let indexRes = astex.getCachedFunctionNodeIndex(source)
      if indexRes.isOk:
        let index = res.get(indexRes)
        if index.hasKey(functionName):
          let fnNode = index.getOrDefault(functionName)
          if castex.scanAstForCertifiedExemptionP(fnNode, functionName):
            return (ct.ExtractedContract(), params)
    except CatchableError:
      discard  # axiom:best-effort(ioboundary catch)
    ## Phase 0: @axiom-hint annotation takes precedence.
    let hintSmt = su.extractAxiomHintForFunction(source, functionName)
    if hintSmt.len > 0:
      var contract = ct.ExtractedContract()
      contract.preconditions.add(hintSmt)
      for tc in cparam.generateTypeDrivenContracts(params):
        contract.preconditions.add(tc)
      return (contract, params)
    ## Phase 1: AST-based extraction.
    let indexRes = astex.getCachedFunctionNodeIndex(source)
    if indexRes.isOk:
      let index = res.get(indexRes)
      if index.hasKey(functionName):
        let fnNode = index.getOrDefault(functionName)
        let contract = castex.extractContractFromAstP(functionName, fnNode, params)
        var outContract = contract
        for tc in cparam.generateTypeDrivenContracts(params):
          outContract.preconditions.add(tc)
        return (outContract, params)
    ## Phase 2: Type-Driven Contract Synthesis fallback.
    var outContract = ct.ExtractedContract()
    for tc in cparam.generateTypeDrivenContracts(params):
      outContract.preconditions.add(tc)
    return (outContract, params)
  except CatchableError:
    discard  # axiom:best-effort(ioboundary catch)
  (ct.ExtractedContract(), @[])
{.pop.}
