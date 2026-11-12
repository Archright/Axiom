## publication_license_eval.nim — license-scan adjudication of the
## publication-integrity gate.
##
## Evaluates a ScanCode (scancode-toolkit, pip-pinned) JSON report against
## compliance/policy/license-policy.yml, the origin declarations in
## compliance/provenance/source-origin.yml (via the shared parser
## tools/ci/publication_origin.nim), and the audited detection attributions
## in compliance/provenance/license-attribution.yml:
##
##   (1) LICENSE ACCOUNTING — every detected SPDX license atom (dual `X OR Y`
##       expressions split into disjuncts; composite AND expressions split
##       into atoms) must be accounted for by EITHER
##       (a) the file's declared license (source-origin.yml), OR
##       (b) an attribution entry (file, atom) in license-attribution.yml
##           carrying one of the closed classifications:
##           self-license-text | documentary-mention |
##           subject-manifest-record | upstream-header |
##           spurious-scanner-match.
##       Anything else is a publication blocker. Attribution entries are
##       per-(file, atom) — there is NO file-glob or license-glob catch-all,
##       so a NEW detection (e.g. a GPL text in a new file) has no entry and
##       FAILS (fail-closed). Adding an entry is a visible, reviewed act,
##       never a silent rule weakening (AGENTS.md §0.9).
##   (2) COPYRIGHT ACCOUNTING — a detected copyright holder must share a
##       significant token with the file's declared copyright field OR with
##       an attributed holder string for that file. Detections with NO
##       significant token (pure "(c) inc"-style scanner noise, no
##       identifiable holder) are counted as noise, not violations — they
##       carry no holder to account.
##   (3) Files in the scan without an origin declaration are violations
##       (defense-in-depth with the provenance-validate job).
##
## Tool substitution record (honesty, not coverage deletion): the gate spec
## named ScanCode — installed as `scancode-toolkit==32.5.0` with the
## mandatory companion pin `pluggy==1.5.0` (pluggy 1.7 breaks the ScanCode
## plugin loader; measured 2026-11-09). The hosted runner install uses the
## same two pins, so local baseline and CI run the same scanner.
## Measured limitation (declared, not hidden): ScanCode 32.5 emits
## `license_detections[].license_expression_spdx` and per-file
## `detected_license_expression_spdx` — there is no legacy `licenses` key;
## this evaluator reads the 32.5 schema.
##
## Verdicts (closed set): PASS / FAIL / UNKNOWN (unparsable inputs — always
## blocking). Exit: 0 = PASS, 1 = FAIL, 2 = UNKNOWN.
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, options, os, parseopt, strutils]
import core/trusted/layer_declaration
import core/results
import tools/ci/publication_yaml
import tools/ci/publication_origin

axiomLayer "tools"

const
  ToolName = "publication_license_eval"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2
  Classifications = ["self-license-text", "documentary-mention",
                     "subject-manifest-record", "upstream-header",
                     "spurious-scanner-match"]

type
  Inputs = object
    scanPath: string
    policyPath: string
    originPath: string
    attributionPath: string
    outPath: string
    stripPrefix: string

  Attribution = object
    file: string
    classification: string
    evidence: string
    licenses: seq[string]   # normalized (lowercased) atoms
    copyrights: seq[string] # holder strings, matched by token overlap

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom: explicit `p.next()` loop; space-separated option
  ## values consume the next cmdArgument token.
  var inputs = Inputs()
  var p = initOptParser(commandLineParams())
  while true:
    p.next()
    case p.kind
    of cmdEnd:
      break
    of cmdLongOption, cmdShortOption:
      let key = p.key
      var val = p.val
      if val.len == 0:
        p.next()
        if p.kind != cmdArgument:
          return err("option '--" & key & "' requires a value")
        val = p.key
      case key
      of "scan": inputs.scanPath = val
      of "policy": inputs.policyPath = val
      of "origin": inputs.originPath = val
      of "attribution": inputs.attributionPath = val
      of "out": inputs.outPath = val
      of "strip-prefix": inputs.stripPrefix = val
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  for req in [("scan", inputs.scanPath), ("policy", inputs.policyPath),
              ("origin", inputs.originPath),
              ("attribution", inputs.attributionPath),
              ("out", inputs.outPath)]:
    if req[1].len == 0:
      return err("--" & req[0] & " is required")
  ok(inputs)

