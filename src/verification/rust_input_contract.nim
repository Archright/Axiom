import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

## Rust subject INPUT CONTRACT (feat/rust-subject-v1 Phase 1-A) — the
## fail-closed LLBC↔source binding check that runs BEFORE anything consumes
## the LLBC:
##
##   (a) LLBC file-table pre-validation — validateLlbcFileTable
##       (llbc_to_canonical.nim, the 7 reject-not-skip rules);
##   (b) Cargo crate identity — Cargo.lock + Cargo.toml raw sha256 digests
##       (contract §10.2: Cargo.lock is defined identically to nimble.lock —
##       the run_context.nim precedent is mirrored byte-for-byte). An absent
##       Cargo.lock/Cargo.toml FAILS the contract: v1 requires a Cargo crate;
##   (c) binding — two modes:
##       dep-info mode (depInfoPath given, the lane's default): the rustc
##       dep-info file is the authoritative input set. Every LLBC local file
##       must be a dep-info input, hash-match disk, every dep-info subject
##       `.rs` input must exist on disk, and no embedded entry may
##       masquerade as subject source (content hash collision with a subject
##       file). Subject files absent from BOTH the LLBC table and the dep-info
##       set are cfg-excluded and do not fail the contract. The dep-info
##       sha256 is recorded for the identity sidecar.
##       exact mode (no depInfoPath, legacy/tests): the validated LLBC local
##       file table (relPath + sha256(contents)) must equal the subject `.rs`
##       file set exactly. This mode is structurally impossible for real
##       crates whose cfg-excluded files never reach the LLBC (the serde_json
##       "LLBC not current" finding) — the lane always supplies dep-info.
##
## Any violation → not-ok with a reason naming the offending paths / rule —
## never a skip, never a widened pass. A vacuous equality (both sides empty)
## is a documented pass: the Cargo identity in (b) still pins the subject.
##
## STALENESS NAMING (the dvcNotCurrent precedent, certificate_verifier.nim):
## an equivalence mismatch means the LLBC was extracted against a DIFFERENT
## version of the subject source — the artifact is structurally valid, it is
## merely NOT CURRENT product truth. The classification caller maps this to
## eaMismatch (the existing mismatch axis, no new verdict vocabulary) and
## NEVER to eaInternalError; the reason carries the diagnostic.

import std/[json, os, strutils, algorithm, unicode]
import core/axiom_pragmas
import core/crypto/hash_kernel
import core/results
import core/context/run_context
import core/topology/node_filter
import verification/llbc_to_canonical

axiomIoBoundary()

type
  RustSubjectFileDigest* = object
    ## One subject `.rs` file, D1 record material: subject-relative POSIX
    ## path + sha256 hex of the file bytes.
    relPath*: string
    sha256*: string

  RustCargoIdentity* = object
    ## §10.2 run-envelope digests. Definition mirrors the nimble.lock
    ## precedent (run_context.nim): raw sha256 of the file, hex-encoded.
    ## Envelope-level ONLY — these do NOT enter the certificate identity
    ## chain (that binding is a later phase).
    lockfileDigest*: string   ## Cargo.lock
    manifestDigest*: string   ## Cargo.toml

  RustInputContractResult* = object
    ## The single outcome of the input contract for one (LLBC, subjectRoot)
    ## pair. `ok` iff the LLBC local file table is BOUND to the source rustc
    ## actually read. Two binding modes:
    ##   - dep-info mode (depInfoPath given): every LLBC local file is a
    ##     dep-info input, hash-matches disk, every dep-info subject `.rs`
    ##     input exists on disk, and no embedded entry masquerades as a
    ##     subject file. Subject files absent from BOTH the LLBC table and
    ##     the dep-info set are cfg-excluded and do not fail the contract.
    ##   - exact mode (no depInfoPath, legacy): the LLBC local table and the
    ##     subject `.rs` set are exactly equal (path + hash).
    ## `reason` is "" iff ok; it names the violated rule and the offending
    ## paths (deterministic order).
    ok*: bool
    reason*: string
    localFiles*: seq[LlbcFileTableEntry]
      ## validated LLBC local file table (when validation passed)
    embeddedFiles*: seq[LlbcEmbeddedEntry]
      ## the §6d embeddedContentAttested entries, propagated for the identity
      ## sidecar (document order; populated when the file-table validation
      ## passed — a later sub-check's refusal keeps it; no verdict impact)
    subjectFiles*: seq[RustSubjectFileDigest]
      ## subject `.rs` set, byte-lex sorted by relPath (when collected)
    subjectFingerprint*: string
      ## D1 finalized fingerprint over the subject `.rs` set
      ## (encodeFingerprintRecord + finalizeSourceFingerprint)
    cargo*: RustCargoIdentity
      ## valid only when ok
    usedFallback*: bool
      ## the subject walk fell back from git ls-files to walkDirRec
    depInfoDigest*: string
      ## sha256 of the rustc dep-info file bytes (dep-info mode only; "" when
      ## the mode is exact or the file is absent)
    depInfoFiles*: seq[string]
      ## subject-relative `.rs` inputs listed by the dep-info (dep-info mode
      ## only; document order, duplicates removed)
    rejection*: RustFileTableRejection
      ## the file-table half's structured producer facts when (a) failed
      ## (`rule == ""` otherwise) — propagated verbatim for the §6c v2
      ## production-time rejection binding; `ok`/`reason` are unchanged

