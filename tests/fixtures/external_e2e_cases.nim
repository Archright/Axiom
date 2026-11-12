type
  ExternalOutcome* = enum
    eoProved
    eoDisproved
    eoUnknown
    eoUnsupported
    eoNoSpecification
    eoBlocked

  E2ECase* = object
    source*: string
    expectedOutcome*: ExternalOutcome

const
  OutcomeGolden*: seq[E2ECase] = @[
    E2ECase(
      source: "func add(x, y: int): int {.axiom: \"result == x + y\".} = x + y",
      expectedOutcome: eoProved
    ),
    E2ECase(
      source: "func alwaysZero(x: int): int {.axiom: \"result == 0\".} = x + 1",
      expectedOutcome: eoDisproved
    ),
    E2ECase(
      source: "func findMax(arr: seq[int], n: int): int {.axiom: \"result >= 0\".} = var m = 0; for i in 0..<n: if arr[i] > m: m = arr[i]; m",
      expectedOutcome: eoUnknown
    ),
    E2ECase(
      source: "func bitShift(x: int, n: int): int {.axiom: \"result == x * 2^n\".} = x shl n",
      expectedOutcome: eoUnsupported
    ),
    E2ECase(
      source: "func bareAdd(x, y: int): int = x + y",
      expectedOutcome: eoNoSpecification
    ),
    E2ECase(
      source: "func dependsOnHelper(x: int): int {.axiom: \"result == helper(x) + 1\".} = helper(x) + 1",
      expectedOutcome: eoBlocked
    ),
  ]