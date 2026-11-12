# corpus_probe.nim — Signature corpus probe for WP4-i structural ingress
# Build from Axiom repo root:
#   nim c --path:src --path:tools --path:<user-home>/.choosenim/toolchains/nim-2.2.10 -o:/tmp/corpus_probe probe/corpus_probe.nim
# Run: /tmp/corpus_probe

import compiler/ast
import core/results
import core/parser_utils
import core/parsers/pnode_nav
import std/json
import std/options
import std/os
import std/strutils
import std/tables

# ── Corpus cases ──────────────────────────────────
type CorpusCase = object
  name*: string
  source*: string

let corpusCases = @[
  CorpusCase(name: "case0_func_real", source: """func getBitsBE*(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): T =
  ## Treats `data` as an unsigned big endian integer and returns a slice of bits
  ## extracted from it, assuming 0 to be the possition of the most significant bit.
  let totalBits = data.len * 8

  template normalizeIdx(idx): int =
    when idx is BackwardsIndex: totalBits - int(idx)
    else: int(idx)

  let
    a = normalizeIdx(slice.a)
    b = normalizeIdx(slice.b) + 1
    sliceLen = b - a

  const resultBits = sizeof(result) * 8
  doAssert a < b and sliceLen <= resultBits and b <= totalBits

  let limbs = cast[ptr UncheckedArray[T]](unsafeAddr data[0])

  template readLimb(idx: int): auto =
    when cpuEndian == bigEndian or sizeof(result) == 1:
      limbs[][idx]
    else:
      swapBytes(limbs[][idx])

  let
    firstLimbIdx = a div resultBits
    firstLimbUnusedBits = (a mod resultBits)
    firstLimbUsedBits = resultBits - firstLimbUnusedBits
    firstLimb = readLimb firstLimbIdx

  if sliceLen > firstLimbUsedBits:
    let
      bitsFromSecondLimb = sliceLen - firstLimbUsedBits
      secondLimb = readLimb(firstLimbIdx + 1)
    ((firstLimb shl firstLimbUnusedBits) shr (firstLimbUnusedBits - bitsFromSecondLimb)) or
    (secondLimb shr (resultBits - bitsFromSecondLimb))
  else:
    (firstLimb shl firstLimbUnusedBits) shr (resultBits - sliceLen)"""),
  CorpusCase(name: "case0_template_real", source: """template getBitsBE*(data: openArray[byte], slice: HSlice): BiggestUInt =
  getBitsBE(data, slice, BiggestUInt)"""),
  CorpusCase(name: "case1_int", source: "func probe(a: int): int = a"),
  CorpusCase(name: "case2_seq", source: "func probe(a: seq[byte]): int = 0"),
  CorpusCase(name: "case3_openarray", source: "func probe(a: openArray[byte]): int = 0"),
  CorpusCase(name: "case4_hslice", source: "proc probe(s: HSlice): int = 0"),
  CorpusCase(name: "case5_typedesc", source: "func probe(T: typedesc[int]): int = 0"),
  CorpusCase(name: "case6_typeset", source: "func probe(T: type[SomeUnsignedInt]): int = 0"),
  CorpusCase(name: "case7_oa_hslice", source: "func probe(a: openArray[byte], s: HSlice): int = 0"),
  CorpusCase(name: "case8_full", source: "func probe(data: openArray[byte], slice: HSlice, T: type[SomeUnsignedInt]): int = 0"),
  CorpusCase(name: "case_empty", source: "")
]

# ── AST extraction helpers ──────────────────────────
func stripExportMarker*(name: string): string =
  if name.endsWith("*"): name[0 .. ^2] else: name

func extractParamsFromProcNode*(procNode: PNode): seq[tuple[name: string, typ: string]] =
  if procNode.isNil: return
  for child in procNode:
    if child.isNil: continue
    if child.kind == nkFormalParams:
      for paramNode in child:
        if paramNode.isNil: continue
        if paramNode.kind == nkIdentDefs and paramNode.len >= 2:
          let paramName = pNodeText(paramNode[0])
          let paramType = pNodeText(paramNode[1])
          if paramName.len > 0:
            result.add((name: paramName, typ: paramType))
        elif paramNode.kind == nkIdentDefs and paramNode.len == 1:
          let paramName = pNodeText(paramNode[0])
          if paramName.len > 0:
            result.add((name: paramName, typ: ""))

