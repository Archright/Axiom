import std/[os, strutils]

import core/results
import verification/ast_extractor
import verification/fingerprint_engine

type
  AsiReportFixture* = object
    tempRoot*: string
    srcRoot*: string
    certRoot*: string
    sourcePath*: string
    certPath*: string

proc cleanupFixture*(fixture: AsiReportFixture) =
  if dirExists(fixture.tempRoot):
    removeDir(fixture.tempRoot)

proc createAsiReportFixture*(
  name: string;
  changedAfterCertificate: bool = false
): AsiReportFixture =
  result.tempRoot = joinPath("logs", name)
  result.srcRoot = joinPath(result.tempRoot, "src")
  result.certRoot = joinPath(result.tempRoot, "certs")
  if dirExists(result.tempRoot):
    removeDir(result.tempRoot)
  discard existsOrCreateDir(result.tempRoot)
  discard existsOrCreateDir(result.srcRoot)
  discard existsOrCreateDir(result.certRoot)

  result.sourcePath = joinPath(result.srcRoot, "safe.nim")
  result.certPath = joinPath(result.certRoot, "safe.json")
  writeFile(result.sourcePath, """
proc safe*(x: int): int {.raises: [].} =
  assert x >= 0
  x
""".strip())

  let fingerprint = block:
    let extractedRes = extractFunctionBody(readFile(result.sourcePath), "safe")
    if extractedRes.isOk:
      computeFingerprint(extractedRes.get().body, @["assert x >= 0"])
    else:
      "fallback:fnv1a64:0"
  let structural = block:
    let extractedRes = extractFunctionBody(readFile(result.sourcePath), "safe")
    if extractedRes.isOk:
      computeStructuralFingerprintCandidates(
        extractedRes.get().body,
        @["assert x >= 0"],
        "safe"
      )[0]
    else:
      "fallback:structural:0"
  writeFile(result.certPath, """
{
  "functionName": "safe",
  "modulePath": "$1",
  "fingerprint": "$2",
  "currentFingerprint": "$2",
  "structuralFingerprint": "$3",
  "trusted": true,
  "winningStrategy": "gateway-fixture",
  "constraints": ["assert x >= 0"]
}
""".strip()
    .replace("$1", result.sourcePath.replace("\\", "/"))
    .replace("$2", fingerprint)
    .replace("$3", structural))

  if changedAfterCertificate:
    writeFile(result.sourcePath, """
proc safe*(value: int): int {.raises: [].} =
  assert value >= 0
  value
""".strip())

proc createDefaultLayoutAsiReportFixture*(name: string): AsiReportFixture =
  result.tempRoot = joinPath("logs", name)
  result.srcRoot = joinPath(result.tempRoot, "src")
  result.certRoot = joinPath(result.srcRoot, "verification", "certificates")
  if dirExists(result.tempRoot):
    removeDir(result.tempRoot)
  discard existsOrCreateDir(result.tempRoot)
  discard existsOrCreateDir(result.srcRoot)
  discard existsOrCreateDir(joinPath(result.srcRoot, "verification"))
  discard existsOrCreateDir(result.certRoot)

  result.sourcePath = joinPath(result.srcRoot, "safe.nim")
  result.certPath = joinPath(result.certRoot, "safe.json")
  writeFile(result.sourcePath, """
proc safe*(x: int): int {.raises: [].} =
  assert x >= 0
  x
""".strip())

  let fingerprint = block:
    let extractedRes = extractFunctionBody(readFile(result.sourcePath), "safe")
    if extractedRes.isOk:
      computeFingerprint(extractedRes.get().body, @["assert x >= 0"])
    else:
      "fallback:fnv1a64:0"
  let structural = block:
    let extractedRes = extractFunctionBody(readFile(result.sourcePath), "safe")
    if extractedRes.isOk:
      computeStructuralFingerprintCandidates(
        extractedRes.get().body,
        @["assert x >= 0"],
        "safe"
      )[0]
    else:
      "fallback:structural:0"
  writeFile(result.certPath, """
{
  "functionName": "safe",
  "modulePath": "safe.nim",
  "fingerprint": "$1",
  "currentFingerprint": "$1",
  "structuralFingerprint": "$2",
  "trusted": true,
  "winningStrategy": "gateway-fixture",
  "constraints": ["assert x >= 0"]
}
""".strip()
    .replace("$1", fingerprint)
    .replace("$2", structural))
