# Design

## Scope and evidence boundary

This change measures a Native engine path; it does not decide that the path is suitable for players. The production Host must continue treating MainHero as Player-controlled until the probe and any later safety acceptance pass.

## Probe protocol

1. Start from the existing freshB Campaign source through Native SaveAs; verify the source hash and operate only on the disposable clone.
2. Enter an ordinary Campaign field Battle Mission through the original Attack and Ready UI-handler path. Delegate troop formations with the current F6-equivalent order and capture the MainAgent baseline.
3. Require Campaign clock Stop, an active Battle mode, the same active MainAgent, Player controller, and no existing scripted navigation lease. Begin a short Native-AI controller lease with a hard maximum duration.
4. During the lease, passively sample the same Mission and MainAgent's controller, formation membership/ownership, position, health, and Mission state. Do not issue player movement, combat input, or model requests.
5. Restore the original Player controller on explicit restore, timeout, Mission end/change, or protocol stop. Confirm the MainAgent is Player-controlled again before continuing Native aftermath. Record Campaign day/time mode before and after.
6. Remove the disposable clone only after confirming its final hash and leave the original source save untouched.

## Interpretation

- Controller becomes AI, MainHero changes position or combat state, and Player restoration succeeds: evidence that the Native controller path produces an observable action in this sample; not a survival guarantee or general product approval.
- Controller becomes AI but the MainHero remains idle, loses its formation, or cannot be restored: the current handoff is not a viable fallback; retain F6 as troop-only and stop this path.
- The battle ends before the lease can be sampled, an event changes Mission identity, or the evidence omits controller/position/health: inconclusive; do not repeat the same fixture without changing the probe or setup.

## Safety and time

The lease is only for an opt-in test clone and must fail closed outside ordinary Campaign field Battle Missions. Its watchdog uses monotonic `EngineTime.ApplicationTime`; it never changes the Campaign clock, which must remain stopped. Cleanup restores controller state and never edits roster, injury, encounter, or battle outcome directly.
