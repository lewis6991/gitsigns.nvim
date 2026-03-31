# Pull Request Guidelines

- Create a topic branch before opening a PR. Do not open PRs from `main`.
- Keep unrelated local files and unrelated edits out of the PR.
- Run `make build`, `make doc-check`, and the relevant `make test-*`
  targets before opening the PR.
- Use `gh pr create --base main --fill` to open the PR.
- Use the commit subject as the default PR title unless a repo-specific
  title would be clearer.
- In the PR body, describe the change and the problem it aims to solve.

## Example

```bash
git switch -c ci/some-change
git add <files>
git commit ...
git push -u origin HEAD
gh pr create --base main --fill
```
