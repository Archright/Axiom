import std/unittest
import ui/ax_tui_reporter

suite "Entropy-Weighted ASI":
  test "AxProofSummary carries all four ASI metric fields":
    var summary = AxProofSummary()
    summary.engineAsiFixed4 = "0.1000"
    summary.weightedAsiFixed4 = "0.2000"
    summary.entropyAsiFixed4 = "0.3000"
    summary.substantiveAsiFixed4 = "0.4000"
    check summary.engineAsiFixed4 == "0.1000"
    check summary.weightedAsiFixed4 == "0.2000"
    check summary.entropyAsiFixed4 == "0.3000"
    check summary.substantiveAsiFixed4 == "0.4000"
