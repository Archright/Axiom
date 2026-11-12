import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
import std/[strutils, json]

type
  PushRef* = object
    localRef*: string      ## refs/heads/main
    localSha*: string      ## 40-hex
    remoteRef*: string     ## refs/heads/main
    remoteSha*: string     ## 40-hex (or 0000...0000 for new)

  PushContext* = object
    refs*: seq[PushRef]
    commits*: seq[string]  ## local SHAs being pushed

func remoteBranch*(pr: PushRef): string {.raises: [].} =
  ## Extract branch name: "refs/heads/main" -> "main"
  if pr.remoteRef.startsWith("refs/heads/"):
    pr.remoteRef["refs/heads/".len .. ^1]
  else:
    pr.remoteRef

func targetRemoteRef*(ctx: PushContext): string {.raises: [].} =
  ## First push ref's remote ref for ancestry check.
  if ctx.refs.len > 0: ctx.refs[0].remoteRef else: ""

func commitShas*(ctx: PushContext): lent seq[string] {.raises: [].} =
  ## Commit SHAs being pushed. No copy.
  ctx.commits

func parsePushStdin*(input: string): PushContext {.raises: [].} =
  ## Parse git pre-push stdin format:
  ## <local-ref> <local-sha> <remote-ref> <remote-sha>\n
  ## Exception-safe: malformed lines are silently skipped.
  for line in input.splitLines():
    try:
      let parts = line.strip().split(' ')
      if parts.len == 4:
        result.refs.add(PushRef(
          localRef: parts[0], localSha: parts[1],
          remoteRef: parts[2], remoteSha: parts[3]))
        result.commits.add(parts[1])
    except CatchableError:
      discard  # malformed line — skip

func toJson*(ctx: PushContext): JsonNode {.raises: [].} =
  ## Serialize PushContext to JSON for env var transmission
  result = newJObject()
  var refsArr = newJArray()
  for r in ctx.refs:
    refsArr.add(%* {
      "localRef": r.localRef, "localSha": r.localSha,
      "remoteRef": r.remoteRef, "remoteSha": r.remoteSha
    })
  result["refs"] = refsArr
  result["commits"] = %ctx.commits

func parsePushContext*(jsonStr: string): PushContext {.raises: [].} =
  ## Deserialize PushContext from JSON string
  ## NOTE: proc (not func) because std/json.parseJson has side effects.
  try:
    let j = parseJson(jsonStr)
    for r in j["refs"]:
      result.refs.add(PushRef(
        localRef: r["localRef"].getStr,
        localSha: r["localSha"].getStr,
        remoteRef: r["remoteRef"].getStr,
        remoteSha: r["remoteSha"].getStr))
    for c in j["commits"]:
      result.commits.add(c.getStr)
  except CatchableError:
    discard  # invalid JSON — return empty context

{.pop.}
