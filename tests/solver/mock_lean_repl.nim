## Lean REPL JSON 프로토콜 에뮬레이터
## docs/spec/lean_repl_protocol.md 스펙을 정확히 구현한다.
## 각 시나리오에 대해 mock 응답 = 실제 Lean 4 응답

import std/[json, streams, strutils]

proc mockLeanRepl*(inputStream: Stream, outputStream: Stream) =
  ## Run the mock REPL loop. Reads JSON commands, writes JSON responses.
  ## Protocol: commands separated by blank lines, responses are single JSON lines.
  var envCounter = 0

  while true:
    # Read lines until blank line (Lean REPL protocol delimiter)
    var lines: seq[string]
    try:
      while true:
        let line = inputStream.readLine()
        if line.len == 0:
          break
        lines.add(line)
    except EOFError, IOError:
      break  # §7: EOF / broken pipe → clean exit

    if lines.len == 0:
      break

    let rawInput = lines.join("\n")

    # Skip comments (# or --)
    if rawInput.startsWith("#") or rawInput.startsWith("--"):
      continue

    var request: JsonNode
    try:
      request = parseJson(rawInput)
    except JsonParsingError:
      outputStream.write("{\"env\": " & $envCounter & ",\"messages\":[{\"severity\":\"error\",\"data\":\"invalid JSON\"}]}\n")
      outputStream.flush()
      continue

    let cmd = request{"cmd"}.getStr("")
    if cmd.len == 0:
      continue

    # #exit command
    if cmd == "#exit":
      break

    # §2: explicit env tracking
    let reqEnv = request{"env"}.getInt(-1)
    if reqEnv >= 0:
      envCounter = reqEnv + 1
    else:
      inc envCounter

    var response = newJObject()
    response["env"] = %*envCounter
    response["messages"] = newJArray()

    # §5: sorry detection
    if "sorry" in cmd:
      response["sorries"] = %*[{"goal": "⊢ sorry", "proofState": 0}]

    # §3: tactic mode detection (ends with 'by')
    if cmd.strip().endsWith(":= by"):
      response["proofStates"] = %*[0]
      # Extract goal from command
      let parts = cmd.split(": ")
      if parts.len >= 2:
        let goalPart = parts[^1].split(" :=")[0]
        response["goals"] = %*["⊢ " & goalPart]
      else:
        response["goals"] = %*["⊢ True"]

    outputStream.write($response & "\n")
    outputStream.flush()

when isMainModule:
  ## stdin/stdout mode for subprocess pipe testing
  mockLeanRepl(newFileStream(stdin), newFileStream(stdout))
