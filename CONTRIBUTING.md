# Contributing

Thanks for looking. This project is unusual: the code is written by an agent under human review, and the documents are the contract the code is held to. Please read this page before opening a pull request.

## Ground rules

- **The game is the authority.** A change that makes the agent look better than the game actually allows is a regression, however green the gates are.
- **Native actions only.** If a player cannot do it through a menu, a dialogue, a trade, a battle or the map, the Mod does not do it.
- **Evidence over assertion.** "It works" means a run receipt shows the state changed. A command exiting zero proves only that a command exited zero.
- **One increment at a time.** A pull request that changes the action surface, the observation schema and the harness in one go will be sent back.

## Set up

See the README's *Build and install* section. In short: Bannerlord 1.4.8, .NET SDK 8+, PowerShell 7, then

```powershell
./Dev/ChronicleFramework/harness/Initialize-ChronicleWorkspace.ps1 -GameRoot "<your game folder>"
./Dev/ChronicleFramework/harness/Run-Harness.ps1 -Phase Docs
./Dev/ChronicleFramework/harness/Run-Harness.ps1 -Phase Build
```

harness.local.json records your machine's paths and is gitignored. Never commit it, an API key, a save file, or anything under TestResults\.

## What a change must carry

1. **The contract.** Behaviour the model can observe or trigger must be written into docs\DEVELOPMENT.md in the same change that implements it: the action id, the schema, the native handler, the side effects and the time behaviour.
2. **The harness.** New or changed actions need a phase that executes them in a disposable campaign and asserts the observation delta. harness\Check-Docs.ps1 compares the action catalog against the documents and fails if one side moved alone.
3. **A run receipt.** Paste the run id from TestResults\ into the pull request. If the run did not reach the assertion, say so and say where it stopped.
4. **The contract version bump** in harness\Run-Harness.ps1, harness\Check-Docs.ps1 and docs\DEVELOPMENT.md, whenever the change alters behaviour or the gate.

## Documentation

- docs\DEVELOPMENT.md: the contract. Every capability, its acceptance rule and its evidence.
- docs\MAINLINE.md: mechanism facts, confirmed unknowns and the current open questions. Add facts here when a live run teaches you something the code alone does not say.
- docs\SYSTEM_INVENTORY.md: what the game exposes and what the Mod can reach.
- docs\Research\<category>/: one authoritative document per category. Do not start a second file for the same category.

Documents are edited in place; prose has no changelog file. When a document and the code disagree, that is a bug, and -Phase Docs reports it.

## Style

- C#: netstandard2.0 for the Mod, net8.0 for the host, warnings are errors in the host project.
- PowerShell: 7.0 or newer, and every script declares the requirement on line 1.
- Comments explain why a decision was made; the code says what it does.

## Security

Report a vulnerability privately through GitHub's security advisory form rather than a public issue. Do not include API keys, save files or player data in a report.
