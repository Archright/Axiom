import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [Exception].}
import std/[os, strutils, json]
import std/sets
import shared_types/cert_bridge
import shared_types/io_bridge
import core/proof/proof_universe_lock

const
  missingGreenFunctionsPath = "logs/missing_green_functions.json"
  defaultGraphPath = "logs/global_symbol_graph.json"
  defaultCertDir = "build/certificates"
  stagingTypeMapBaseDir = "build" / "staging" / "assets" / "type_mappings"

when isMainModule:
  let srcRoot = joinPath(getCurrentDir(), "src")
  let certDir = joinPath(getCurrentDir(), defaultCertDir)
  let missingListPath = joinPath(getCurrentDir(), missingGreenFunctionsPath)
  discard existsOrCreateDir(joinPath(getCurrentDir(), "logs"))
  var destructiveClean = false
  for i in 1 ..< paramCount():
    if paramStr(i) == "--destructive-clean":
      destructiveClean = true
  let functions = collectFunctions(srcRoot)
  let existingGreen = loadExistingGreenKeys(certDir)
  var missing: seq[FunctionRef] = @[]
  for fn in functions:
    if fn.modulePath & "#" & fn.name notin existingGreen:
      missing.add(fn)
  writeMissingList(missingListPath, missing)

  let graph = buildGlobalSymbolGraph(srcRoot)
  let gHash = graphHash(graph)
  let graphPath = joinPath(getCurrentDir(), defaultGraphPath)
  let dir = parentDir(graphPath)
  if dir.len > 0:
    discard existsOrCreateDir(dir)
  if not writeFileSafe(graphPath, $graphSnapshotJson(graph) & "\n"):
    stderr.writeLine("Failed to write graph to " & graphPath)

  writeCertificates(certDir, functions, gHash, destructiveClean)

  ## Asset staging (canonical mutation goes through promotion, never direct write).
  ## type_mappings are staged to build/staging/assets/type_mappings/ and promoted
  ## atomically via tools/promote_assets.nim (AssetPromotionBoundary).
  let typeMapCerts = generateTypeMappingCertificates()
  let typeMapDir = joinPath(getCurrentDir(), stagingTypeMapBaseDir)
  createDir(typeMapDir)
  for cert in typeMapCerts:
    let fname = normalizeIdentForFilename(cert.nimType) & ".json"
    let tpath = joinPath(typeMapDir, fname)
    let tnode = %*{
      "nimType": cert.nimType,
      "leanType": cert.leanType,
      "smtSort": cert.smtSort,
      "mappingProofObligation": cert.mappingProofObligation,
      "verified": cert.verified,
      "sourceHash": cert.sourceHash
    }
    try:
      if not writePrettyJsonFile(tpath, tnode):
        stderr.writeLine("Failed to write type mapping to " & tpath)
    except CatchableError: # axiom:best-effort(type mapping write failure is non-fatal; other certificates still generated)
      discard
  stdout.writeLine("typeMappingCertificates=" & $typeMapCerts.len)
  stdout.writeLine("typeMappingStagingDir=" & typeMapDir.replace("\\", "/"))

  stdout.writeLine("functions=" & $functions.len)
  stdout.writeLine("missingBeforeGeneration=" & $missing.len)
  stdout.writeLine("missingList=" & missingListPath.replace("\\", "/"))
  stdout.writeLine("globalSymbolGraph=" & graphPath.replace("\\", "/"))