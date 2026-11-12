import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [CatchableError].}

import std/[json, os, strutils, strformat, hashes, sets, options]
import core/ast_kernel
import core/results
import core/sloc_policy
import core/crypto/hash_kernel

type
  EvidenceRecord* = object
    id*: string
    fixture_source*: string
    fixture_raw_sha256*: string
    metric*: string
    context*: JsonNode
    expected_result*: JsonNode
    observed_facts*: seq[string]
    observed_result*: string
    policy_refs*: seq[string]
    ratified_policy_version*: string
    ratified_at*: string

proc computeObserved(src: string; metric: string; ctx: JsonNode): string =
  let parsed = parseSourceToPNode(src)
  if parsed.isErr:
    return "err:parseFailed"
  let node = parsed.get()
  if metric == "sourceSloc":
    let sloc = sourceSloc(node)
    return $sloc
  elif metric == "effectiveSloc":
    let whenCtx = if ctx != nil and ctx.kind != JNull:
      var knownDef: HashSet[string]
      var knownUndef: HashSet[string]
      if ctx.hasKey("defines") and ctx["defines"].kind == JObject:
        let defs = ctx["defines"]
        if defs.hasKey("knownDefined") and defs["knownDefined"].kind == JArray:
          for k in defs["knownDefined"]:
            if k.kind == JString: knownDef.incl(k.str)
        if defs.hasKey("knownUndefined") and defs["knownUndefined"].kind == JArray:
          for k in defs["knownUndefined"]:
            if k.kind == JString: knownUndef.incl(k.str)
      var tc: Option[string]
      var tcpu: Option[string]
      var copts: HashSet[string]
      if ctx.hasKey("targetOS") and ctx["targetOS"].kind == JString:
        tc = some(ctx["targetOS"].str)
      if ctx.hasKey("targetCPU") and ctx["targetCPU"].kind == JString:
        tcpu = some(ctx["targetCPU"].str)
      if ctx.hasKey("compileOptions") and ctx["compileOptions"].kind == JArray:
        for c in ctx["compileOptions"]:
          if c.kind == JString: copts.incl(c.str)
      WhenContext(
        defines: DefineContext(knownDefined: knownDef, knownUndefined: knownUndef),
        targetOS: tc,
        targetCPU: tcpu,
        compileOptions: copts
      )
    else:
      WhenContext()
    let r = effectiveSloc(node, whenCtx)
    if r.isErr:
      return "err:" & $r.error
    else:
      return $r.get()
  else:
    return "err:unknownMetric"

proc generateEvidence*(manifestPath: string; outputPath: string) =
  if not fileExists(manifestPath):
    stderr.writeLine &"Manifest not found: {manifestPath}"
    quit(1)
  let manifestContent = readFile(manifestPath)
  let manifest = parseJson(manifestContent)
  if manifest.kind != JArray:
    stderr.writeLine "Manifest root must be a JSON array"
    quit(1)
  var records: seq[EvidenceRecord]
  for i in 0 ..< manifest.len:
    let entry = manifest[i]
    let fixture = entry["fixture"].str
    let metric = entry["metric"].str
    let ctx = entry["context"]
    let expected = entry["expected"]
    let policies = if entry.hasKey("policy") and entry["policy"].kind == JArray:
      var refs: seq[string]
      for r in entry["policy"]:
        if r.kind == JString: refs.add(r.str)
      refs
    else: @[]
    let policyVersion = entry["ratified_policy_version"].str
    let ratifiedAt = entry["ratified_at"].str
    let hash = sha256Hex(fixture)
    let observed = computeObserved(fixture, metric, ctx)
    let evId = &"ev-{i+1:03d}"
    records.add(EvidenceRecord(
      id: evId,
      fixture_source: fixture,
      fixture_raw_sha256: hash,
      metric: metric,
      context: ctx,
      expected_result: expected,
      observed_facts: @[],
      observed_result: observed,
      policy_refs: policies,
      ratified_policy_version: policyVersion,
      ratified_at: ratifiedAt
    ))
  let output = %*records
  let dataDir = "tests/sloc/evidence"
  if not dirExists(dataDir):
    createDir(dataDir)
  writeFile(dataDir / "evidence.json", output.pretty())
  echo &"Generated {records.len} evidence records to {dataDir}/evidence.json"

proc main(args: seq[string]) =
  let manifestPath = if args.len > 0: args[0] else: "data/sloc_ratified_manifest.json"
  let outputPath = if args.len > 1: args[1] else: "tests/sloc/evidence/evidence.json"
  generateEvidence(manifestPath, outputPath)

when isMainModule:
  main(commandLineParams())