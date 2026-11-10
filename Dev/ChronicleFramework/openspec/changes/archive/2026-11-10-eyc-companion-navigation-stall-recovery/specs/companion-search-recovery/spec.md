# Spec Delta

## ADDED Requirements

### Requirement: Reconcile Native Tavern scene observations after navigation
The Host MUST compare the current observed Wanderer distance and Native conversation-action eligibility with the prior completed navigation attempt whenever it obtains a fresh Tavern scene observation, including an automatic observation.

#### Scenario: Native navigation measurably approaches a Wanderer
- **GIVEN** the MainAgent completed Native navigation toward a currently observed friendly Wanderer
- **WHEN** a fresh scene scan shows the distance decreased by at least the configured measurable-progress threshold
- **THEN** the Host MUST clear the no-progress counter and keep that current Wanderer eligible for the next Native interaction decision.

#### Scenario: Repeated Native navigation does not approach the target
- **GIVEN** the MainAgent completed Native navigation toward the same currently observed Wanderer twice
- **AND** each fresh scene scan shows less than the measurable-progress threshold and Native conversation action remains unavailable
- **WHEN** the Host builds the next Companion action catalog
- **THEN** it MUST temporarily exclude that Wanderer for the current search and present another currently eligible candidate or the original Native Leave action, without submitting another navigation to the excluded target.

#### Scenario: Automatic scene scan reconciles navigation progress
- **GIVEN** the Companion loop performs a Native `missionSceneAgents` query itself after a completed navigation
- **WHEN** the returned scene data contains the selected Wanderer's current distance and the current state contains Native interaction eligibility
- **THEN** the Host MUST apply the same progress/stall policy used for an explicit scene-query action before constructing the next model request.
