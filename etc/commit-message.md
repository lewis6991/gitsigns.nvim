# Commit Message Guidelines

Read this file before creating or amending commits in this repo.

- Use the subject format `<type>(<scope>): <verb phrase>`.
- Keep the subject under 72 characters.
- Include a detailed body that explains the problem and solution.
- Wrap body and footer lines at 72 characters.
- Run `make commitlint COMMIT=HEAD` to lint your latest commit locally.
- Run `make commitlint RANGE=origin/main..HEAD` to lint a commit range.
- Run `make commitlint-hook` to install a local `commit-msg` hook.
- When scripting `git commit`, use real newlines between paragraphs,
  such as separate `-m` flags or a message file.
- Do not store literal `\n` sequences in the final commit message.
