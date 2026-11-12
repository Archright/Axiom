## SMT Dry-Run — Parse Z3 output for sort mismatches and status.
import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, osproc, strutils, json]

proc parseZ3Errors(output: string): JsonNode =
  result = %*{"raw": output, "sortMismatches": newJArray()}
  for line in output.splitLines():
    let lower = line.toLowerAscii()
    if "sort mismatch" in lower:
      result["sortMismatches"].add(%line.strip())
    elif "unsat" in lower: result["status"] = %"unsat"
    elif "sat" in lower: result["status"] = %"sat"

proc main() =
  if paramCount() < 1:
    echo "Usage: smt_dryrun <smt_file>"
    quit 1
  let content = readFile(paramStr(1))
  let (output, exitCode) = execCmdEx("z3 -smt2 -in", input = content)
  var result = parseZ3Errors(output)
  result["exitCode"] = %exitCode
  echo result.pretty()

main()
