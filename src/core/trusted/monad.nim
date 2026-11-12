import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

## AxiomSafe[T] — sealed wrapper that only contains verified values.
## At compile time, 'unverified raw data' and 'verified data' are physically separated.
## Uses distinct type to ensure deterministic safety where mixing is impossible even by mistake.

type
  AxiomSafe*[T] = distinct T
  ## Sealed wrapper: values must be extracted via unsafeReveal.
  ## This is a compile-time contract that enforces proof of gateway passage.

## Seal a verified value as AxiomSafe. Callable only after gateway passage.
func seal*[T](value: T): AxiomSafe[T] {.inline.} =
  AxiomSafe[T](value)

## Extract raw value from AxiomSafe. Caller bears verification responsibility.
func unsafeReveal*[T](safe: AxiomSafe[T]): T {.inline.} =
  T(safe)

## AxiomSafe equality comparison (for hash chain verification).
func `==`*[T](a, b: AxiomSafe[T]): bool {.inline.} =
  unsafeReveal(a) == unsafeReveal(b)

{.pop.}

{.pop.}
