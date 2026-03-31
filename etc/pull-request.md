# Pull Request Guidelines

- Create a topic branch before opening a PR. Do not open PRs from `main`.
- Ensure the local topic branch tracks its remote branch.
- Keep unrelated local files and unrelated edits out of the PR.
- Run `make build`, `make doc-check`, and the relevant `make test-*`
  targets before opening the PR.
- Use `gh pr create --base main --fill` to open the PR.
- Use the commit subject as the default PR title unless a repo-specific
  title would be clearer.
- In the PR body, describe the problem and the solution.
- Do not include testing sections or command lists in the PR body.

## Example

```bash
git switch -c ci/some-change
git add <files>
git commit ...
git push -u origin HEAD
gh pr create --base main --fill
```
