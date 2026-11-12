## Unit tests for DeterministicEnv — environment freezing,
## extra variable injection, and deterministic hashing.

import std/[unittest, tables, strutils]
import core/gate/deterministic_env

suite "DeterministicEnv":
  test "buildDeterministicEnv sets sourceDateEpoch from git":
    var env = buildDeterministicEnv()
    # Epoch must be positive (either git timestamp or fallback to midnight UTC)
    check env.sourceDateEpoch > 0

  test "buildDeterministicEnv includes default env vars":
    var env = buildDeterministicEnv()
    # SOURCE_DATE_EPOCH and SOURCE_DATE_ROOT are always set
    check "SOURCE_DATE_EPOCH" in env.envVars
    check "SOURCE_DATE_ROOT" in env.envVars
    check env.envVars["SOURCE_DATE_EPOCH"] == $env.sourceDateEpoch

  test "extra vars merged into envVars":
    var extras: Table[string, string]
    extras["MY_CUSTOM_VAR"] = "custom_value"
    extras["BUILD_ID"] = "42"

    var env = buildDeterministicEnv(extras)
    check env.envVars["MY_CUSTOM_VAR"] == "custom_value"
    check env.envVars["BUILD_ID"] == "42"
    # Defaults still present
    check "SOURCE_DATE_EPOCH" in env.envVars

  test "buildDeterministicHash is deterministic":
    var env1 = buildDeterministicEnv()
    var env2 = buildDeterministicEnv()
    # Force same epoch so hashes match
    env1.sourceDateEpoch = 1700000000
    env2.sourceDateEpoch = 1700000000
    let h1 = buildDeterministicHash(env1)
    let h2 = buildDeterministicHash(env2)
    check h1 == h2

  test "different epochs produce different hashes":
    var env1 = buildDeterministicEnv()
    var env2 = buildDeterministicEnv()
    env1.sourceDateEpoch = 1000000000
    env2.sourceDateEpoch = 2000000000
    check buildDeterministicHash(env1) != buildDeterministicHash(env2)

  test "toEnvTable returns the same table as envVars field":
    var env = buildDeterministicEnv()
    let tbl = toEnvTable(env)
    check tbl == env.envVars

  test "freezeTimestampForDeterministicHash produces passC flag":
    let passC = freezeTimestampForDeterministicHash(1700000000)
    check passC.startsWith("--passC:-D__DATE__=")
    check "-D__TIME__=" in passC
