# Spec Delta

## Purpose

Lets the autonomous StoryMode agent resume an unfinished “Establish Your Clan” goal after a Host restart without losing the verified outcome of its last Native objective attempt.

## ADDED Requirements

### Requirement: Persist a model-selected EYC objective before its subflow
The Host MUST record the selected EYC objective, current original Journal snapshot, and Native route-state fingerprint in the existing same-Campaign checkpoint before beginning the objective subflow from a safe MapState.

#### Scenario: Objective is selected on a safe map
- **GIVEN** the original EYC Journal has an unmet objective and the model selects that current catalog entry
- **WHEN** the Host is at a safe Native Campaign MapState before beginning the child route
- **THEN** it stores that pending selection and its Journal/Native baseline in the Campaign checkpoint without storing prompt text, raw model output, or credentials.

#### Scenario: Host stops before a safe checkpoint
- **GIVEN** the last Native state is an active encounter, Mission, inquiry, or other non-checkpointable state
- **WHEN** the Host or Harness stops
- **THEN** the system MUST retain the previous verified save and MUST NOT claim that a new in-memory objective record survived restart.

### Requirement: Resume a pending objective after budget-limited Host restart
When a same-Campaign checkpoint contains a model-selected pending objective and its original Journal snapshot is unchanged, the Host MUST resume that objective using fresh Native observations instead of making another high-level objective-selection call.

#### Scenario: Budget ends after a Native query
- **GIVEN** the model selected PartySize and the Native route reached a read-only volunteer-options query before the model budget ended
- **WHEN** a new Host starts from the same Campaign save while the original Journal still shows PartySize unmet
- **THEN** it resumes the PartySize subflow, rereads the current Native state and recruitment options even if the map or menu changed, and asks the model only for the next current choice.

#### Scenario: Pending objective is stale
- **GIVEN** a checkpoint contains a pending objective selection
- **WHEN** a fresh Journal value advances or the Native route-state fingerprint changes
- **THEN** the Host discards the stale continuation and returns the current unmet objectives to the model planner.

### Requirement: Do not retry a known no-progress route in an unchanged state
The Host MUST temporarily omit a route from the planner catalog after a verified no-progress route failure when its Journal and Native availability fingerprints remain unchanged.

#### Scenario: Failed route remains unchanged after restart
- **GIVEN** an EYC objective route failed without Journal progress and its saved route fingerprint matches current Native state
- **WHEN** the objective planner is called again
- **THEN** the failed route is excluded for this planning step while other supported unmet objectives remain model-selectable.

#### Scenario: Previously blocked route becomes available
- **GIVEN** an objective was temporarily excluded after a no-progress failure
- **WHEN** its original Journal advances or its Native route-state fingerprint changes
- **THEN** the objective is restored to the current planner catalog.
