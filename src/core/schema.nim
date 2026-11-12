## Schema-as-Code — Umbrella Re-export Module
##
## Import this single module to access all schema types, macros, and
## validation utilities from src/core/schema/*.
##
## Usage:
##   import core/schema
##
## This keeps import paths short and provides a single SSOT entry point
## for the schema subsystem. Individual sub-modules remain independently
## importable for targeted access.

import core/trusted/layer_declaration
axiomLayer "domain"
import core/schema/task_schema
export task_schema

import core/schema/policy_schema
export policy_schema

import core/schema/cst_schema
export cst_schema

import core/schema/git_schema
export git_schema

import core/schema/io_schema
export io_schema

import core/schema/schema_utils
{.push raises: [].}
export schema_utils

{.pop}
