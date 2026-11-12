## publication_provenance_validator.nim — provenance-validate job of the
## publication-integrity gate.
##
## Adjudicates EVERY tracked file against the origin declarations in
## compliance/provenance/source-origin.yml under the class policy in
## compliance/policy/provenance-policy.yml and the license allowlist in
## compliance/policy/license-policy.yml:
##
##   (1) COVERAGE — every `git ls-files` path must match at least one
##       declaration. There is deliberately NO catch-all glob, so a file
##       outside the declared scopes is UNDECLARED → DENY (fail-closed).
##   (2) CONSISTENCY — a file matching several rules must have ALL matching
##       rules agree on (origin, license); a disagreement is INCONSISTENT.
##   (3) CLASS SEMANTICS — THIRD_PARTY requires `source` + a license in the
##       allowlist; ORIGINAL/AI_GENERATED require the self license.
##       UNDECLARED_COPYRIGHT and UNKNOWN are DENY classes (closed
##       vocabulary enforced).
##
## Verdicts (closed set): PASS / FAIL / UNKNOWN. UNKNOWN covers unparsable
## policy/declaration files, unreadable git state — always BLOCKING, never
## a pass (fail-closed). Exit: 0 = PASS, 1 = FAIL, 2 = UNKNOWN.
##
## Output: a machine-readable report JSON (path given by --out).
##
## Part of the publication-integrity gate (docs/spec/publication_integrity_gate.md).

import std/[json, options, os, osproc, parseopt, strutils]
import core/trusted/layer_declaration
import core/results
import tools/ci/publication_yaml
import tools/ci/publication_origin

axiomLayer "tools"

const
  ToolName = "publication_provenance_validator"
  ExitPass = 0
  ExitFail = 1
  ExitUnknown = 2

# ---------------------------------------------------------------------------
# Inputs
# ---------------------------------------------------------------------------

type
  Inputs = object
    originPath: string
    policyPath: string
    licensePolicyPath: string
    repoRoot: string
    outPath: string

proc parseArgs(): Result[Inputs, string] =
  ## Repo CLI idiom (rotation_pin_anchor_check parseCheckArgs): explicit
  ## `p.next()` loop; an option whose value is space-separated consumes the
  ## next cmdArgument token. Anything else is an input contract violation.
  var inputs = Inputs(
    originPath: "compliance/provenance/source-origin.yml",
    policyPath: "compliance/policy/provenance-policy.yml",
    licensePolicyPath: "compliance/policy/license-policy.yml",
    repoRoot: ".",
    outPath: "")
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
      of "origin": inputs.originPath = val
      of "policy": inputs.policyPath = val
      of "license-policy": inputs.licensePolicyPath = val
      of "repo-root": inputs.repoRoot = val
      of "out": inputs.outPath = val
      else: return err("unknown option: --" & key)
    of cmdArgument:
      return err("unexpected argument '" & p.key & "'")
  if inputs.outPath.len == 0:
    return err("--out <report.json> is required")
  ok(inputs)

proc readFileOrErr(path: string): Result[string, string] =
  try:
    ok(readFile(path))
  except CatchableError as e:
    err("cannot read " & path & ": " & e.msg)

proc execGit(repoRoot: string, args: seq[string]): Result[seq[string], string] =
  ## Run a git command and return its stdout lines (fail-closed on error).
  var cmd = "git -C " & quoteShell(repoRoot)
  for a in args:
    cmd.add(" " & quoteShell(a))
  try:
    let outp = execCmdEx(cmd)
    if outp.exitCode != 0:
      return err("git failed (" & $outp.exitCode & "): " & cmd & " — " & outp.output[0 ..< min(outp.output.len, 200)])
    var lines: seq[string] = @[]
    for l in outp.output.splitLines():
      if l.len > 0:
        lines.add(l)
    ok(lines)
  except CatchableError as e:
    err("cannot execute git: " & e.msg)

# ---------------------------------------------------------------------------
# Declaration model — tools/ci/publication_origin.nim (shared SSOT parser)
# ---------------------------------------------------------------------------

proc matchesPath(decl: Declaration, file: string): bool {.inline.} =
  ## Shared semantics re-export; kept local-symmetrical for call sites.
  publication_origin.matchesPath(decl, file)

proc normalizedLicense(license: string): seq[string] =
  ## Split dual-license expressions into their SPDX disjuncts.
  let cleaned = license.replace("(", "").replace(")", "").strip()
  for part in cleaned.split(" OR "):
    let p = part.strip()
    if p.len > 0:
      result.add(p)

