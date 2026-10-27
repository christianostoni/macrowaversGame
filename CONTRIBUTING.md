# How we work

Six people. `main` is the merge of the finished features: it always builds and always runs.
Ask in the team chat if anything here is unclear, then fix this document in a PR.

Everything is in English: code, comments, identifiers, scripts, docs, UI text and commits (team decision, 2026-10-14).

## 1. Branches

Never push directly to `main`: everything goes through a pull request. Branch from a fresh `main`.

Branch names are optional conventions, not rules: nothing checks them. When you can, use:

| Branch | For |
|---|---|
| `feature/AR126-<n>-<slug>` | A feature |
| `fix/AR126-<n>-<slug>` | A bug fix |
| `spike/AR126-<n>-<slug>` | Throwaway research, never merged. Rename it to `feature/` to keep the work |

The Jira key links the branch to its ticket. Slugs are lowercase with dashes.

## 2. Pull requests

```bash
git switch main && git pull
git switch -c feature/AR126-12-orbit-gesture
# ...work, commit, push...
gh pr create --base main --fill            # or the GitHub UI; fill in the template
```

1. **The author** opens the PR into `main` and fills in the template: what changes and how to test it. Keep it
   small, one thing per PR. To catch up with `main`, rebase: `git pull --rebase origin main`.
2. **A teammate reviews it on their own Mac**: `gh pr checkout <number>`, build, run the unit tests (Cmd-U) and
   run the app. CI does not build or test, so this is the only build check. The simulator is enough, unless the PR
   touches hands, world sensing, immersion or comfort: then it runs on a Vision Pro.
3. **CI must be green** (PR title, Lint). GitHub does not block a merge with a red
   check on this repository, so the reviewer checks it.
4. **The reviewer approves and merges** with "Squash and merge", the only merge method enabled. The PR title becomes
   the commit on `main` and the branch is deleted automatically.

## 3. Commits

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary`, summary in the imperative,
under 72 characters. The `commit-msg` hook checks commits (enable the hooks once with
`git config core.hooksPath .githooks`) and CI checks PR titles.

Types: `feat` (something the player can notice), `fix`, `perf`, `refactor` (no behaviour change), `test`, `docs`,
`style`, `build`, `ci`, `chore`, `revert`. Scopes: `untangle`, `dragon`, `orchard`, `story`, `audio`, `ui`, `assets`.
Example: `fix(dragon): breathe fire out of the mouth`.

## 4. Before you open the PR

- `swiftlint lint --strict` passes (the `pre-commit` hook runs it on staged files, CI on everything).
- Game rules under `Model/` have unit tests and they pass (Cmd-U). Views and RealityKit code are tested by running them.
- No new warnings.

## 5. The Xcode project

`Macrowavers.xcodeproj` is committed. `Sources/Macrowavers` and `Tests/MacrowaversTests` are synced folders: a new
file under them joins the target automatically, without touching `project.pbxproj`.

- New target, build setting, capability or package: change it in Xcode and commit `project.pbxproj` in a small PR.
- Signing team: only in `Configs/Local.xcconfig` (copied from the example, gitignored). If Xcode writes a
  `DEVELOPMENT_TEAM` into the project, remove it before committing.
- Per-user state (`xcuserdata/`, `*.xcuserstate`) is gitignored and refused by the `pre-commit` hook.

## 6. Assets and Git LFS

- Every binary format in `.gitattributes` is stored in Git LFS. The `pre-commit` hook blocks files over 5 MB that
  are not.
- Sources go in `Assets/`; exports the app loads (`.usdz`, audio) go in `Sources/Macrowavers/Resources/`.
- Keep single files under 25 MB and textures at 2K unless a close-up needs 4K.
