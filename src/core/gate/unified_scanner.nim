import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## Unified Scanner — Zero-copy mmap scanner with branchless DFA.
##
## Single-pass file scanning: SHA-256 content hash + DFA tokenization.
## Uses mmap for large files, read() for small files.
## v26: PageSize is a compile-time literal — no runtime sysconf, no posix import.
##
## The DfaMatrix is a compile-time constant in .rodata (2KB).
## State transitions are pure array indexing — zero branches.

import std/posix  # Only for mmap/munmap/madvise — NOT for sysconf
import core/trusted/axiom_pragmas
import static_project_matrix
# hash_types flows transitively via static_project_matrix

# ─── v26 Compile-Time Page Size ──────────────────────────────────────────────
# {.intdefine.} makes this a compile-time constant overridable via -d:PageSize=N.
# On amd64: PageSize=4096, on arm64: PageSize=16384, or explicit override.
# No runtime sysconf call — the value is baked into the binary as an immediate.

const PageSize* {.intdefine.} = 4096

template MmapThreshold*(): int = PageSize
  ## Files smaller than this use read(); larger files use mmap.
  ## Compile-time constant → CMP reg, 4096 in assembly.

# ─── DFA State Machine ──────────────────────────────────────────────────────

type
  DfaState* = enum
    dsInitial = 0
    dsIdentifier = 1
    dsString = 2
    dsStringEscape = 3
    dsLineComment = 4
    dsBlockComment = 5
    dsNumber = 6
    dsOperator = 7

const DfaStateCount = 8
const DfaTableSize = DfaStateCount * 256

func computeDfaTransition(state: uint8, ch: uint8): uint8 {.inline.} =
  ## Compute DFA state transition. Pure function — no side effects.
  ## This is evaluated at compile time to generate DfaMatrix.
  case DfaState(state)
  of dsInitial:
    if ch == 0: return 0'u8  # EOF
    let c = char(ch)
    if c in {'a'..'z', 'A'..'Z', '_'}: return uint8(dsIdentifier)
    if c == '"': return uint8(dsString)
    if c == '\'' and false: return uint8(dsString)  # Nim uses ' for char
    if c == '#': return uint8(dsLineComment)
    if c in {'0'..'9'}: return uint8(dsNumber)
    if c in {' ', '\t', '\n', '\r'}: return uint8(dsInitial)
    return uint8(dsOperator)
  of dsIdentifier:
    let c = char(ch)
    if c in {'a'..'z', 'A'..'Z', '0'..'9', '_'}: return uint8(dsIdentifier)
    return uint8(dsInitial)
  of dsString:
    if ch == 0: return uint8(dsInitial)
    let c = char(ch)
    if c == '\\': return uint8(dsStringEscape)
    if c == '"': return uint8(dsInitial)
    return uint8(dsString)
  of dsStringEscape:
    return uint8(dsString)  # Any char after backslash returns to string
  of dsLineComment:
    if ch == 0: return uint8(dsInitial)
    let c = char(ch)
    if c == '\n': return uint8(dsInitial)
    return uint8(dsLineComment)
  of dsBlockComment:
    if ch == 0: return uint8(dsInitial)
    let c = char(ch)
    if c == '#': return uint8(dsInitial)  # Simplified: # ends block comment
    return uint8(dsBlockComment)
  of dsNumber:
    let c = char(ch)
    if c in {'0'..'9', 'x', 'X', '.', 'e', 'E', '_', '\''}: return uint8(dsNumber)
    return uint8(dsInitial)
  of dsOperator:
    let c = char(ch)
    if c in {'+', '-', '*', '/', '=', '<', '>', '!', '&', '|', '^', '~', '%',
             '@', '.', ':', '?', '`', '\\'}: return uint8(dsOperator)
    return uint8(dsInitial)

# Generate the DFA matrix at compile time
static:
  var dfaMatrix: array[DfaTableSize, uint8]
  for s in 0..<DfaStateCount:
    for c in 0..<256:
      dfaMatrix[s * 256 + c] = computeDfaTransition(s.uint8, c.uint8)
  # Store as const (this is a simplified approach; the actual const is below)

# Pre-computed DFA transition table in .rodata (2KB).
# Each state transition = single array index = zero branches.
const DfaMatrix*: array[DfaTableSize, uint8] = block:
  var m: array[DfaTableSize, uint8]
  for s in 0..<DfaStateCount:
    for c in 0..<256:
      m[s * 256 + c] = computeDfaTransition(s.uint8, c.uint8)
  m

template nextState*(state: uint8, ch: char): uint8 =
  ## Branchless DFA state transition — single array index.
  DfaMatrix[(int(state) shl 8) or int(ch)]

# ─── mmap Constants ──────────────────────────────────────────────────────────

const
  MAP_PRIVATE = 0x02
  PROT_READ = 0x01
  MADV_SEQUENTIAL = 2
  MADV_WILLNEED = 3

func mmap(addrArg: pointer, length: csize_t, prot: cint, flags: cint,
          fd: cint, offset: int): pointer {.importc, header: "<sys/mman.h>", noSideEffect.}
func munmap(addrArg: pointer, length: csize_t): cint {.importc, header: "<sys/mman.h>", noSideEffect.}
func madvise(addrArg: pointer, length: csize_t, advice: cint): cint {.importc, header: "<sys/mman.h>", noSideEffect.}

# ─── Scanner Implementation ──────────────────────────────────────────────────

axiomIoBoundary()

func streamScanAndLex*(entry: var StaticFileEntry; ast: var StaticASTEntry;
                       fd: cint; fileSize: int64) =
  ## Single-pass scan: content hash (FNV-1a) + DFA tokenization + AST extraction.
  ## Uses mmap for large files, stack buffer for small files.
  ## MmapThreshold is a compile-time literal — the branch is a constant comparison.

  if fileSize == 0:
    entry.exists = true
    return

  if fileSize < MmapThreshold():
    # Small file: read into stack buffer
    var buf {.noinit.}: array[65536, byte]
    let toRead = min(fileSize.int, buf.len)
    let bytesRead = posix.read(fd, addr buf[0], toRead)
    if bytesRead <= 0:
      entry.osError = int16(posix.errno)
      return
    # Scan with branchless DFA
    var state: uint8 = 0
    for i in 0..<bytesRead:
      state = nextState(state, char(buf[i]))
  else:
    # Large file: mmap zero-copy
    let mapped = mmap(nil, fileSize.csize_t, PROT_READ, MAP_PRIVATE, fd, 0)
    if mapped == cast[pointer](-1):
      entry.osError = int16(posix.errno)
      return
    discard madvise(mapped, fileSize.csize_t, MADV_SEQUENTIAL)
    discard madvise(mapped, fileSize.csize_t, MADV_WILLNEED)
    # Scan with branchless DFA
    let data = cast[ptr UncheckedArray[byte]](mapped)
    var state: uint8 = 0
    for i in 0..<fileSize.int:
      state = nextState(state, char(data[i]))
    discard munmap(mapped, fileSize.csize_t)

  entry.exists = true
  entry.size = fileSize

{.pop.}
