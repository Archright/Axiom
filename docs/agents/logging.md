# Logging, Output, and Encoding

> Extracted from AGENTS.md §5. Refer back to AGENTS.md §2 for the condensed version.

## Korean Text Corruption Prevention (Encoding & Output)

- Never use PowerShell's `echo ... >> file` or `Add-Content` for file editing. (In Windows environment, encoding is forced to UTF-16LE or CP949 causing UTF-8 file corruption)
- When file modification is needed, always use agent's dedicated File Edit tools (`SearchReplace`, `Write`, etc.) to maintain UTF-8.
- All text files are forced to UTF-8 (`charset = utf-8`, `working-tree-encoding=UTF-8`) by `.editorconfig` and `.gitattributes`.
- Nim automatically sets UTF-8 code page (`chcp 65001`) on Windows console startup, so (per `std/encodings`, `std/terminal` official docs) there are no issues during CLI execution, but explicit encoding management is essential when writing shell scripts.

## Output Principle

- Use the principle of stdout for data, stderr for operational logs as the default (diagnostics and progress notes go to stderr; machine-parsed output stays on stdout).
