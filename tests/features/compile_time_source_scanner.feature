Feature: Compile-Time Source Scanner — scans source files at compile time for gate metadata
  As the Axiom build system,
  I want a compile-time scanner that extracts module metadata from sources,
  So that gate manifests can be populated without runtime I/O.

  Background:
    Given the Axiom gate infrastructure is initialized

  Scenario: scanner extracts module name and exports from a source file
    Given a source file "module.nim" exporting proc "verify"
    When I run the compile-time source scanner on "module.nim"
    Then the scanner reports module "module" with export "verify"

  Scenario: scanner handles an empty source file gracefully
    Given an empty source file "empty.nim"
    When I run the compile-time source scanner on "empty.nim"
    Then the scanner reports module "empty" with no exports
