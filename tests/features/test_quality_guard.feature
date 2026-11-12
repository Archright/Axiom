Feature: Test Quality Guard — compile-time test quality enforcement
  As the Axiom integrity engine,
  I want compile-time test quality enforcement that rejects stub-heavy or low-density test files,
  So that the test suite remains meaningful and guards against false confidence.

  Background:
    Given the test quality guard module is initialized

  @spec-density @guard-ring
  Scenario: Module compiles without errors
    Given the module source is available
    When the module is compiled
    Then it compiles without errors
    And all exported funcs have {.raises: [].} annotations

  @spec-density @guard-ring
  Scenario: check-true density rejects stub files
    Given a test file with 80% check true density
    When enforceTestQuality runs on that file
    Then compilation fails with stub rejection error

  @spec-density @guard-ring
  Scenario: check-true density allows real tests
    Given a test file with 20% check true density
    When enforceTestQuality runs on that file
    Then compilation succeeds without errors

  @spec-stub-marker @guard-ring
  Scenario: Stub marker detection on same line
    Given a test file containing 'test "foo": ## @stub'
    When countStubMarkedTests scans the file
    Then the stub count is 1 and total tests is 1

  @spec-stub-marker @guard-ring
  Scenario: Stub marker detection on preceding line
    Given a test file containing '## @stub' before a test declaration
    When countStubMarkedTests scans the file
    Then the test is counted as a stub

  @spec-stub-marker @guard-ring
  Scenario: Stub marker detection on first body line
    Given a test file with '## @stub' as the first line inside a test body
    When countStubMarkedTests scans the file
    Then the test is counted as a stub

  @spec-stub-marker @guard-ring
  Scenario: Unmarked tests are not counted as stubs
    Given a test file containing a test without ## @stub
    When countStubMarkedTests scans the file
    Then the stub count is 0

  @spec-stub-marker @guard-ring
  Scenario: Stub marker ratio enforcement
    Given a test file where 50% of tests are marked ## @stub
    When enforceStubMarkerLimit runs on that file
    Then compilation fails with stub ratio error

  @spec-stub-marker @guard-ring
  Scenario: Stub marker ratio within limits
    Given a test file where 20% of tests are marked ## @stub
    When enforceStubMarkerLimit runs on that file
    Then compilation succeeds without errors

  @spec-ttl @guard-ring
  Scenario: Temporary stub annotation is detected
    Given a test file with '{temporaryStub: [ttl: 7, debtID: "DEBT#170"]}'
    When parseTemporaryStubAnnotation parses the file
    Then it returns isTemporary=true with the correct debtID and ttl

  @spec-ttl @guard-ring
  Scenario: Files without annotation are not flagged as temporary
    Given a test file without {temporaryStub} annotation
    When parseTemporaryStubAnnotation parses the file
    Then it returns isTemporary=false

  @spec-coverage @guard-ring
  Scenario: Tier 1 modules require test files
    Given a Tier 1 core module
    When enforceCoreTestCoverage runs
    Then a test file exists for that module
