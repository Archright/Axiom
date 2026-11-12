import std/[unittest, options, sets, strutils, json]
import compiler/[ast, idents]
import core/results
import core/sloc_policy
import core/ast_kernel

proc isJsonNull*(n: JsonNode): bool =
  n == nil or n.kind == JNull

proc ratifiedExpected*(fixture: string; metric: string; ctx: JsonNode = nil): JsonNode =
  let manifestPath = "data/sloc_ratified_manifest.json"
  let content = readFile(manifestPath)
  let manifest = parseJson(content)
  for entry in manifest:
    if entry["fixture"].str == fixture and entry["metric"].str == metric:
      let entryCtx = entry["context"]
      if isJsonNull(ctx) and isJsonNull(entryCtx):
        return entry["expected"]
      if not isJsonNull(ctx) and not isJsonNull(entryCtx):
        if ctx == entryCtx:
          return entry["expected"]
  result = nil

proc parseSrc*(src: string): PNode =
  let parsed = parseSourceToPNode(src)
  assert parsed.isOk(), "parse failed: " & src
  result = parsed.get()

proc whenCond*(whenStmt: PNode): PNode =
  whenStmt[0][0]

proc whenBranch*(whenStmt: PNode, idx: int): PNode =
  whenStmt[idx]

proc sourceSlocOf*(src: string): int =
  sourceSloc(parseSrc(src))

proc effectiveSlocOf*(src: string, ctx: WhenContext): Result[int, UnknownReason] =
  effectiveSloc(parseSrc(src), ctx)