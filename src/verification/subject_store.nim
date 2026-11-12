import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}

import std/[algorithm, json, os, strutils]
import core/axiom_pragmas
import core/results
import core/trusted/append_store
import verification/verification_subject

axiomIoBoundary()

## Subject Store — the append-only certifiable-subject vault
## (certification continuity contract §4.1/§5 INV-8 pattern: one immutable
## record per subject, keyed by its content-derived subjectId).
##
## Layout mirrors the runtime-canonical certificate vault resolution
## (cert_vault_role.cvRuntimeCanonical → data/trusted/certificates): subjects
## live under data/trusted/subjects/<subjectId>.json — one record per file,
## filename = the canonical id itself (self-verifying, tamper-evident key).
##
## Append-only, fail-closed: saveSubject refuses to overwrite an existing
## subject file (a second write for the same id is REJECTED — a subject is
## constructed exactly once, contract §4.1 "단일 생성"). Writes go through
## append_store.writeRecord (write-tmp → fsync → rename → fsync(parentDir))
## so a record is either fully present or fully absent after a crash.
##
## Subject identity is captured from the certification inputs at the I/O
## boundary (baseSha/headSha digests); the store itself never re-derives
## trees (INV-3).

const
  SubjectStoreDir* = "data" / "trusted" / "subjects"
    ## Runtime-canonical subject vault (aligned with cert_vault_role's
    ## data/trusted runtime store pattern).

func isSubjectId*(s: string): bool {.raises: [].} =
  isHexOfLen(s, 64)

func subjectPath*(dir: string; subjectId: string): string {.raises: [].} =
  dir / subjectId & ".json"

proc parseSubjectText*(text: string): Result[VerificationSubject, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Text → validated subject (parseJson side effect lives at the I/O
  ## boundary; model validation stays pure in verification_subject).
  var node: JsonNode
  try:
    node = parseJson(text)
  except CatchableError:
    return err("subject_store: malformed JSON (fail-closed)")
  subjectFromJson(node)

proc saveSubject*(subject: VerificationSubject; dir: string = SubjectStoreDir): Result[string, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Persist ONE subject record, append-only. Refuses (err) when the subject
  ## is malformed, when the subjectId is not a plausible canonical id, or when
  ## the record already exists — a subject is never overwritten (fail-closed).
  let problem = validateSubject(subject)
  if problem.len > 0:
    return err(problem)
  if not isSubjectId(subject.subjectId):
    return err("subject_store: refusing to persist non-canonical subjectId (fail-closed)")
  let path = subjectPath(dir, subject.subjectId)
  if fileExists(path):
    return err("subject_store: subject already exists — append-only, overwrite refused (fail-closed): " & path)
  if not dirExists(dir):
    createDir(dir)
  let jsonText = toCanonicalJson(subject)
  if not writeRecord(path, jsonText & "\n"):
    return err("subject_store: durable write failed for " & path)
  ok(path)

proc loadSubject*(subjectId: string; dir: string = SubjectStoreDir): Result[VerificationSubject, string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Load + fully validate one subject by its id. Unknown id, malformed file,
  ## or a record whose subjectId does not re-derive → err (fail-closed: a
  ## tampered record is never read as valid).
  if not isSubjectId(subjectId):
    return err("subject_store: invalid subjectId (must be 64 lowercase hex chars)")
  let path = subjectPath(dir, subjectId)
  if not fileExists(path):
    return err("subject_store: subject not found: " & path)
  let text = readFile(path)
  parseSubjectText(text)

proc listSubjects*(dir: string = SubjectStoreDir): Result[seq[string], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## Deterministic listing (sorted) of all stored subject ids. A file whose
  ## name is not a canonical subject id is a store-integrity violation → err
  ## (fail-closed: garbage is never silently skipped).
  if not dirExists(dir):
    return ok(newSeq[string]())
  var ids: seq[string] = @[]
  for kind, path in walkDir(dir):
    if kind != pcFile or not path.endsWith(".json"):
      continue
    let base = extractFileName(path)
    let id = base[0 .. ^6]  # strip ".json"
    if not isSubjectId(id):
      return err("subject_store: non-canonical file in subject vault (fail-closed): " & base)
    ids.add(id)
  ids.sort()
  ok(ids)

proc findSubjectsByHeadSha*(headSha: string; dir: string = SubjectStoreDir): Result[seq[VerificationSubject], string]
    {.raises: [CatchableError, OSError, Exception], axiomEffect: IOEffect, tags: [AxiomIOEffect, IOEffect, RootEffect].} =
  ## All stored subjects matching one headSha, in deterministic
  ## (sorted-id) order. Empty headSha → err (fail-closed).
  if headSha.len == 0:
    return err("subject_store: empty headSha (fail-closed)")
  let listing = listSubjects(dir)
  if listing.isErr:
    return err(listing.error)
  var matches: seq[VerificationSubject] = @[]
  for id in listing.get:
    let loaded = loadSubject(id, dir)
    if loaded.isErr:
      return err(loaded.error)
    if loaded.get.headSha == headSha:
      matches.add(loaded.get)
  ok(matches)

{.pop.}
