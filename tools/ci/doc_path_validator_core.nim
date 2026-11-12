## doc_path_validator_core.nim — pure reference-resolution core for doc path validation
##
## The document reference contract (docs/spec/document_reference_contract.md) is the
## single source of truth for how documentation file-path references are resolved when
## the target is ABSENT in a fresh clone. This module holds the PURE decision logic:
##   - the reference policy value types,
##   - the pure manifest parser (JSON string → config),
##   - the per-path policy lookup (fail-closed default MUST_EXIST),
##   - the absence-resolution decision (whether a missing target is permitted),
##   - path canonicalization + unused-entry detection (S8),
##   - a display-only reason projection.
##
## It performs NO I/O and NO `make` probing. `probeMakeTarget` (I/O + subprocess) and the
## file-reading `loadReferencePolicy` wrapper live in doc_path_validator.nim; this module
## receives their results as plain values (`TargetProbe`, `ReferencePolicyConfig`), so the
## decision path is deterministic and unit-testable with no filesystem/Make dependency.

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/[json, options, strutils, tables]

type
  TargetProbe* = enum
    ## Tri-state result of probing a canonical reproducer target via `make -n`.
    ## Distinguishes "target exists" from "target absent" from "probe itself failed".
    ## A probe failure is NEVER collapsed into absence/existence (fail-closed): a
    ## missing prerequisite (same exit 2 but naming a different target), a parse
    ## error, or a missing `make` binary must NOT be silently read as ABSENT.
    tpExists
    tpAbsent
    tpProbeError

  ResolveReason* = enum
    ## Minimal decision states produced by the pure resolver and the unused-entry
    ## checker. Human-facing wording is delegated to `reasonText`; decision logic
    ## switches on the enum only.
    rrOk                      ## reference resolves (historical/external absent, generated+exists-reproducer, must_exist present)
    rrMustExistFailed         ## unclassified/must_exist target absent
    rrGeneratedNoReproducer   ## GENERATED_ALLOWED but no canonical reproducer declared
    rrTargetAbsent            ## GENERATED_ALLOWED, reproducer target absent (tpAbsent)
    rrProbeError              ## reproducer probe failed (tpProbeError) — unverifiable, never promoted
    rrMalformedPolicy         ## policy manifest unparseable/invalid
    rrUnusedPolicy            ## declared policy entry never referenced by any active doc

  ReferencePolicy* = enum
    rpMustExist, rpHistoricalAllowed, rpGeneratedAllowed, rpExternalAllowed

  ReferencePolicyEntry* = object
    policy*: ReferencePolicy
    reproducerTarget*: string  ## canonical `make <target>` identity; REQUIRED & non-empty for
                               ## rpGeneratedAllowed; forbidden otherwise.

  ReferencePolicyConfig* = object
    entries*: Table[string, ReferencePolicyEntry]
    malformed*: bool           ## manifest present but unparseable/invalid → fail-closed
    malformedReason*: string

const referencePolicyNames*: array[ReferencePolicy, string] = [
  "MUST_EXIST", "HISTORICAL_ALLOWED", "GENERATED_ALLOWED", "EXTERNAL_ALLOWED"
]

func parseReferencePolicy*(value: string): Option[ReferencePolicy] =
  ## Pure: canonicalize a manifest `policy` string into a ReferencePolicy.
  case value.toLowerAscii()
  of "must_exist":         result = some(rpMustExist)
  of "historical_allowed": result = some(rpHistoricalAllowed)
  of "generated_allowed":  result = some(rpGeneratedAllowed)
  of "external_allowed":   result = some(rpExternalAllowed)
  else: result = none(ReferencePolicy)

proc parseReferencePolicyConfig*(raw: string): ReferencePolicyConfig =
  ## Pure (in behavior): parse a policy-manifest JSON document into a
  ## ReferencePolicyConfig. Declared `proc` rather than `func` because the stdlib
  ## `parseJson` is annotated `.sideEffect`; it performs no I/O and its raises are
  ## fully contained by the try/except, so the result is deterministic and
  ## unit-testable with a plain string input.
  ## On any invalid input the result is marked malformed (fail-closed) — never a
  ## silent empty config. An entry may carry {policy, [reproducerTarget], [comment]};
  ## any other per-reference key (e.g. a stray `authority`) is a hard malformed.
  var j: JsonNode
  try:
    j = parseJson(raw)
  except:
    result.malformed = true
    result.malformedReason = "unparseable JSON"
    return
  if j.kind != JObject:
    result.malformed = true
    result.malformedReason = "top-level must be a JSON object"
    return
  for key, node in j:
    if node.kind != JObject:
      result.malformed = true
      result.malformedReason = "entry '" & key & "' must be a JSON object"
      return
    # Reject any per-entry key beyond {policy, reproducerTarget, comment}
    # (INVARIANT-DRP-6). `comment` is a permissible inert documentation field;
    # any other stray key (e.g. a semantic field like `authority`) is a hard
    # malformed so it can never influence resolution.
    for fkey in node.fields.keys:
      if fkey != "policy" and fkey != "reproducerTarget" and fkey != "comment":
        result.malformed = true
        result.malformedReason = "entry '" & key & "' has unknown field '" & fkey & "'"
        return
    let polNode = node{"policy"}
    if polNode == nil or polNode.kind != JString:
      result.malformed = true
      result.malformedReason = "entry '" & key & "' missing string 'policy'"
      return
    let pol = parseReferencePolicy(polNode.str)
    if pol.isNone:
      result.malformed = true
      result.malformedReason = "entry '" & key & "' has unknown policy '" & polNode.str & "'"
      return
    var entry = ReferencePolicyEntry(policy: pol.get)
    let rt = node{"reproducerTarget"}
    if rt != nil:
      if rt.kind != JString:
        result.malformed = true
        result.malformedReason = "entry '" & key & "' 'reproducerTarget' must be a string"
        return
      entry.reproducerTarget = rt.str.strip()
    # GENERATED_ALLOWED WITHOUT a declared reproducer is not "malformed" — it is a
    # precise, resolvable decision rrGeneratedNoReproducer (FAIL) at resolve time.
    result.entries[key] = entry

