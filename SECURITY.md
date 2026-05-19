# Security

Publican runs local Homebrew commands on the user's Mac. Please treat command construction, confirmation prompts, and output parsing as security-sensitive.

## Reporting Security Issues

Please do not open a public issue for a security problem.

For now, report security concerns privately to the project maintainer before disclosure. If a public contact address is added later, this file should be updated.

## Safety Expectations

- Mutating commands must show the exact `brew` command before execution.
- Publican should not run destructive commands silently.
- Publican should not request administrator credentials itself.
- Homebrew ownership or permission fixes should be explained, not performed automatically.
- Release builds should be signed and notarised before broad public distribution.
