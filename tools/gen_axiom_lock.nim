import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils, algorithm, pegs]

proc normalizeStyle(s: string): string =
  s.replace("_", "").toLowerAscii

proc extractAxiomNames(content: string): seq[string] =
  result = @[]
  # Forward: {.axiomTryImpl.} proc foo() or {.axiomTryImpl, ...} proc foo()
  let forwardPeg = peg"""
    AxiomPragma <- '{.' \s* { [a-zA-Z0-9_]+ } \s* ( ',' [^}]* )? '.}' \s*
                   ( 'proc' / 'func' ) \s+ { [a-zA-Z0-9_*]+ }
  """
  # Reverse: proc foo() {.axiomTryImpl.}
  let reversePeg = peg"""
    ReversePragma <- ( 'proc' / 'func' ) \s+ { [a-zA-Z0-9_*]+ } \s*
                     '(' [^)]* ')' [^{{]* '{.' \s* { [a-zA-Z0-9_]+ } \s*
                     ( ',' [^}]* )? '.}'
  """
  var i = 0
  while i < content.len:
    var matches: array[2, string]
    var matched = false
    # Try forward
    if content.match(forwardPeg, matches, i):
      let normalized = normalizeStyle(matches[0])
      if normalized in ["axiomtryimpl", "axiomimpl", "axiomopaque"]:
        result.add(matches[1])
      matched = true
    # Try reverse
    elif content.match(reversePeg, matches, i):
      let normalized = normalizeStyle(matches[1])
      if normalized in ["axiomtryimpl", "axiomimpl", "axiomopaque"]:
        result.add(matches[0])
      matched = true
    # Advance
    if matched:
      let nl = content.find('\n', i)
      i = if nl >= 0: nl + 1 else: content.len
    else:
      inc i

proc main() =
  var names: seq[string]
  for f in walkDirRec("src"):
    if f.endsWith(".nim") and not f.endsWith("_shadow.nim"):
      names.add(extractAxiomNames(readFile(f)))
  names.sort()
  writeFile("axiom.lock", "# Auto-generated. Do not edit.\n" & names.join("\n") & "\n")
  echo "[gen_axiom_lock] ", names.len, " axioms written."

when isMainModule: main()
