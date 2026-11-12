import core/trusted/layer_declaration
axiomLayer "infrastructure"
import std/os
import std/sets
import std/strutils
import std/options

import core/json/std_redirect
import core/utils/io_utils
import core/json/json_utils
import core/axiom_pragmas

import core/asset_collector
import verification/cert_fingerprinter
import verification/cert_vault_role
import verification/cert_writer
import verification/cert_vault_role
# axiomIoBoundary

{.push raises: [].}

proc loadExistingGreenKeys*(certDir: string): HashSet[string] {.refines: "src/verification/cert_builder_shadow.nim".} =
  result = initHashSet[string]()
  if not dirExists(certDir):
    return
  for certPath in walkPattern(joinPath(certDir, "*.json")):
    try:
      let nodeOpt = readJsonFile(certPath)
      if nodeOpt.isNone:
        continue
      let node = nodeOpt.get()
      if node.kind != JObject:
        continue
      let trusted = node{"trusted"}.getBool(false)
      let status = node{"status"}.getStr("").strip().toLowerAscii()
      let fn = node{"functionName"}.getStr("").strip()
      let modPath = node{"modulePath"}.getStr("").strip().replace("\\", "/")
      if trusted and (status == "green" or status == "certgreen") and fn.len > 0 and modPath.len > 0:
        result.incl(modPath & "#" & fn)
    except CatchableError: # axiom:best-effort(JSON traversal skip malformed entry)
      discard

proc writeCertificates*(certDir: string; functions: seq[FunctionRef]; graphFingerprint: string = ""; destructiveClean: bool = false; repoRoot: string = "") {.axiomDecision(id = "DECISION-0627", reason = "Write guard for canonical path enforced before batch certificate writing", adr = "docs/adr/0001-fail-closed-result-type.md", introduced = "v32"), raises: [CatchableError], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  let canonicalDir = resolveCertificate(cvCanonicalRead)
  let runtimeCanonicalDir = resolveCertificate(cvRuntimeCanonical)
  if (certDir.startsWith(canonicalDir) or certDir.startsWith(runtimeCanonicalDir)) and not promotionActive:
    raise newException(CatchableError, "DIRECT CANONICAL WRITE FORBIDDEN — must go through explicit promotion context (set promotionActive=true or use --promote flag)")
  try:
    discard existsOrCreateDir(certDir)
  except OSError, IOError:
    return
  if destructiveClean:
    var expectedIrHashes: seq[string]
    for fn in functions:
      if fn.irHash.len > 0:
        expectedIrHashes.add(fn.irHash)
    cleanOrphanCertificates(certDir, expectedIrHashes)
  for fn in functions:
    let certFileName = if fn.irHash.len > 0: fn.irHash & ".json" else: fn.name & ".json"
    let certPath = joinPath(certDir, certFileName)
    if not destructiveClean and fileExists(certPath):
      continue
    let (fingerprint, body) = fingerprintFunction(fn.sourcePath, fn.name)
    if body.len == 0:
      continue
    try:
      if not writeCertificateWithFingerprint(certPath, fn, fingerprint, body, graphFingerprint):
        discard  # write failure is non-fatal; {.raises: [].} prevents stderr logging
    except CatchableError: # axiom:best-effort(cert write failure is non-fatal)
      discard
{.pop.}