proc loadJson(path: string): Result[JsonNode, string] =
  try:
    ok(parseJson(readFile(path)))
  except CatchableError as e:
    err("cannot parse " & path & ": " & e.msg)

proc readFileOrErr(path: string): Result[string, string] =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("cannot read " & path & ": " & e.msg)

proc normalizeLicense(license: string): seq[string] =
  ## Lowercase; strip parens; split `X OR Y` dual expressions and composite
  ## `X AND Y` expressions into single atoms.
  let cleaned = license.replace("(", " ").replace(")", " ")
  let spaced = cleaned.multiReplace((" AND ", " "), (" OR ", " "))
  for p in spaced.split():
    if p.len > 0:
      result.add(p.toLowerAscii())

proc normalizePath(path: string, stripPrefix: string): string =
  ## Scan paths are reported relative to the scan root: a `.` root yields
  ## `./file` (leading "./" stripped here), a directory root yields
  ## `<dirname>/file` (stripped when --strip-prefix matches). The result is
  ## the repository-relative path used by source-origin.yml.
  var p = path
  if stripPrefix.len > 0 and p.startsWith(stripPrefix & "/"):
    p = p[stripPrefix.len + 1 ..^ 1]
  if p.startsWith("./"):
    p = p[2 ..^ 1]
  p

proc significantTokens(s: string): seq[string] =
  ## Lowercased tokens of length >= 4 minus the generic stop words — used
  ## for the copyright-holder accounting overlap. Deterministic.
  const Stop = ["copyright", "rights", "reserved", "licensed", "under",
                "either", "version", "international", "authors", "gmbh",
                "inc", "llc", "ltd", "and", "the"]
  for tok in s.toLowerAscii().multiReplace(
      (".", " "), (",", " "), ("(", " "), (")", " "), ("©", " "),
      (":", " "), (";", " "), ("-", " ")).split():
    if tok.len >= 4 and tok notin Stop:
      result.add(tok)

proc holderAccounted(detected: string, declared: string): bool =
  ## True when the detected copyright holder shares at least one
  ## significant token with the declared copyright field. An empty declared
  ## field accounts nothing — honesty over convenience.
  if declared.strip().len == 0:
    return false
  let d = significantTokens(detected)
  if d.len == 0:
    return false
  let c = significantTokens(declared)
  for t in d:
    if t in c:
      return true
  false

proc detectedAtoms(fe: JsonNode): seq[string] =
  ## Atoms from the ScanCode 32.5 schema: per-detection
  ## `license_expression_spdx` (fallback `license_expression`) plus the
  ## file-level `detected_license_expression_spdx`; deduplicated, in
  ## first-seen order (deterministic for a fixed report).
  var seen: seq[string] = @[]
  proc addExpr(e: string) =
    if e.len == 0:
      return
    for a in normalizeLicense(e):
      if a notin seen:
        seen.add(a)
  let dets = fe{"license_detections"}
  if dets != nil and dets.kind == JArray:
    for d in dets:
      var e = d{"license_expression_spdx"}.getStr("")
      if e.len == 0:
        e = d{"license_expression"}.getStr("")
      addExpr(e)
  addExpr(fe{"detected_license_expression_spdx"}.getStr(""))
  seen

proc detectedHolders(fe: JsonNode): seq[tuple[holder: string, line: int]] =
  let copyrights = fe{"copyrights"}
  if copyrights == nil or copyrights.kind != JArray:
    return
  for ce in copyrights:
    var h = ce{"copyright"}.getStr("")
    if h.len == 0:
      h = ce{"value"}.getStr("")
    if h.len > 0:
      result.add((h, ce{"start_line"}.getInt(0)))

proc loadAttributions(text: string): Result[seq[Attribution], string] =
  let node = parseRestrictedYaml(text)
  if node.isErr:
    return err("license-attribution.yml: " & node.error)
  var entries: seq[Attribution] = @[]
  for e in node.get.yListMaps("attributions"):
    let file = e.yStr("file")
    let classification = e.yStr("classification")
    if file.len == 0:
      return err("attribution entry without file")
    if classification notin Classifications:
      return err("attribution for " & file &
        " has unknown classification: " & classification)
    var lics: seq[string] = @[]
    for l in e.yListStrs("licenses"):
      for a in normalizeLicense(l):
        lics.add(a)
    entries.add Attribution(
      file: file, classification: classification,
      evidence: e.yStr("evidence"),
      licenses: lics,
      copyrights: e.yListStrs("copyrights"))
  if entries.len == 0:
    return err("license-attribution.yml has no attributions")
  ok(entries)

