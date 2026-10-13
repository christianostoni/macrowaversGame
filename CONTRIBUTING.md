# How we work

Five people, 40 days, one-week sprints, one Vision Pro each. This document is the contract that keeps `main`
buildable every day and ready for the demo at every sprint end. Ask in the team chat if anything here is unclear,
then fix the document in a PR.

## 1. Branches

One long-lived branch, `main`, and short-lived branches that start from it and come back to it through a PR.
`main` is the merge of the finished features: it always builds and always runs.

| Branch | Lives | Comes from | Goes into | Merge style |
|---|---|---|---|---|
| `main` | Forever | | | Default branch. PRs only, tagged `vX.Y.Z` at each sprint end |
| `feature/AR126-<n>-<slug>` | Days | `main` | `main` | Squash merge |
| `fix/AR126-<n>-<slug>` | Hours | `main` | `main` | Squash merge |
| `spike/AR126-<n>-<slug>` | Days | `main` | Nowhere | Throwaway. Rename to `feature/` to keep it |

Names are checked by CI. The Jira key (`AR126-12`) in the branch name is what links the branch, its commits and the
PR to the ticket once GitHub for Jira is connected: use it whenever there is a ticket. Slugs are lowercase with
dashes: `feature/AR126-12-orbit-gesture`.

Never push directly to `main`. Everything goes through a PR, and so should you.

## 2. A feature, start to finish

```bash
git switch main && git pull                # start from a fresh main
git switch -c feature/AR126-12-orbit-gesture
# ...work, commit small, push often...
git push                                   # first push sets the upstream
gh pr create --base main --fill            # or use the GitHub UI; the template asks the right questions
```

1. **Keep it small.** Aim for a PR a teammate can review in 15 minutes: under about 400 changed lines, one thing.
   Split big features into steps that each leave `main` working (a flag or an unused type is fine).
2. **Rebase, don't merge, to catch up:** `git pull --rebase origin main` on your branch. The Quick start in
   README.md sets `pull.rebase` for you. Never rebase a branch someone else has checked out.
3. **Open the PR early** as a draft if you want eyes on the direction. Mark it ready when CI is green.
4. **Review within one working day.** One approval is expected. Reviewers pull the branch and run it for anything
   visual or spatial; the simulator is fine unless the PR touches hands, world sensing, immersion or comfort, in which
   case the reviewer runs it on a headset.
5. **The author merges,** with "Squash and merge". The PR title becomes the commit on `main`, so it follows the
   commit format below. The branch is deleted automatically.
6. Move the Jira ticket. Done means merged into `main` and the checklist in the PR template ticked.

Spikes (Sprint 1 research, "does hand tracking feel OK for this?") are `spike/` branches. They can be messy, they
are never merged, and their findings go into the Jira ticket or a doc, not into `main`.

## 3. Commits

