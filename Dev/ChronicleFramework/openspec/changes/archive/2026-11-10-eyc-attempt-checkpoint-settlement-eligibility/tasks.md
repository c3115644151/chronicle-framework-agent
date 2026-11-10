# Tasks

## 1. Safe settlement checkpoint policy

- [x] 1.1 Update the EYC attempt checkpoint state gate to match the Harness's verified safe settlement boundary; add a package regression that resumes a pending Companion attempt from `town_backstreet` with zero objective-planner calls and rejects a hostile Party encounter or disabled Native Leave option. Build and packaged Host passed at `TestResults/20261107-105306` (0 real model calls / 0 Native commands).
- [x] 1.2 `Run-Harness.ps1 -Phase Docs` passed at `TestResults/20261110-172023` after the code/spec update; OpenSpec 1.16.0 validation reported one active change with all planning artifacts valid.

## 2. Bounded same-Campaign confirmation

- [x] 2.1 `TestResults/20261110-172629` resumed the same Campaign `683a2e21c4a64cfd8a1bb4f3392afc3d` from the retained `freshB` settlement save. After one `goalClassification` response, the next provider response was directly in `native-storymode-companion-hiring`; no second `selectEstablishYourClanObjective` request occurred, so the fresh Host consumed the persisted pending route before re-planning. It made 11 decisions / 20 Native actions, with ¥0.110897952 estimated actual spend and ¥0.1842696 cumulative reserved ceiling against the ¥0.20 limit. The same Wanderer target then stalled: 9 navigation attempts, 8 same-target repeats, nearest observed distance about 1.363, zero interactable observations and zero interaction attempts. The route shifted toward a looter and stopped before the next provider request; no new safe save was accepted from Mission/active move, so the original hash-verified source remains authoritative. Video covered 166/166 frames, retained 21 indexed keyframes, deleted the source MP4, and all processes/session were cleaned. This confirms checkpoint eligibility/Host route resume but not Companion progress or EYC completion; the repeated navigation is recorded as a separate follow-up under #130.

## Workflow follow-up

- This is a focused implementation correction under the existing GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130); it does not create a new product issue.
- Archive this change after the deterministic regression, Docs and bounded continuation evidence are recorded; the full natural EYC acceptance gate remains in #130.
