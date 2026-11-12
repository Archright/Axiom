import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, strutils]

proc main() =
  var count = 0
  var foundProc = 0
  for path in walkDirRec("src"):
    if path.endsWith(".nim"):
      inc count
      if count <= 3:
        let content = readFile(path)
        let lines = content.splitLines()
        for line in lines:
          let s = line.strip()
          if s.startsWith("proc ") or s.startsWith("func "):
            inc foundProc
            if foundProc <= 5:
              stdout.write(path & ": " & s[0 .. min(60, s.len-1)] & "\n")
            break
  stdout.write("Total .nim files: " & $count & "\n")
  stdout.write("Procs found in first 3: " & $foundProc & "\n")

when isMainModule:
  main()