[Conventional Commits](https://www.conventionalcommits.org): `type(scope): summary`, summary in the imperative,
under 72 characters. The `commit-msg` hook checks this locally and CI checks PR titles.

| Type | Use for |
|---|---|
| `feat` | Something the player can notice |
| `fix` | A bug fix |
| `perf` | Frame time, memory, load time |
| `refactor` | Code change with no behaviour change |
| `test`, `docs`, `style`, `build`, `ci`, `chore` | The usual |

Scopes are free-form but keep them consistent: `orbit`, `input`, `scene`, `audio`, `ui`, `rcp`, `assets`.
Examples: `feat(orbit): snap released moons to a stable orbit`, `fix(input): ignore pinches while paused`,
`perf(scene): share planet materials`, `chore(rcp): re-export solar_system.reality`.

Commit messages describe the change; the PR describes the why and how to test.

## 4. Releases: one per sprint

Sprints end on Thursdays. Sprint 1 is research; the first release is the end of Sprint 2.

| Sprint end | Version | Meaning |
|---|---|---|
| Sprint 2 | `v0.1.0` | First playable loop |
| Sprint 3 | `v0.2.0` | |
| Sprint 4 | `v0.3.0` | |
| Sprint 5 | `v0.4.0` | Feature and content complete |
| Sprint 6 | `v1.0.0` | Release. Fixes only during this sprint |

Release captain rotates each sprint. There is no release branch: a release is a tag on `main`. On the last
sprint day:

1. Freeze `main` for the afternoon: only `fix/` PRs merge until the demo build is tagged.
2. Open a small PR `chore(release): 0.2.0` from `feature/AR126-<n>-release-0-2-0` that bumps the version
   (Xcode -> Macrowavers target -> General: Version 0.2.0, Build +1) and moves the `Unreleased` notes in
   `CHANGELOG.md` under `## [0.2.0] - <date>`. Merge it.
3. Build `main` on every headset. The sprint review demo runs from this build.
4. Tag `main`: `git switch main && git pull && git tag -a v0.2.0 -m "Sprint 2" && git push origin v0.2.0`.
   The Release workflow turns the tag into a GitHub Release with the changelog notes.
5. Hand the captain role to the next person.

**Fix after the tag**: something in the demo build is broken. Branch `fix/AR126-<n>-<slug>` from `main`, fix, PR,
then bump the patch version and tag `v0.2.1` as above.

## 5. The Xcode project

`Macrowavers.xcodeproj` is committed. `Sources/Macrowavers` and `Tests/MacrowaversTests` are **synced folders**,
so files never have to be added to the project by hand and feature branches do not conflict on `project.pbxproj`
(see `docs/decisions/0004`). Consequences:

- Adding a file: create it under `Sources/` or `Tests/`, in Xcode or in Finder. It is part of the target.
- New target, build setting, capability, framework, package: change it in Xcode and commit `project.pbxproj` in a
  small PR of its own, so the diff is easy to review.
- Signing team: in `Configs/Local.xcconfig` (copied from the example, gitignored). Never in the project file.
- Per-user state (`xcuserdata/`, `*.xcuserstate`) is gitignored and refused by the `pre-commit` hook.

## 6. Assets, Git LFS and Reality Composer Pro

Every binary format in `.gitattributes` is stored in Git LFS. The `pre-commit` hook blocks files over 5 MB that
are not. Clone size stays small and history stays fast.

- Keep single files under 25 MB. Textures at 2K by default. Ask before adding a 4K texture or a long audio file.
- Sources go in `Assets/` (Blender, PSD, WAV). Exports the app loads go in `Sources/Macrowavers/Resources/`.
- **RCP 3 projects cannot be merged.** The bundle holds an opaque store. The rule is one owner per scene at a
  time: write "editing SolarSystem scene" on the Jira ticket or in chat before you open it, commit and push in
  your own PR when done, then release it. If two people need the same scene, split it into two scenes.
- RCP 3 remembers the Xcode project by absolute path. Re-link on your own Mac; never commit link files.
- Default hand-off from RCP to Xcode is exporting `.reality` files into `Resources/`. If the team prefers the
  "linked project" route, RCP writes into the committed `.xcodeproj`: review that diff like any other.
- Designers commit too. The Quick start in README.md sets everything up, and the PR template applies to art PRs
  as well.

## 7. Definition of done

A PR can be merged when:

- CI is green: SwiftLint strict, build and unit tests on the visionOS simulator, title and branch name checks.
- One approval, all review threads resolved.
- Ran on a headset if it touches hands, world sensing, immersive spaces, or anything that could cause discomfort.
- No new warnings. Frame time still 90 fps on device for anything in the render loop (RealityKit Trace).
- Game rules under `Model/` have unit tests. Views and RealityKit code are tested by running them.
- `CHANGELOG.md` has a line under `Unreleased` for anything a player or the team would notice.

## 8. Everyday commands

| Command | What |
|---|---|
| Quick start in README.md | Once per machine |
| `open Macrowavers.xcodeproj` | Open the project |
| Cmd-U, `swiftlint lint --strict`, `swiftlint --fix` | What CI runs |
| `git switch -c feature/AR126-12-slug main` | New feature branch (after `git pull` on `main`) |
| `git switch -c fix/AR126-31-slug main` | New bug fix branch |
| `git switch -c spike/AR126-27-slug main` | New throwaway branch |
| `git tag -a v0.2.0 -m "Sprint 2"` | Tag the sprint release on `main` (see section 4) |
| `gh pr create --base main --fill` | Open a PR from the terminal |
| `gh pr checkout 42` | Review a teammate's PR locally |
