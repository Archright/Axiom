import core/trusted/layer_declaration
axiomLayer "domain"
{.push raises: [].}

## OGR / PAR Metrics — pure computation functions.
##
## OGR (Obligation Grounding Rate): fraction of VKS targets that have
## at least one generated obligation.
## PAR (Proof Attempt Rate): fraction of generated obligations that were
## actually attempted (entered proofAttempted phase).
##
## Both functions are pure ({.raises: [].}) and deterministic.
## VKD definition is unchanged — these are auxiliary metrics only.

type
  OgPMetrics* = object
    ogr*: float  ## Obligation Grounding Rate: targetsWithObligations / eligibleTargets
    par*: float  ## Proof Attempt Rate: attempted / generated

func computeOgrPar*(
  eligibleTargets: int,
  targetsWithObligations: int,
  generated: int,
  attempted: int
): OgPMetrics {.raises: [].} =
  ## Pure computation of OGR and PAR from raw counts.
  ##
  ## OGR = |targets with obligations>0| / |eligible targets|
  ## PAR = |attempted| / |generated|
  ##
  ## Zero-denominator guard: returns 0.0 for the affected metric
  ## when the denominator is 0 (no eligible targets or no generated
  ## obligations). This is the mathematically correct limit and
  ## avoids division-by-zero without special-casing in callers.
  let ogr = if eligibleTargets > 0:
      targetsWithObligations.float / eligibleTargets.float
    else: 0.0
  let par = if generated > 0:
      attempted.float / generated.float
    else: 0.0
  OgPMetrics(ogr: ogr, par: par)

{.pop.}
