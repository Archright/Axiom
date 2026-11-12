## regen_index.nim — Regenerate manifest.d/_index.json
import core/trusted/layer_declaration
axiomLayer "tools"
import std/[os, algorithm, strutils]

var entries: seq[string]
for f in walkDir("src/gate/manifest.d"):
  if f.kind == pcFile and f.path.endsWith(".json") and not f.path.endsWith("_index.json"):
    entries.add(extractFilename(f.path))

entries.sort()

writeFile("src/gate/manifest.d/_index.json", entries.join("\n") & "\n")
echo "Regenerated _index.json with ", entries.len, " entries"
