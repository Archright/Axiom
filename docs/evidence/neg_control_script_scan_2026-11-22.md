# NEG-1 negative control: script-scan must block a non-Latin added line

> **Kind**: deliberate negative control. This file is NOT evidence of a product
> state; it exists to prove that the landing gate blocks an added line that carries a
> code point outside the Unicode Script allowlist.
>
> **Expected outcome**: the pull_request venue reports `publication-integrity` green
> (the `script-scan` dimension is a landing-venue dimension and is skipped on
> `pull_request`), and the `merge_group` venue fails `script-scan`, which makes
> `publication-integrity` fail and ejects the pull request from the merge queue.
>
> **After observation**: the pull request is closed without merging and the branch is
> deleted, so this file never reaches `main`.

The next line is the controlled violation. It must not be translated.

한글 한 줄.