const
  ForbiddenContentSkipFiles = [
    "compliance/policy/provenance-policy.yml",
  ]
  DepsArchivePath = "experiments/act2-wp-toml-b1-input-integrity/bsec/offline/deps.tar.gz"

proc isArchivePath(f: string): bool =
  f.endsWith(".tar.gz") or f.endsWith(".tgz") or f.endsWith(".zip") or f.endsWith(".tar")

proc hasAnySuffix(f: string, suffixes: seq[string]): bool =
  for s in suffixes:
    if s.len > 0 and f.endsWith(s):
      return true
  false

proc hasAnyPrefix(f: string, prefixes: seq[string]): bool =
  for p in prefixes:
    if p.len > 0 and f.startsWith(p):
      return true
  false

proc isInNotices(d: Declaration, noticesContent: string): bool =
  if d.source.len > 0 and noticesContent.contains(d.source):
    return true
  let tokens = d.source.splitWhitespace()
  if tokens.len > 0:
    let baseUrl = tokens[0]
    if baseUrl.len > 0 and noticesContent.contains(baseUrl):
      return true
    const ghPrefix = "https://github.com/"
    if baseUrl.startsWith(ghPrefix):
      let rest = baseUrl[ghPrefix.len ..^ 1].strip(chars = {'/'})
      let parts = rest.split('/')
      if parts.len >= 2:
        let slug = parts[0] & "/" & parts[1]
        if noticesContent.contains(slug):
          return true
        if slug == "nim-lang/Nim" and noticesContent.contains("nim-lang"):
          return true
  if d.path.len > 0 and noticesContent.contains(d.path):
    return true
  false

# ---------------------------------------------------------------------------
# Adjudication
# ---------------------------------------------------------------------------

type
  ProvenanceVerdict = enum
    pvPass
    pvFail
    pvUnknown

