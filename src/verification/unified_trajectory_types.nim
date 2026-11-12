import core/trusted/layer_declaration
axiomLayer "infrastructure"
{.push raises: [].}
# axiomIoBoundary

## Unified Trajectory Types — Pure type definitions for pipeline stage tracking.
##
## Extracted from unified_trajectory.nim to enforce Layer Boundary policy:
## core/ modules may only import pure type modules from verification/.

type
  StageKind* = enum
    skCliEntry       ## CLI 진입 (args, flags)
    skTopology       ## 토폴로지 스캔
    skPreSieve       ## Pre-Sieve (Subjective Logic)
    skSwat           ## SWAT/BMC Layer 1
    skCegar          ## CEGAR Layer 2
    skKInduction     ## k-Induction 폴백
    skLegislator     ## Legislator (LLM 불변량)
    skScribe         ## Scribe (Lean 전술)
    skJudge          ## Judge (Lean 커널)
    skCertificate    ## 인증서 생성
    skReport         ## 보고서 생성
    skRunAccounting  ## X1 canonical run accounting (CanonicalRunResult reference record)

  StageStatus* = enum
    ssStarted
    ssSucceeded
    ssFailed
    ssTimeout
    ssBlocked        ## Pre-Sieve 차단
    ssSkipped        ## 예산 부족으로 건너뜀

const trajectoryLogPath* = "logs/ax_prove_trajectory.jsonl"

{.pop.}
