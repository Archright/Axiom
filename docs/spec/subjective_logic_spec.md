# Subjective Logic Applied to Axiom Pre-Sieve

## Mathematical Foundation

Source: Jøsang, A. "Subjective Logic: A Formalism for Reasoning Under Uncertainty"

### Binomial Opinion
ω = (b, d, u, a) where b+d+u=1, b,d,u,a ∈ [0,1]
- b = belief mass (evidence for safety)
- d = disbelief mass (evidence for danger)
- u = uncertainty mass (ignorance)
- a = base rate (prior probability of danger)

### Probability Projection
E(ω) = b + a·u

### Cumulative Fusion (same proposition, independent observers)
b_{A⊕B} = (b_A·u_B + b_B·u_A) / (u_A + u_B - u_A·u_B)
d_{A⊕B} = (d_A·u_B + d_B·u_A) / (u_A + u_B - u_A·u_B)
u_{A⊕B} = (u_A·u_B) / (u_A + u_B - u_A·u_B)
a_{A⊕B} = (a_A·u_B + a_B·u_A) / (u_A + u_B)  [commutative]

### Binomial Product — AND (different frames, eq.4.6)
b_{x∧y} = b_x·b_y + ((1-a_x)·a_y·b_x·u_y + a_x·(1-a_y)·u_x·b_y) / (1-a_x·a_y)

### Binomial Comultiplication — OR (De Morgan, eq.4.7 corrected)
u_{x∨y} = u_x·u_y + (a_y·d_x·u_y + a_x·u_x·d_y) / (a_x+a_y-a_x·a_y)
[Note: original paper uses (1-a_y), (1-a_x); corrected via De Morgan duality]

### Negation — NOT
ω_{¬x} = (d_x, b_x, u_x, 1-a_x)

## Implementation Details

- ε-padding: u < 1e-6 → normalized to u=ε with relative-ratio preservation
- Dogmatic Case II prevention: all opinions padded before fusion
- Commutative base rate: weighted average preserves order independence
- Division by zero guard: |denom| < 1e-12 → denom = 1e-12
- Final normalization: fuseAll applies padOpinion to final result

## Axiom Pre-Sieve Application

3 rules observe the SAME proposition (code integrity) → Cumulative Fusion (⊕)
Future multi-frame: memory safety ∧ concurrency safety → Binomial Product (AND)

Opinion mapping per rule:
- topology: a=0.5 (neutral prior)
- ast: a=0.3 (conservative — AST is structurally precise)
- unsat_core: a=0.4 (moderate — Z3 is mathematically precise but incomplete)
