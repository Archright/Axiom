## tools/shared/magic_allowlist.nim
## Known Nim compiler magic procs that are available without explicit import.
## These are built-in to system.nim and should not be flagged as missing imports
## by the L1 validator.
##
## Dependencies: std/[sets] only. No src/ imports.
## Used by: tools/axiom_validator (L1)

import core/trusted/layer_declaration
axiomLayer "tools"
{.push raises: [].}

import std/sets

const
  ## Nim system.nim built-in magic procs.
  ## These are available in every module without explicit import.
  ## Source: Nim compiler's system.nim {.magic.} annotations.
  systemMagicProcs*: HashSet[string] = toHashSet([
    # I/O
    "echo", "print", "repr", "quit",
    # Arithmetic
    "inc", "dec", "succ", "pred", "abs", "sgn",
    "min", "max", "clamp", "odd",
    # Type conversion
    "ord", "chr", "high", "low", "sizeof",
    "alignof", "offsetof",
    # Memory
    "alloc", "dealloc", "realloc", "alloc0",
    "GC_ref", "GC_unref", "GC_collectGarbage",
    # String
    "add", "del", "insert", "contains",
    "startsWith", "endsWith", "find", "rfind",
    "split", "join", "strip", "repeat",
    "parseInt", "parseFloat", "parseBool",
    "intToStr", "floatToStr", "toHex", "toOct",
    # Sequence/Array
    "newSeq", "setLen", "shrink", "grow",
    "reset", "swap", "sort", "sorted", "reverse",
    "zip", "unzip", "map", "apply", "filter",
    "foldl", "foldr", "all", "any", "count",
    "deduplicate", "flatten",
    # Table/Set
    "initTable", "initHashSet", "initOrderedSet",
    # Exception
    "raise", "getCurrentException", "getCurrentExceptionMsg",
    "getStackTrace", "getStackTraceEntries",
    # System
    "defined", "declared", "new", "unsafeNew",
    "reset", "default", "typeof", "compiles",
    "addr", "unsafeAddr", "cast", "sizeOf",
    "onAlloc", "onDealloc",
    # Threads
    "createThread", "joinThread", "create",
    # Channels
    "open", "close", "send", "recv", "peek",
    # Compile-time
    "static", "staticExec", "gorge", "staticRead",
    "staticExec", "gorgeEx",
    # Miscellaneous
    "zeroMem", "copyMem", "moveMem", "equalMem",
    "atomicDec", "atomicInc", "atomicLoad", "atomicStore",
    "cas", "fence",
    # Predicates
    "isNil", "isNamed",
  ])

  ## Known Nim built-in types (also available without import).
  systemMagicTypes*: HashSet[string] = toHashSet([
    "int", "int8", "int16", "int32", "int64",
    "uint", "uint8", "uint16", "uint32", "uint64",
    "float", "float32", "float64",
    "char", "string", "bool", "byte",
    "seq", "array", "set", "openArray",
    "pointer", "ref", "ptr", "untyped", "typed",
    "typedesc", "void", "auto", "any",
    "Natural", "Positive", "BiggestInt", "BiggestFloat",
    "cint", "cuint", "csize", "csize_t",
    "cchar", "cschar", "cuchar", "cshort", "cushort",
    "clong", "culong", "clonglong", "culonglong",
    "cfloat", "cdouble", "clongdouble",
    "cstring", "TaintedString",
    "Exception", "CatchableError", "Defect",
    "IOError", "OSError", "KeyError", "ValueError",
    "RangeError", "OverflowError", "DivByZeroError",
    "IndexError", "FieldError", "ObjectConversionError",
    "FloatingPointError", "FloatInvalidOpError",
    "FloatDivByZeroError", "FloatOverflowError",
    "FloatUnderflowError", "FloatInexactError",
  ])

func isMagicProc*(name: string): bool =
  ## Check if a proc name is a known Nim built-in magic proc.
  name in systemMagicProcs

func isMagicType*(name: string): bool =
  ## Check if a type name is a known Nim built-in type.
  name in systemMagicTypes
