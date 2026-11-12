@legacy
Feature: ax uses full routing with gate

  Scenario: ax wrapper routes prove directly to the ax proof shortcut
    Given the executable name is "ax"
    When mainLoop receives arguments ["prove", "--limit", "1"]
    Then the planned action should be cliRunAxProofShortcut
