# CI

`.github/workflows/ci.yml` runs on every PR into `main` and on every push to `main`, on GitHub's Linux runners:

| Job | What |
|---|---|
| PR title | Conventional Commits format (the title becomes the squash commit on `main`) |
| Lint | `swiftlint lint --strict` in the SwiftLint container |

CI does not build the app or run the tests: macOS runners cost ten times the free minutes of a private repository.
The author and the reviewer build the PR and run the unit tests (Cmd-U) on their own Mac (see CONTRIBUTING.md).

`.github/workflows/release.yml` turns a `vX.Y.Z` tag into a GitHub Release with notes generated from the PRs merged
since the previous tag.

## The checks do not block merges

GitHub enforces branch rules (required checks, required approvals) on a private repository only on a paid plan or
when the repository is public. Here a red check does not block a merge: the reviewer checks that CI is green before
merging. The repository settings allow only squash merges and delete merged branches.