func rawDigestHex(d: array[32, byte]): string =
  ## 32 raw sha256 bytes → 64-char lowercase hex (the disk-side digest form
  ## comparable with sha256Hex of the LLBC-embedded contents).
  const digits = "0123456789abcdef"
  result = newString(64)
  for i in 0 ..< 32:
    result[i * 2] = digits[int(d[i] shr 4)]
    result[i * 2 + 1] = digits[int(d[i] and 0xF)]

func equivalenceProblems(entries: seq[LlbcFileTableEntry];
    subjectFiles: seq[RustSubjectFileDigest];
    requireExact: bool = true): seq[string] {.raises: [].} =
  ## (c) the PURE half of the file-set equivalence: deterministic linear
  ## scans (subject-scale N); every category is reported, offending paths
  ## byte-lex sorted. Empty result = the sets bind. A vacuous equality (both
  ## sides empty) is a documented pass — the Cargo identity still pins the
  ## subject. `requireExact = false` (dep-info mode) drops the
  ## subject-not-in-LLBC category: a subject file rustc never read (cfg
  ## excluded) is not a binding violation; the dep-info half supplies the
  ## authoritative input set instead.
  var missingInLlbc, missingOnDisk, hashMismatch: seq[string]
  for sf in subjectFiles:
    var found = false
    for e in entries:
      if e.relPath == sf.relPath:
        found = true
        let llbcHash = sha256Hex(e.contents)
        if llbcHash != sf.sha256:
          hashMismatch.add(sf.relPath & " (llbc=" & llbcHash &
            " disk=" & sf.sha256 & ")")
        break
    if not found and requireExact:
      missingInLlbc.add(sf.relPath)
  for e in entries:
    var found = false
    for sf in subjectFiles:
      if sf.relPath == e.relPath:
        found = true
        break
    if not found:
      missingOnDisk.add(e.relPath)
  if missingInLlbc.len > 0:
    result.add("subject file(s) missing from the LLBC local table: [" &
      missingInLlbc.join(", ") & "]")
  if missingOnDisk.len > 0:
    result.add("LLBC local file(s) missing from the subject file set: [" &
      missingOnDisk.join(", ") & "]")
  if hashMismatch.len > 0:
    result.add("content hash mismatch: [" & hashMismatch.join("; ") & "]")

func depInfoTokens(text: string): seq[string] {.raises: [].} =
  ## rustc dep-info (Make syntax): `<target>: <dep> <dep> ...`, with `\`
  ## line continuations and `\ ` escaped spaces. Returns the dependency
  ## tokens only (the target before the first ':' is dropped). Deterministic
  ## document order; no path normalization here.
  var logical: seq[string] = @[]
  var cur = ""
  for rawLine in text.splitLines():
    if rawLine.len > 0 and rawLine[^1] == '\\':
      cur.add(rawLine[0 ..< rawLine.len - 1])
      cur.add(" ")
    else:
      cur.add(rawLine)
      logical.add(cur)
      cur = ""
  if cur.len > 0:
    logical.add(cur)
  for line in logical:
    let colon = line.find(':')
    if colon < 0:
      continue
    let deps = line[colon + 1 .. ^1]
    var i = 0
    while i < deps.len:
      while i < deps.len and deps[i] in {' ', '\t'}:
        inc i
      if i >= deps.len:
        break
      var tok = ""
      while i < deps.len and deps[i] notin {' ', '\t'}:
        if deps[i] == '\\' and i + 1 < deps.len:
          inc i
          tok.add(deps[i])
        else:
          tok.add(deps[i])
        inc i
      if tok.len > 0:
        result.add(tok)

