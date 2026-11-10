# Tasks

## 1. Share navigation-progress reconciliation

- [x] 1.1 Apply one helper after both automatic and explicit Native Tavern scene scans; extend the fake Host package test to prove one successful approach is retained, then two unchanged/non-interactable scans exclude the target while keeping Native Leave available. Build and packaged Host passed at `TestResults/20261110-181859` with zero real model calls and zero Native gameplay commands.
- [x] 1.2 `Run-Harness.ps1 -Phase Docs` passed at `TestResults/20261110-185258`; `Check-Docs` validated the project inventory and OpenSpec 1.16.0 validated the active change/spec set. Package evidence is `TestResults/20261110-181859`.

## 2. Bounded same-Campaign confirmation

- [x] 2.1 `TestResults/20261110-182841` continued the same Campaign ID from the hash-verified `freshB` save with a 20-decision / ¥0.20 ceiling. The pending Companion objective resumed after goal classification without another objective-selection call. In this sample the Wanderer became Native-interactable after one navigation, so the live no-progress branch was not triggered; the package regression verifies automatic scan reconciliation and target exclusion after two stagnant observations. Native `missionInteract` opened the original conversation. The current hire quote was 432 Denars while the player held 424, so the model chose the Native “cannot pay” response and left. It then followed PartySize and submitted Native `recruitAll`: MainParty 1→19, Gold 424→64. The next request was rejected before Native execution because the reservation would raise ¥0.1881624 past ¥0.20; estimated spend was ¥0.104729088 over 14 decisions / 20 Native actions. Native checkpoint `ChronicleEycDev-freshB-20261110183132-08783004` (SHA-256 `A393432750AF30065F1BD9E521DA66911A18BC66891DC285D19D0340617D7308`) was retained. Capture passed 269/269 frames, kept indexed keyframes and deleted the source MP4; process cleanup passed. No-model readback `TestResults/20261110-184422` verified Journal Gold64/2000, PartySize19/25, Renown20/50, Companions0/1 and attempts `companions=blocked`, `partySize=pending`. This confirms the bounded Host resume and real Native action path, but not EYC completion or a naturally stalled NPC; the two-campaign #130 gate remains unverified.

## Workflow follow-up

- This focused change stays under existing GitHub Issue [#130](https://github.com/c3115644151/chronicle-framework-agent/issues/130); it creates no parallel product issue.
- Archive only after all tracked tasks and stable-spec synchronization are verified.
