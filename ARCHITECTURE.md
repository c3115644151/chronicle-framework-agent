# Architecture

Chronicle Framework is three cooperating pieces with one rule between them: **the game is the authority**. The Mod never lets the host claim an action succeeded; the host never lets the model decide something the game did not offer.

## Processes

```
+------------------------------+      files only        +-----------------------------+
| Bannerlord process           |                        | ChronicleAgentHost.exe      |
|  Mod: ChronicleFramework.dll |  AgentRuns/ChronicleAgent |  .NET 8, one campaign run  |
|   - observation projection   | ---------------------> |   - model conversation      |
|   - native action execution  |   state / request files |   - action catalog          |
|   - receipts and events      | <--------------------- |   - decision budget, receipts |
+------------------------------+  command.json/responses +-----------------------------+
             ^                                                       ^
             | started by the Mod as one child process                | driven by
+------------------------------+                                     |
| PowerShell 7 harness         |-------------------------------------+
|  disposable campaign, gates  |  Run-Harness.ps1 -Phase ...
+------------------------------+
```

The harness never links against the game or the host. It starts both, reads their receipts and judges.

## The mailbox protocol

Root: %USERPROFILE%\Documents\Mount and Blade II Bannerlord\AgentRuns\ChronicleAgent

| Path | Direction | Content |
| --- | --- | --- |
| command.json | host -> Mod | The single action to execute, with the observation it was chosen against |
| responses\ | Mod -> host | Execution receipts, completion markers, inquiry answers |
| events.jsonl | Mod -> everyone | Append-only event stream, capped at 16 MiB and then restarted |
| state | Mod -> host | Latest observation projection |
| checkpoints, inquiry replies, story-mode clan name, banner-editor completion | host -> Mod | Requests the Mod answers through native handlers |

Properties the protocol is built on:

- **Observation-matched execution.** The Mod executes a command only if the live state still matches the observation the host decided against. Otherwise the command expires and the host has to decide again. This is what makes a stale decision harmless instead of destructive.
- **Idempotence by id.** Every command carries an id; a re-delivered command returns the previous receipt instead of executing twice.
- **No secrets on disk.** The API key is inherited through the environment of the host child process. It never appears in a request file, a receipt or a log.
- **Bounded events.** events.jsonl rotates at a fixed size, and per-decision traces go to the harness evidence directory instead.

## The action surface

The agent chooses from a declared catalog, not from free-form code. Each entry has an id, a parameter schema, a native handler and an expected observation delta. The catalog tracks:

- **183 acceptance-tracked actions** (ACT): each has at least one observed, asserted behaviour in the harness.
- **74 observable-only behaviours** (OBS): projections the model can read that do not change state.
- **23 documented non-applicable cases** (N/A): behaviours that exist in the game but are out of the agent's reach by design, with the reason recorded.

Action families: map movement and pursuit, settlement menus and overlays, dialogues and inquiries, trade and barter, party roster and upgrades, recruitment, quest acceptance and delivery, tournaments and arenas, battle hand-off and post-battle state, captivity and escape, time control, quick information, and character development.

Anything the model asks for that is not in the catalog is refused by the host with a specific error and the nearest valid alternative. The refusal is part of the trace, not an exception.

## The decision loop

1. The Mod projects the world into the observation schema: bounded, versioned, no global game-state dump.
2. The host builds the request from the goal contract, the observation, the catalog, the remaining budget and recent history.
3. The provider returns a decision, a refusal or a stop.
4. The host validates the decision against the catalog and the current observation, then writes one command.
5. The Mod executes it natively and returns a receipt with the resulting observation delta.
6. The host records the receipt, decrements the budget and repeats until the goal is verified, the budget is spent, or the agent stops.

The loop has no other exit. A run that ends because the budget ran out is reported as exactly that, never as success.

## Acceptance ladder

Code and contract move together. harness\Check-Docs.ps1 fails when:

- a document claims a capability the code does not implement, or a code path exists with no contract entry;
- a harness script lacks the PowerShell 7 requirement line, or a source file carries non-ASCII text without a UTF-8 BOM;
- the action catalog, the acceptance-tracked set, the observable set or the non-applicable set changes size without the contract changing in the same commit;
- a path in the documents or the workspace no longer resolves through harness\HarnessPaths.ps1.

The contract version in harness\Run-Harness.ps1, harness\Check-Docs.ps1 and docs\DEVELOPMENT.md must agree. Bumping it belongs to the change that alters behaviour, not to a separate chore.

## Evidence

A phase passes only when its receipt proves the effect:

- the game started and the window was kept alive without stealing focus;
- the campaign loaded and the protocol handshake completed;
- the action executed natively and the observation delta matches the claim;
- the goal state changed, or the run is reported as unfinished with the exact reason.

TestResults\<run>/ holds what the run produced: receipts, decision traces, per-decision token and cost records, and screenshots. Documents reference run ids instead of copying results, so the receipt stays the single source of truth.
