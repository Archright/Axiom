import core/trusted/layer_declaration
axiomLayer "gate"
{.push raises: [].}

## Lightweight Symbol Table types for the nimtry PNode extractor.
##
## Extracted from nimtry_extract.nim to enable import-based architecture.

import std/tables
import gate/architecture_ast_facts

type
  DeclKind* = enum
    dkProc
    dkFunc
    dkMethod
    dkVar
    dkLet
    dkConst
    dkType

  SymbolEntry* = object
    kind*: DeclKind
    exported*: bool
    location*: SourceLocation

  SymbolTable* {.acyclic.} = ref object ## All value-type fields — no cycles possible.
    symbols*: Table[string, seq[SymbolEntry]]
    imports*: seq[string] ## raw module path strings (e.g. "os", "std/strutils")

  CalleeCategory* = enum
    ccLocal      ## declared in same file
    ccImported   ## matches an import statement
    ccStdLibrary ## matches std/... or known std module
    ccUnknown    ## could not be classified

const KnownStdModules*: seq[string] = @[
  "system", "std/assertions", "std/assertions", "std/bitops",
  "std/enumutils", "std/exitprocs", "std/formatfloat",
  "std/isolation", "std/jsconsole", "std/jsfetch",
  "std/jsformdata", "std/jsheaders", "std/jsobjc",
  "std/json", "std/jsonutils", "std/lenientops",
  "std/logic", "std/macros", "std/macrocache",
  "std/math", "std/monotimes", "std/numutils",
  "std/objectdollar", "std/objectserialization",
  "std/options", "std/oserrors", "std/parsecfg",
  "std/parsecsv", "std/parseopt", "std/parsesql",
  "std/parseutils", "std/pegs", "std/paths",
  "std/posix", "std/posts", "std/prelude",
  "std/punycode", "std/rationals", "std/rcursors",
  "std/re", "std/streams", "std/strbasics",
  "std/strformat", "std/strscans", "std/strtabs",
  "std/strutils", "std/strutils", "std/sugar",
  "std/sums", "std/syncio", "std/tables",
  "std/tdblogs", "std/terminal",
  "std/threads", "std/times", "std/typedthreads",
  "std/unicode", "std/union", "std/uri",
  "std/uuid", "std/wordrecognition", "std/xmlparser",
  "std/xmltree", "std/sequtils", "std/sets",
  "std/algorithm", "std/hashes",
  # unqualified standard modules
  "os", "osproc", "strutils", "strformat", "tables",
  "sequtils", "sets", "algorithm", "hashes", "math",
  "times", "json", "jsonutils", "options", "streams",
  "terminal", "re", "pegs", "xmltree", "xmlparser",
  "macros", "sugar", "unicode", "logging", "syncio",
  "typedthreads", "threads", "cpuinfo",
  "marshal", "endians", "md5", "sha1", "base64",
  "cookies", "distros", "dynlib", "enumutils",
  "envvars", "exitprocs", "importutils", "ioutils",
  "lenientops", "lineinfos", "lists", "memfiles",
  "mistypes", "nimalone", "nimbase", "nimbasement",
  "nitivec", "packedsmallranges", "pathnorm",
  "paths", "private/pposix", "private/since",
  "puppy", "quirks", "random", "rdstdin",
  "reset", "ropes", "rst", "rstast",
  "rstgen", "segfaults", "selectors", "sha2",
  "sha3", "sharedlist", "sharedtables", "sharedqueue",
  "sqlite3", "stdin_fconsole", "stdtypes",
  "strbasics", "strscans", "strtabs",
  "subexes", "system", "system/nipl",
  "tdblogs", "testutils", "undo", "unicodeplus",
  "unittest", "varints", "wordrecognition",
  "coroutines", "fenv"
]

{.pop.}