func extractGenericParams*(procNode: PNode): seq[string] =
  if procNode.isNil: return
  for child in procNode:
    if child.isNil: continue
    if child.kind == nkGenericParams:
      for gp in child:
        if gp.isNil: continue
        if gp.kind == nkIdentDefs and gp.len >= 1:
          let gpName = pNodeText(gp[0])
          if gpName.len > 0:
            result.add(gpName)
        elif gp.kind == nkIdent:
          let gpName = pNodeText(gp)
          if gpName.len > 0:
            result.add(gpName)

func extractProcInfo*(ast: PNode): seq[Table[string, string]] =
  for node in findNodesP(ast, ProcDefKinds):
    var info: Table[string, string]
    if node.len > 0 and not node[0].isNil:
      let nameNode = findFirstNodeP(node[0], {nkIdent})
      if nameNode.isSome():
        let nm = if nameNode.get().kind == nkIdent:
                    nameNode.get().ident.s
                  elif nameNode.get().kind == nkSym:
                    nameNode.get().sym.name.s
                  else:
                    ""
        info["name"] = stripExportMarker(nm)
        info["exported"] = $(nm.endsWith("*"))
        info["kind"] = $node.kind
    let params = extractParamsFromProcNode(node)
    var paramStrs: seq[string]
    for p in params:
      if p.typ.len > 0:
        paramStrs.add(p.name & ": " & p.typ)
      else:
        paramStrs.add(p.name)
    info["params"] = paramStrs.join(", ")
    let gparams = extractGenericParams(node)
    info["genericParams"] = gparams.join(", ")
    result.add(info)

# ── nim check baseline ────────────────────────────
proc nimCheckOk*(source: string; label: string): bool =
  let tmpFile = "/tmp/wpi_nimcheck_" & label & ".nim"
  let cacheDir = "/tmp/wpi_nimcache_" & label
  writeFile(tmpFile, source)
  let cmd = "nim check --nimcache:" & cacheDir & " " & tmpFile
  let exitCode = execShellCmd(cmd)
  try: removeFile(tmpFile) except: discard
  try: removeDir(cacheDir) except: discard
  result = exitCode == 0

# ── real extraction probe ─────────────────────────
proc probeRealExtraction*(): JsonNode =
  ## Read the subject file directly to show source extraction produces non-empty content.
  ## Candidate construction sites for sourceCode in OrchestrationProofRequest:
  ##   src/cli/payload_bridge.nim:67-68 (readFileOpt(modulePath) -> sourceCode)
  ##   src/cli/payload_bridge.nim:102-103 (same pattern for second path)
  ##   src/verification/batch_uap/loop_depth_scheduler.nim:257 (sourceCode: uapReq.sourceCode)
  let subjectPath = "<workspace>/nim-stew-clean-c75502c/stew/bitops2.nim"
  let content = readFile(subjectPath)
  result = %*{"length": content.len, "head200": content[0 ..< min(200, content.len)], "tail200": content[max(0, content.len - 200) ..< content.len]}

# ── Main ──────────────────────────────────────────
var corpusResults = %*[]

for caseItem in corpusCases:
  let parseResult = parseNimRes(caseItem.source)
  var procs = %*[]
  var errorMsg = ""
  var parseOk = false

  if parseResult.ok:
    parseOk = true
    let ast = parseResult.value
    let procInfos = extractProcInfo(ast)
    for info in procInfos:
      let p = %*info
      procs.add(p)
  else:
    parseOk = false
    errorMsg = parseResult.err

  let nimOk = nimCheckOk(caseItem.source, caseItem.name)
  let caseResult = %*{"case": caseItem.name, "parseOk": parseOk, "errorMsg": errorMsg, "procs": procs, "nimCheckOk": nimOk}
  corpusResults.add(caseResult)

# ── real extraction ───────────────────────────────
let realExtraction = probeRealExtraction()

let note = "not-reachable-from-probe: no importable proc returns function source for (modulePath, functionName). Candidate construction sites: src/cli/payload_bridge.nim:67-68 (readFileOpt reads entire file as sourceCode), src/cli/payload_bridge.nim:102-103, src/verification/batch_uap/loop_depth_scheduler.nim:257."
let output = %*{"corpusResults": corpusResults, "realExtraction": realExtraction, "realExtractionNote": note}

# Write to canonical directory
let outDir = "<workspace>/experiments/act2-wpi-structural-ingress/canonical"
createDir(outDir)
writeFile(outDir / "signature_corpus.json", $output)
