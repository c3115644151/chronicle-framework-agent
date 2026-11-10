# Spec Delta

## MODIFIED Requirements

### Requirement: Persist a model-selected EYC objective before its subflow
The Host MUST record the selected EYC objective, current original Journal snapshot, and Native route-state fingerprint in the existing same-Campaign checkpoint before beginning the objective subflow from a safe Native Campaign MapState, including a verified settlement menu.

#### Scenario: Objective is selected on a safe map
- **GIVEN** the original EYC Journal has an unmet objective and the model selects that current catalog entry
- **WHEN** the Host is at a safe Native Campaign MapState before beginning the child route
- **THEN** it stores that pending selection and its Journal/Native baseline in the Campaign checkpoint without storing prompt text, raw model output, or credentials.

#### Scenario: Host stops before a safe checkpoint
- **GIVEN** the last Native state is an active hostile encounter, Mission, inquiry, or other non-checkpointable state
- **WHEN** the Host or Harness stops
- **THEN** the system MUST retain the previous verified save and MUST NOT claim that a new in-memory objective record survived restart.

#### Scenario: Safe settlement menu permits a same-Campaign checkpoint
- **GIVEN** the Native Campaign is in a Town, Village or Castle menu, the current settlement identity matches the settlement encounter, the settlement is not under siege, and no modal, battle, PartyScreen, inventory or captivity state is active
- **WHEN** the menu is `town_backstreet`
- **THEN** the Host may read or write its objective-attempt checkpoint only if the current original `town_backstreet_back` option is visible, enabled and marked as Leave; another settlement menu must still match a current Native settlement record.

#### Scenario: Pending objective resumes from a safe settlement menu
- **GIVEN** a same-Campaign checkpoint contains a pending EYC objective and the original Journal snapshot is unchanged
- **AND** the loaded Campaign begins at that verified settlement menu
- **WHEN** the fresh Host reads the checkpoint and current Native Journal
- **THEN** it resumes the saved objective without another high-level EYC objective-selection call, then re-observes the current Native route before acting.

#### Scenario: Hostile encounter is not a settlement checkpoint
- **GIVEN** the Campaign has a non-settlement encounter such as a hostile looter or bandit Party
- **WHEN** the Host reads or writes objective-attempt memory
- **THEN** it MUST reject that state as a checkpoint location even if the overall GameState is `MapState`.