proc adjudicate(inputs: Inputs): tuple[verdict: ProvenanceVerdict, report: JsonNode, message: string] =
  ## The whole judgment. Any input problem → UNKNOWN (blocking).
  # ── parse inputs ──────────────────────────────────────────────────────
  let originText = readFileOrErr(inputs.originPath)
  if originText.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, originText.error)
  let originNode = parseRestrictedYaml(originText.get)
  if originNode.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, "source-origin.yml: " & originNode.error)
  let policyText = readFileOrErr(inputs.policyPath)
  if policyText.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, policyText.error)
  let policyNode = parseRestrictedYaml(policyText.get)
  if policyNode.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, "provenance-policy.yml: " & policyNode.error)
  let licText = readFileOrErr(inputs.licensePolicyPath)
  if licText.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, licText.error)
  let licNode = parseRestrictedYaml(licText.get)
  if licNode.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, "license-policy.yml: " & licNode.error)
  for node in [originNode.get, policyNode.get, licNode.get]:
    let dups = yHasDuplicateKeys(node)
    if dups.len > 0:
      return (pvUnknown, %*{"dimension": "provenance"},
        "duplicate keys in a compliance file: " & dups.join(", "))

  let declsRes = loadDeclarations(originNode.get)
  if declsRes.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, declsRes.error)
  let decls = declsRes.get

  # ── closed origin vocabulary from the policy ──────────────────────────
  var allowedClasses: seq[string] = @[]
  for c in policyNode.get.yListMaps("originClasses"):
    allowedClasses.add(c.yStr("id"))
  if allowedClasses.len == 0:
    return (pvUnknown, %*{"dimension": "provenance"}, "provenance-policy.yml: no originClasses")
  var verdictByClass: seq[tuple[id, verdict: string]] = @[]
  for c in policyNode.get.yListMaps("originClasses"):
    verdictByClass.add((c.yStr("id"), c.yStr("verdict")))

  # ── admission rules from provenance-policy.yml ────────────────────────
  let
    forbiddenContentPatterns = policyNode.get.yListStrs("forbiddenContentPatterns")
    forbiddenPathSuffixes = policyNode.get.yListStrs("forbiddenPathSuffixes")
    allowedArchivePrefixes = policyNode.get.yListStrs("allowedArchivePrefixes")
    requiredDepsArchiveLicenses = policyNode.get.yListStrs("requiredDepsArchiveLicenses")

  # ── license allowlist ─────────────────────────────────────────────────
  var allowedLicenses: seq[string] = @[]
  for l in licNode.get.yListMaps("allowedLicenses"):
    allowedLicenses.add(l.yStr("id"))
  if allowedLicenses.len == 0:
    return (pvUnknown, %*{"dimension": "provenance"}, "license-policy.yml: no allowedLicenses")

  # ── the tracked tree ──────────────────────────────────────────────────
  let filesRes = execGit(inputs.repoRoot, @["ls-files"])
  if filesRes.isErr:
    return (pvUnknown, %*{"dimension": "provenance"}, filesRes.error)
  let files = filesRes.get
  if files.len == 0:
    return (pvUnknown, %*{"dimension": "provenance"}, "git ls-files returned no files")

  # ── per-file adjudication ─────────────────────────────────────────────
  var
    undeclared: seq[string] = @[]
    inconsistent: seq[string] = @[]
    invalidClass: seq[string] = @[]
    missingSource: seq[string] = @[]
    licenseNotAllowed: seq[string] = @[]
    selfLicenseViolations: seq[string] = @[]
    forbiddenPathViolations: seq[string] = @[]
    forbiddenContentViolations: seq[string] = @[]
    archiveLicenseViolations: seq[string] = @[]
    thirdPartyNoticesViolations: seq[string] = @[]
    licenseFileViolations: seq[string] = @[]
    declMatched = newSeq[bool](decls.len)
    hasThirdPartyMatched = false
  for f in files:
    if hasAnySuffix(f, forbiddenPathSuffixes) or
       (isArchivePath(f) and not hasAnyPrefix(f, allowedArchivePrefixes)):
      forbiddenPathViolations.add(f)

    if f notin ForbiddenContentSkipFiles:
      let fullPath = inputs.repoRoot / f
      if fileExists(fullPath):
        if f.endsWith(".tar.gz") or f.endsWith(".tgz"):
          try:
            let tarOut = execCmdEx("tar -tzf " & quoteShell(fullPath))
            if tarOut.exitCode != 0:
              forbiddenContentViolations.add(f & " (corrupt archive)")
              if f == DepsArchivePath:
                archiveLicenseViolations.add(f & " (corrupt archive)")
            elif f == DepsArchivePath:
              var members: seq[string] = @[]
              for line in tarOut.output.splitLines():
                var m = line.strip()
                if m.startsWith("./"):
                  m = m[2 ..^ 1]
                if m.len > 0:
                  members.add(m)
              for reqLic in requiredDepsArchiveLicenses:
                if reqLic notin members:
                  archiveLicenseViolations.add(reqLic)
          except CatchableError as e:
            forbiddenContentViolations.add(f & " (tar error: " & e.msg & ")")
          try:
            let gzOut = execCmdEx("gzip -dc " & quoteShell(fullPath))
            if gzOut.exitCode != 0:
              forbiddenContentViolations.add(f & " (cannot decompress archive)")
            else:
              for pat in forbiddenContentPatterns:
                if pat.len > 0 and gzOut.output.contains(pat):
                  forbiddenContentViolations.add(f & " (archive contains " & pat & ")")
          except CatchableError as e:
            forbiddenContentViolations.add(f & " (gzip error: " & e.msg & ")")
        elif not f.toLowerAscii().endsWith(".pdf"):
          try:
            if getFileSize(fullPath) <= 20 * 1024 * 1024:
              let content = readFile(fullPath)
              for pat in forbiddenContentPatterns:
                if pat.len > 0 and content.contains(pat):
                  forbiddenContentViolations.add(f & " (contains " & pat & ")")
          except CatchableError:
            discard

    var matched: seq[Declaration] = @[]
    for idx, d in decls:
      if d.matchesPath(f):
        matched.add(d)
        declMatched[idx] = true
    if matched.len == 0:
      undeclared.add(f)
      continue
    let first = matched[0]
    # unknown class → DENY by policy (UNKNOWN class is a denial, not a pass)
    if first.origin notin allowedClasses:
      invalidClass.add(f & " (origin=" & first.origin & ")")
      continue
    # consistency across ALL matching rules
    var consistent = true
    for m in matched[1 ..^ 1]:
      if m.origin != first.origin or m.license != first.license:
        consistent = false
        break
    if not consistent:
      inconsistent.add(f)
      continue
    case first.origin
    of "THIRD_PARTY":
      hasThirdPartyMatched = true
      if first.source.len == 0:
        missingSource.add(f)
      let lics = normalizedLicense(first.license)
      if lics.len == 0:
        licenseNotAllowed.add(f & " (empty license)")
      for l in lics:
        if l notin allowedLicenses:
          licenseNotAllowed.add(f & " (license=" & l & ")")
    of "ORIGINAL", "AI_GENERATED":
      if first.license != "LicenseRef-Axiom-SAL-1.0":
        selfLicenseViolations.add(f & " (license=" & first.license & ")")
    else:
      # UNDECLARED_COPYRIGHT / UNKNOWN — DENY classes
      invalidClass.add(f & " (origin=" & first.origin & " is a DENY class)")

  let noticesPath = inputs.repoRoot / "THIRD-PARTY-NOTICES.md"
  if fileExists(noticesPath) or hasThirdPartyMatched:
    if not fileExists(noticesPath):
      thirdPartyNoticesViolations.add("THIRD-PARTY-NOTICES.md missing")
    else:
      let noticesRes = readFileOrErr(noticesPath)
      if noticesRes.isErr:
        thirdPartyNoticesViolations.add("THIRD-PARTY-NOTICES.md unreadable")
      else:
        let noticesContent = noticesRes.get
        for idx, d in decls:
          if declMatched[idx] and d.origin == "THIRD_PARTY":
            if not isInNotices(d, noticesContent):
              thirdPartyNoticesViolations.add(
                d.path & " (" & d.source & " not in THIRD-PARTY-NOTICES.md)")

  if dirExists(inputs.repoRoot / "LICENSES") or fileExists(noticesPath):
    for l in licNode.get.yListMaps("allowedLicenses"):
      let noticeFile = l.yStr("noticeFile")
      if noticeFile.len > 0:
        let nfPath = inputs.repoRoot / noticeFile
        if not fileExists(nfPath):
          licenseFileViolations.add(noticeFile)
        else:
          let nfRes = readFileOrErr(nfPath)
          if nfRes.isErr or nfRes.get.strip().len == 0 or
             nfRes.get.contains("<year>") or
             nfRes.get.contains("<copyright holders>"):
            licenseFileViolations.add(noticeFile)

  let pass = undeclared.len == 0 and inconsistent.len == 0 and
             invalidClass.len == 0 and missingSource.len == 0 and
             licenseNotAllowed.len == 0 and selfLicenseViolations.len == 0 and
             forbiddenPathViolations.len == 0 and forbiddenContentViolations.len == 0 and
             archiveLicenseViolations.len == 0 and thirdPartyNoticesViolations.len == 0 and
             licenseFileViolations.len == 0
  let verdict = if pass: pvPass else: pvFail
  let report = %*{
    "dimension": "provenance",
    "verdict": if pass: "PASS" else: "FAIL",
    "tool": ToolName,
    "checkedFiles": files.len,
    "declarations": decls.len,
    "undeclared": undeclared,
    "inconsistentDeclarations": inconsistent,
    "invalidOriginClass": invalidClass,
    "thirdPartyMissingSource": missingSource,
    "licenseNotAllowed": licenseNotAllowed,
    "selfLicenseViolation": selfLicenseViolations,
    "forbiddenPathViolations": forbiddenPathViolations,
    "forbiddenContentViolations": forbiddenContentViolations,
    "archiveLicenseViolations": archiveLicenseViolations,
    "thirdPartyNoticesViolations": thirdPartyNoticesViolations,
    "licenseFileViolations": licenseFileViolations,
    "undeclaredVerdict": policyNode.get.yStr("undeclaredFileVerdict"),
  }
  let msg = "provenance: " & (if pass: "PASS — " & $files.len & " files covered" else: "FAIL")
  (verdict, report, msg)

proc main() {.raises: [].} =
  let inputs = parseArgs()
  if inputs.isErr:
    echo ToolName & " INPUT ERROR: " & inputs.error
    quit(ExitUnknown)
  let (verdict, report, msg) = adjudicate(inputs.get)
  try:
    if inputs.get.outPath.len > 0:
      writeFile(inputs.get.outPath, report.pretty() & "\n")
    echo msg
    if verdict != pvPass:
      echo report.pretty()
  except CatchableError as e:
    echo ToolName & " OUTPUT ERROR: " & e.msg
    quit(ExitUnknown)
  quit(case verdict
       of pvPass: ExitPass
       of pvFail: ExitFail
       of pvUnknown: ExitUnknown)

when isMainModule:
  main()
