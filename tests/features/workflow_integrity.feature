@legacy
@workflow @integrity
Feature: Workflow Integrity Enforcement
  Agents must follow established integrity procedures when modifying global rules and features.

  Rule: CONTEXT.md must be updated first when changing global rules
    Scenario: When a requirement affects global rules
      Given a new requirement affecting global rules has arisen
      When about to modify code
      Then the requirement must be reflected in CONTEXT.md document first

  Rule: BDD scenarios must be defined first for CONTEXT.md feature changes
    Scenario: When reflecting feature changes in CONTEXT.md
      Given there are functional changes to CONTEXT.md
      When about to modify the document
      Then BDD(Given-When-Then) scenarios must be defined in .feature files first

  Rule: Minimal changes through TDD
    Scenario: When starting implementation after scenario definition and approval
      Given BDD scenarios are defined and approved
      When starting implementation
      Then failing tests must be written first using TDD
      And only minimal code changes that pass tests must be reflected

  Rule: Bug reproduction and user scenario fixation
    Scenario: When implementing bug fixes or new user scenarios
      Given a bug is discovered or there is a new user requirement
      When performing implementation
      Then a BDD test (feature file) reproducing the situation must be written and fixed

  Rule: 100% test coverage enforcement
    Scenario: When attempting to commit code
      Given code changes are complete
      When running prek tests
      Then test coverage must satisfy 100%
      And commits must be blocked by quality gate if below 100%
  Rule: Quality gate must block commits without CONTEXT.md and BDD/TDD updates
    Scenario: When src/ changes are staged without CONTEXT.md update
      Given a change has been made to files under src/
      And CONTEXT.md has not been updated
      When a commit is attempted via git commit
      Then the pre-commit quality gate must block the commit with exit code 1

    Scenario: When src/ changes are staged without BDD scenario update
      Given a change has been made to files under src/
      And no .feature file in tests/bdd/ or tests/features/ has been modified
      When a commit is attempted via git commit
      Then the pre-commit quality gate must block the commit with exit code 1

    Scenario: When src/ changes are staged without gateway test update
      Given a change has been made to files under src/
      And no test file in tests/gateway/ has been modified
      When a commit is attempted via git commit
      Then the pre-commit quality gate must block the commit with exit code 1
