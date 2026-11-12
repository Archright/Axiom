import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
## IoToken — CPS Structural Enclosure for I/O Boundary Enforcement
## ============================================================
## Provides compile-time + runtime enforcement that I/O operations
## occur only within designated boundary closures.
##
## Design principles (v7 — C-level abort prevention):
##   - `=copy` is {.error.} — prevents aliasing (compile-time)
##   - `=destroy` is PURE MEMORY DEALLOCATION — no Defect raises
##     (prevents C-level abort during GC unwinding)
##   - `withIoBoundary` finally block handles protocol validation:
##     * Normal exit + unconsumed → raise AxiomLeakDefect (safe, not unwinding)
##     * Unwinding + unconsumed → append leak info to current exception msg
##   - CPS pattern: token is only accessible inside the closure
##
## AGENTS.md §0.6: Static First Enforcement
## ============================================================

import std/strutils
import core/trusted/effect_bridge  # For AxiomIOEffect

# ─── Defect Type ────────────────────────────────────────────────────────────────

type
  AxiomLeakDefect* = object of Defect
    ## Raised when IoToken is not consumed inside a withIoBoundary closure.
    ## Only raised during NORMAL EXIT (not unwinding) to avoid C-level abort.

  IoToken* = object
    ## Opaque I/O boundary token. Cannot be copied — only moved via sink.
    ## Must be consumed (marked consumed=true) before the boundary closure exits.
    consumed*: bool
    raw*: pointer
    ## raw is a sentinel pointer (cast[pointer](1) when alive, nil when dead).
    ## Used by =destroy to distinguish live tokens from moved-away tokens.

# ─── Type Operations ────────────────────────────────────────────────────────────

proc `=copy`*(dest: var IoToken; src: IoToken) {.error.} =
  ## IoToken cannot be copied. Use sink/move semantics only.
  ## This prevents aliasing — at most one reference exists at any time.

proc `=sink`*(dest: var IoToken; src: IoToken) =
  ## Move semantics: transfer ownership.
  `=destroy`(dest)
  wasMoved(dest)
  dest.raw = src.raw
  dest.consumed = src.consumed

func markConsumed*(t: var IoToken) =
  ## Mark this token as consumed. Call this after completing the I/O operation.
  t.consumed = true
  t.raw = nil

# ─── CPS Structural Enclosure ──────────────────────────────────────────────────

proc withIoBoundary*(operation: proc(t: var IoToken) {.tags: [AxiomIOEffect].}) {.raises: [CatchableError].} =
  ## Execute an I/O operation within a structural boundary.
  ## The token is created here and can ONLY be accessed inside the closure.
  ## After the closure returns (normally or via exception), the finally block
  ## validates that the token was consumed.
  ##
  ## Case 1: Normal exit + unconsumed → raise AxiomLeakDefect (safe, not unwinding)
  ## Case 2: Unwinding + unconsumed → append leak info to current exception
  ##
  ## Usage:
  ##   withIoBoundary(proc(t: var IoToken) {.tags: [AxiomIOEffect].} =
  ##     # ... do I/O work with token t ...
  ##     t.markConsumed()
  ##   )
  var token = IoToken(raw: cast[pointer](1), consumed: false)
  try:
    operation(token)
  finally:
    if not token.consumed:
      if getCurrentException() == nil:
        # Case 1: Normal exit, token not consumed — safe to raise
        raise newException(AxiomLeakDefect,
          "IoToken leak: not consumed inside synchronous boundary. " &
          "Always call t.markConsumed() after completing I/O.")
      else:
        # Case 2: Unwinding in progress — do NOT raise (would cause C-level abort)
        # Append leak info to the existing exception message
        let orig = getCurrentException()
        orig.msg = orig.msg & " [AxiomTokenLeak: IoToken not consumed]"

{.pop.}
