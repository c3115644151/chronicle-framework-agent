# Design

## Context

The natural Campaign trace `TestResults/20261110-220446` shows three separately billed `observeAgain` decisions after Native `pursue` and before the next encounter dialogue. Each decision waits on the same in-progress Native chase; no new strategic action was selected. The existing `AgentHostNativeMapMovementMonitor` only handles Settlement movement and its EYC-specific hostile interruption path.

## Goals

- Let the Host observe a just-selected Native pursuit for one bounded window before requesting another model decision.
- Return early on a Native encounter, conversation, inquiry, incident, target loss, stopped Campaign clock, changed target, or movement stop.
- Preserve the model's ownership of encounter choices and subsequent strategic actions.
- Record observation count, elapsed time, target identity and Campaign day/mode before and after for evidence.

## Non-Goals

- Do not pause, resume, advance or fast-forward Campaign time.
- Do not alter Native `pursue`, visibility, target acquisition or pursuit behavior.
- Do not automatically choose Fight, Leave, Surrender or any other encounter response.
- Do not poll indefinitely; at the bounded-window end, provide fresh Native state to the model.

## Decisions

- Start the monitor only after a successfully accepted `pursue` action and a fresh MapState still shows that exact target as the current target while Campaign time is advancing.
- Poll `ReadStateAsync` at one-second intervals for at most ten seconds. Stop early when the observed Native pursuit precondition ceases to hold or an interrupting UI/event appears.
- Keep the current model-controlled `observeAgain` available for subsequent bounded waits. The automatic initial window reduces the first idle model call; each later model decision remains an explicit opportunity to reconsider the current world state.
- Return an immutable watch result containing the latest Native receipt and counters. The caller records a no-model-decision Host trace row and then re-enters the normal decision loop.
- Test with Fake Native/Provider sequences for encounter, conversation/incident, target loss/stopped time, unchanged pursuit until window expiry, and cancellation. Assert zero clock actions and no provider request during the automatic window.

## Risks

Harness visual-capture progress logs record each passive-window boundary, stop reason, poll count, elapsed seconds, Campaign day and time mode. They must not include prompt/response content or affect runtime decisions.

- A ten-second Host wait adds response latency when no interrupt occurs. It is bounded, cancellation-aware, and only follows a model-selected pursuit.
- The Native state projection may omit an interrupt type; tests should assert only fields actually present in the 1.4.8 Bridge schema. Unknown interrupt observability remains explicit rather than inferred.
