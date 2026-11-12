import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
## Subjective Logic engine for Pre-Sieve evidence synthesis.
## Based on Jøsang's Subjective Logic theory.
## All functions are pure (func) — zero heap allocation, O(1) operations.

const epsilon* = 1e-6

type BinomialOpinion* = object
  b*, d*, u*, a*: float  ## belief, disbelief, uncertainty, base rate

func validate*(omega: BinomialOpinion): bool {.raises: [].} =
  abs(omega.b + omega.d + omega.u - 1.0) < 1e-9

func padOpinion*(omega: BinomialOpinion): BinomialOpinion {.raises: [].} =
  ## ε-padding with relative-ratio preservation normalization.
  ## Ensures u >= epsilon for all opinions (prevents dogmatic Case II).
  if omega.u < epsilon:
    let currentBd = omega.b + omega.d
    if currentBd < 1e-12:
      return BinomialOpinion(b: 0.0, d: 1.0 - epsilon, u: epsilon, a: omega.a)
    let scale = (1.0 - epsilon) / currentBd
    BinomialOpinion(b: omega.b * scale, d: omega.d * scale, u: epsilon, a: omega.a)
  else:
    omega

func probabilityProjection*(omega: BinomialOpinion): float {.raises: [].} =
  ## E = b + a·u — expected probability of danger
  omega.b + omega.a * omega.u

# ── Cumulative Fusion (same proposition, independent observers) ──
# Jøsang eq. 4.96 — with commutative base rate averaging

func cumulativeFusion*(x, y: BinomialOpinion): BinomialOpinion {.raises: [].} =
  let wa = padOpinion(x)
  let wb = padOpinion(y)
  let denom = wa.u + wb.u - wa.u * wb.u
  BinomialOpinion(
    b: (wa.b * wb.u + wb.b * wa.u) / denom,
    d: (wa.d * wb.u + wb.d * wa.u) / denom,
    u: (wa.u * wb.u) / denom,
    a: (wa.a * wb.u + wb.a * wa.u) / (wa.u + wb.u))

func fuseAll*(opinions: seq[BinomialOpinion]): BinomialOpinion {.raises: [].} =
  ## Fuse all opinions via cumulative fusion. Returns padded result.
  if opinions.len == 0: return BinomialOpinion(b: 0.0, d: 0.0, u: 1.0, a: 0.5)
  if opinions.len == 1: return padOpinion(opinions[0])
  result = opinions[0]
  for i in 1 ..< opinions.len:
    result = cumulativeFusion(result, opinions[i])
  result = padOpinion(result)

# ── Binomial Product — AND (different frames, conjunction) ──
# Jøsang eq. 4.6

func binomialAnd*(x, y: BinomialOpinion): BinomialOpinion {.raises: [].} =
  let wa = padOpinion(x)
  let wb = padOpinion(y)
  let ax = wa.a
  let ay = wb.a
  let rawDenom = 1.0 - ax * ay
  let denom = if abs(rawDenom) < 1e-12: 1e-12 else: rawDenom
  BinomialOpinion(
    b: wa.b * wb.b + ((1-ax)*ay*wa.b*wb.u + ax*(1-ay)*wa.u*wb.b) / denom,
    d: wa.d + wb.d - wa.d * wb.d,
    u: wa.u * wb.u + ((1-ay)*wa.b*wb.u + (1-ax)*wa.u*wb.b) / denom,
    a: ax * ay)

# ── Binomial Comultiplication — OR (different frames, disjunction) ──
# Derived via De Morgan: x∨y = NOT(NOT x ∧ NOT y)
# Corrected u-formula: uses a_y, a_x (NOT (1-a_y), (1-a_x))

func binomialOr*(x, y: BinomialOpinion): BinomialOpinion {.raises: [].} =
  let wa = padOpinion(x)
  let wb = padOpinion(y)
  let ax = wa.a
  let ay = wb.a
  let rawDenom = ax + ay - ax * ay
  let denom = if abs(rawDenom) < 1e-12: 1e-12 else: rawDenom
  BinomialOpinion(
    b: wa.b + wb.b - wa.b * wb.b,
    d: wa.d * wb.d + (ax*(1-ay)*wa.d*wb.u + (1-ax)*ay*wa.u*wb.d) / denom,
    u: wa.u * wb.u + (ay*wa.d*wb.u + ax*wa.u*wb.d) / denom,
    a: rawDenom)

# ── Negation — NOT ──

func binomialNot*(x: BinomialOpinion): BinomialOpinion {.raises: [].} =
  BinomialOpinion(b: x.d, d: x.b, u: x.u, a: 1.0 - x.a)
{.pop.}
