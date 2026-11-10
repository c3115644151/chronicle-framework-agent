# native-party-pursuit-monitor Specification

## Purpose
Reduce repeated model polling after the model has already selected an ordinary Native party pursuit, while returning fresh state at meaningful Native transitions.

## Requirements

### Requirement: Passively observe a model-selected Native party pursuit
After a current Native `pursue` action is accepted, the Host MUST passively read fresh Native state for no more than ten seconds before requesting another model decision, provided the exact selected target remains active, MainParty is moving in MapState, and Native Campaign time is flowing. The Host MUST NOT issue Pause, Resume, Advance, FastForward, or another gameplay action during this observation window.

#### Scenario: Pursuit continues through the bounded observation window
- **GIVEN** the model selected a currently visible hostile Party and Native accepted `pursue`
- **WHEN** fresh Native reads continue to show MapState, the same `targetPartyId`, MainParty moving, and Campaign time flowing
- **THEN** the Host observes for at most ten seconds without a model decision, then returns the latest Native state to the normal decision loop

#### Scenario: Native encounter or conversation interrupts pursuit
- **GIVEN** passive observation is active for a selected Party
- **WHEN** fresh Native state reports an encounter or map conversation
- **THEN** the Host returns immediately; on an encounter it may refresh current visible party targets so the exact hostile party identity can be checked, but it MUST NOT choose an encounter option

#### Scenario: Target is lost or Native movement stops
- **GIVEN** passive observation is active for a selected Party
- **WHEN** Native clears or changes `targetPartyId`, MainParty stops moving, or Campaign time stops
- **THEN** the Host returns the latest state for model replanning and does not restart pursuit or alter the clock

#### Scenario: Map incident interrupts pursuit
- **GIVEN** passive observation is active for a selected Party
- **WHEN** a Native map incident appears
- **THEN** the Host returns immediately so the existing incident flow can resolve current choices

#### Scenario: Host cancellation
- **GIVEN** passive observation is active
- **WHEN** the linked Host cancellation token is canceled
- **THEN** the observation exits without a Native action and propagates cancellation
