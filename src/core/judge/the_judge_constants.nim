import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}
# axiomIoBoundary
{.push noSideEffect.}

const
  leanDefaultVarDecl* = "variable {α : Type} [Inhabited α] [LE α] [OfNat α 0}\n"
  leanDeterministicTacticBlock* = "  simpa using h_sys\n"

{.pop.}

{.pop.}
