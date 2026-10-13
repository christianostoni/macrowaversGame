# 5. Feature branches into `main`, one tag per sprint

Date: 2026-10-13. Status: accepted. Supersedes [0001](0001-gitflow-with-sprint-releases.md).

## Context

GitFlow (0001) added a `develop` branch, release branches and back-merges. In practice the team wants one place
that holds the game as it is: the merge of the finished features. A second long-lived branch doubled the merges
and made it unclear where the playable build lives.

## Decision

`main` is the only long-lived branch and the default one. Work happens on `feature/`, `fix/` and `spike/`
branches cut from `main`; features and fixes come back through reviewed PRs with a squash merge, spikes are never
merged. Each sprint ends with a version bump PR and a `vX.Y.Z` tag on `main`. Branch names carry the Jira key when
there is a ticket. Conventional Commits, enforced by a hook and CI, stay as before.

## Consequences

- `main` must build and run at all times: keep PRs small and use flags for unfinished work.
- No release branch: the afternoon before the demo `main` is frozen to fixes, then tagged.
- No back-merges, fewer branches to explain to designers.
- If the team ever needs to stabilise a demo while features keep landing, a short-lived `release/X.Y.Z` branch
  cut from `main` can come back without changing the rest of this workflow.
