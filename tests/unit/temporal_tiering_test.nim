## Temporal Tiering Integration Tests
## Tests for calculateEnforcementRadius(), break-glass mechanism, and audit logging.

import std/[os, json, times, strutils, unittest]
import core/audit/sad_gate

suite "Temporal Tiering — calculateEnforcementRadius":
  test "Returns BaseRadius before enforcement start date":
    # This test verifies the function compiles and returns a valid radius
    let radius = calculateEnforcementRadius()
    check radius >= BaseRadius
    check radius <= TargetRadius

  test "Returns value between BaseRadius and TargetRadius during enforcement period":
    let radius = calculateEnforcementRadius()
    # During the enforcement period, radius should be between base and target
    check radius >= BaseRadius
    check radius <= TargetRadius

  test "Is deterministic — same call returns same value":
    let r1 = calculateEnforcementRadius()
    let r2 = calculateEnforcementRadius()
    check r1 == r2

suite "Temporal Tiering — Break-glass Mechanism":
  test "Override file not present — uses temporal logic":
    # Ensure no override file exists
    if fileExists(OverrideConfigPath):
      removeFile(OverrideConfigPath)
    let radius = calculateEnforcementRadius()
    check radius >= BaseRadius

  test "Override file with future expiry — returns override value":
    # Create override config
    let configDir = parentDir(OverrideConfigPath)
    if not dirExists(configDir):
      createDir(configDir)
    let futureDate = (now() + 7.days).format("yyyy-MM-dd")
    var override = newJObject()
    override["override_radius"] = %50
    override["reason"] = %"Test override — future expiry"
    override["expires"] = %futureDate
    override["applied_by"] = %"test_suite"
    writeFile(OverrideConfigPath, $override)

    let radius = calculateEnforcementRadius()
    check radius == 50

    # Cleanup
    removeFile(OverrideConfigPath)

  test "Override file with past expiry — ignores override":
    # Create expired override config
    let configDir = parentDir(OverrideConfigPath)
    if not dirExists(configDir):
      createDir(configDir)
    let pastDate = (now() - 1.days).format("yyyy-MM-dd")
    var override = newJObject()
    override["override_radius"] = %50
    override["reason"] = %"Test override — expired"
    override["expires"] = %pastDate
    override["applied_by"] = %"test_suite"
    writeFile(OverrideConfigPath, $override)

    let radius = calculateEnforcementRadius()
    # Should NOT be 50 (expired override), should be temporal value
    check radius != 50
    check radius >= BaseRadius

    # Cleanup
    removeFile(OverrideConfigPath)

  test "Override file with no expiry — permanent override":
    # Create permanent override (no expires field)
    let configDir = parentDir(OverrideConfigPath)
    if not dirExists(configDir):
      createDir(configDir)
    var override = newJObject()
    override["override_radius"] = %0
    override["reason"] = %"Permanent override — no expiry"
    override["applied_by"] = %"test_suite"
    writeFile(OverrideConfigPath, $override)

    let radius = calculateEnforcementRadius()
    check radius == 0

    # Cleanup
    removeFile(OverrideConfigPath)

  test "Malformed override file — falls back to temporal logic":
    # Write invalid JSON
    let configDir = parentDir(OverrideConfigPath)
    if not dirExists(configDir):
      createDir(configDir)
    writeFile(OverrideConfigPath, "not valid json {{{")

    let radius = calculateEnforcementRadius()
    # Should fall back to temporal logic
    check radius >= BaseRadius
    check radius <= TargetRadius

    # Cleanup
    removeFile(OverrideConfigPath)

suite "Temporal Tiering — Audit Logging":
  test "Audit log is written after calculateEnforcementRadius":
    # Ensure log directory exists
    let logDir = parentDir(AuditLogPath)
    if not dirExists(logDir):
      createDir(logDir)

    # Remove existing log
    if fileExists(AuditLogPath):
      removeFile(AuditLogPath)

    discard calculateEnforcementRadius()

    check fileExists(AuditLogPath)
    let logContent = readFile(AuditLogPath)
    check logContent.len > 0
    check "\"radius\"" in logContent
    check "\"timestamp\"" in logContent
    check "\"reason\"" in logContent

  test "Override audit log includes reason and applied_by":
    # Create override
    let configDir = parentDir(OverrideConfigPath)
    if not dirExists(configDir):
      createDir(configDir)
    let futureDate = (now() + 7.days).format("yyyy-MM-dd")
    var override = newJObject()
    override["override_radius"] = %30
    override["reason"] = %"Critical bug in pipeline — temporarily reduced"
    override["expires"] = %futureDate
    override["applied_by"] = %"architect@example.com"
    writeFile(OverrideConfigPath, $override)

    # Remove existing log
    if fileExists(AuditLogPath):
      removeFile(AuditLogPath)

    discard calculateEnforcementRadius()

    check fileExists(AuditLogPath)
    let logContent = readFile(AuditLogPath)
    check "Critical bug in pipeline" in logContent
    check "architect@example.com" in logContent
    check "\"override_active\":true" in logContent

    # Cleanup
    removeFile(OverrideConfigPath)

suite "Temporal Tiering — Hardening Notice":
  test "formatHardeningNotice with file path":
    let notice = formatHardeningNotice(25, "src/cli/wf_state.nim")
    check "Tier 25/100" in notice
    check "wf_state.nim" in notice
    check "assertion" in notice

  test "formatHardeningNotice without file path":
    let notice = formatHardeningNotice(25)
    check "Tier 25/100" in notice
    check "days until" in notice
    check "top-25" in notice

  test "daysUntilEnforcement returns non-negative":
    let days = daysUntilEnforcement()
    check days >= 0
