# CI

`.github/workflows/ci.yml` runs on every PR into `main` and on every push to `main`:

| Job | Runner | What |
|---|---|---|
| PR title | ubuntu | Conventional Commits format |
| Lint | ubuntu (SwiftLint container) | `swiftlint lint --strict` |
| Build and test | macOS | `xcodebuild test` on the visionOS simulator (the `.xcodeproj` is committed) |

`.github/workflows/release.yml` turns a `vX.Y.Z` tag into a GitHub Release with notes generated from the PRs merged
since the previous tag.

## The macOS runner

Build and test runs on GitHub's hosted `macos-26` image, which ships Xcode 26.6 and visionOS simulators up to 26.5,
the project's deployment target. If the target moves past what the image ships, check the image status at
https://github.com/actions/runner-images/blob/main/images/macos/macos-26-arm64-Readme.md.

Hosted minutes: macOS minutes count 10x. GitHub Free gives 2,000 minutes per month on private repos, so about 200
macOS minutes. Every PR runs the build once, and once more when it merges into `main`. Public repositories get
unlimited minutes.

## The checks do not block merges

GitHub enforces branch rules (required checks, required approvals) on a private repository only on a paid plan or
when the repository is public. Here a red check does not block a merge: the reviewer checks that CI is green before
merging (see CONTRIBUTING.md). The repository settings allow only squash merges and delete merged branches.
