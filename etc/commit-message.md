# Commit Message Guidelines

Read this file before creating or amending commits in this repo.

- Use the subject format `<type>(<scope>): <verb phrase>`.
- Keep the subject under 72 characters.
- Include a detailed body that explains the problem and solution.
- Wrap body and footer lines at 72 characters.
- When a commit resolves a specific issue, add a footer like
  `Resolves #1525`.
- Run `make commitlint COMMIT=HEAD` to lint your latest commit locally.
- Run `make commitlint RANGE=origin/main..HEAD` to lint a commit range.
- Run `make commitlint-hook` to install a local `commit-msg` hook.
- When scripting `git commit`, prefer `git commit -F <file>` for
  multi-line messages.
- If you use `-m`, pass real line breaks, not literal `\n`.
