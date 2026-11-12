{.push raises: [].}

## Fuzz input generator for AFL PBT gate.
##
## Generates a corpus of edge-case inputs for `fuzz_gate.nim`.
## Outputs one file per test case into the corpus directory.
##
## Usage: nim c -r tests/fuzz/generate_fuzz_input.nim [output_dir]
## Default output_dir: tests/fuzz/corpus/

import std/[os, strutils]

const
  DefaultCorpusDir = "tests/fuzz/corpus"

# ---------------------------------------------------------------------------
# Edge-case generators
# ---------------------------------------------------------------------------

func emptyInput(): string = ""

func whitespaceOnly(): seq[string] =
  @[" ", "\t", "\n", "\r\n", "   \t\n  "]

func numericEdgeCases(): seq[string] =
  @[
    "0",
    "1",
    "-1",
    "2147483647",     # int32 max
    "-2147483648",    # int32 min
    "2147483648",     # int32 overflow
    "-2147483649",    # int32 underflow
    "9223372036854775807",  # int64 max
    "-9223372036854775808", # int64 min
    "99999999999999999999", # exceeds int64
    "00000",
    "-0",
    "+1",
    "1_000_000",      # Nim underscore notation
    "0x10",           # hex
    "0o10",           # octal
    "0b1010",         # binary
    "1e10",           # scientific
    "3.14",           # float
    "NaN",
    "Inf",
    "-Inf",
  ]

func specialCharacters(): seq[string] =
  @[
    "!",
    "@",
    "#",
    "$",
    "%",
    "^",
    "&",
    "*",
    "(",
    ")",
    "-",
    "=",
    "+",
    "[",
    "]",
    "{",
    "}",
    "\\",
    "|",
    ";",
    ":",
    "'",
    "\"",
    "<",
    ">",
    ",",
    ".",
    "/",
    "?",
    "`",
    "~",
  ]

func jsonEdgeCases(): seq[string] =
  @[
    "{}",
    "[]",
    "null",
    "true",
    "false",
    "\"\"",
    "{\"key\": \"value\"}",
    "[1, 2, 3]",
    "{\"nested\": {\"a\": 1}}",
    "{invalid json",
    "null byte: \x00",
    "unclosed {",
    "unclosed [",
    "trailing comma,",
    "{\"key\": }",
    "NaN",           # not valid JSON
    "undefined",     # not valid JSON
  ]

func longStrings(): seq[string] =
  @[
    'A'.repeat(256),
    'B'.repeat(1024),
    'C'.repeat(4096),
    '0'.repeat(10000),
  ]

func unicodeEdgeCases(): seq[string] =
  @[
    "\u0000",        # null byte
    "\u0001",        # SOH
    "\u001f",        # unit separator
    "\u0080",        # first non-ASCII
    "\u00ff",        # latin-1 boundary
    "\u0100",        # first latin extended
    "\u4e00",        # CJK start
    "\uffff",        # BMP end
    "한글",           # Korean
    "🎉",            # emoji (multi-byte)
    "\xef\xbb\xbf",  # UTF-8 BOM
  ]

func boundaryStrings(): seq[string] =
  @[
    "null\x00byte",
    "line\nbreak",
    "tab\there",
    "cr\rreturn",
    "crlf\r\n",
    "\t\t\t",
    "\n\n\n",
  ]

# ---------------------------------------------------------------------------
# Corpus writer
# ---------------------------------------------------------------------------

proc writeCorpusFile(dir: string, name: string, content: string) =
  let path = dir / name
  try:
    writeFile(path, content)
  except IOError:
    echo "Warning: failed to write " & path

proc generateCorpus(outputDir: string) =
  ## Generate full fuzz corpus into outputDir.
  try:
    createDir(outputDir)
  except CatchableError:
    echo "Error: cannot create directory " & outputDir
    return
  var count = 0

  # Empty
  writeCorpusFile(outputDir, "empty.txt", emptyInput())
  inc count

  # Whitespace
  for i, ws in whitespaceOnly():
    writeCorpusFile(outputDir, "ws_" & $i & ".txt", ws)
    inc count

  # Numeric edge cases
  for i, num in numericEdgeCases():
    writeCorpusFile(outputDir, "num_" & $i & ".txt", num)
    inc count

  # Special characters
  for i, ch in specialCharacters():
    writeCorpusFile(outputDir, "special_" & $i & ".txt", ch)
    inc count

  # JSON edge cases
  for i, j in jsonEdgeCases():
    writeCorpusFile(outputDir, "json_" & $i & ".txt", j)
    inc count

  # Long strings
  for i, ls in longStrings():
    writeCorpusFile(outputDir, "long_" & $i & ".txt", ls)
    inc count

  # Unicode
  for i, uc in unicodeEdgeCases():
    writeCorpusFile(outputDir, "unicode_" & $i & ".txt", uc)
    inc count

  # Boundary strings
  for i, bs in boundaryStrings():
    writeCorpusFile(outputDir, "boundary_" & $i & ".txt", bs)
    inc count

  echo "Generated " & $count & " corpus files in " & outputDir

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

when isMainModule:
  let args = commandLineParams()
  let outputDir = if args.len > 0: args[0] else: DefaultCorpusDir
  generateCorpus(outputDir)
