Feature: JSON utility functions
  As a developer
  I want safe JSON parsing utilities
  So that I can handle malformed JSON without crashes

  Scenario: Parse valid JSON string
    Given a valid JSON string
    When parseJsonOpt is called
    Then it returns Some with the parsed JSON node

  Scenario: Parse invalid JSON string
    Given a malformed JSON string
    When parseJsonOpt is called
    Then it returns None without raising an exception

  Scenario: Parse empty string
    Given an empty string
    When parseJsonOpt is called
    Then it returns None
