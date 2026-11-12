import std/[strutils, os, sequtils]

let manifestPath = "config/gates.manifest.toml"
let content = readFile(manifestPath)
let lines = content.splitLines()

# Split into blocks by [[gates]] markers
var blocks: seq[string] = @[]
var currentBlock: seq[string] = @[]

for line in lines:
  if line.strip() == "[[gates]]":
    if currentBlock.len > 0:
      blocks.add(currentBlock.join("\n"))
    currentBlock = @[line]
  else:
    currentBlock.add(line)

if currentBlock.len > 0:
  blocks.add(currentBlock.join("\n"))

# Filter blocks where file exists
proc hasValidFile(blockText: string): bool =
  for line in blockText.splitLines():
    let trimmed = line.strip()
    if trimmed.startsWith("file = "):
      let filePath = trimmed[8..^2]
      return fileExists(filePath)
  result = false

let validBlocks = blocks.filterIt(it.hasValidFile())

# Reconstruct file with header comments (lines before first [[gates]])
var preamble: seq[string] = @[]
for line in lines:
  if line.strip() == "[[gates]]":
    break
  preamble.add(line)

# Write output
var output = preamble.join("\n")
for _, entry in validBlocks:
  output.add("\n")
  output.add(entry)
output.add("\n")

writeFile(manifestPath, output)
echo "Cleaned manifest: removed ", blocks.len - validBlocks.len, " entries. ", validBlocks.len, " entries remain."