proc main() {.raises: [].} =
  let inputsRes = parseArgs()
  if inputsRes.isErr:
    echo ToolName & " INPUT ERROR: " & inputsRes.error
    quit(ExitUnknown)
  let inputs = inputsRes.get

  # ── policy ────────────────────────────────────────────────────────────
  let policyText = readFileOrErr(inputs.policyPath)
  if policyText.isErr:
    echo ToolName & " UNKNOWN: " & policyText.error; quit(ExitUnknown)
  let policyNode = parseRestrictedYaml(policyText.get)
  if policyNode.isErr:
    echo ToolName & " UNKNOWN: license-policy.yml: " & policyNode.error
    quit(ExitUnknown)
  var allowed: seq[string] = @[]
  for l in policyNode.get.yListMaps("allowedLicenses"):
    for n in normalizeLicense(l.yStr("id")):
      allowed.add(n)
  if allowed.len == 0:
    echo ToolName & " UNKNOWN: license-policy.yml has no allowedLicenses"
    quit(ExitUnknown)
  var deniedFamilies: seq[string] = @[]
  for f in policyNode.get.yListStrs("deniedLicenseFamilies"):
    deniedFamilies.add(f.toLowerAscii())

  # ── origin declarations (shared SSOT parser) ─────────────────────────
  let originText = readFileOrErr(inputs.originPath)
  if originText.isErr:
    echo ToolName & " UNKNOWN: " & originText.error; quit(ExitUnknown)
  let originNode = parseRestrictedYaml(originText.get)
  if originNode.isErr:
    echo ToolName & " UNKNOWN: source-origin.yml: " & originNode.error
    quit(ExitUnknown)
  let declsRes = loadDeclarations(originNode.get)
  if declsRes.isErr:
    echo ToolName & " UNKNOWN: source-origin.yml: " & declsRes.error
    quit(ExitUnknown)
  let decls = declsRes.get

  # ── attribution baseline ──────────────────────────────────────────────
  let attrText = readFileOrErr(inputs.attributionPath)
  if attrText.isErr:
    echo ToolName & " UNKNOWN: " & attrText.error; quit(ExitUnknown)
  let attrsRes = loadAttributions(attrText.get)
  if attrsRes.isErr:
    echo ToolName & " UNKNOWN: " & attrsRes.error
    quit(ExitUnknown)
  let attrs = attrsRes.get

  proc attrsFor(file: string): seq[Attribution] =
    result = @[]
    for a in attrs:
      if a.file == file:
        result.add(a)

  # ── ScanCode report ───────────────────────────────────────────────────
  let scan = loadJson(inputs.scanPath)
  if scan.isErr:
    echo ToolName & " UNKNOWN: " & scan.error
    quit(ExitUnknown)
  let files = scan.get{"files"}
  if files.isNil or files.kind != JArray:
    echo ToolName & " UNKNOWN: scan report has no files array"
    quit(ExitUnknown)

  var
    filesWithLicenses = 0
    filesWithCopyrights = 0
    noiseDetections = 0
    licenseViolations: seq[JsonNode] = @[]
    copyrightViolations: seq[JsonNode] = @[]
    usedLicenseAttr: seq[tuple[f, a: string]] = @[]
    usedCopyrightAttr: seq[tuple[f, h: string]] = @[]
  for fe in files:
    if fe{"type"}.getStr("file") != "file":
      continue
    let path = normalizePath(fe{"path"}.getStr(""), inputs.stripPrefix)
    let atoms = detectedAtoms(fe)
    let holders = detectedHolders(fe)
    if atoms.len > 0:
      inc filesWithLicenses
    if holders.len > 0:
      inc filesWithCopyrights
    if atoms.len == 0 and holders.len == 0:
      continue
    let declOpt = firstMatch(decls, path)
    let fileAttrs = attrsFor(path)
    var declaredSet: seq[string] = @[]
    if declOpt.isSome:
      declaredSet = normalizeLicense(declOpt.get.license)
    # (1) license atoms
    for a in atoms:
      if a in declaredSet:
        continue
      var attributed = false
      for at in fileAttrs:
        if a in at.licenses:
          attributed = true
          if (path, a) notin usedLicenseAttr:
            usedLicenseAttr.add((path, a))
          break
      if attributed:
        continue
      var denied = false
      for fam in deniedFamilies:
        if a.startsWith(fam):
          denied = true
          break
      licenseViolations.add(%*{
        "file": path, "atom": a, "deniedFamily": denied,
        "reason": "neither declared (source-origin.yml) nor attributed (license-attribution.yml)"})
    # (2) copyright holders
    for h in holders:
      if significantTokens(h.holder).len == 0:
        # "(c) inc"-style noise: no identifiable holder to account.
        inc noiseDetections
        continue
      var accounted = false
      if declOpt.isSome and holderAccounted(h.holder, declOpt.get.copyright):
        accounted = true
      if not accounted:
        for at in fileAttrs:
          for ch in at.copyrights:
            if holderAccounted(h.holder, ch):
              accounted = true
              if (path, ch) notin usedCopyrightAttr:
                usedCopyrightAttr.add((path, ch))
              break
          if accounted:
            break
      if not accounted:
        copyrightViolations.add(%*{
          "file": path, "holder": h.holder, "startLine": h.line,
          "reason": "holder not accounted by declaration or attribution"})
    # (3) declaration presence (defense-in-depth with provenance-validate)
    if declOpt.isNone:
      licenseViolations.add(%*{
        "file": path, "atom": "", "deniedFamily": false,
        "reason": "file has no origin declaration"})

  # unused attribution entries (cleanup signal, not a failure)
  var unusedLicenses = 0
  var unusedCopyrights = 0
  for at in attrs:
    for a in at.licenses:
      if (at.file, a) notin usedLicenseAttr:
        inc unusedLicenses
    for ch in at.copyrights:
      if (at.file, ch) notin usedCopyrightAttr:
        inc unusedCopyrights

  let verdict =
    if licenseViolations.len == 0 and copyrightViolations.len == 0: "PASS"
    else: "FAIL"
  let report = %*{
    "dimension": "license-scan",
    "verdict": verdict,
    "tool": ToolName,
    "scanner": "scancode-toolkit==32.5.0 + pluggy==1.5.0",
    "filesScanned": files.len,
    "filesWithLicenseDetection": filesWithLicenses,
    "filesWithCopyrightDetection": filesWithCopyrights,
    "licenseViolations": licenseViolations,
    "copyrightViolations": copyrightViolations,
    "noiseDetections": noiseDetections,
    "attributionEntries": attrs.len,
    "attributionUsedLicenses": usedLicenseAttr.len,
    "attributionUnusedLicenses": unusedLicenses,
    "attributionUnusedCopyrights": unusedCopyrights,
    "classificationVocabulary": Classifications,
    "rightsVerificationLimit": "automated analysis passing is not proof of non-infringement (provenance-policy.yml rightsVerificationLimit)",
  }
  try:
    writeFile(inputs.outPath, report.pretty() & "\n")
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  echo ToolName & ": " & verdict & " (files=" & $files.len &
    " licenseDetections=" & $filesWithLicenses &
    " copyrightDetections=" & $filesWithCopyrights & ")"
  for n in licenseViolations:
    if n{"deniedFamily"}.getBool:
      echo "  DENIED-FAMILY LICENSE UNACCOUNTED: " & n{"file"}.getStr &
        " -> " & n{"atom"}.getStr & " (" & n{"reason"}.getStr & ")"
    else:
      echo "  LICENSE UNACCOUNTED: " & n{"file"}.getStr &
        " -> " & n{"atom"}.getStr & " (" & n{"reason"}.getStr & ")"
  for n in copyrightViolations:
    echo "  COPYRIGHT UNACCOUNTED: " & n{"file"}.getStr &
      " -> " & n{"holder"}.getStr
  quit(if verdict == "PASS": ExitPass else: ExitFail)

when isMainModule:
  main()