func referencePolicyFor*(cfg: ReferencePolicyConfig, path: string): ReferencePolicyEntry =
  ## Pure: returns the declared policy for *path*, defaulting to MUST_EXIST (fail-closed).
  ## The path is consumed ONLY here — it is not threaded into the resolver.
  result = cfg.entries.getOrDefault(path, ReferencePolicyEntry(policy: rpMustExist))

func resolveReferencePolicy*(entry: ReferencePolicyEntry,
                             probe: TargetProbe): tuple[allowed: bool, reason: ResolveReason] =
  ## Pure: decides whether ABSENCE of a referenced path is permitted under *entry*'s
  ## policy. For GENERATED_ALLOWED, *probe* is the make -n tri-state of the reproducer
  ## target; for all other policies *probe* is ignored (the caller passes a sentinel).
  ## The `path` is deliberately NOT passed: it is only needed for lookup, which the
  ## caller already performed via referencePolicyFor.
  case entry.policy
  of rpMustExist:
    result = (false, rrMustExistFailed)               # INVARIANT-DRP-2
  of rpHistoricalAllowed, rpExternalAllowed:
    result = (true, rrOk)                              # INVARIANT-DRP-3 / DRP-5
  of rpGeneratedAllowed:
    if entry.reproducerTarget.len == 0:
      result = (false, rrGeneratedNoReproducer)        # INVARIANT-DRP-4
    else:
      case probe
      of tpExists:     result = (true, rrOk)           # INVARIANT-DRP-4/4a
      of tpAbsent:     result = (false, rrTargetAbsent)
      of tpProbeError: result = (false, rrProbeError)  # fail-closed: never promoted to allowed

func canonicalizePath*(path: string): string =
  ## Pure, case-agnostic canonical normal form for comparing doc references against
  ## policy-manifest keys. NOT a filesystem resolution — it only normalizes textual
  ## path shape so that the same logical path cannot differ only by case, slash style,
  ## `.`/`..`, duplicate separators, or trailing slash. Comparison MUST go through this
  ## before the cross-check (S8), otherwise identical paths could be mis-flagged as
  ## unused due to irrelevant textual variance.
  var s = path.strip().replace('\\', '/')
  # collapse duplicate leading separators to a single root slash
  while s.startsWith("//"):
    s = s[1 .. ^1]
  # drop leading "./"
  while s.startsWith("./"):
    s = s[2 .. ^1]
  # normalize element separators / resolve "." and ".." textually
  var parts: seq[string] = @[]
  for seg in s.split('/'):
    if seg.len == 0 or seg == ".":
      continue
    if seg == "..":
      if parts.len > 0:
        discard parts.pop()
      continue
    parts.add(seg)
  result = parts.join("/").toLowerAscii()
  # strip a lone trailing slash (produced by a split artifact) without nuking root
  while result.len > 1 and result.endsWith("/"):
    result = result[0 .. ^2]

func findUnusedPolicyEntries*(cfg: ReferencePolicyConfig,
                              referencedPaths: openArray[string]): seq[string] =
  ## Pure (S8): returns the manifest keys that are declared but whose canonical form
  ## never appears among the canonicalized set of actually-referenced paths. A declared
  ## carve-out that no active doc reference uses is a dead exception → the caller must
  ## FAIL. Determination is gated on `referencedPaths` having been canonicalized by the
  ## caller (dependency on extraction recall documented in the contract).
  var refSet: Table[string, bool]
  for p in referencedPaths:
    refSet[canonicalizePath(p)] = true
  for key in cfg.entries.keys:
    if not refSet.hasKey(canonicalizePath(key)):
      result.add(key)

func reasonText*(code: ResolveReason): string =
  ## Display-only projection of a decision state. Never used for decision logic —
  ## the enum itself is authoritative.
  case code
  of rrOk:                  "reference resolves (absence permitted by policy)"
  of rrMustExistFailed:     "unclassified/MUST_EXIST target absent — reference must resolve"
  of rrGeneratedNoReproducer: "GENERATED_ALLOWED without a canonical reproducer target"
  of rrTargetAbsent:        "GENERATED_ALLOWED reproducer target does not exist"
  of rrProbeError:          "reproducer probe failed — could not confirm target (unverifiable)"
  of rrMalformedPolicy:     "policy manifest is malformed"
  of rrUnusedPolicy:        "policy entry is declared but never referenced by any active doc"
