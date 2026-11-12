import std/[unittest, json]
import verification/state_manager

suite "Algebraic Safety Guard":
  test "certIntrinsic node is excluded from reset":
    let entry = %*{"status": "certIntrinsic", "attemptCount": 999}
    check shouldResetHealAttemptEntry(entry) == false

  test "node with successCount > 0 is excluded from reset":
    let entry = %*{"status": "unattempted", "attemptCount": 999, "successCount": 1}
    check shouldResetHealAttemptEntry(entry) == false

  test "normal high-attempt node is still reset":
    let entry = %*{"status": "unattempted", "attemptCount": 999, "successCount": 0}
    check shouldResetHealAttemptEntry(entry) == true
