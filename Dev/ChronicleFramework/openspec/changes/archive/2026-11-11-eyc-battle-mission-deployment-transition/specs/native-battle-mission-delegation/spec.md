# Spec Delta

## ADDED Requirements

### Requirement: Finish the current Native field deployment before troop delegation
After the original Campaign Attack option enters a supported field Battle Mission in Deployment mode, the Host MUST complete Native deployment through the current field-deployment handler, verify the same Mission reaches Battle mode, and only then issue the existing F6-equivalent troop delegation once. The Host MUST NOT call the model during this transition or change Campaign time.

#### Scenario: Native field deployment advances to Battle
- **GIVEN** the current Mission is an active hostile Campaign field battle in Deployment mode, MainHero remains Player-controlled, and no Inquiry is open
- **WHEN** the bounded Native deployment-finish operation completes
- **THEN** the Host observes the same Mission in Battle mode before issuing troop delegation, keeps Campaign time stopped, and does not request another model decision during the transition

#### Scenario: Deployment cannot safely finish
- **GIVEN** the current Mission is not an eligible Campaign field battle, is already ended, has an active Inquiry, or the Native deployment handler is unavailable
- **WHEN** the Host attempts to finish deployment
- **THEN** it rejects or stops without issuing troop delegation, changing Campaign time, or claiming a battle result

#### Scenario: Native deployment finish is rejected or ambiguous
- **GIVEN** the original Native deployment-finish operation was submitted
- **WHEN** the handler rejects it, times out, or the same Mission fails to reach Battle mode within the bounded observation window
- **THEN** the Host does not repeat the non-idempotent operation, does not send F6, and returns an explicit unresolved transition result

### Requirement: Commit the current Native Ready configuration
The Host MUST invoke the current Native Order of Battle `ExecuteBeginMission` command only when its Ready control is enabled. This preserves the original deployment configuration and callback chain; a direct call that skips the current view-model command MUST NOT be treated as equivalent.

#### Scenario: Ready is enabled for the active field deployment
- **GIVEN** the current Mission is an eligible ordinary field battle in Deployment mode and the Native Ready control is enabled
- **WHEN** the Host submits the deployment-finish action
- **THEN** the original Native Order of Battle Ready command commits the current formation configuration and triggers the Native deployment-finish callback once

#### Scenario: Ready is disabled or the current Native UI is unavailable
- **GIVEN** the current Native Ready control is disabled, its current ViewModel cannot be resolved, or a modal is active
- **WHEN** the Host submits the deployment-finish action
- **THEN** the bridge rejects without directly calling `DeploymentHandler.FinishDeployment`, changing Campaign time, or retrying the action