func subjectRelativePath(p, subjectRoot: string): string {.raises: [].} =
  ## Absolute path under `subjectRoot` → subject-relative POSIX path; "" for
  ## a path outside the subject tree (generated OUT_DIR files, toolchain
  ## paths). The comparison is byte-prefix on the normalized root — no
  ## symlink resolution, no case folding (D3: a physical path never reaches
  ## a hash).
  var root = subjectRoot
  while root.len > 1 and root[^1] == '/':
    root.setLen(root.len - 1)
  if p.len > root.len + 1 and p[0 ..< root.len] == root and
      p[root.len] == '/':
    return p[root.len + 1 .. ^1]
  ""

proc cargoIdentity(subjectRoot: string):
    tuple[ok: bool, reason: string, cargo: RustCargoIdentity] {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## (b) Cargo crate identity. Cargo.lock digest mirrors run_context.nim's
  ## nimble.lock construction byte-for-byte (sha256FileT → raw bytes →
  ## sha256Hex); Cargo.toml digest is the same definition. Absent or
  ## unreadable → fail-closed with the offending file named.
  let lockPath = subjectRoot / "Cargo.lock"
  if not fileExists(lockPath):
    return (false,
      "Cargo.lock absent — v1 requires a Cargo crate (fail-closed)",
      RustCargoIdentity())
  let lockRaw = sha256FileT(lockPath)
  if lockRaw.isErr():
    return (false, "cannot read Cargo.lock: " & lockRaw.error,
            RustCargoIdentity())
  var lockStr = newString(32)
  for i in 0 .. 31:
    lockStr[i] = char(lockRaw.value[i])
  let manPath = subjectRoot / "Cargo.toml"
  if not fileExists(manPath):
    return (false,
      "Cargo.toml absent — v1 requires a Cargo crate (fail-closed)",
      RustCargoIdentity())
  let manRaw = sha256FileT(manPath)
  if manRaw.isErr():
    return (false, "cannot read Cargo.toml: " & manRaw.error,
            RustCargoIdentity())
  var manStr = newString(32)
  for i in 0 .. 31:
    manStr[i] = char(manRaw.value[i])
  (true, "", RustCargoIdentity(
    lockfileDigest: sha256Hex(lockStr),
    manifestDigest: sha256Hex(manStr)))

proc rustSubjectInputContract*(root: JsonNode; subjectRoot: string;
    depInfoPath: string = ""): RustInputContractResult {.
    raises: [], axiomEffect: IOEffect,
    tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## THE input contract: (a) file-table pre-validation → (b) Cargo identity
  ## → (c) binding. With `depInfoPath` the binding is the rustc dep-info
  ## contract (the authoritative input set); without it the legacy exact
  ## set equality applies. First failure wins; the reason names the rule and
  ## the offending paths.
  result.ok = false

  # (a) LLBC file-table pre-validation — before anything consumes the LLBC.
  let ft = validateLlbcFileTable(root)
  if not ft.ok:
    result.reason = "LLBC files table pre-validation failed: " & ft.reason
    result.rejection = ft.rejection
    return
  result.localFiles = ft.entries
  result.embeddedFiles = ft.embedded

  # (b) Cargo crate identity — v1 requires a Cargo crate.
  let cargoStep = cargoIdentity(subjectRoot)
  if not cargoStep.ok:
    result.reason = cargoStep.reason
    return
  result.cargo = cargoStep.cargo

  # (c1) the subject `.rs` file set (rustSourcePolicy → same D1 collector).
  let collected = collectSubjectFileSet(subjectRoot, rustSourcePolicy)
  result.usedFallback = collected.usedFallback
  var records: seq[seq[byte]]
  for relEntry in collected.paths:
    if unicode.validateUtf8(relEntry) >= 0:
      result.reason = "invalid UTF-8 subject filename '" & relEntry & "'"
      return
    let digestInfo = sha256FileT(subjectRoot / relEntry)
    if digestInfo.isErr():
      result.reason = "cannot read subject file '" & relEntry & "': " &
        digestInfo.error
      return
    let hex = rawDigestHex(digestInfo.value)
    records.add(encodeFingerprintRecord(relEntry, digestInfo.value))
    result.subjectFiles.add(RustSubjectFileDigest(
      relPath: relEntry, sha256: hex))
  result.subjectFiles.sort(proc(a, b: RustSubjectFileDigest): int =
    cmp(a.relPath, b.relPath))
  result.subjectFingerprint = finalizeSourceFingerprint(records)

  # (c2) binding — dep-info mode when the lane supplies the rustc dep-info,
  # legacy exact mode otherwise.
  if depInfoPath.len > 0:
    if not fileExists(depInfoPath):
      result.reason = "rust subject input contract FAILED (dep-info absent — " &
        "the authoritative rustc input set is unavailable, fail-closed): " &
        depInfoPath
      return
    var depText = ""
    try:
      depText = readFile(depInfoPath)
    except CatchableError as e:
      result.reason = "rust subject input contract FAILED (dep-info " &
        "unreadable — fail-closed): " & depInfoPath & ": " & e.msg
      return
    result.depInfoDigest = sha256Hex(depText)
    var depRel: seq[string] = @[]
    for tok in depInfoTokens(depText):
      let rel = subjectRelativePath(tok, subjectRoot)
      if rel.len > 0 and rel notin depRel:
        depRel.add(rel)
    result.depInfoFiles = depRel
    # (c2-i) every LLBC local file is a dep-info input.
    var missingInDep: seq[string] = @[]
    for e in ft.entries:
      if e.relPath notin depRel:
        missingInDep.add(e.relPath)
    # (c2-ii) every dep-info subject input exists on disk.
    var depMissingOnDisk: seq[string] = @[]
    for rel in depRel:
      if not fileExists(subjectRoot / rel):
        depMissingOnDisk.add(rel)
    # (c2-iii) no embedded entry masquerades as a subject file: an embedded
    # content hash equal to a subject `.rs` hash means the LLBC carries the
    # subject source under a non-subject path (the file-table validator
    # classified it as generated) — fail closed.
    var masquerade: seq[string] = @[]
    for emb in ft.embedded:
      for sf in result.subjectFiles:
        if emb.contentSha256 == sf.sha256:
          masquerade.add(emb.rawPath & " ≡ " & sf.relPath)
    # (c2-iv) the LLBC local files hash-match disk (the existing pure half,
    # exact-set category disabled: cfg-excluded subject files are allowed).
    let problems = equivalenceProblems(ft.entries, result.subjectFiles,
                                       requireExact = false)
    var allProblems: seq[string] = @[]
    if missingInDep.len > 0:
      allProblems.add("LLBC local file(s) missing from the rustc dep-info " &
        "input set: [" & missingInDep.join(", ") & "]")
    if depMissingOnDisk.len > 0:
      allProblems.add("dep-info input(s) missing on disk: [" &
        depMissingOnDisk.join(", ") & "]")
    if masquerade.len > 0:
      allProblems.add("embedded content masquerades as subject source: [" &
        masquerade.join("; ") & "]")
    for p in problems:
      allProblems.add(p)
    if allProblems.len > 0:
      result.reason = "rust subject input contract FAILED (LLBC not current " &
        "with the subject source — fail-closed): " & allProblems.join("; ")
      return
    result.ok = true
    return

  # (c2-legacy) exact equivalence — path sets EXACTLY equal, per-path hashes
  # equal; the comparison itself is the pure equivalenceProblems func above.
  let problems = equivalenceProblems(ft.entries, result.subjectFiles)
  if problems.len > 0:
    result.reason = "rust subject input contract FAILED (LLBC not current " &
      "with the subject source — fail-closed): " & problems.join("; ")
    return
  result.ok = true

{.pop.}
