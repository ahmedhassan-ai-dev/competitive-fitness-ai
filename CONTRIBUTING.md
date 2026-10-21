# Team development workflow

## Branches and PRs
- `main` = reviewed integration branch.
- `feat/<issue>-<topic>`, `fix/<issue>-<topic>`, `docs/<issue>-<topic>`.
- Never commit directly to `main` once branch protection is enabled.
- Make small PRs, link the issue, include tests, screenshots if UI, and risks.
- At least one teammate reviews code before squash merge. For contracts/schema changes, notify both Mobile and Backend owners.

## Daily cadence
- Short morning sync: yesterday, today, blockers.
- Integrate frequently (at least daily) against `main`.
- Freeze features on Day 12; reserve Days 13-14 for testing/demo/report.

## Definition of done
- Behavior meets acceptance criteria.
- Tests/checks pass locally; CI passes when configured.
- No secrets, datasets or generated build artifacts in commits.
- Update docs if a contract, config, or workflow changes.
- Record brief progress in `docs/reports/` at each integration checkpoint.

## Commit style
`feat(ai): add squat phase transitions`
`fix(api): reject duplicate rep event`
`docs: record camera setup decision`
