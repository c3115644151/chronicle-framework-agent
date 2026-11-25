## What changed

Describe the increment in one paragraph. One capability, one boundary.

## Contract

- [ ] `docs/DEVELOPMENT.md` updated in this change (action id, schema, native handler, side effects, time behaviour)
- [ ] Contract version bumped in `harness/Run-Harness.ps1`, `harness/Check-Docs.ps1` and `docs/DEVELOPMENT.md`, if behaviour or the gate changed
- [ ] `docs/MAINLINE.md` updated with any new mechanism fact or resolved unknown

## Evidence

- Harness run id(s) under `Dev/ChronicleFramework/TestResults`:
- Phase result (Docs / Preflight / Build / AgentLoop / Smoke / other):
- If the run did not reach the assertion, where it stopped and why:

## Checks

- [ ] `./Dev/ChronicleFramework/harness/Run-Harness.ps1 -Phase Docs` passes
- [ ] `./Dev/ChronicleFramework/harness/Run-Harness.ps1 -Phase Build` passes (if the Mod or host changed)
- [ ] No key, save file, `harness.local.json` or `TestResults` content is included
