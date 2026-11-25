# Chronicle Framework 开发与 Harness 契约
- `settlementOverlayCharacters`是schema 21中的有限视图，只在Settlement Characters overlay当前可见时按本体`MenuLocations + HeroAgentLocationModel.WillBeListedInOverlay`生成，并携带玩家Overlay显示的Issue/Quest标记。用户确认聚落人物与地图贵族领主名旁都有蓝色委托标记；W2-AU将Native Party Nameplate的类别补到`mapPartyTargets`，不暴露全局Issue/Quest清单，并由临时Native Issue与引擎帧验证`AvailableIssue`。`talkToSettlementHero(HeroId)`经QuickTalkPermission和CampaignMapConversation作地图快速“交谈”；`visitSettlementHero(HeroId)`经Visit permission进入NPC的Location Mission。W2-D运行`TestResults/20261001-101331`验证QuickTalk返回原Village菜单/MapState，`20261001-095934`验证Visit进入目标Mission；二者不可混称。两者都只接受本轮可见overlay名单，不用Harness全场景Notable诊断里的隐藏ID。
Contract version: 7.700
Contract 7.700 corrects one sentence the Host wrote about a menu it had not fully read: at a cornered map encounter it said it had "no bounded action" while the original game still offered exactly one. A zero-model receipt (`TestResults/20261126-opening-surrender/Temp/OpeningScenarioResult.json`) now holds the whole 12-item encounter menu. Only `surrender` is available and enabled; `attack` and `leave_soldiers_behind` are available but disabled; the other nine are unavailable. The accepted surrender runs on by itself to `prisoner_wait` and then `menu_captivity_end_wilderness_escape`, whose only clickable option is `mno_continue`, with heroHitPoints 6 → 11 → 16.

`ExplainNoAction` in `agenthost/AgentHostBattleSimulationLoop.cs` now names that situation instead of claiming no bounded action exists, and the existing scenario `battle-loop-surrenders-only-as-last-resort-in-explicit-captivity-recovery-mode` asserts the wording so a later edit cannot soften it back. `harness/Test-AgentOpeningScenario.ps1` gained `-EncounterOption` and records every menu option with both its available and enabled flags, so the surface is measured instead of described. Provider self-test: 430 scenarios, 0 differing from `TestResults/_selftest-baseline.json`.

Where it landed: `docs/DESIGN.md` 9.3, `docs/Research/F/MilitaryPartiesAndCaptivity.md` F10 and F12, `docs/MAINLINE.md` ACT-G01-04, the screenshot `docs/media/opening-cornered-encounter.png`, and contract 7.700 in all three places.
Contract version: 7.699
Contract 7.699 turns the opening fork into a distribution and names the single action the model is offered there, because the previous contract measured the encounter surface from one run and described it in prose. The instrument is `harness/Test-AgentOpeningScenario.ps1`, registered as the `OpeningScenario` stage (`harness/stages/OpeningScenario.ps1`, phase `'OpeningScenario' { @('Preflight', 'Build', 'OpeningScenario') }`, `$openingScenarioScript` in `harness/Run-Harness.ps1`). Each repeat loads the fixture save from scratch, walks it in `-StepDays` (default 0.05) steps, stops at the first menu or sentence that asks the party to answer, records a full snapshot at every step, then stops the process so the next repeat starts from the same bytes. Parameters: `-LoadSaveName` (default `ChronicleEycDev-freshB-20261123092350-d1a1805e`), `-ScenarioDays` (0.25 to 5, default 2.0), `-Repeats` (1 to 5, default 3), `-RepeatWallClockSeconds` (default 600), `-TimeoutSeconds` (default 240). Zero model requests, no save writes.

Five assertions judge it: `FixtureUnchanged`, `AllRepeatsRecorded`, `EveryRepeatReachedAVerdict`, `ConversationForksCarryNativeOptions` (a conversation fork must carry at least two clickable sentences, otherwise the window was caught between ticks), and `EveryRepeatStoppedItsProcess`. The fork is classified as `bandit-conversation`, `conversation`, `encounter-menu`, `other-menu` or `no-fork`; the classifier looks at content, because the observer always emits a `conversation` and a `mapIncident` object and their mere presence says nothing.

Receipts `TestResults/20261125-opening-scenario/OpeningScenarioResult.json` and `TestResults/20261125-opening-scenario-2/Temp/OpeningScenarioResult.json` (both Passed, all five assertions true) hold six replays of the same checkpoint: interrupted at campaign days 0.747, 0.747, 0.933, 0.864, 0.974 and 1.194 against the same `mountain_bandits_chief` (`mountain_bandits_2145` twice, `mountain_bandits_2289` once) with three different sentences and the same two clickable options (`bandit_start_defender_3` / TextObject `LLEffOga`, `bandit_start_defender_2` / `aQYMefHU`). The hero stood at 9, 9, 6, 7, 5 and 1 of 100 hit points at the meeting, and the roster was already `healthy=0` / `wounded=1` before it. Adding the two `IdlePressure` receipts on this checkpoint (0.873 and 0.817 days) and one quiet probe (1.2 days, never interrupted), nine replays of the same save all fork inside 1.2 campaign days and none reaches a second day: the meeting is a distribution over roughly half a day, not a fixed event.

Two instrument defects had to be fixed before that receipt was worth trusting. A child that never returned would have hung the whole run, so `Invoke-AgentCli` now starts each CLI call as a `System.Diagnostics.Process`, reads both streams asynchronously and kills the child at `-TimeoutSeconds + 90`, which turns a stalled container into a reported failure instead of a hung stage. And because the stage only collects stdout when the script returns, the instrument now writes a timestamped line per step to `OpeningScenarioProgress.log` beside the receipt: the first apparent hang of this round was a healthy run whose only symptom was eight minutes of silence. The whole phase then ran as RunId `20261125-231213`, with Preflight, Build and OpeningScenario all Passed and the stage script exiting 0 after three repeats (receipt `TestResults/20261125-231213/OpeningScenarioResult.json`).

The action surface at that fork is one action. `agenthost/AgentHostBattleSimulationLoop.cs:1104-1131` allows `bandit_start_defender_1`, `common_encounter_ultimatum` and `common_bandit_surrender_declined`, plus `bandit_start_defender_3` only when `recoverPlayerCaptivity` is set and the conversation carries no fight response. The measured conversations carried no `_1`, and `_2` is never on that list, so the EYC/Autonomy route offers the model exactly one move at its first decision: surrender. `_2` is usable elsewhere - VillageToolsQuest treats it as the compromise (`agenthost/AgentHostVillageToolsQuestLoop.cs:1148`, `agenthost/AgentHostVillageToolsQuestPolicy.cs:729`) and the safe-passage harness selects it before entering barter (`harness/Test-AgentSafePassageBarterContext.ps1:228`) - so the gap is slice selection, not missing native capability.

Where it landed: `docs/DESIGN.md` 9.1 states the opening interruption as a distribution and 9.3 records the single offered action with the cross-slice contrast; `docs/Research/F/MilitaryPartiesAndCaptivity.md` carries both receipts beside the existing encounter section; `harness/gate/11-workspace-init.ps1` asserts the phase shape, the progress log and the script's judging vocabulary. The Docs gate numbers are unchanged: Catalog 126, ACT 183, OBS 74, NA 23.


Contract version: 7.698

Contract 7.698 turns the wound into a measurement with a cause, because the previous contract left it as a correlation between starvation and a map encounter. Two changes made that possible. The party observation now carries `heroHitPoints` and `heroMaxHitPoints` beside the roster counts (`mod/AgentObserver.cs`, party block), so hit points are readable instead of inferred from `wounded`. And `harness/Test-AgentIdlePressure.ps1` gained `-ShelterInTown`: the party walks to the nearest non-hostile town that is not under siege, then spends each chunk in the native `town_wait` screen (`rest -Days`, polling `data.targetCampaignDay`, leaving through `wait_leave`) instead of advancing on the map, with `ShelteredPartyNotEncountered`, `ShelteredPartyStayedInTown`, `ShelteredPartyNotBesieged` and a `shelter-besieged` stop reason of its own.

Two runs of the 25-man fixture `ChronicleW7P-manual-20261101-eyc-complete` one campaign day per chunk, zero model requests, settle it. Receipt `TestResults/20261125-idle-hp-starved/IdlePressureResult.json` (Passed, stop `party-shrunk`): while food stays positive the hero sits at 100/100 and the roster has no wounded; on the day food goes negative hit points drop 100 to 87 and three men are counted wounded, then 68 and nine, then 49 and fourteen. Receipt `TestResults/20261125-idle-hp-fed/IdlePressureResult.json` (Passed, stop `chunk-budget-exhausted`, `-TopUpFoodUnits 24` buying 12 units of grain for 144 gold at `town_ES3`): twelve days at 100/100 hit points, zero wounded, same daily wage drain of 78 gold. Starvation is the only cause in the room, and `wounded` is the count of characters whose current hit points sit below the wound threshold rather than a tally of battle injuries.

The same reading explains the opening checkpoint rather than contradicting it. A standing-still probe (`TestResults/_probe-hp2.ps1`, forty `advance -Days 0.01` steps, no movement and no encounter) puts `ChronicleEycDev-freshB-20261123092350-d1a1805e` at 23/100 hit points on load, draining 10 to 18 points per campaign day, with the roster flipping at 20/100 on campaign day 91117.449. The bandits only arrive near 91118.0. The earlier contract recorded the wound as appearing together with the encounter; it appeared half a day before it.

Two observation traps are now written into the instrument and the docs. Entering a settlement sets `PlayerEncounter.IsActive` with `encounteredPartyId` equal to that settlement, so `encounterActive` alone never means a hostile fight (the first sheltered run threw a false alarm on exactly this). And a siege can begin while the party waits inside the walls: the first sheltered run had its `town` menu replaced by `encounter_interrupted_siege_preparations`, which is why picking a town with `underSiege=false` is not enough and why the stop reason and its assertion exist.

Where it landed: `docs/DESIGN.md` 9.1 replaces the unattributed-wound paragraph with the two-run table, the hit-point chain and both traps; `docs/Research/F/MilitaryPartiesAndCaptivity.md` carries the probe numbers and the starvation mechanism; `harness/Test-AgentIdlePressure.ps1` samples `heroHitPoints`, tolerates the settlement encounter, and names a besieged shelter; `harness/gate/11-workspace-init.ps1` refuses an idle-pressure script that cannot record hit points or a siege verdict; the contract version is 7.698 in `harness/Run-Harness.ps1`, `harness/Check-Docs.ps1` and this file.

Contract version: 7.697
Contract 7.697 records the first measurement of a real opening checkpoint, because the cost table had been written against an assumed treasury instead of a save file. `ChronicleEycDev-freshB-20261123092350-d1a1805e` starts at campaign day 91117.285 with 0 gold, one man, an empty larder and `moraleContext.isStarving` already true; the 1000 gold in the cost table is the EYC objective baseline, not cash in hand.

Two independent idle runs on that checkpoint (`harness/Test-AgentIdlePressure.ps1 -ChunkDays 1 -MaxChunks 12`, receipts in `TestResults/20261125-idle-freshB/` and `TestResults/20261125-idle-freshB-2/`, zero model requests) stop with `menu-opened` after 0.873 and 0.817 campaign days respectively: a bandit party catches the lone hero, the party reads healthy 0 / wounded 1, and `context.conversation` offers only `bandit_start_defender_3` and `bandit_start_defender_2`. The two runs met different bandits (`mountain_bandits_2145`, `looters_2541`) and got the same option ids, which is why the option set is attributed to the player's predicament rather than to the dialogue text.

Three consequences are recorded rather than inferred: idling measures nothing on this checkpoint because the world interrupts on the first day; the first real decision is what to say in an encounter that is already lost; and the wound is unattributed, because the party was starving from the moment the save loaded and the fed/starved comparison already showed starvation alone produces wounded troops on the day the larder hits zero. Cargo capacity 30 to 10 and speed 5.189 to 4.988 are likewise unattributed while `itemCount` stayed at 1.

Where it landed: `docs/DESIGN.md` 9.1 now separates the cost table from the measured checkpoint and states that the opening decision is a lost encounter rather than a hiring budget, `docs/Research/F/MilitaryPartiesAndCaptivity.md` carries the observation fields (`moraleContext.isStarving`, `effectiveMorale`, `context.conversation.options[].id`) plus the same open attribution, and 9.1's earlier claim that opening survival is not hard on day one is corrected instead of appended to.

Contract version: 7.696
Contract 7.696 records what the model is actually offered at a decision point, because that turned out to be the missing half of the income question. The generic campaign loop builds its model-facing catalog in one place: `agenthost/AgentHostCampaignLoop.cs:1036` `BuildActionCatalog` returns only `mapSettlementTargets`, `move` and the map-conversation dialogue verbs, and returns an empty list once `moving` or `goalVerified` is true; `BuildControlCatalog` at `:1083` then offers a single `done`. A model standing in a town menu therefore has no `tradeOptions` and no `sellPrisonerOne`, no matter how much gold it holds or how empty the larder is.

The market verbs exist only inside slices that the objective router starts - the EYC gold objective at `:723` leading to `AgentHostEstablishClanGoldSaleLoop`, the one `trade` inside VillageToolsQuest, and the single permitted food purchase in the Supply slice. So the EYC model does choose whether to earn, but the gold slice itself decides how: one sale of one thing.

The new self-test `campaign-loop-offers-no-market-verb-outside-objective-slices` (in `AgentHostCampaignLoop.RunContractSelfTests`, 430 scenarios now) pins that boundary to the code rather than to prose: in a town menu with gold 900 and an empty food inventory, `goalVerified=false` lists only `move`, and a verified arrival lists only `done`. `harness/gate/05-observation-and-provider.ps1` rejects the loop if the scenario name disappears. Scenario design consequences are written in `docs/DESIGN.md` 9.3 and `docs/Research/E/EconomyAndTrade.md`: a survival scenario is a real test of where the AI walks and whether it fights, not of whether it budgets, and any scenario that lets it manage money has to move market verbs into the campaign loop first, which is a player-action-surface change with its own real-game verification.

The measured base for this contract is the provider self-test receipt: 430 scenarios, all passing, and two consecutive runs compared as multisets of scenario records produced no difference (the comparison must be a multiset because several scenarios share a name and their emission order carries no meaning).

Contract version: 7.695
Contract 7.695 turns the starvation hypothesis into an intervention. `harness/Test-AgentIdlePressure.ps1` gained `-TopUpFoodUnits` (and `-MarketArrivalTimeoutSeconds`, default 240): before the idle window it walks the nearest friendly town, opens `town/trade`, reads `tradeOptions`, drafts `trade` with `direction=buy` and `inventorySide=OtherInventory` cheapest-first, commits once with `tradeConfirm`, leaves with `town_leave` and only then starts the same 1-day-per-chunk window. The whole purchase costs no campaign time: the confirmation receipt reports identical `campaignDayBefore`/`campaignDayAfter`/`campaignDayAtCommit` and `timeControlMode` Stop on both sides. A new assertion `TopUpBoughtFood` requires the purchase to raise food inventory and lower gold, and `harness/gate/11-workspace-init.ps1` now rejects the stage if the script loses `TopUpFoodUnits`, `isFood`, `tradeConfirm` or `TopUpBoughtFood`.

The receipt (`TestResults/20261125-idle-pressure-fed-2/IdlePressureResult.json`, Passed=true, stop reason `chunk-budget-exhausted`) answers the open question 7.694 left: the same fixture, same 12 days, same `advance`-only loop, one difference - a stocked larder. Food 24.5 to 8.9 units, zero wounded, 25 members kept, morale 42 to 47, gold 2133 to 1197. The starved runs on the same fixture end at 14 wounded, 24 members and `party-shrunk`. So the wounded are the consequence of hunger, not of an unlogged map encounter during fast-forward; wound counts stay a distribution, but the order (food to zero, morale collapse, wounded, member loss) is the criterion.

The economic consequence is the part worth carrying into scenario design: buying food is cheap relative to wages. 24 units (18.5 days at 1.3 per day) cost 144 denars, 9.2 denars a day against a 78-denar wage - about 12 percent. The idle pressure is wages, not hunger; hunger is what a party that never walks into a market pays. Market quotes read the same day at `town_ES3`: `grain` 12, `fish` 14, `butter` 22, `meat` 24, `cheese` 26, `grape` 30, `olives` 41, `beer` 64, `date_fruit` 85 denars per unit, so food prices move with settlement and stock and must be read from the current `tradeOptions` rather than a table.

Contract 7.694 makes idleness itself a measured pressure rather than an assumption. `harness/Test-AgentIdlePressure.ps1` (stage `IdlePressure`) loads a fixture, samples the party, then does nothing but `advance -Days 1` and `state` until the party shrinks, a menu opens, the clock fails to move or the wall-clock budget runs out; it writes `IdlePressureResult.json` with every daily sample and asserts that gold never rose, the clock returned to Stop, the fixture hash is unchanged and the process stopped. No model request is made.

The 12-day receipt (`TestResults/20261125-idle-pressure-daily/IdlePressureResult.json`, fixture `ChronicleW7P-manual-20261101-eyc-complete`, 25 members, 2277 gold, 12.5 units of food, wage 78, food change -1.3) fixes the shape of the failure: nine days of paying exactly the daily wage (-78 per day, -1.3 food per day, morale rising 42 to 46), then the day food goes negative (0.8 to -1.3) morale drops 33 in one step and three soldiers turn wounded, then wounded climb 3 to 9 to 14 over two more days while morale falls to 6, and on day 12 one member leaves (25 to 24, wage 78 to 76) which is the stop condition.

Four mechanisms are now measured rather than inferred: the daily gold deduction is the whole wage with no rounding; `FoodChange` counts prisoners as half a member (0.05 x (25 + 2/2) = 1.30); `Food` is not clamped at zero once stock is gone; and the starvation morale penalty lands once, on the day food turns negative. What stays unknown is why healthy soldiers become wounded: `encounterActive` was false at every sample and the event stream holds no battle command, so starvation damage and an unreceipted map encounter are still indistinguishable, and the instrument must not be cited as evidence that a fight happened.

One generalisation is refused: this 25-member fixture measured 78 per day (3.12 per member) against the 2 x members estimate of 50, so `TotalWage` tracks troop composition and budgets must use measured values.

The stage is wired into `Run-Harness.ps1 -Phase IdlePressure` (`Preflight, Build, IdlePressure`) and passed there in run `TestResults/20261125-210118` (4-day chunks, stop reason `party-shrunk`, exit 0). The first attempt in `TestResults/20261125-205949` failed before loading because the harness brought up a cold Steam client and the 45-second login wait expired (`steam-user-not-logged-on`); the default login wait in `harness/HarnessStartupEvidence.ps1` and `harness/Agent-Cli.ps1` is now 90 seconds so a cold start is not read as a broken client. Two runs at the same 24 members ended with 14 and 13 wounded, so the wound count is a distribution rather than a fixed number and only the ordering (wounds accumulate after food turns negative) should be held constant.

Contract 7.693 turns the ransom-side sale into a stage that can be re-run. `harness/Test-AgentPrisonerRansomSale.ps1` drives the whole chain with no model request: load a fixture, walk a town menu to `town_backstreet`, take `sell_some_prisoners`, draft each sale through `sellPrisonerOne`, commit the draft once through `partyScreenDone`, then compare the party gold, the prisoner count and the campaign day against the pre-trade observation. It is registered as `PrisonerRansomSale` (`harness/stages/PrisonerRansomSale.ps1`, phase `Preflight, Build, PrisonerRansomSale`) and asserts the native receipt fields rather than the CLI exit code: `nativeGoldChangeAfter` per draft, `nativeTransactionAmount` and `playerGoldBefore/After` at commit.

The receipt (`TestResults/20261125-202821/PrisonerRansomSaleResult.json`) also fixes what a prisoner is worth. Fixture day 91179.34, gold 2277, two `looter` prisoners, right-side limit 22: two drafts take the price from 5 to 10 and one Done moves gold 2277 to 2287, prisoners 2 to 0, with the campaign day and the Stop time mode unchanged. A `looter` is therefore worth 5 denars against the 50 that the earlier `TestResults/20261030-012146/RansomCancelRuntime.json` receipt paid for a mounted ransacker, and the 374 the 2026-10-29 menu quoted for a mixed batch of seven. Price tracks troop tier, not headcount.
Contract 7.692 puts the income side of a scenario beside its cost side. Expenses were priced in 7.690; what the party can earn depends on which verbs the host lets the model execute, and the host narrows verbs per slice (`agenthost/NativeMailboxClient.cs`: `SupplySliceActions` 7, `VillageToolsQuestActions` 19, `BattleSimulationActions` 12).

The EYC route has the narrowest money verb set: `agenthost/AgentHostEstablishClanGoldSaleLoop.cs` accepts only `trade` with `direction=sell`, `inventorySide=PlayerInventory`, `amount=1`, plus `sellPrisonerOne`. There is no buy. Gold therefore grows only by selling what the party already holds - battle loot, prisoners, quest rewards - with the Quest Journal gold progress as the receipt that each sale committed.

The arena is the counterexample worth recording: `mod/AgentTournamentAdapter.cs` captures the original `TournamentVM` and exposes five real handlers (join, watch round, skip round, skip all rounds, leave) with `canPlayerJoin`, `wageredDenars`, `expectedBetDenars`, `prizeItemId` and `result.playerWon` observed, but `agenthost` has no `tournamentJoin` reference and no slice allowlist contains it. The mechanism is connected; the verb is not visible. So "the model never won prize money" carries no information yet - the route is not in the action surface. Wiring it needs a real arena Mission run to verify what skipping rounds actually settles, which is a product-surface change tracked on the board, not a documentation task.

The stale rows ACT-J10-01 and ACT-J10-02 in SYSTEM_INVENTORY and the tournament bullet in MAINLINE said Chronicle had no tournament capability at all; both are corrected to the adapter-exists-verb-not-exposed state.

Contract 7.691 corrects the deadline paragraph with a receipt instead of a guess. Campaign days are cheap: one Native rest in a town wait menu crosses three daily boundaries in 60 to 61 seconds of wall clock, with no clock command, as the MultiDaySupplyBaseline receipts show. So the 1..400 decision budget is not what limits an eight-day earning window - the limit is that waiting costs money. A 25-member party idling three days spends 177 to 255 denars, a fifth of the starting capital at the moment the party is fully staffed.

The distinction matters for what gets changed next. The earlier draft said a run that ended early was probably budget-limited; that hypothesis is now withdrawn, because the same receipts show days are bought with a single action. What a short run proves is that the model chose not to earn, not that it ran out of turns to try.

Contract 7.690 prices a scenario before anyone plays it. Section 9.1 of docs/DESIGN.md now carries the daily cash burn measured on this machine - wage 2 per non-hero member, food 0.05 units per member per day, food priced 9 to 30 denars per unit - and states the consequence: a one-member party burns under 1.5 denars a day, so an opening-survival scenario judged by bankruptcy can never fail.

The burn starts the moment the player hires. A tier-one recruit costs 20 denars and then 2 denars of wages plus 0.05 units of food every day, and a soldier earns nothing on his own, so the payback horizon is over ten days. That makes hiring, not fighting, the first decision in this project that has a computable cost before the choice - which is exactly the cost-sense criterion the design was missing a natural test for.

Establish Your Clan carries the same arithmetic as a deadline: 24 recruits cost 480 denars up front, and at 25 members the party burns 59 to 85 denars a day, leaving 520 denars for six to nine campaign days. The next long run has to measure whether -MaxDecisions and campaign time allow eight days of earning, because a run that ends on budget exhaustion before that is evidence about the budget rather than about the model.

docs/Research/E/EconomyAndTrade.md records the calibration and its hole: four independent receipts give the linear slope and two of them are the mailbox state stream itself (903 states at one member with wage 0 and food change -0.05, 18 states at two members with wage 2 and -0.1). The measured 2 denars per recruit disagrees with the documented tier-one base of 1, and that stays listed as unknown rather than explained away.

Contract 7.689 puts the scenario layer into docs/DESIGN.md and says plainly that the only work in scope is L0. Section 2 and 3 are now read as a coordinate rather than a plan: no refactor of the acting-character resolution, no mailbox partitioning, no observation slicing until a second agent actually has to enter.

The new section 9 defines a scenario as five things - starting checkpoint, world configuration, pressure sources, observable outcome, budget - and shows the four knobs that already exist for them: harness/Agent-DecisionLoop.ps1 takes -Goal, -AllowedActionNames and -MaxDecisions (1..400), PersistentEycCampaign resumes from a checkpoint key, and the decision ledger records decisions, tokens and trace. So a scenario is a checkpoint plus an action surface plus a budget plus a decidable ending, with no new framework.

It also states the red line the harness already tempts: -AllowedActionNames is a narrowing tool for a self-test that asserts one link (self-tests use mapSettlementTargets,move), not a statement of the correct answer for a scenario. A real run gets the whole action surface, or what it validates is the script rather than the model.

Six scenario families are written down as things the existing action surface can already run - opening survival, war as income, town economy, relationships, captivity and rebuild, Establish Your Clan - with war and vassalage left undesigned because it needs surfaces that do not exist yet. What is borrowed from the Minecraft-style agent projects is the long autonomous loop and self-verification; what is deliberately not borrowed is the automatic curriculum, because generating the next thing to do is exactly the pre-given answer the design judges runs against.

Contract 7.688 records what this project is a substrate for. docs/DESIGN.md now opens with three layers - L0 the current one (a model driving Hero.MainHero through original menus, dialogue, trade, party, quests, map and battle resolution), L1 several AI-played characters sharing one campaign with separate observation and intent, L2 the kingdom rulers deciding at day or week scale - and with the four things that keep L0 from blocking L1.

Those four are measured, not hoped for: mod has 130 Hero.MainHero and 158 MobileParty.MainParty references across 69 source files, so the acting character must be resolved in one place whenever a family of actions is touched rather than read as a bare singleton in new code; the mailbox root in mod/AgentProtocol.cs is a fixed AgentRuns/ChronicleAgent path with one command.json, so partitioning it per agent session is a root change and the commandId reply shape already works; observation must be sliced by what an agent knows, which is the real L1 problem, not concurrency; and the 32 per-scenario Native interfaces stay split, since P5 showed they are the validation boundary rather than redundant transport.

agenthost needs no work for L1: all 33 of its source files reference Hero.MainHero or MobileParty.MainParty zero times. What is not built is also stated in the document: no multi-agent scheduler, no turn arbitration, no configuration switches held open for a consumer that does not exist.

Contract 7.687 makes a sentence the unit of a line in both default-read documents. A contract paragraph used to sit on one line of up to 7,105 characters, so an editor wraps it arbitrarily and a one-word edit shows up in review as a replacement of the whole paragraph. `docs/DEVELOPMENT.md` and `docs/MAINLINE.md` now break a prose paragraph after every sentence - on 。！？； and on a full stop followed by a space and a capital letter, backtick or parenthesis - and nowhere else. Rendering is unchanged: consecutive non-blank lines are still one Markdown paragraph.

Tables and list items were left alone on purpose. A Markdown table row cannot contain a newline, and a wrapped list item needs a two-space continuation indent that changes what the Markdown means, so both keep their single long line. DEVELOPMENT went from 1,119 to 2,626 lines with its longest line from 2,955 to 1,611 characters; MAINLINE from 1,018 to 2,227, leaving 84 long table rows and two list items.

Because the wrapping rewrites `MAINLINE.md` bytes it invalidates the recorded focus hash, so the change runs `harness/Set-ContextFocus.ps1 -Review` and records the new `mainlineSha256`. Gate numbers stay: Catalog 126/126, ACT 183, OBS 74, NA 23, OpenSpec 7/7.

Contract 7.686 finishes the same split inside the engineering contract.
`docs/DEVELOPMENT.md` opened with 70 dated run paragraphs interleaved with the `Contract 7.<n>` sections - the same dated-diary shape that 7.685 removed from `MAINLINE.md` - so those paragraphs moved verbatim into `docs/RUNLOG.md`, with their `TestResults/` citations, and DEVELOPMENT keeps the contract-version history plus a pointer.
The five contract elements the gate requires of DEVELOPMENT and the three UI-automation assertions are all in the stable body and were verified present after the move.
Default context read: 1,453,018 -> 939,564 bytes (-35%) across 7.685 and 7.686, with Catalog 126/126, ACT 183, OBS 74 and NA 23 unchanged.

Contract 7.685 splits the two documents by what a reader needs to keep.
`docs/MAINLINE.md` keeps the durable technical facts, mechanic contracts, unknowns, denominators and acceptance rules; `docs/RUNLOG.md` — a new required root document — carries the dated record of real runs, diagnoses and continuations that had grown past the last third of the file, and `MAINLINE.md` ends with a pointer that new records are written there and do not flow back.
`Check-Docs.ps1` routes `RUNLOG.md` with the other required roots, and `Prune-TestResults.ps1` protects the run directories it cites by default, because a run cited only in the log is as load-bearing as one cited in the contract.
The default context read drops from 1,453,018 to 1,018,187 bytes without losing an asserted fact.
`DESIGN.md` becomes what its name says — the player-experience design document: what a viewer watches, which choices carry weight, what the world is allowed to do to the agent — and keeps its confirmed-optimization ledger as a section, still empty.
Contract 7.684 splits the two gate keepers by responsibility.
`Check-Docs.ps1` keeps the arguments, the root map, the OpenSpec summary and the receipt, and dot-sources seventeen topic chunks from `harness/gate/` in name order; each chunk is an ordinary Harness script with its own `#Requires -Version 7.0` declaration, so the scan that rejects scripts without one still holds.
`Run-Harness.ps1` keeps the phase table, `Invoke-Stage` and the run receipt, and dispatches each stage body from `harness/stages/<Stage>.ps1`; a stage named in the phase table whose script is missing now throws instead of returning a null result that the loop would read as a pass.
The gate assertions that read the old dispatch switch out of one file now read the driver and every stage script as one text, and the two checks that counted a dispatch arm by its eight-space indentation count the `Invoke-Stage -Name '<Stage>' -Action {` line instead.

Contract 7.683 splits the Mod's Native protocol by concern without changing what it does.
`AgentProtocol.cs` keeps only the forty-eight conversation fields, the constructor and a `Poll` shell that parses the command and hands it to `DispatchCommand`; the one hundred and seventy-one `case` labels and their handlers live in `Protocol/ChronicleAgentProtocol.Dispatch.cs` and `Actions/ChronicleAgentProtocol.Actions.<Family>.cs`, mission leases and timing and response writing in `Protocol/`, JSON reading helpers in `Model/`, and the Harness diagnostics and fixtures in `Harness/`.
`Check-Docs` no longer reads one file: it concatenates `AgentProtocol.cs` with every `ChronicleAgentProtocol*.cs` under `mod/` into `$agentProtocolSource`, so both source-shaped assertions and the pause/resume/fast-forward contract now name the handler each label dispatches to and the Native speed that handler sets.

Contract 7.682 decides whether a recording is undecodable from the file's own structure, not from whether a media tool happens to be installed where the check runs.
`Prune-TestResults.ps1` walks the top-level MP4 box chain: a chain that does not parse, or that never declares the movie box carrying the stream table, cannot be decoded on any host.
The retention self-test previously reached that verdict only where `ffprobe.exe` was on the PATH, so the docs gate failed on a clean CI runner, which has none, and passed on the development machine, which does.
`ffprobe` still fills the receipt's diagnostic fields when it is available.
Contract 7.681 makes the OpenSpec summary independent of the caller's working directory. `Get-OpenSpecWorkspaceSummary` pushes the project root before invoking the CLI and pops it afterwards, because the CLI resolves its OpenSpec root from the process working directory, not from the script's location. A gate run started from the repository root previously failed with `no_openspec_root` even though `openspec/` sits one level down, which is exactly how the CI runner starts it.
Contract 7.680 gives every owner its own directory: `mod/` holds the Mod sources with `module/` (SubModule.xml and ModuleData), `agenthost/` holds the Agent Host, `harness/` holds every `.ps1`, `docs/` holds the contract documents, `Research/`, `DESIGN.md`, `SYSTEM_INVENTORY.md` and `ContextState.json`, and `tools/ApiProbe/` holds the API probe; `openspec/`, `TestResults/` and the untracked `harness.local.json` stay at the project root.
Because no script's own directory is the project root any more, each script resolves each root through `HarnessPaths.ps1` and carries evidence, settings and source joins through that map instead of assuming a sibling layout.
The Mod project no longer excludes sibling trees: evidence and the Agent Host no longer live under it.
Retention resolves its reference documents from `docs/` and refuses to run when a reference document is missing, because the previous default silently degraded to no documented-run protection and deleted 983 evidence directories.
Contract 7.679 routes every Harness file path through `HarnessPaths.ps1`.
`Get-HarnessLayout` returns one ordered root map (`HarnessRoot`, `StageRoot`, `GateRoot`, `DocsRoot`, `ModRoot`, `AgentHostRoot`, `ResearchRoot`, `OpenSpecRoot`, `EvidenceRoot`, `ToolRoot`); `Run-Harness.ps1` and `Check-Docs.ps1` resolve stage scripts, game sources, and documents from those roots instead of joining their own directory with filename literals.
`Check-Docs.ps1` now fails when a required layout root is missing, and when `Run-Harness.ps1` names a stage script the stage root does not contain, so a directory move reports the missing names instead of running an unverified path.
The Build stage also restores the Mod project when `obj\project.assets.json` is absent, so a workspace without build intermediates reaches `--no-restore` with a real assets file instead of failing on NETSDK1004.

Contract 7.678 makes `processStopped` mean the process is gone from the process list, not merely absent from an identifier lookup.
PowerShell 7 on .NET reports a signaled process as gone by identifier while the entry can still be listed, so a stop followed immediately by the name check saw the process and `Test-AgentLoop.ps1` failed its goal-checkpoint reload precondition on three consecutive runs.
`Agent-Cli.ps1` now waits through `Test-ProcessIdListed`, which treats any listing as alive, in both the session stop tree and the startup crash tree.
The stop receipt keeps its shape; only what `processStopped` guarantees changed.

Contract 7.677 extends the PowerShell 7 requirement to every Harness script, not only the ones that spawn children: each tracked `.ps1` declares `#Requires -Version 7.0` as its first statement, and `Check-Docs.ps1` rejects any script that omits it.
The same contract fixes three `ConvertTo-Json` calls that relied on the default depth 2: that default replaces nested containers with their .NET type name and, on PowerShell 7 only, writes a truncation warning onto the same stdout that carries the JSON mailbox payload, the Harness session file and the config receipt.
Serialization depth is now explicit for `Agent-Cli.ps1` (mailbox payload 12, session 12) and `Run-Harness.ps1` (config receipt 8).

Contract 7.671 makes the Agent Host health check query only the selected model when the configured OpenAI-compatible endpoint is OpenRouter.
OpenRouter's `/models` listing can exceed the Host's bounded health-response limit; its documented `q` filter returns the selected model row while preserving the existing exact-ID check.
A provider self-test covers the filtered path with one health request, zero inference, and zero Native commands.
The live `particle-ai/particle-1:free` retry that exposed this issue reached Native MapState but failed before any decision because the unfiltered catalog exceeded the response limit.

Contract 7.672 extends bounded `Retry-After` handling only to direct OpenRouter model IDs ending in `:free`: one explicit header retry of at most 30 seconds, and only when the per-decision HTTP budget allows it. Paid OpenRouter routes are not automatically retried. The package regression covers a 429→Retry-After→successful JSON Schema decision and proves a one-request budget still refuses the retry. This addresses the observed free Particle route 429 while keeping retry count and wait bounded.

Contract 7.673 paces direct OpenRouter `:free` model requests at a minimum 3.1-second interval, keeping the loop below the published 20-requests-per-minute ceiling. The interval also applies between a 429 and its single bounded retry; unrelated providers and paid OpenRouter models remain unpaced by this free-route rule.

Contract 7.674 makes the zero-priced OpenRouter `openrouter/free` provider smoke classify the actual EYC goal rather than the unrelated map-arrival goal. The router is eligible only for free models that support the requested structured-output features; its answer still passes the same Native decision/catalog validation as a fixed model.

Contract 7.675 makes the Smoke stage verdict come from the worker's own serialized gate: `Test-Module.ps1` writes `Passed` and `GateFailures` into `SmokeResult.json` and exits non-zero only for those failures, while `Run-Harness.ps1` requires a Boolean `Passed` instead of treating an unavailable process exit code as a failure.
A redirected worker that runs for minutes can exit without the `Process` object publishing an exit code; the exit code remains an additional failure signal, and a missing one no longer aborts a healthy run.
These harness scripts are UTF-8 with BOM: an editing tool that drops the BOM makes Windows PowerShell 5.1 read the Chinese text as ANSI and fail to parse the file.

Contract 7.676 requires PowerShell 7 for the whole Harness: every script that spawns a child declares `#Requires -Version 7.0` and launches it through `$HarnessPowerShell` (`Join-Path $PSHOME 'pwsh.exe'`) instead of Windows PowerShell 5.1 with `-ExecutionPolicy Bypass`.
The 7.7 Core runtime publishes a redirected worker's exit code, so the 5.1 case where `Process.ExitCode` stayed null no longer reproduces locally; the worker receipt remains the Smoke verdict.
The CI Docs gate already ran on `shell: pwsh`, so local and CI interpreters now agree.
Script source keeps its UTF-8 BOMs because the Docs gate still requires them.

Contract 7.656 corrects the read-only DSH XD Pool aggregate-status preflight origin to `http://127.0.0.1:2733`.
The previous `3477` value was wrong for this installed DSH Desktop runtime and caused a false preflight failure.
Verified on this machine without inference: authenticated GET returned aggregate enabled; `open_router` enabled/configured; and selected model exactly `particle-ai/particle-1:free`.
The preflight still separately requires exact direct model presence in `/v1/models`, and does not call a model or inspect provider credential values.

Contract 7.657 makes DSH gateway credentials endpoint-specific: for loopback `127.0.0.1:8326/v1`, the Harness reads only `%DSH_HOME%\openai-gateway\api-key` (or `%USERPROFILE%\.dsh\openai-gateway\api-key` when `DSH_HOME` is unset).
If that dedicated key file is absent, DSH preflight fails closed; it never reuses `CHRONICLE_LLM_API_KEY`, which may belong to a paid provider.
The provider-health regression uses a synthetic temporary DSH key and proves this separation without a model call or logging either key.

Contract 7.658 applies the endpoint-selected credential only to the child environment for a bounded live-model test, then restores the parent process value. The Host still uses one generic `CHRONICLE_LLM_API_KEY` variable; the Harness supplies the matching provider key for the chosen endpoint and never prints it. This keeps paid-provider credentials from being sent to a local DSH gateway and keeps the local DSH key from being written into global user environment settings.

DSH XD Pool usage reconciliation limit (installed plugin `dsh-xdpool@2.7.5`): the active process can expose per-call usage samples, but startup backfill reconstructs only day-level channel/model totals from its 90-day ledger.
Per-call timestamps and a Chronicle run/request ID are not recoverable from that backfill.
Treat this endpoint as corroborating aggregate evidence only; Chronicle's own sanitized per-decision receipt is the per-run token source.
Missing DSH rows or missing provider-reported usage mean unknown, never zero, and the plugin has no currency-price receipt.

Contract 7.659 adds a pre-inference price check for DSH's direct OpenRouter route: Harness retrieves the public OpenRouter model detail through the local proxy, verifies the exact selected model slug, and requires explicit zero prompt and completion prices.
The receipt records the model ID, price fields, source URL, and verification time; it stores no credentials or response body.
Other DSH upstream providers remain blocked until a provider-specific authoritative price source is implemented.
This is a current published list-price check, not a billing receipt or a guarantee against provider/account policy changes.

Contract 7.660 applies OpenRouter's published `:free` limit to the persistent Campaign Harness: at most four provider decisions per continuation and exactly one outer HTTP request per decision. The free endpoint allows 50 requests/day and failed attempts count; the guard limits one accidental burst but cannot see calls the user makes through other DSH clients, so it does not claim account-wide quota headroom.

Contract 7.667 adds the DSH WorkBuddy loopback endpoint `127.0.0.1:8328/v1`.
It uses a dedicated `CHRONICLE_DSH_XDPOOL_API_KEY` variable, separate from the generic model API key, pins JSON Object output, and rewrites tool-call-only wording because this route receives no tool catalog.
For explicit StoryMode Establish Your Clan goal classification, it sends only the complete goal and currently allowed goal IDs; the Host still validates the response against the original full request.
The provider smoke compares against the Host's canonical `supported-establish-your-clan` classification ID. The read-only preflight checks the gateway's exact model ID and current XD Pool credit multiplier; the multiplier is not a currency price receipt.
Persistent runs through this route are capped at four decisions and one HTTP request per decision.
The zero-model EYC checkpoint readback reports current settlement/target, MainParty movement, and Native time mode alongside Journal and saved attempt memory so a stalled continuation can be diagnosed without another LLM request.

Contract 7.668 extends safe provider-failure evidence for DSH WorkBuddy.
When the exact WorkBuddy `risk_blocked` HTTP 403 envelope is recognized, the Host may extract only allowlisted upstream business codes `11140` / `11141` from the nested upstream detail.
It does not retain the error message, selected account labels, response body, or credentials.
The safe code is added to provider-smoke and Campaign progress receipts.
A fake-response regression checks the allowed code and proves account labels and raw message text are absent; it does not retry a real route or prove that a future upstream error will contain a code.

Contract 7.669 adds the explicitly opted-in DSH XD Pool China route `xdpool/hy4flash-free` at `127.0.0.1:8326/v1`.
A zero-call preflight requires the exact model in the live gateway catalog and verifies the plugin selection is enabled with zero multiplier and a free-promotion tag.
When the plugin's read-only status route is unavailable after DSH provider-ID migration, the Harness falls back to the current DSH profile selection plus a recent (60-minute) zero-multiplier receipt; if either check fails, it sends no request.
A bounded provider smoke uses JSON Object, `max_tokens`, one HTTP request and a 128-token output cap.
The multiplier is a DSH internal credit measure, not a currency price; no CNY receipt is claimed.
Persistent continuations through this direct route remain capped at four model decisions and one HTTP request per decision.

Contract 7.670 updates the EYC Gold child to recognize a pre-existing Native MainParty settlement move when it starts.
While that exact move is in progress and Campaign time is advancing, the child reuses `AgentHostNativeMapMovementMonitor` to wait up to 10 seconds and reread Native state, without spending an LLM decision or changing clock mode.
If the move is still active while `TimeControlMode=Stop`, it returns the current Native state to the EYC parent for the existing bounded same-target Native Move recovery; it does not hide time advance in a sale or movement action.
A conversation, arrival, lost target or hostile interruption returns to the ordinary Native action/parent-recovery path.
Synthetic regression covers target adoption and rejects party pursuit, arrival, stopped party and open menu as settlement moves; the next live continuation must verify behavior from a saved stalled-move checkpoint.

The bounded real retry `TestResults/20261121-222611` verified that guard in Bannerlord 1.4.8: 4 DeepSeek decisions/4 requests, 10,397 prompt/222 completion tokens, estimated ¥0.021966048; Native Trade was canceled, Town Map recovered, and a new hash-verified same-Campaign checkpoint `ChronicleEycDev-freshB-20261121222907-a9926406` (`3B3FB984F48F65B9BB5AD2826630A87AC4A5ABF49CD293300671A2074A910CA6`) was saved.
Gold/Journals did not advance.
Zero-model readback `TestResults/20261121-223428` confirms MapState Town, original EYC active, Gold0/2000, Party1/25, Renown20/50, Companion0/1; Gold and Renown attempts are blocked at their current route fingerprints.
Source save remained unchanged and game/Host processes were cleaned.

Earlier 12-decision attempt `TestResults/20261121-220704` ran from the preceding checkpoint, made 12 DeepSeek decisions/requests, 38,714 prompt/647 completion tokens, estimated ¥0.084674112, and reached no EYC progress.
It completed Native Trade Cancel/Town Leave, then explored the Gold training-issue route; moving toward `village_EW1_1` naturally encountered hostile `looters_1671` (11 bandits) with one healthy MainParty member and effective Stop.
Native MapState `encounter_meeting` exposed only the two current bandit responses (“Fight” and “negotiate”); the decision cap expired before response, so the run was not safely checkpointed and the previous manifest remained authoritative.
Filtered Native receipt: `TestResults/20261121-220704/Temp/NativeEncounterBoundary.json`.
This is an interrupted encounter observation, not a completed BattleSimulation or quest outcome.

The replacement route smoke `TestResults/20261121-124033` used `auto:noema-free` and completed one structured goal-classification decision without starting Bannerlord or sending Native commands (509 prompt/121 completion tokens).
FreeLLMAPI routed it to `custom/nvidia/nemotron-3-ultra-550b`; the response was `json_schema` and no price receipt was returned.
NVIDIA lists a free API endpoint for this model, while its model card says the hosted trial is governed by NVIDIA API Trial Terms ([NVIDIA model page](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b), [model card](https://build.nvidia.com/nvidia/nemotron-3-ultra-550b-a55b/modelcard)).
This is a route smoke only, not EYC planner/action quality or full-campaign evidence; provider cost remains unpriced.
Use this exact `auto:noema-free` route only for the next bounded real-model continuation, and preserve route/usage receipts.

Direct model metadata check then confirmed `nvidianemotron-3-ultra-550b` supports `response_format`, `tools` and `tool_choice`.
Its one-shot provider smoke `TestResults/20261121-125431` used the old 128-token smoke cap; FreeLLMAPI logged a truncated JSON response at `finish_reason=length` before any decision or Native command.
The smoke cap is now an explicit run-only `-ProviderSmokeMaxOutputTokens` parameter (64–2048, default 128), so a route-specific bounded smoke can use 256 without changing production or MCM settings.
Contract version: 7.625.

The follow-up one-shot smoke `TestResults/20261121-130514` passed at 256 output tokens.
FreeLLMAPI routed directly to `custom/nvidia/nemotron-3-ultra-550b`; the model returned one valid `json_schema` decision (509 prompt / 140 completion tokens), with no Native commands.
Provider cost was not returned, so the smoke is not evidence of zero cost.
A persistent Campaign attempt `TestResults/20261121-124753` saved same-Campaign checkpoint `ChronicleEycDev-freshB-20261121125011-15603b8c` (`27BCEA6CD79505FB8E0C5553C365E976CDD57C1948726DBBC8F51A3D0D6BCF21`) after three provider failures.
Its zero usage had been correctly reported as unavailable at the time.
The next bounded live attempt `TestResults/20261121-131538` resumed that checkpoint and made three successful HTTP responses via `custom/nvidia/nemotron-3-ultra-550b`; each response was rejected locally as `provider-decision-ambiguous`, so no Native action ran.
The local FreeLLMAPI request log correlates the three responses to 1,600 prompt / 339 completion tokens in total; no price receipt was returned.
`TestResults/20261121-131538/ProviderUsageReconciliation.json` records that evidence and corrects the campaign manifest's failed-response counters; estimated cost remains incomplete.
This exposed a Host accounting defect: post-response validation and parsing failures discarded provider usage and route metadata, making the run appear to have zero tokens.
The provider now attaches route/status/format/finish/model/usage/fallback metadata plus only the bounded top-level field-name/type shape to post-response truncation, empty-content, malformed-JSON, and decision-normalization failures.
It does not persist model response contents or credentials.
Package regression `TestResults/20261121-134537` passes with 407 provider scenarios and zero live model/Native actions, including ambiguous field-shape telemetry.
Runs `133727` and `134336` failed only because the test expected comma delimiters while the diagnostic sanitizer converts them to underscores; the assertion now checks the sanitized shape.
The same Campaign was safely checkpointed as `ChronicleEycDev-freshB-20261121131757-65162cdb` (`3B33FA392B7575A9D25599308DAF4699AA0BD78A600D2A3721C344F8446AF06A`).
Contract version: 7.633.

The bounded post-change FreeLLMAPI run `TestResults/20261121-080121` resumed the safe same-Campaign checkpoint, but did not exercise the multi-call branch: all 10 accepted decisions reported `providerToolCallsDiscarded=0`, and both provider failures were truncated responses.
The Renown child returned the Native encounter without a battle; a later decision also truncated and the Host stopped safely in MapState.
It saved checkpoint `ChronicleEycDev-freshB-20261121081128-2c8c0d44` (`6A5F70D1D1F39569E84E6F485EBB12CD958ED8D8E158022D5BE5095079174718`) with no EYC Journal progress.
This keeps the provider serialization fix at synthetic-only verification until a later natural response produces a batch.

Camera hold target refinement: the first sustained Harmony test (`TestResults/20261118-080240`) proved the patch installation and kept the view away from the vertical clamp, but the pitch still wandered between `-0.27` and `-0.66`, which looked too steep in the retained frame.
The lease now captures a per-battle target: preserve a valid starting third-person pitch, or use Native's `-0.2` default when the starting view is near-vertical.
Each Native camera update returns the frame pitch to that target when it drifts.
The probe now checks at least three AI-controlled samples within 0.15 radians of the target and captures a second engine frame after sample three.

The guarded rerun `TestResults/20261111-121911` reached the intended Native `GoToTarget` state for 8 seconds with MainAgent.Controller=AI and its singleton Formation AI disabled, but all three samples stayed at the same position (8.01m from the point), HP78.
This is a valid negative result for this exact `SandBox.AgentNavigator` setup, not proof that every Native navigation route fails.
Harness guards/build, zero model calls, source hash, disposable-clone removal and process cleanup passed; the test phase's `Passed` means the probe completed and cleaned up, not that movement succeeded.
No production action was added.
`Run-Harness.ps1 -Phase Docs` passed at `TestResults/20261111-122215` before this result was written down.

Correction to the earlier RTSCamera comparison: the `TestResults/20261111-105107` probe tested only a subset of the installed RTS Camera 5.4.16 handoff. Decompiling its installed DLLs showed additional AI component initialization, watch/agent flags, unpause/scripted movement handling, Formation membership refresh, and deactivation of `MissionMainAgentController`. The previous negative sample must not be read as proof that the full Native route cannot move MainHero.

The Harness-only full Native handoff probe `TestResults/20261111-130714` reproduced the AI initialization on the same disposable field-battle clone.
During its 10-second lease MainHero moved about42m with HP78; after expiry Native state returned to Player control and `MissionMainAgentController` reactivated.
A second no-model probe kept the handoff until the mission ended or 180 seconds: `TestResults/20261111-131322` ended in Native loot at about57 seconds, with MainHero moving about119m and HP78→37, Party20→17 (11 healthy/6 wounded), Renown20→22.611.
Campaign time stayed Stop/day-stable; source save stayed hash-identical, clone was removed after hash verification, and the process stopped.
This demonstrates one full ordinary looter battle with Native AI movement; it does not establish a general safety rate or add a Host action.

同日有界续跑`TestResults/20261107-065613`使用同一freshB Campaign，单次DeepSeek决策上限和¥0.05费用硬上限。真实请求只用了1549输入/65输出tokens，估算¥0.001632096（reserved上限¥0.0066168）；该调用只识别了EYC目标，Host随后因无剩余决策预算安全结束，0 Native动作、无EYC进度。Native确认同Campaign并保存安全Town菜单检查点`ChronicleEycDev-freshB-20261107065842-02327a26`（SHA-256 `9D7802209252BCF523648C713CE1FE33F4B15E481F12EF8FE5689C52418D6CC9`），清理后无游戏/Host进程。图像序列确认仍在Sargot Town菜单。该次没有读取Companion搜索记忆，因此不能验证旧指纹迁移；它提供了成本边界和调用层次证据：EYC至少先做目标识别、再选子目标、再由子流程决定Native动作，单决策续跑不是有效的进度切片。其后实际续跑与结果见下条记录。

紧随其后的3决策续跑`TestResults/20261107-070300`触及Companion路由：模型识别EYC、选Companion，并在原版Sargot后巷菜单执行一次Native `menuSelect town_backstreet`；实际费用估算¥0.01301761（7828输入/183输出tokens，reserved ¥0.0288792），Journal没有增长。Native trace记录检查点读取成功，但`noCandidateTownCount=0`，所以当前分支没有旧空Tavern记录可迁移，记忆下降路径仍未判定；不重复跑同一无记录状态。Native同Campaign安全检查点为`ChronicleEycDev-freshB-20261107070528-323f29cf`（SHA-256 `F4BFBEC1CDEDBFACCF84B9CB94BF1522563B93AB8B9DE8DC5E588888C12686D8`），图像确认位于后巷/酒馆菜单，清理后无游戏/Host进程。其后续与结果见下条记录。

`TestResults/20261107-071342`将同Campaign续跑上限设为10决策/¥0.10。模型自行继续Companion路线：走进酒馆、返回镇中心、离开后查询部队并选择移动到Town EW6；随后因眼前劫匪触发遭遇并选择追近。9次请求已估算¥0.04364508、预留¥0.0921528；下一请求还需预留¥0.0097224，超过¥0.10预算而未发出，故没有重放任何Native动作。实际Journal没有增长，Companion子流程通过Native接口写入了1条新空Town记忆，但游戏处在`encounter_meeting`且Encounter活动，Harness按安全规则拒绝SaveAs；上一安全检查点仍为`...07070528-323f29cf`，清理后游戏/Host进程已退出。截图确认主队在聚落外遇到一支18人劫匪队伍。其后¥0.20续跑结果见当前任务OpenSpec的3.1a记录。

`TestResults/20261107-072137`中19次模型决策 / ¥0.093680064 (54326 prompt / 1069 completion tokens) 后，在同一次Campaign里退出劫匪遭遇、尝试Renown路线并自主转到PartySize；最后一项发布移动EW3动作后预算结束，Journal仍未增长。Native SaveAs在稳定Map状态成功，检查点`ChronicleEycDev-freshB-20261107072404-a9aa2b09`（SHA-256 `943D835DD38AB58483D4E85427F8C6078194FD512CC6D8100AB41BDD28A375F0`）保留同Campaign身份；游戏/Host清理通过。后续从该原版移动状态继续，优先看是否到EW3并在Town志愿者菜单执行一次真实招募；详见OpenSpec 3.1b的单轮预算计划。

后续`TestResults/20261107-072945`证明当前格式empty-Town记忆读取到1条并与当前Journal匹配，跨同一Campaign的Native SaveAs、游戏重启和Host重启仍保留；本轮Gold一直为670，故没有验证资源下降刷新。真实模型19决策 / ¥0.091832544，处理一次原版劫匪威胁后仍未增加任何EYC Journal数值，也未招募，最终在Sargot Town安全SaveAs至`ChronicleEycDev-freshB-20261107073215-51b70a75`（SHA-256 `F4E2A052BCFBC1C46617B8B538F5E7ABDFE8854B00EB18631C4294465F140503`）；同Campaign确认，所有游戏/Host进程退出。下一步跟随OpenSpec 3.1c做一个有界续跑，重点查看当前Town是否进入原版志愿兵UI并形成Journal增长，不再重复已通过的 memory/persistence 测试。

Persistent EYC evaluation supports isolated Campaign branches.
Omit `-PersistentEycCampaignKey` to resume the original `PersistentEycCampaign.json` and `ChronicleEycDev-*` lineage; use a distinct 1–8 character key (for example `-PersistentEycCampaignKey freshB`) to create a separate manifest and `ChronicleEycDev-freshB-*` save lineage.
A branch validates its own manifest key and only searches/prunes saves with its matching prefix; do not copy or rewrite another branch's manifest to switch campaigns.
The keyed seed pass performs only original StoryMode creation/tutorial skip and saves the first stable Native MapState before starting the Agent; the same Harness invocation then runs the real-model continuation from that verified seed and checkpoints it.
After continuation, a Native `MapState/town_backstreet` is a checkpointable settlement menu only when the current `town_backstreet_back` Leave option is visible/enabled, the associated town is not under siege, and no Mission/modal/battle screen is active.
This is for the two-independent-new-campaign acceptance gate, not a second gameplay mode.

The first persistent StoryMode continuation after DeepSeek routing passed Build, game Smoke and AgentHostPackage, then failed before inference with `campaign-loop-request-invalid`; the Native Campaign was loaded and a same-Campaign checkpoint was saved without gameplay progress or model cost (`TestResults/20261103-023801`).
Its sanitized receipt shows the full EYC request omitted six currently approved Host actions (`incidentSelect`, `partyLootTransferOne`, `partyScreenCancel`, `prisonerRecruitmentOptions`, `recruitPrisoner`, `sellPrisonerOne`).
Root cause: `Test-AgentLiveModelLoop.ps1` duplicated a stale 35-action allowlist while the compiled Host approved more.
The Host now exposes a read-only `--campaign-action-catalog`; the EYC live integration Harness obtains its exact action set from that production catalog before starting Bannerlord, and Docs asserts it cannot regress to a second hardcoded list.
This is a Harness/product contract synchronization fix, not a model failure.

The next same-Campaign run (`TestResults/20261103-024911`) passed that request gate and made 6 DeepSeek decisions, 3 Native actions and about ¥0.0289 estimated spend before safely checkpointing the unchanged EYC journal.
During the PartySize move the model first returned `stop` despite the current Native move, then returned `mapSettlementTargets` where the current catalog allowed only `observeAgain`; no invalid Native action was sent.
The Provider classified the second response as `provider-control-unavailable`, and the PartySize loop treated it as fatal instead of using the existing one-retry current-catalog recovery used by adjacent Host routes.
PartySize now retries that class once with feedback containing only the current action/control allowlist; a package regression simulates unavailable-control during a moving map route and verifies the recovered action proceeds without replaying or substituting a Native command.
Build/AgentHostPackage passed this fix at `TestResults/20261103-025730`; the same Campaign checkpoint is `ChronicleEycDev-20261103025130-ac20bdfb`, SHA-256 `8962926BEA4A275F8A27277247FB5AEE0B8ECBE879C2E1EE6670661694BD237B`.
Contract version 7.500.
The next same-Campaign run (`TestResults/20261103-024911`) passed that request gate and made 6 DeepSeek decisions, 3 Native actions and about ¥0.0289 estimated spend before safely checkpointing the unchanged EYC journal.
During the PartySize move the model first returned `stop` despite the current Native move, then returned `mapSettlementTargets` where the current catalog allowed only `observeAgain`; no invalid Native action was sent.
The Provider classified the second response as `provider-control-unavailable`, and the PartySize loop treated it as fatal instead of using the existing one-retry current-catalog recovery used by adjacent Host routes.
PartySize now retries that class once with feedback containing only the current action/control allowlist; a package regression simulates unavailable-control during a moving map route and verifies the recovered action proceeds without replaying or substituting a Native command.
Build/AgentHostPackage passed this fix at `TestResults/20261103-025730`.

The next same-Campaign run (`TestResults/20261103-030205`) exercised that recovery and reached a Native map event, but ended before progressing EYC. It made 162 DeepSeek decisions and 86 accepted Native actions (767,935 prompt / 8,876 completion tokens; estimated ¥1.6600127) while the same objective state remained Gold0, Party1, Renown20 and Companion1.
The “Troublemakers” Map Incident exposed three current options.
The model chose the visible index but serialized `OptionIndex` as a string; the provider schema had incorrectly declared this catalog integer as a string, so the Native incident resolver correctly rejected the malformed value twice without submitting a command.
The provider now emits `OptionIndex` as an integer enum from the current catalog and a contract test asserts integer type and enum values 0/1/2.
`AgentHostPackage` passed at `TestResults/20261103-031255` (319 Provider, 24 Campaign-loop and 22 battle-loop scenarios; 0 model calls/0 Native commands).
The follow-up real DeepSeek run `TestResults/20261103-031619` selected incident option index 0 through the corrected schema; the original incident resolved and Native MainParty grew from 1 to 5.
It then stopped at `training-issue-budget-exhausted` without completing EYC. Trace review found that the final Native training dialog had a clickable direct offer, but its localized TextObject.IdString was the placeholder `!`; Chronicle's hardcoded text-ID check filtered it out and left only Reject in the model catalog.
The Host now allows the stable direct-offer option ID only for the current contact reached from the visible training marker, while still excluding alternative/Lord outcomes and repeat acceptance after the training issue is active.
A package regression verifies the offer remains listed and resolvable with the placeholder text ID. Build and AgentHostPackage passed at `TestResults/20261103-034146` (320 Provider, 24 Campaign-loop and 22 battle-loop scenarios; 0 model calls/0 Native commands).
The same Campaign checkpoint is `ChronicleEycDev-20261103031845-5cb6c8a3`, SHA-256 `5CD780BC474654BE66A80D0D1E0C64B825B8AD36829335B0233E5AFA179A1185`; Campaign instance unchanged.
Contract version 7.502.

In the explicit fresh-campaign lifecycle Harness only, provider base URL/model/output mode/cost ceiling from the process environment override the saved MCM profile for the started Host request and carry a `harness-environment-override` source label.
The mod never writes these values back to the user's MCM settings.
The live Host's model-list health check must use the same temporary endpoint as the preflight.
When an OpenAI-compatible provider returns an incomplete message envelope, the Host records only structural fields (choice count, message/content presence and kind, tool-call count, finish reason and format mode) in the failure receipt.
It does not retain model prompt or response text.
This lets a natural campaign distinguish an upstream format response from a Host parser error without copying private conversation content into TestResults.

The MCM Start Agent request action catalog must exactly equal AgentHostCampaignLoop.AllSupportedActions. Check-Docs derives both sets and fails if they drift, because a stale MCM list can reject a valid Campaign request before any provider is called. The 2026-10-30 natural StoryMode attempt exposed four omitted actions; the MCM request now includes the full current union.

AgentHostLifecycleReceipt now allows decision metrics and classification flags to be absent in early Host errors, so a rejected request keeps its error code/message instead of failing receipt serialization. Campaign-loop request rejection also names which bound or action-set check failed and lists safe missing/unexpected action IDs; it never records provider credentials or prompt contents.

Agent-Cli startup writes a compact JSONL trace for launch monitoring, sampled startup-loop phases, the campaign-loaded marker, window-layout calls, session creation and the initial protocol probe.
The focused ArenaMaster runtime test runs the CLI in a hidden child process with a 300-second minimum wall-clock bound; after process exit it refreshes the process object and trusts a valid completed Native result if the operating system exit code is unavailable.
A nonzero exit code or a mismatched/incomplete result remains a failure.
Cleanup stops only a newly started process whose command line names that test's disposable save, then restores the saved engine configuration when no Bannerlord client remains.
Its failure receipt names the exact test step and pre-cleanup session/process state.
The Mission observation now exposes whether Native MissionConversationLogic has received its rendering-time ConversationManager initialization; missionInteract rejects early calls before invoking the original Agent.OnUse handler.
These diagnostics make a stuck launch bounded and locatable; a trace alone is not proof of a successful protocol handshake or Native interaction.

Engine delegation principle: the Agent chooses long-term goals, targets, commitments and consequential responses, and verifies the result.
When a particular Native task already starts an NPC-controlled Mission or an original tactical simulation, let the game engine perform continuous movement/combat and observe its result; do not build frame-level control simply because the player entered 3D. This is route-specific, not a blanket claim that all battles are delegable: if the Native encounter disables simulation, record a distinct capability gap and only then decide whether direct control or a different strategy is needed.
Never treat starting/ending a Mission as proof of success; check the Native quest/reward aftermath.

Long Campaign wait rule: do not pair UnstoppableFastForward with sparse Agent/model polling on a route where parties or quests can collide.
The escort exploration on 2026-10-29 moved the world over two days during a few seconds of fast-forward; a hostile party appeared adjacent to the caravan, then the caravan and quest disappeared before the next stable observation, so the outcome was unclassified.
For similar routes, keep model planning event-driven and low-frequency, but collect Native state/event changes frequently enough to stop on an encounter, map event, objective stage change or quest end; capture the game window around transitions when telemetry cannot explain them.
`Capture-LiveGameWindow.ps1` passively attaches to the existing Bannerlord window, samples Native state fingerprints during the clip, produces a compact indexed contact sheet plus state-transition frames, and deletes a successful source video; it sends no game input and launches no second client.
`Observe-LiveCampaign.ps1` supplies the state-only fallback when a live window is minimized: it logs Native snapshots and an optional active Quest journal, optionally pauses on a visible hostile, and never moves the player, advances time or calls a model.
`TestResults/20261029-090936-live-ui-transition/TownArenaMenuTransition-receipt.json` confirms 133 frames/8.867 seconds at complete coverage, captured both map-menu transitions with 12 indexed transition frames, and removed the source video.
`TestResults/20261029-085325-live-window-capture/livecapture-smoke4-receipt.json` confirms a 3.1-second unchanged-screen clip condensed to one representative tile.
Current-window diagnosis then showed Bannerlord was minimized/offscreen; the capture utility now fails fast without restoring or moving it, documented by `TestResults/20261029-092445-live-window-capture/minimized-guard-test-receipt.json`.
Capture failure after a recording has already started also includes FFmpeg stdout/stderr so a future empty-frame or device error is diagnosable.
Pause time before choosing a consequential response, and do not infer success/failure from an active-quest list entry disappearing.

Quest terminal outcomes: `QuestBase` dispatches `OnQuestCompletedEvent` with the exact Native result after its own consequence, then `QuestManager` removes the object from active quests.
Chronicle records that result in Campaign SaveData; the existing on-demand `questDetails` query returns `isTerminal` and exact `terminalStatus` for that QuestId after it leaves `state.quests`.
The Agent checks the final Journal entry and event enum; list absence is not proof.
Natural Escort Quest Success (2/2) and Fail (caravan destroyed) both passed separate save/load readback; receipts: `TestResults/20261029-live-storymode/EscortQuestTerminalObserverVerification.json` and `EscortQuestFailureTerminalVerification.json`.
Timeout, Cancel and Betrayal remain untested.

Native Map Incidents are blocking player choices, not passive notifications.
The observer reads only the active `MapIncidentVM` options from the current `MapIncidentView`; the Host asks the Agent to choose an exact current `OptionIndex`, then the Native adapter calls the original option-select and Done handlers together.
The original handler applies that option's effects and closes the panel, which restores its previous Campaign time mode/lock.
The EYC parent resolves an Incident before objective planning, and rechecks it after a child route is interrupted.
If the same incident remains, or the view closes while another Native time lock remains, the Host stops without replaying the option or injecting a clock command.
A Map lock with no active `mapIncident` observation remains a separate diagnostic gap.

Postbattle Loot `PartyState` also participates in the Native Yes/No inquiry bridge.
`PartyVM.ExecuteDone` can ask whether to leave transferable survivors behind; the observer now reads that current PartyScreen roster and inquiry text, and BattleSimulation routes the shown buttons through the original `SingleQueryPopUpVM` handler.
The Agent's choice sees the current parent EYC goal/progress and left/right roster, so it can weigh party growth against the troop type it would take.
It must reread PartyState after each response; `partyScreenDone` completing its callback alone is not proof that the screen closed.

The EYC PartySize route may use both current RecruitmentVM volunteer offers and current MainParty prisoner offers.
The prisoner path reads conformity XP, recruitable count and Native prisoner-limit preview, then uses one original `PartyCharacterVM.ExecuteRecruitTroop` per action.
`confirmPartySizeWarning` (member cap) and `confirmPrisonerLimitWarning` (prisoner cap, with speed/escape consequences) are separate decisions; an over-limit prompt is never silently accepted.
When a prisoner offer is temporarily over-cap, the EYC Parent resolves any active Native Inquiry using a fresh Journal snapshot before it replans; the child action does not claim a recruit unless its Native receipt shows one prisoner moved to MainParty.

Model connection is an OpenAI-compatible provider contract, not a FreeLLMAPI product dependency.
MCM Global settings store the HTTPS base URL, model ID, structured-output mode (`auto`, `json_schema`, `json_object`, or `required_tool_call`), and the DeepSeek-only per-run CNY ceiling; API keys stay in the current user's environment and the game passes them only to its owned Agent Host child.
HTTP is accepted only for loopback endpoints.
The legacy MCM `OllamaBaseUrl` JSON property is still read for migration, although its UI label and behavior are provider-neutral.

Native inventory UI can produce a real `InquiryData` while the active GameState is `InventoryState` (for example, the Native “over inventory limit” confirmation after clicking Done on a trade).
The observer and `respondInquiry` support this inquiry in Map, Mission, Inventory and PartyState; `tradeConfirm` is reported as accepted while that Native confirmation is pending, and only as completed after its native callback closes the trade and verifies roster, market and gold changes.
The exact affirmative/negative handler remains the active Native Inquiry ViewModel callback.
Village “Buy Provisions” is also a Native Trade InventoryState: permit the standard trade adapter only when `Settlement.CurrentSettlement.IsVillage` and the current Native menu is `village`, and report that scope explicitly in `tradeOptions`.
The Native Village panel is not an ordinary Town merchant or a freely transferable stash.

Native Tournament panel observation/actions are available through `ChronicleTournamentAdapter` for manual Harness play. It captures the current Native `TournamentVM`, verifies it belongs to the active Mission, and calls only the original `ExecuteJoinTournament`, `ExecuteSkipRound`, `ExecuteSkipAllRounds`, `ExecuteWatchRound`, or `ExecuteLeave` handler. The Agent Host action catalog does not yet expose these commands; this helper is not evidence that autonomous tournament play works.

Mission observation prefers `Mission.Current` and reflectively reads the active state's public/private `CurrentMission` property when the static pointer is null; it also reports the active state's fully qualified type and Native Mission lifecycle flags.
`missionRetreat` calls the original `BattleEndLogic.TryExit` through the current MissionState and also supports its postbattle `MissionEnded` phase.
This is the engine handler for the Native TAB battle exit path, not arbitrary keyboard injection; a resulting Yes/No Inquiry must still be observed and answered explicitly.
It does not control combat movement or claim victory.

Agent and engine responsibility is split per observed Native route.
The Agent decides goals, targets, commitments, tradeoffs, and when to stop/replan; when a Native task already creates NPC combat/navigation behavior, let that engine behavior run and verify its Mission/Quest/Gold/Party outcome instead of inventing frame-by-frame inputs.
This is not a blanket assumption that all 3D scenes self-resolve: verify each route's Native mission behavior and exit, then add direct control only for actions the goal actually requires and the engine does not already perform.
The observer also reports `timeControlModeLocked`, so a stopped in-flight move can be distinguished from an ordinary stopped clock before any retry.

Campaign menu observation calls each Native option's condition before serializing it and includes the Native tooltip in addition to availability/enabled state. A disabled action such as `Send Troops` must carry its player-facing reason when the original handler provides one; the Agent can then choose a valid alternative or address the specific prerequisite rather than treating all disabled options alike.

When MainParty Morale is zero, the State also includes a conditional `party.moraleContext` with the Native recent-event morale, starvation, unpaid wages, food variety, and effective morale calculation inputs. This diagnostic exists to explain a source-verified `Send Troops` precondition and is omitted while morale is positive.

Provider output compatibility is explicit: local loopback auto mode keeps JSON Schema; remote auto mode uses the broadly supported JSON-object format and Chronicle validates every returned property against the current action/control catalog.
DeepSeek `api.deepseek.com` auto mode selects strict required function calls and disables thinking, matching the upstream API's documented constraint that required tool calls need thinking off.
The player can override that mode in MCM for another service.
Provider health is a read-only standard `/models` request before the first decision; a catalog listing is not inference evidence.

The default Agent Host output ceiling is 256 tokens per decision.
For direct DeepSeek, the Host uses the pinned official V4 BPE tokenizer via Microsoft.ML.Tokenizers 2.0.1 on the rendered system/user chat and structured output metadata.
Each request reserves 15% above the rendered chat plus structured metadata token count, then adds 256 service-wrapper tokens, the full output-token allowance, and peak cache-miss input pricing converted at the conservative 8 CNY/USD rate.
The default CNY 5 value is a pre-request reservation threshold, not a guaranteed invoice cap; API-returned `usage` remains the actual billed usage.
Per-request traces retain chat/schema estimates, raw serialized-body BPE counts, reserved tokens, and provider usage without saving prompts or request bodies.
If the estimate would exceed CNY 5, the Host stops before sending that request.
Other providers do not use DeepSeek pricing and have no universal monetary limit.

Two natural StoryMode runs have now exercised the direct DeepSeek route.
`TestResults/20261026-224448` completed official Tutorial skip, natural EYC activation, and 13 model decisions / 8 Native actions, then stopped on `recruitment-rejection-limit`; model output used canonical `observeAgain: true` but the PartySize subloop checked only the legacy `control` string.
The shared normalizer and regression test now cover both forms.
`TestResults/20261026-234615` completed 14 decisions / 8 actions and moved to `village_ES3_2`; after Native opened the known VillagersInNeed conversation, the model chose `dialogueContinue` but the dispatcher rejected it in the narrower Campaign map transport before sending the Native action.
The transport now permits the two dialogue action shapes through the PartySize adapter, while the subloop remains responsible for exact quest/hero/current-option checks.
`TestResults/20261027-011851` then selected Companions instead of PartySize, so it does not verify the repaired village dialogue route.

`TestResults/20261027-011851` is the first natural StoryMode run with the per-Host DeepSeek budget active.
Companion hiring consumed 73 decisions / 69 Native actions and stopped with `provider-budget-exhausted` before the next request; original EYC remained active and incomplete.
The final Host receipt shows 437,238 prompt / 3,824 completion tokens, 63,488 cache hits / 377,292 misses, ¥0.94686181 usage estimate, and ¥4.9852152 reserved upper bound against the ¥5 limit.
Companion diagnostics show 28 same-target navigation repeats, 0 nearby interactable observations, and no successful conversation, so the Host repeated a native movement route without getting closer in a useful way.
A package-tested progress guard now lets the model switch candidates after one stalled approach and excludes that candidate after the second completed attempt without measurable distance improvement; this repair is not yet live-verified.
That second run also gives the first concrete prompt-size signal: one `move` decision sent a 305,831-byte request with a 110,645-byte observation and 68,573 prompt tokens, including 3,200 cached and 65,373 uncached tokens.
Its usage-based peak estimate was ¥0.1576056.
Request sizing and cache-use diagnostics are now recorded per decision, including the largest Native-state field byte counts without storing state contents; the field responsible for the large observation remains unknown until the next run's trace is read.
2026-10-31 cache follow-up over natural DeepSeek Flash receipts `031135`, `042808`, and `024803`: together 790 decisions used 3,024,518 prompt tokens, of which 707,456 (23.4%) hit cache and 2,317,062 missed; every decision had some hit, averaging about 896 cached tokens per call.
Provider requests place a route-specific system prompt before a per-decision serialized Native observation/action catalog, so this pattern is consistent with reuse of the static prompt prefix and misses on changing world/UI context; exact per-message attribution is not returned by the API, so that explanation is an inference.
In the Tavern Companion subgoal, the raw `mission.nearbySceneAgents` roster duplicates the separate compact current-scene Wanderer and nearby-interactable lists, and the 901-byte MainHero skill list does not affect choosing from the current Native hire quote/options.
The model request omits only these two task-irrelevant/redundant fields while retaining mission identity, current Native-derived Wanderer summaries, Gold, Journal, and the full unprojected state for Host action validation.
`TestResults/20261031-195016/Temp/AgentHostPackage/AgentHostPackageManifest.json` records a synthetic 40-agent projection at 7,133 raw Mission bytes→108 projected bytes and 2,677→285 pinned DeepSeek BPE prompt tokens (2,392 estimated tokens saved).
A Fake Native/Provider transport regression confirms the actual decision request receives the projection while retaining the candidate lists; package self-tests ran with 0 real model calls/0 Native game commands.
These are synthetic size/token estimates, not live-token savings or quality evidence; real-model impact remains unverified while tests are paused.
`TestResults/20261027-011851` used the real DeepSeek route in another natural StoryMode.
It reached the original EYC planner, then spent 73 decisions / 69 Native actions inside Companions and stopped when its ¥5 reservation ceiling would have been exceeded by another request.
Native quest completion was not verified.
The Host receipt reports 437,238 prompt / 3,824 completion tokens; using DeepSeek's reported cache data, the conservative peak estimate is ¥0.94686181, while the total upper-bound reservation was ¥4.9852152.
Companion diagnostics show 28 repeated navigations to the same candidate, 0 nearby interactable observations, and no conversation.
The new progress-aware route guard passed package tests but has not yet been live-verified.
All Harness-owned Bannerlord launches now temporarily set only `engine_config.txt:disable_sound=1` before process startup.
The guard records the original value in a config-side backup, restores only when Bannerlord is no longer running and the value is still the Harness-set `1`, and leaves the backup/records a conflict instead of overwriting a concurrent user edit.
`Run-Harness` attempts stale sound-guard recovery before a new run.
This does not change Windows master volume, MCM preferences, or permanent game settings.
A no-game test toggled `disable_sound` 0→1→0 and verified the entire `engine_config.txt` hash returned exactly to its starting value.
The in-game Smoke receipt `TestResults/20261027-011610/Temp/SmokeResult.json` confirms 0 before launch, 1 during the game process, 0 after cleanup, successful restoration, and no leftover sound backup.
The natural StoryMode run `TestResults/20261027-011851` records the same 0→1→0 lifecycle, confirming the normal long-run path used the quiet setting; this verifies the engine configuration path, not captured acoustic output.
When the player starts the autonomous Agent, Native input ownership is acquired before the Agent Host is spawned.
A high-priority `ScreenManager` global layer claims keyboard/mouse UI input; while an owned Host is starting/running/stopping, a separate Mission `InputManager` gate blocks physical Mission actions, and a Harmony guard suppresses the game's focus-loss Escape-menu path.
The Native `ChronicleAgentControl` GameKey is the emergency hand-back; it requests a safe Host stop, but the input gates stay active until the owned process exits.
Native quick information tells the player who owns control and shows the current hand-back key.
Returning control or detecting a missing/exited Host restores the original Mission context and Native focus-loss behavior.
Failure to install the layer/focus guard or a missing/conflicting toggle binding rejects Host startup, so the Agent cannot run with an unprotected player-input path.
`TestResults/20261026-053427` confirms the layer is topmost with `InputUsageMask.All`, routes a game-process synthetic mouse-button state and Escape through `ScreenManager` without handing them to lower screen layers, exercises the Native focus-loss callback with `StopGameOnFocusLost` temporarily true in memory, and verifies release after Host exit.
`TestResults/20261026-164936/AgentHostLifecycleEvaluationResult.json` additionally verifies AI→player→AI→player by sending the registered NumpadMultiply through Native `Input.PressKey` inside the game process; both Host handshakes/stops succeed, Campaign day/location, fixture hash, and Native action count remain unchanged.
This is a synthetic engine key state, not a physical desktop keyboard event; the dedicated mouse probe does not emit a physical mouse event, exercise a Mission, or change real OS window focus.
The dedicated test disables the Harness focus guard and records native focus permission as allowed before AI takeover, so it tests the product guard rather than a test-only block.
`AgentPlayerInputOwnership.cs` is the only runtime owner of this state; do not add separate per-screen locks or duplicate the ownership flag.

The Native control key is registered as a serializable, options-visible `GameKeyContext` under `CampaignMapCategory`; `ModuleData/global_strings.xml` supplies its category, name, and description.
The module build and release packager both include this resource, and Smoke reads the three resolved labels from `GameTextManager`.
`TestResults/20261026-164423/Temp/SmokeResult.json` also instantiates the installed Native `GameKeyOptionCategoryVM` for `CampaignMapCategory` and confirms the Chronicle entry is present with its localized name, description, and current key (`optionsVisible=True`).
This verifies it enters the Native keybinding data model; the rendered page layout and a physical user rebind gesture are still unverified.

The general `agent-host-lifecycle-test` Harness mode has its own focus-loss guard to prevent test windows from opening Escape. The dedicated input-ownership test sets `CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST=1` so that Harness guard is not installed; otherwise it would hide the product guard's behavior. Keep this test override explicit and retain a separate receipt proving the Native product guard and player-mode passthrough.

Lifecycle objective-subflow diagnostics may include a numeric `providerHttpStatus` for a rejected remote HTTP response; raw provider error text, credentials and model content remain excluded. This lets the Harness distinguish transient gateway failures (502/503/504) from rate limits or configuration failures before deciding whether a state-checked Native exit and parent replan is safe.

The PartySize executor counts each model decision once against its configured decision budget.
If the model asks to stop while the fresh Native catalog still contains safe actions, Host rejects that control before sending a game command, explains the exact current action and its effect, and asks once more.
If it still stops in a Town Backstreet with only the original enabled Back option, Host may call that exact current Native menu handler and verify the same Town menu and active EYC before resuming model decisions; no recruit, Gold, or time action is substituted.
Other repeated stops mark PartySize temporarily unavailable on the current free Map and let the parent continue to unmet objectives.
It clears unavailable routes after Journal progress, without claiming the skipped objective is complete.
Package self-test `TestResults/20261025-182805` checks the parent replan policy and the exact Backstreet exit recovery followed by the simulated RecruitmentVM→Native recruit→Journal route; these are fake Native/provider contracts, not live-game or real-model success claims.
Natural run `TestResults/20261025-183732` continued after a PartySize stop in the Town main menu and reached a Gold sale, but did not enter Backstreet, so it does not verify this specific fallback.

Companion `missionNavigateToAgent`/`missionInteract` numeric arguments are normalized only for one exact formatting wrapper around a decimal value, then must match the current Native `argumentValues` and observed local Wanderer candidate.
`[4]`, `**4**`, and `` `4` `` can canonicalize to index `4`; prose, mixed values, or an index absent from the current Native catalog remain rejected.
`TestResults/20261025-193149` package tests both accepted canonicalization and negative out-of-catalog rejection; it does not prove a live Companion hire.
Natural run `TestResults/20261025-183732` emitted a bracketed index and later ended on HTTP429 before the original Journal showed a recruited Companion.

Lifecycle objective-subflow progress now carries an optional `recruitmentOfferSummary`: current Gold, party size/capacity, total/available/affordable offer counts and lowest affordable cost.
It deliberately omits notable IDs, troop IDs/names and free-text response text.
This helps distinguish “no affordable Native offer” from a model choosing stop while a current offer exists.
`TestResults/20261025-193149` includes a no-model self-test that checks the counts and rejects any fixture Hero/Troop identifiers in the trace.

Companion objective-subflow progress now carries an optional aggregate `companionNavigationSummary`: Native scene scans, navigation attempts/repeats to the same target, starting and observed target-distance ranges, interactable-nearby samples, interaction attempts, and successful conversation starts.
Target identities and names are used only in memory to correlate measurements, then omitted from the receipt.
This distinguishes repeated navigation with no measured approach from reaching an interactable person but failing to open dialogue.
A package self-test verifies aggregate values and rejects fixture Hero IDs/names; it does not prove a live Tavern interaction.

A 2026-10-31 fresh real-model run selected the Companion objective and entered the original town Tavern, where Native initially reported `MissionState/StartUp`, `encounterActive=true`, and `encounteredPartyId` equal to the current settlement.
The old generic encounter guard treated this friendly interior Mission as an interruption.
The Host now recognizes only a live Mission whose Native scene name contains `tavern` and whose encountered party exactly matches the current settlement; while Native `CurrentState` is `Initializing`, it waits passively with a 20×500ms bound and confirms the EYC quest is still active before permitting Tavern actions.
True map-party encounters remain blocked.
Fake Native regression passes; a fresh real-model Campaign still needs to prove post-startup Wanderer observation and hiring.

The subsequent natural run verified that Tavern fix with DeepSeek Flash: the model navigated the current town menu, queried/approached/interacted with a current Tavern Wanderer, completed the original hire dialogue, paid through the Native consequence, and the EYC Journal reported Companion 1/1.
This is the first real-model objective subflow completion in the fresh StoryMode gate.
The same run later interrupted twice on PartySize safe-stop, found no safe Renown action, and stopped on Gold because Native Town Trade remained tagged with the current Settlement as an encounter owner; Gold Sale's narrow Trade-VM exception is implemented and is awaiting package verification before the next Campaign.

The PartySize executor handles one source-verified StoryMode exception: first MainParty arrival at `village_ES3_2` can automatically open `VillagersInNeed` dialogue with its quest villager.
A fresh real-model run reached this screen but the model stopped twice while Native showed only “click to continue”; no answer was selectable and no EYC progress was claimed.
The Host now calls the original `dialogueContinue` handler only for this exact quest/character/location when the live Native option list is empty, then rereads state after every line.
It leaves actual answers to the model, allows only the current clickable non-mission answer, and fails closed if state or text does not progress.
The package fake route verifies continue → visible answer → defer → Village RecruitmentVM → Journal-verified recruit; this is a deterministic Host UI step, not an LLM decision, and its fresh-campaign runtime verification is still pending.
Contract evidence is in `Research/J/TasksEventsAndNarrative.md` J12 and MAINLINE's mechanic contract.

The Native active-conversation snapshot includes the current `CharacterObject` ID/name as well as optional Hero ID/name.
These fields are emitted only while a conversation is active; the current StoryMode villager has a CharacterObject identity that lets the Host scope this one recovery without treating unrelated Mission conversations as interchangeable.
The output is regression-checked as comma-delimited JSON; `TestResults/20261026-010410` caught the first implementation's missing comma after `characterName`, which produced a malformed Native response during a real bandit conversation.
The corrected build passes `AgentHostPackage`, and `TestResults/20261026-024929` confirms a live Native bandit Conversation parses with `characterId=looter`, `characterName=劫匪`, and `heroId=null`; fixture hash and process cleanup passed.
This does not verify the separate StoryMode VillagersInNeed trigger or its deferral branch.

The Companion executor may strip only a single known formatting wrapper (`[4]`, `**4**`, or `` `4` ``) from a numeric `AgentIndex`/`DurationSeconds` string returned by a provider, then must match the resulting integer against the fresh Native `argumentValues` before any action.
Values outside that current list and other prose remain rejected.
The Companion contract self-test proves both the exact in-catalog normalization and negative out-of-catalog case; no IDs or durations are inferred from the game goal.

`FreshStoryModeNativeMenuLeaveEvaluation`是非模型的窄Native集成测试：同一个新Campaign先通过兄长对话的原版“跳过教程”及确认，原生推进对话后自然结束训练场Mission并进入活动EYC的首个MapState；
该状态仍位于`training_field_menu`。
Harness只选择当前启用的原版`training_field_leave`并通过`GameMenu.RunMenuOptionConsequence`调用原版处理器，随后验证回到地图、训练场菜单/地点退出、EYC仍活动、CampaignDay与Stop档位未变、无存档写入，并捕获前后引擎画面和Native post-action观察（包括若出现的Inquiry）。
`TestResults/20261022-194410`完整通过；
`20261022-195530`复测后还在收据中明确记录`brother-dialogue-path-no-tab-fallback`。
两次教程Mission离开均由原版兄长对话路径完成，没有使用Tab兜底。
这项测试只验证开局准备与单项Native菜单动作，不计作AI决策或长程EYC目标进展。
`TestResults/20261022-193820`曾在兄长对话仍活跃时过早模拟原版Leave Area并触发游戏空引用崩溃；
现Harness改为每1.5秒推进一次原版“点击继续”，且仅在ConversationManager已结束对话、场景仍未退出时才启动2.5秒Native Leave Area兜底。
该兜底在训练场场景尚未单独实测，严禁在对话仍活跃时触发；
其它Town Mission Leave证据不能替代该特定验证。
后续弹出的通知/询问也不会由本测试自动确认。

Fresh StoryMode observer的原版Native菜单退出快照是schema JSON根对象本身，字段路径为`context.inquiryOpen`与`context.inquiry`，不是Agent Host邮箱包裹使用的`state.context`。`20261022-194410`的快照实际包含离开训练场后标题“通知”、仅affirmative“好”的`YesNoInquiry`；当时测试汇总误读为嵌套对象，导致log显示`InquiryOpenAfter=false`/`Inquiry=null`，与同一运行保存的快照相矛盾。`Test-AgentFreshCampaign.ps1`现在读平面路径，`Check-Docs.ps1`回归检查该schema形态并拒绝旧错误路径；汇总Inquiry仅包含玩家可见字段、排除一次性token；旧收据保持不变，新路径由`20261023-033645`窄运行实测确认。

独立的`FreshStoryModeNativeInquiryResponseEvaluation`阶段从全新自然StoryMode经原版skip/tutorial leave触发这条通知，用`Agent-Cli.ps1 respondInquiry`按新鲜token选择Native唯一可见且启用的affirmative按钮。它是无模型、仅Native事务/回调和时间/Quest后验测试，不算AI自主能力，不保存进度；为复用CLI而临时创建的测试session只绑定当前Bannerlord PID，仅当session路径原本不存在时才建，结束后按PID归属清理session、命令和响应文件，不启动AgentHost也不发送LLM请求。必须验证VM handler回执、弹窗关闭、EYC保持active、CampaignDay/raw Stop不变与进程清理，并把Inquiry token从结果摘要中去除；只有真实Agent Host模型自己在同一局面选择并提交该动作，才算产品闭环证据。

正常AgentHostPackage阶段会先检查D盘`BuildCache/Packages`内只属于该Harness的`ChronicleAgentHost-win-x64-<32位GUID>`临时发布目录；仅清理创建超过24小时、且当前没有Bannerlord或AgentHost运行的目录，并在回执中记录数量和字节数。未达到年龄的保持不动；不扫描/清理其它BuildCache或用户数据。

从 2026-11-21 起的运行与诊断时间条目（连同它们引用的 `TestResults/` 收据）已整体移到 [RUNLOG.md](RUNLOG.md)；本文件的顶部区域只保留契约版本沿革与稳定的工程契约。

## 当前产品边界

在精确的友好城镇酒馆 Mission 中，Host会先通过既有Native `missionSceneAgents`读取当前场景候选，再把候选交给模型；这类只读感知不再占一次模型决策。仅在当前无对话、同伴目标未由Native状态满足且场景候选尚未读取时执行；当前对话与已达标后的原版离场仍沿原有流程。该观察记录为`native-tavern-scene-observation`，计入Native命令统计但标明没有模型决策和改变游戏状态的输入。`TestResults/20261107-032130` AgentHostPackage覆盖两次场景读取均不增加模型调用、并保留模型导航/交谈/雇佣决策；下一次真实模型长测再测实际token节省，不把包内自测当作运行成本证明。

EYC Companion子流程现在复用存档中的Campaign-scoped Agent checkpoint保存“当前EYC目标快照下，哪些Town Tavern已确认没有可招募Wanderer”。
它只在原版酒馆场景扫描确认无合格候选、且Agent已返回Native MapState后写入`agentCheckpointSet`；
Host重启后用`agentCheckpointGet`读取，按Native Campaign identity验证并从候选Town中排除这些地点。
EYC Journal四项目标发生变化时，该记忆失效并清空；
候选出现时也移除该城镇的旧“无候选”标记。
若当前场景没有候选且原版目录仅剩`missionLeave`，Host提交这个唯一可用的原版离场动作并等回Map后再落盘；
有任何可选Wanderer或对话时仍由模型决策。
它不注入目标进度或改动Quest/资源/游戏时钟。
`TestResults/20261107-040422` AgentHostPackage的Fake Native测试确认空酒馆离场、存档写入、跨Host重启过滤与其它Town可选。
真实Campaign运行`TestResults/20261107-041139`保存检查点后，`TestResults/20261107-043410`下次启动的安全摘要确认`checkpointReadAttempted=true`、`noCandidateTownCount=1`、`memoryMatchedCurrentJournal=true`、没有发生Journal失效；
该轮没有完成EYC目标。
检查点读写和记忆复用已获得真实Campaign证据，但同伴招募尚未完成。

若EYC目标子流程因Bandit等事件返回父循环、此时原版 MainParty 仍在前往Settlement，Companion恢复后会继承Native当前`GoToSettlement`目标并被动监视路途；不再重新查询目标表或重复提交相同`move`。当前停止/遭遇仍走既有上层恢复路径。`TestResults/20261107-044809` AgentHostPackage与`TestResults/20261107-050137`自然续跑已验证继承移动并避免重复EW2目的地。但真实续跑还显示，监视器为确认可见敌对Bandit而暂停移动后，EYC父循环先按“普通暂停移动”返回处理，压过了下面已经存在的Bandit坐镇路线，导致子流程重选Companion而未处理敌人。现在只有确认当前Native Map有该Bandit时，父循环才先路由已实现的BattleSimulation；没有可见敌人的暂停移动仍走原有Native Move恢复。`TestResults/20261107-051813` AgentHostPackage回归覆盖这条优先级，真实敌对中断尚待复测。

在自然续跑`TestResults/20261107-053329`中，追上敌对劫匪后Native不提供可用坐镇战斗（主队无士兵）；真实模型选择了原版投降，并接受原版赎金询问，Campaign Map恢复。主角/Party仍为1人，金币从1000降到670，Renown维持20。这验证的是原版投降/赎回恢复，不是战斗胜利或EYC目标进度。之后另一次敌对中断也没有可坐镇战斗结果，Agent回到`town_EW3`的原版招募入口并查询志愿者，预算到顶前尚未招募；原版Town菜单安全存档成功，当前EYC仍未完成。

Campaign地图已在进行原版`GoToSettlement`移动时，如果 EYC Host 从Bandit/其他已处理事件中重启Companion子流程，Host将从当前Native `targetSettlementId`继承路线，并沿用现有被动时间/遭遇观察器；只有到达城镇、出现新状态或需要模型决策时才恢复目标规划。该恢复不发新的移动命令、不更改时间速率，也不替代遇敌决策。

真实模型续跑`TestResults/20261107-041139`使用DeepSeek和¥0.10预算，进入原版Town ES3 Tavern后没有 eligible Wanderer，Host以唯一可用的原版Leave返回Map，随后Agent选择Town EW2。该段10次模型决策/10条Native命令，估算¥0.05229593、reserved ¥0.0974016；EYC Journal未变化。Native SaveAs将同一Campaign存为`ChronicleEycDev-freshB-20261107041407-7b7149c4`（SHA-256 `D3581AFB22DA8CEAFA9753666D963623172C84530998D8F444C087DAA0A95C92`），进程清理成功。该运行证明自动Leave后Agent继续选了另一个Town；当时的收据没有输出检查点记忆摘要，下一次恢复运行要用新增的安全汇总确认Campaign checkpoint读取、Journal指纹匹配和记忆重用，不能把这一段当作跨重启实测通过。

自2026-10-19起，产品主线是AI自主控制MainHero/MainParty游玩单机Campaign。一个Agent需支持持续自主推进与玩家临时交办两种模式；临时指令完成/受阻后回到自主目标循环，不能退化为玩家逐步点选的遥控器。首个长程门禁是由真实模型从自然StoryMode流程完成原版`Establish Your Clan`四项目标并由Native判定任务完成；本首测允许玩家先走原版TrainingField兄长对话并确认Tutorial skip，AI从随后首个稳定Campaign MapState接管；不允许使用预备存档或注入进度。Tutorial skip是玩家原版开局操作，不算Agent能力，完整未跳过教程自治留作后续扩展。此次门禁只证明首段闭环，不等于整个自主玩家产品完成。NPC/同伴Agent保留为后续玩法候选，但同伴加入MainParty本身没有独立Campaign Party Think循环，因此不假设其比MainHero更容易接入。工作顺序以GitHub Project中MainHero StoryMode门禁唯一进行中的产品Issue为准。
当前StoryMode父循环已把Gold、动态PartySize、Renown及Companion四个目标接入已有Native子流程。
Town Tavern Companion路由只用当前菜单、同一Mission内观察到的Wanderer、原版导航/交谈及当前可点击雇佣对话；
Native AgentNavigator/Leave输入租约活动时由Host只读轮询状态，不再为`observeAgain`额外调用模型；
当前目录不接受的回复最多给两次本目录反馈，超限后安全失败且不重放Native动作。
可恢复的Provider输出错误若发生在无对话/弹窗、无敌对遭遇/移动的自由Campaign Map，父Host可仅把当前未完成路线暂时排除并基于新鲜Journal重新规划。
若错误发生在Companion的友好Town/Tavern `StartUp` Mission内，父Host仅调用一次原版`missionLeave`，验证返回仍有EYC Quest的自由Map后再排除Companion路线；
其他Mission、战斗、捕获、对话和未验证状态仍fail closed。
Host包Fake Native/Provider回归验证这些边界，不等同真实Campaign或真实模型通过。
此区别和当前四目标集成状态以Focus/MAINLINE为准。
EYC父循环每轮最多20个目标周期曾在真实自然运行约243/320个累计模型决策时提前结束，留下至少77个可用决策预算。现移除该独立20轮限制，循环次数以同一请求的累计决策预算为上限；它不增加token预算/耗时预算，也不能覆盖模型停止/失败或原版Quest失败。`TestResults/20261031-185533` AgentHostPackage通过；Fake Native父循环验证连续21次部分Gold进展后，只有第21轮原版Quest Native lifecycle转为completed才允许父循环报告成功。SelfTest发出0次模型调用、0条Native游戏命令。该回归证明删掉20轮截断并保留原版任务后验，不证明自然Campaign完成。
Gold子流程遇到Provider/Native故障时返回失败收据，其中保留已有子流程Trace、Native动作计数、路由和安全失败码；父级不得因失败后验缺失而宣称执行了未记录的动作，更不得重放非幂等交易。真实响应错误文本仅限安全摘要长度，不保存模型prompt/回复正文或认证信息。
新增的`AgentHostEstablishClanAutonomyEvaluation`是后续真实模型集成调试入口：从已有活动StoryMode存档的逐字节临时副本加载，真实模型可驱动四目标父循环，随后清理副本；它不是新战役门禁。产品验收仍要求玩家原版Tutorial skip后从首个稳定MapState接管，并在两个独立自然新建的StoryMode战役完成原版Quest。

EYC实机诊断只做只读FreeLLMAPI目录检查、构建、AgentHost包合同测试和Native启动Smoke，不在Campaign前再花一次真实模型调用；
在真实Native状态可见后，第一条模型请求就是生产EYC目标分类。
独立`AgentHostProvider`保留为opt-in路由诊断工具，不证明EYC分类能力，也不保证后续请求仍可用；
即使它成功，也不得作为随后启动EYC游戏循环的“模型就绪”门槛或理由，因为下一次请求可能立即遇到不同冷却/上游状态。
若当前目标是完整EYC实测，跳过独立Provider smoke；
若当前目标仅为FreeLLMAPI故障诊断，则至多做一次单路由诊断，不把成功外推为Campaign可用性。
Direct FreeLLMAPI model用本机`/v1/models.supported_parameters`选输出协议：优先模型声明的原生`response_format`；
只有模型未声明该参数且同时声明`tools`与`tool_choice`时才用一个强制、无副作用的decision tool-call；
参数仍须通过同一Native目录/本地校验。
Auto路由保持JSON Schema，使FreeLLMAPI只挑选兼容候选；
未声明两种能力的Direct model在请求前安全失败，不做无约束文本解析。
模型目录`ready`只代表存在可选路由，不证明上游当下能回答；
每次真实请求按实际路由、结构化结果和错误日志区分上游/代理传输故障与AgentHost协议/参数错误。

通用目标分类按当前`allowedControls`只附带可用目标类型的简短语义，区分“目标类型受支持”与“该目标的Native前置条件当前可用”；Host在分类后再以Native状态核验任务/对象。Provider smoke的默认输出上限与游戏内MCM profile保持一致（1024 tokens），但用户显式配置优先。分类合同或测试配置调整时，用离线Host合同检查控制列表/提示范围一致，并记录真实模型决定；不得把一次Provider烟测当作EYC完整闭环证据。

Fresh StoryMode setup Harness只在显式`CHRONICLE_FRESH_CAMPAIGN_STORYMODE`辅助标记下从原版`InitialStateOption`目录执行官方`StoryModeNewGame`菜单委托；
Campaign自身及原版CharacterCreation流程负责创建角色，再由Native `ConversationManager`选择训练场兄长的原版`player_answer_skip_tutorial`与`end_tutorial_yes`选项。
不直接调用`CompleteTutorialPhase`、不写Quest/资源、也不保存或回载预备档；
启动必须经过BLSE standalone与稳定Steam就绪检查，避免直接启动`Bannerlord.exe`触发Steam API警告。
Harness分别记录教程跳过后首个稳定MapState和原版EYC Quest实际激活，不把二者当成同一个状态；
非模型setup仍须验证EYC自然活动，而实时ModelEvaluation从首个稳定MapState接管，即使Quest尚未进入Journal。
对已确认Skip的StoryMode，若当前确为`training_field_menu`且Native列出启用的`training_field_leave`，Host由真实模型选择该可见菜单动作并重新观察；
它不预设选择、不调用时钟API，其他状态则安全失败。
跳过与屏幕转场仍有连续引擎截图/录像，首帧和稳定帧都必须可区分，不能仅凭日志声称视觉已看见。

Native Tutorial-skip链会因运行时序不同而在首个稳定Campaign MapState之前或之后激活EYC。因而Bootstrap边界不是“仅当Quest尚未激活才离开训练场”：精确`training_field_menu`、训练场地点与当前启用原版Leave选项成立时，Agent都必须先通过模型选当前Native `menuSelect`；退出后以新鲜MapState同时核实已离开训练场且EYC仍active，再处理可能出现的Native开局姓名/旗帜界面和四目标。不能让Companion、Gold或Renown子流程顺带承担这一步。

原版第一块旗帜`SceneNotification`会异步显示。若Native已识别精确StoryMode卡片但`IsReady`/`canContinue`尚未成立，Host每250ms只读重查，不占一次模型决策、不发Native动作；卡片确认可继续后才交给模型选择原版Close handler。若受限重查次数耗尽或通知类型不符，则安全失败，不猜测关闭动作。

`FreshStoryModeModelEvaluation`在同一个新建Campaign进程中完成上述Natural StoryMode/官方Skip起点，然后仅用Harness生命周期路径调用既有MCM“启动自主Agent”按钮；
它不保存/回载Campaign，不通过固定动作路线推进四项目标。
目标文本限定为完整EYC主线目标；
FreeLLMAPI单请求默认300秒，Host Ready后Harness观察窗口最多86400秒，并由外层87000秒测试期限兜底。
停止或到限时都会保留失败收据，不重放已执行Native动作。
此前10分钟真实切片只有12次模型决策，且在一次OVH断连后未留下Journal进度；
现在测试上限对齐Host的24小时最长目标循环预算，以便量测多目标连续自治，而不是据短窗口推断整条任务路线。
24小时是用户MCM启动与Harness隔离验收共同使用的最长Host运行窗；
常规运行仍可由MCM停止按钮提前终止，DeepSeek费用上限与2048次决策上限继续约束自主运行。
EYC诊断Smoke最少等待240秒，避免把RGL仍在加载模块资源误判为崩溃；
显式`CHRONICLE_LLM_TIMEOUT_SECONDS`用户设置优先。
该窗口用于验证真实模型能从首个MapState经原版训练场菜单/Native动作继续进入EYC决策循环，不代表全Quest门禁已通过。
评估的`Passed`仅表示本轮预先声明的观测与收尾条件通过；
它不代表原版任务完成。
收据另以`StoryModeOriginalEstablishYourClanCompleted`表示Host确认原版Quest成功，只有该字段为`true`才可算EYC纵向门禁通过。
评估通过条件还要求Host lifecycle收据证明至少执行过一条Native动作；
只有分类或目标选择的样本保留证据但不标为通过。

教程Skip后的原版启动链不是“看到弹窗就关掉”：Host还要由模型选择当前Native通知按钮、继续棕色`FindingFirstBannerPieceSceneNotificationItem`（执行原版`OnPieceFoundAction`）、为MainHero提交通过Native校验的家族名、在BannerEditor保留当前旗帜并调用Done，再处理出现的后续StoryMode教程Inquiry，重新观察回Map后才开始EYC目标循环。棕色卡片的`PauseActiveState=true`由源码和Native运行证据确认；用户另确认它显示时地图时间/队伍移动均停止。本轮完整链Fake Provider自检通过，原版callback/Name/Banner/后续Inquiry已用Native测试验证，但这些仍不能代替真实模型逐步处理。

真实自然开局`TestResults/20261024-034735`已验证模型走过通知、第一块龙旗卡片、家族名提交、BannerEditor Done和后续教程Inquiry，最终Native state返回Campaign Map；本轮没有推进EYC Journal目标。父循环随后选择Companion目标，但子流程在Native动作前安全停止，故这项通过的是开局接管链，不是Establish Your Clan总门禁。

父级规划器遇到模型选择了本轮已标记不可用的目标时，只允许一次修正：反馈列出当前有效ObjectiveId候选集合并注明此前没有Native动作；如果模型仍不在集合内，则明确失败，不由Host替模型随便挑一个目标。该分支已通过Provider合同测试，真实远端模型仍须验证是否会按精确候选列表重新选择。

Harness参数`-FreshStoryModeModel`接受一个显式模型ID，不再固定在源码里的提供商/型号白名单；长度和控制字符在本地校验，之后由当前配置Provider目录按ID精确预检。FreeLLMAPI要求当前execution status可执行；直接远端OpenAI-compatible端点要求HTTPS及准确模型目录匹配；目录就绪不是一次真实回答成功的证明。该覆盖只改变单次Harness进程环境，不改玩家MCM/用户模型配置。真实请求固定所选模型并使用其`supported_parameters`决定JSON Schema或强制decision tool-call，缺少已支持结构化输出时在请求前失败。Provider fallback/routing须在收据中分别记录，不以模型ID替代实际响应路由。

`free-router`作为一个单独白名单选项映射到FreeLLMAPI/OpenRouter的`openrouter/free`远端免费路由；它可选择不同远端模型，但不会经过本机自定义推理端点。由于不声明`response_format`，本次Harness只在模型同时声明`tools`与`tool_choice`时走单次强制decision tool-call，响应/路由/Token均写入脱敏trace。[FreeLLMAPI Free Router](https://freellmapi.co/uk/model/free-router)

启动器只在当前进程缺少FreeLLMAPI客户端密钥时从Windows当前用户环境读取`FREELLMAPI_API_KEY`，仅传给Bannerlord子进程后恢复Harness父进程环境；不写密钥到项目、MCM文件或日志。模型调用前只读检查共享FreeLLMAPI的`/api/ping`和`/v1/models`，网关停止或模型不在当前目录时不启动游戏。MCM实际启动的Host来自本轮验证的win-x64自包含发布目录；测试仅在D盘BuildCache唯一GUID目录暂存，确认Bannerlord和Host进程退出后精确删除。

Host决策事件仅在`visual-capture`及`agent-host-lifecycle-test`模式写入临时目录的`AgentHostProgress.jsonl`，上限16MiB，不记prompt、原始回答或rationale。生命周期Host收据把统一循环的`decisions`正确映射为`decisionCount`；子目标执行结束时另记录`objective-subflow-result`，包含目标ID、状态、终止原因、失败码、动作/Token计数，以及从子流程Native结果提取的精简前后状态（游戏状态、菜单/地点/遭遇、EYC生命周期、资源数量、Quest ID和可选菜单ID/可用性）。不保存自由文本失败说明、Quest/菜单显示文本或prompt，便于区分“提交菜单动作后仍处于遭遇/地点状态”等根因。训练场setup稳定后只写一次Host autostart marker，避免每帧重复日志。此测试仅证明自然新档的Native/Host进展，不替代两个独立Campaign全Quest门禁；不得以本地模型、Fake决策或固定路线补齐真实模型缺口。
Companion子目标仅在无捕获/遭遇/模态且处于Campaign Map时允许`stop`并标记该路线暂时不可用；在Town Mission中即使模型不可达可雇佣的Wanderer，也必须使用当前Native `missionLeave`回到Map后再请求父循环重规划。若Mission内模型仍返回stop/未列控制，Host最多按当前动作目录发起两次无Native副作用的纠正请求；若模型继续不遵守，安全失败而不伪报成功。Mission目录同时列出当前可用的Wanderer navigation/interact与Native Leave，不能把没有候选或模型不愿继续当作无出口。相关Fake Native/Provider合同覆盖Mission内stop→纠正为Leave→Map后再安全stop，真实模型此前在Misson仍stop导致的整局失败由`TestResults/20261024-061135`记录；修复后的真实复测仍须验证。
父循环判定子目标是否能安全replan时也必须使用`AgentHostCampaignStateFacts.IsActiveEncounter`；仅检查Native `encounterActive`会把Town/训练场的菜单遭遇态误判成敌对Party遭遇。Town菜单的上下文`menuId`和当前`SettlementId`匹配时是原版地点菜单，允许在Map返回后标记路线不可用并重规划；真正的`encounter`菜单/遭遇、Captivity与BattleSimulation继续阻断。`AgentHostEstablishYourClanAutonomyLoop`合同自检覆盖Town menu可replan、真实劫匪遭遇不可replan。

地图原生Escape overlay可能由窗口失焦自动弹出；测试运行时只应阻止这一条自动焦点回调，不屏蔽真实玩家手动打开。`TryInstallHarnessFocusLossEscapeMenuGuard`仅在存在Harness临时目录的`visual-capture`、`agent-host-lifecycle-test`及`fresh-campaign-renown`模式修改Native `MapViewsContainer.IsOpeningEscapeMenuOnFocusChangeAllowedForAll`，普通游戏模式不打补丁。自然StoryMode长测收据必须确认guard已安装，否则该次焦点/地图移动测试无效；MOVE等Native命令仍在原版Escape overlay确实打开时拒绝。这个焦点守卫只修Harness环境的自动弹窗，不会替Agent关掉真实游戏内弹窗，也不会改变正常玩家行为。

FreshCampaign Harness在启动任何新战役前将`BannerlordConfig.txt`里的Native `AutoSaveInterval`临时设为`-1`。本机游戏程序集`SandBoxSaveManager.IsAutoSaveDisabled()`已确认`-1`是自动保存关闭哨兵。原设置写入固定小型JSON备份；测试结束并确认Bannerlord进程已退出后只恢复该项原值。若Harness突然中断，下一次`Run-Harness`尝试恢复；若游戏仍运行或当前设置不是Harness所写的`-1`，则保留并报告冲突而不覆盖用户设置。FreshCampaign收据还检查Native `AutoSaveCurrentGame`日志及Save目录manifest，避免把“没有手动Save动作”误称为“没有任何自动写盘”。

`SubModule.cs`仅允许精确审计的Harness例外在Research Gate未就绪时构建；除已有生命周期/Host控制连接外，StoryMode长测的专用分支只在Harness显式ready signal、Native MapState且没有Inquiry/ESC时调用原版SaveHandler.SaveAs，保存检查点并记录Campaign instance、时间和时钟档前后值。它不加入Agent玩家动作、不改玩家可见玩法，也不允许保存正式存档。每次修改都必须先检查完整diff、Build、Smoke和所属Harness证据，再更新`HarnessResearchReadiness.ps1`中的`AuditedHarnessDiagnosticSha256`；该例外不替代新玩家交互或Native能力的机制契约。

当前EYC子流程失败后若fresh Native Map仍被活动Inquiry阻塞（无论该子流程此前是否已执行动作），AgentHost仅将当前已验证Native `YesNoInquiry`及其真实可见、启用按钮交给模型；Host保管一次性Inquiry token，按模型选择调用原版`respondInquiry` handler，并检查新Native状态是否确已回到无Inquiry的MapState且EYC仍active后，重新读取Journal并请求一个全新的父目标计划。不可见/禁用选项、未知Inquiry VM或状态未转场时均安全失败；从不自动恢复/重放已失败的子流程动作。进度trace为定位此类中断记录当前Inquiry类别、标题/截断文案、按钮可见/启用与pause标志，不记token；`AgentHostPackage`自检覆盖此前已执行一动作后弹窗处理与新计划的集成，但Fake通过不代表真实模型开局已处理成功。

真实模型曾两次选择PartySize后，Host只报告“目标子流程失败”，没有子流程错误码。源码核对发现招募子流程的结果结构接受`failure`/`failureCode`参数却未把它们写入返回JSON，导致父循环无法保留实际终止原因；现已补齐字段，并增加Fake Native前置条件回归，验证非MapState会返回`recruitment-map-unavailable`且不调用模型、不发送Native动作。另加一条完整的Fake Native/Provider路径：从原版`training_field_menu`只选当前可见Leave，返回Town后读取招聘报价、提交一名志愿兵并等Journal达到PartySize target；该合同不代表真实战役成功，但能隔离和回归Host/Native adapter逻辑。`TestResults/20261022-234329`的AgentHostPackage合同阶段通过；真实训练场PartySize子流程仍需等可用远端模型回复，再用`objective-subflow-result`轨迹确认原先终止原因。

`TestResults/20261022-200511`首次用真实MCM启动同进程AgentHost并走到自然StoryMode的EYC活动MapState；全程无存档写入、进程清理、7帧有效引擎截图和831/831录像帧，未发生崩溃。Host版本/Campaign连接正常，随后的首个真实请求走`gpt-oss-20b`，FreeLLMAPI实际选中`ovh`并回HTTP429/Retry-After 85秒；单请求90秒Deadline不允许等待，故prompt/completion tokens=0、模型决策0、Native动作0。该失败由上游限流响应明确支持，不是训练场入口、Host连接或模型输出质量故障；FreeLLMAPI目录`execution_status=ready`只是路由可选，不代表当前供应商可服务。当前不重复轰击同一路由；下一次真实模型评测需等冷却恢复或选择一个来源已确认的远端服务路由，绝不切回本地模型。

后续一次服务商轮换得到`TestResults/20261022-220746`：FreeLLMAPI目录对`gemini-2.5-flash`仍标`ready`，但实际Google upstream返回HTTP404 `model_not_found`，无模型tokens/Native动作，表明网关目录别名与上游当前模型名不一致。NVIDIA路由在`203216/205226`曾真实回答两次，但`210449/211231/221321/222136`后续调用全返回429、Retry-After 85秒，0 tokens/0 Native动作；Poolside/OpenRouter `212742`也返回429。这里不是单一游戏入口或一次坏提示的现象：显式已配置远端供应商此时处于限流/目录陈旧状态。没有执行本地模型、没有对自动路由或本地自定义端点做试探性推理。

`-FreshStoryModeModel`远端模型白名单后续增补了`poolside-laguna-s-2.1`：FreeLLMAPI官方目录将该别名路由到Poolside/OpenRouter远端而不是本机推理；其当前接口支持工具调用但未声明`response_format`，Host应按已实现的强制无副作用tool-call协议发送单次决策。下一轮会在自然新战役里直接验证协议和目标链，不另做provider smoke；若OpenRouter上游失败则记录真实响应，不转本地模型。

`free-router`也作为明确的OpenRouter远端免费池路由加入白名单；`TestResults/20261022-232153`在真实新战役Host中调用后仍收HTTP429/Retry-After 85秒，prompt/completion tokens=0、决定0、动作0。因此OpenRouter目前也没有可用的实测服务；本测试不把路由目录ready当作供应商恢复。

Fresh EYC 的真实 Host 切片`TestResults/20261022-164200`显示原版Tutorial skip后首个Campaign MapState的地点菜单是`training_field_menu`，原生状态同时有`encounterActive=true`和`encounteredPartyId=tutorial_training_field`，且`currentSettlementId`相同、存在可用`training_field_leave`。
真实模型两次选择成功：先将完整目标分类为`supported-establish-your-clan`，再选择未完成的同伴目标；
随后的Native同伴子流程误把训练场地点菜单当成劫匪/敌军遭遇并在第一个动作前中止（`companion-campaign-interruption`），Native动作0，源新档无存档写入。
后续真实运行`TestResults/20261022-173044`选声望时同样呈现需处理的训练场菜单；
第三次输出了尝试`menuSelect`但`MenuId`字段写成字面值`MenuId`的错误参数。
源码发现BattleSimulation位置菜单分支仅给出参数名、未给当前Native可选ID枚举。
现已增加共享`AgentHostCampaignStateFacts`把Native地点菜单同真实Party/Encounter分开，并在Companion/Recruitment/GoldSale/BattleSimulation子流程把可见原版Leave选项作为受限`menuSelect`；
BattleSimulation的参数schema同时枚举当前精确`MenuId`和enabled Leave OptionId，真实敌方遭遇仍fail-closed。
该修正已进入Package自检前的源码，窄包验证仍待本轮；
三次实机均只产出真实模型规划/动作提案，未执行Native目标动作、无EYC进度、无存档或游戏崩溃；
第一份诊断视频/截图留存，MP4均已按Harness索引删除。

同一变量还必须传到实机Host进程：`Test-AgentLiveModelLoop.ps1`仅在没有显式Provider timeout时使用各场景默认值；外层EYC Harness默认设置300秒，显式`CHRONICLE_LLM_TIMEOUT_SECONDS`仍由用户决定且范围为5–360秒。该有限请求期限根据实测延迟容纳约50–100秒上游响应及一次明确Retry-After退避；Harness的600秒Host观察窗口与300秒单请求期限分开，且测试总超时为900秒，最终由较短的剩余Host窗口取消，不会无限等待。它不改变用户正常Campaign启动后的持续运行模式。EYC阶段不重复发provider smoke，因此有效模型预算留给真实Campaign真实决策。

AgentHost对“模型响应已返回但未通过动作/控制目录校验”的可恢复决策错误可最多请求两次修正；反馈只包含错误类别和当前Native动作/控制目录，不包含原始模型回复，也不发送Native动作。传输错误、上游429/502、超时不走这条模型决策修正路径；已经执行的Native副作用不因重试重新执行。所有此类分支必须有Fake Provider回归，并在真实模型中按现有Harness收据区分是否生效。

下文标注为“历史”的NPC Actor产品路线已降为未来研究；MainHero GoldSale等历史切片若未有通过收据仍视为失败/未完成证据，只在当前W7缺口审计确认相关时才重跑。

失败测试的录像也要经过证据收尾：按事件抽取关键帧；联系表按源视频实际帧号等距选样，最多64帧，并由真实样本数决定行列、强制偶数宽高与JPEG全范围像素。不能依赖固定低帧率抽样（很短的录像可能被舍弃为零帧），也不能把固定4列写死（会造成空白格或编码错误）。联系表和事件关键帧索引可读后删除原MP4；解码或证据生成失败时保留原片供诊断。修复后的`HarnessShortClipProbe`在实机窗口22帧短录中生成联系表和6个事件帧，并清除了成功原片；具体运行收据记录在`TestResults/20261029-live-storymode`。这样保留的是能解释测试结果的证据，不是整段重复播放的大文件。

W7-K恢复测试专用的`ChronicleW7K-`派生存档时，只允许在Bannerlord和CLI会话都已结束后，通过`Test-AgentHostCampaignLoopEvaluation.ps1 -CleanupPreparedSaveName`按精确Game Saves路径清理。该恢复入口不能接受正式存档名；普通产品失败不得跳过本规则。

Host真实模型的每个有效回复在执行前增量写入Harness `AgentHostProgress.jsonl`；仅在`visual-capture`或`agent-host-lifecycle-test`模式、当前Harness临时目录内启用，限制16MiB，只保存所选动作/参数、模型路由、token与玩家可见状态摘要，不保存prompt、回复正文或rationale。这样即使长测进程被外部打断，也能分辨模型具体选择、Native动作执行前的状态和已知成本。

Village Quest的终止`done`在MapState且Quest已关闭、库存净变化已逐项核实、没有活跃对话时可用，包括玩家仍停在任务人聚落菜单的情况；打开对话或任一后置条件缺失仍不能结束。退出Trade/Inventory后玩家可能自然留在该聚落菜单，无需多执行一次“离开聚落”作为任务完成前置。

Agent Host为每次模型决策按Native当前`allowedActions`/`allowedControls`生成JSON Schema互斥分支；
对话、菜单、地图移动等动作还把策略允许的当前ID编码成参数枚举，避免从可见但不允许的选项中重复选择。
VillageNeedsTools流程读取当前Quest Journal；
每次Native Trade提交后都重新读取Journal再规划，避免用旧进度判断是否还缺货。
欠工具时地图移动只列安全Town，已满足时只列接取任务时从Native当前位置观察到的Quest-giver Village；
来源未观测到就不猜。
无货Town会从后续采购目标中排除。
所有移动仍是普通原版Native `move`，不夹带时钟控制。
无动作目录时Host不调用模型，理由文本在schema中限制为64字符；
村庄Quest目标另要求理由最多8个短词。
FreeLLMAPI使用OpenAI兼容`response_format.json_schema`；
无游戏真实Provider冒烟测试镜像Campaign Host的第一步：把完整用户目标送入生产用`goalScopeClassificationRequired`提示，并要求返回唯一支持的`supportedVillageToolsQuestGoal`控制值；
记录实际`X-Routed-Via`与token，不执行Native命令。
原生Ollama协议仍只留在隔离协议回归，不作为本项目真实模型推理路径。
FreeLLMAPI Mistral Small 3.2→OVH当前使用JSON对象模式与`max_tokens`，并省略该上游不接受的OpenAI专属`store`及空`reasoning_effort`字段；输出仍由本地Host按Native动作目录逐项验证。若自动FreeLLMAPI路由以HTTP 400/422/502返回、且`X-Fallback-Trail`明确标记`provider_bad_request`拒绝JSON Schema，并表明回退轨迹中含OVH Mistral Small，则一次JSON对象模式兼容重试同时改用`max_tokens`，等待OVH节奏并严格后验验证。FreeLLMAPI以502和`keyN=format_ignored`标记结构化输出被上游模型忽略/截断时，也允许对同一尚未执行的决策重试一次JSON对象模式；其余HTTP失败不走此兼容重试。所有输出仍由本地Host按Native动作目录严格解析和验证，失败不会发送Native命令。Provider回归覆盖格式回退与非格式错误拒绝。
OVH匿名Mistral路由的免费请求上限为每模型每分钟2次；真实游戏闭环在31秒节奏下仍观察到第三个请求被网关按`rpm/rpd-limit`拒绝，因此Host对该Mistral路由，以及最近一次响应明确由`ovh/`处理的FreeLLMAPI模型，保守地按请求开始时间至少间隔45秒。其它路由和本地端点不额外等待；等待可被当前取消令牌中断。Provider回归分别覆盖模型直连、自动路由命中OVH、非OVH及非FreeLLMAPI端点。
Harness真实模型预检用本机`/api/ping`探测FreeLLMAPI桌面网关；服务停止时只从默认安装路径隐藏启动桌面进程一次，最多等待30秒确认监听，然后才读取可用模型目录。启动子进程前把已保存的用户代理环境变量临时传给FreeLLMAPI；若用户没有配置任何出站代理且本机`127.0.0.1:7890`确实在监听，就只给这个FreeLLMAPI子进程注入`HTTPS_PROXY`，随后立即恢复Harness自身环境。这样既遵守用户指定的星辰代理，也避免代理变量影响Git/其它应用。该动作不进行UI自动化、不触碰账号窗口，也不会把API key写入磁盘；启动后的FreeLLMAPI应用保持运行供下一轮测试复用。已有服务若仍在运行，不会强行覆盖/重启它的代理配置。
若FreeLLMAPI以HTTP 502并在回退轨迹中报告`keyN=error`或`keyN=upstream_error`，表示该模型决策未得到可用回复，Host可在Native动作执行之前对同一个请求延迟5秒并重试一次；如果仍失败则关闭本轮，不重放任何游戏操作。无游戏Provider回归覆盖一次重试后成功，模型决策总重试次数仍有界。
Agent Host为每次模型决策按Native当前`allowedActions`/`allowedControls`生成JSON Schema互斥分支；
对话、菜单、地图移动等动作还把策略允许的当前ID编码成参数枚举，避免从可见但不允许的选项中重复选择。
每个活动Quest只读一次任务日志；
城镇工具采购前先尝试当前市场，无货城镇会从本轮后续目标中排除，交易结束后才允许离开，避免在同一城镇循环。
无动作目录时Host不调用模型，理由文本在schema中限制为64字符；
村庄Quest目标另要求理由最多8个短词。
FreeLLMAPI优先使用OpenAI兼容`response_format.json_schema`；
若FreeLLMAPI明确回报某上游以`provider_bad_request`拒绝该格式，只对该次决策重试一次`json_object`，再由本地Host逐字段验证动作ID、参数名、当前可见ID和完成条件，验证失败不会执行Native动作。
每条模型收据记录实际`X-Routed-Via`、token数及格式模式；
无游戏的真实Provider冒烟测试还要求模型返回唯一合成Native动作及精确目标参数。
FreeLLMAPI错误收据只保存`X-Routed-Via`、`X-Fallback-Attempts`、`X-Fallback-Trail`等路由头和安全错误码，不保存响应正文/可能含凭据的错误内容。
原生Ollama协议仍只留在隔离协议回归，不作为本项目真实模型推理路径。

Prompt中写到的动作名必须是当前Native协议目录中的确切ID；玩家熟悉的界面/过程术语只能解释动作效果，不能替代可调用ID。W7-K回归锁定 `talkToSettlementHero` 而不是玩家界面描述词，避免模型从提示词学到不存在的动作名。

动作名称和参数仍必须严格匹配当前Native目录；动作的`rationale`只用于可读审计，不影响安全判定，因此允许模型省略并留空记录，若提供仍限制长度。控制/停止决策的`reason`继续必需，因为它解释完成声明或等待意图。该区别避免因非执行字段缺失而丢弃本来有效的原生动作。

当Native对话无可点击选项而出现唯一`dialogueContinue`时，Host拒绝无效模型动作的反馈必须对应玩家看到的金色“点击继续”：它推进当前对话文字，不离开聚落。此反馈必须包含准确的当前动作与空参数要求，并由真实Native对话状态回归覆盖；不能把“退出聚落”意图映射成Continue。

村庄工具任务在动作被Native目录拒绝时，Host将内部生成的`requiredNextStep`作为本次重试的额外System约束，并仍在观察请求中提供结构化反馈；只注入Host自有的恢复指令，不回显模型原始答复。这样要求模型根据当前唯一动作/当前OptionId重新决策，不以脚本代替模型选择；确定性测试检查该指令及Native结果，真实模型仍需复验。

Native拒绝模型选择的动作参数时，恢复规则要区分“动作本身无效”和“动作有效但参数错误”：默认禁止重复无效动作；只有Host能从本轮Native目录指出同一动作仍可用、且问题仅在参数时，才给System恢复指令允许重试该动作，并枚举当前有效参数。当前已按真实模型把Village当作工具购买目标的失败案例，允许`move`只重试到最近观察的安全Town ID；仍由Native策略校验并在执行前拒绝其它Settlement，确定性包回归验证此分支，真实模型复验待进行。

W7-K的真实模型长程验证为独立opt-in `AgentHostVillageToolsQuestEvaluation`，不并入`All`：真实模型固定通过本机FreeLLMAPI入口(`http://127.0.0.1:31415/v1`)调用其当前可用免费服务商；
FreeLLMAPI官方CLI用于生成/维护其它客户端配置和管理Provider密钥，Agent每轮实际推理由官方支持的OpenAI兼容HTTP API完成，不启动子CLI进程。
默认路由`auto`，每次`X-Routed-Via`实际服务商/模型、token数写入收据。
请求密钥只从`FREELLMAPI_API_KEY`或`CHRONICLE_LLM_API_KEY`进程环境读取，不写进MCM JSON、命令行或日志；
LiveModel Harness只读请求`/v1/models?available=true`作预检，并在不匹配该FreeLLMAPI端点时于启动游戏前拒绝，绝不调用本地Ollama。
FreeLLMAPI的出站代理由其本机配置管理；
当前界面显示已启用Google AI Studio、Kilo Gateway、OVH AI Endpoints和AI Horde，但可用性仍以每次请求实际路由/回包为证据。
其余验收仍是：从disposable `AgentBridgeLifecycle`起点用当前Native可见的安全聚落，最多进行有界、普通原版移动；
若到达安全Town，可通过Native招募界面预招募最多5名护卫（留至少500 Denar），这些仅是被单独记录且不计Agent成绩的安全Prelude，不注入资源/Quest/进度。
随后才进入当前Village、只有右上人物列表自然出现蓝色工具委托时，才经原版SaveAs制作独立临时的“村庄菜单+蓝色marker”起点；
第一轮模型从该玩家可感知入口启动，不获得隐藏Quest ID或预设动作序列。
模型经Agent Host Campaign loop完成委托，核对Native交易购买与提交、对话交付、Quest结束及交付前后Inventory按Journal文本精确差值；
留存原生状态/决策轨迹和游戏窗口连续帧，seed存档hash不变，并删除派生存档、Host/CLI/Game进程。
路线中只对已观察到的Native Bandit `encounter_meeting`开放一条安全通行恢复：只允许当前可点击的非战斗Option，先读当前Safe Passage BarterVM，再用原版Auto Balance预览报价；
Auto Balance后必须重新读取原生VM，且当前报价的sessionId和proposalFingerprint必须与模型看过的报价相同。
提交时Host把这两个预期值传入Native，原版handler在执行Offer前再次比对当前BarterVM会话及提案指纹；
会话切换、提案变更、玩家物品、余额不足均不提交。
只有报价仍含原生让路条款、除Denar外没有任何可转让物、金额可支付且留有正余额时才开放Offer，否则安全停止或取消；
不攻击、不重复收费、不显式控制时钟。
若报价探测被拒，只在当前对话仍无可点击选项且尚未进入BarterVM时允许一次原版Continue后重新观察；
其它/无法辨认的遭遇、有限预处理村庄内没有自然可见工具委托、奖励文本无法解析或物品差值不一致仍失败关闭，不遍历全图制造任务，也不把确定性`VillageToolsDelivery`证据算成真实模型通过。
该阶段在常规Smoke窗口基础上至少给予240秒启动预算，以覆盖冷启动时的原版场景资源加载。

W7-N的StoryMode目标选择器为独立opt-in `AgentHostEstablishClanGoalPlannerEvaluation`，不并入`All`。
Native观察明确区分非StoryMode、StoryMode主线尚未激活、活动、历史完成、历史失败；
StoryMode通过官方`JournalLogEntry`判定结束结果，历史记录缺失时返回unknown。
只有当前观察确有活动原版Quest `rebuild_player_clan_storymode_quest`时才开放范围分类；
通过独立只读`IAgentHostQuestDetailsNativeClient`读取同一任务的Journal数值。
原版`RebuildPlayerClanQuest.UpdateProgresses()`用四个缓存JournalLog.CurrentProgress判定Quest成功，且当前Journal值正是玩家任务界面所见；
因此Planner从四个Journal stage的current/target构造唯一权威的任务进度快照。
实时Gold/Party/Renown/Companion与Journal不同步时只附带诊断差异，不覆盖当前任务进度、不单独阻塞模型、不据此宣称任务完成。
藏身处人数以Quest Journal记录的原版target为准，不用模型实时重算值替代当前日志目标。
模型只可在当前Journal未完成的四项目标中选一项，Host不把这个内部选择转换成游戏动作，也不将计划结果称为Quest完成。
该阶段必须用FreeLLMAPI真实路由、已自然激活该Quest的disposable StoryMode存档；
只读planner验证前后Campaign时间、Gold、队伍、Renown、Quest和源存档不变；
W7-O的恢复后重规划允许记录由原版捕获/释放事件造成的Journal/实时Roster差异。
派生档/游戏/Host/CLI清理，且保留屏幕连续帧证据。
旧StoryMode起点可能缺少ChronicleFramework模块时，Harness可仅在游戏启动模块列表中追加该插件，存档本身仍保持逐字节副本；
如RGL错误日志报告未处理启动异常，Agent CLI会保存该进程/模块集/异常的收据，停止准确的测试进程树并恢复EngineConfig，不等待普通加载超时。
Historical completed/failed分支已由源码核实，但尚未由真实完成/失败StoryMode存档作运行验收。

W7-O现从Agent已接管的活动StoryMode存档进入已有Native `prisoner_wait`（不是新发起Battle）的狭窄恢复测试。
只在Native status仍captured、Wait菜单无选项且raw时间为Stop时列出独立的原版`resume`动作，必须以当前`isWaitMenu/isWaitActive`再核资格；
时间已自然流动时由Host只读轮询，不让模型重复设置时钟。
赎金只使用当前Native菜单中enabled的原版接受/拒绝选择，并以当轮金额和Gold作为模型输入。
已对照本机`PlayerCaptivityCampaignBehavior.AddGameMenus`完整枚举原版Captivity继续/赎金页；
只有Native确认当前页面及当前enabled选项时才会提交`menuSelect`，该集合与各回调在Research/F及MAINLINE契约中逐项记录。
Native原版菜单回调本身可能退出等待、恢复`LastTimeControlMode`、释放Hero或返回Captivity wait；
Host把回执后的时钟/脱俘状态作为原版副作用重新观察，不视作自身clock action。
获释后先按原版JournalLog当前/目标规划一项未完成目标，再做一次只读Native后验确认；
返回结果分别保存Journal与live metric差异，不能把选择目标说成任务进度已更新。
此动作不包含新Battle、即时战斗、状态写入或目标达成声明。

历史 MainHero 原型W7-P `AgentHostEstablishClanGoldSaleEvaluation`是单笔Gold目标销售的独立opt-in真实模型切片，不并入`All`，不等于完成Gold 2000或整个StoryMode任务。
默认自然StoryMode来源为现有`save002`（可用`StoryModePlannerSourceSaveName`指定别的保存档）；
若它从Captivity开始，GoldSale Host在同一决策运行中复用已验证的W7-O Captivity流程先回到自由Map，再继续安全Town移动与Native Trade。
只开放本轮Native Trade可见、可转让、价格为正的PlayerInventory Goods报价，一件、一个单位、原版SPItemVM Draft及Done；
来源/库存/金币不得注入。
若Native刚接受普通移动后暂时显示目标已设置但`isMoving=false`，Host只允许一次1秒只读观察来跨过原版状态转换；
测试证明后续Native状态才变为`isMoving=true`，但移动开始后的完整真实Gold sale没有通过。
此独立phase仅保留作历史/可能复用的Native交易试验，不再是当前产品路径；
不得将其视作AI Actor能力或StoryMode产品验收。

W7-K完整阶段不再先额外运行一次真实模型冒烟：同一免费路由上的前置调用会重复战役首轮目标分类并消耗可用额度。阶段仍先做只读FreeLLMAPI目录/执行状态预检、构建、游戏Smoke和不调用模型的AgentHost包/Provider合同回归；随后在实际Campaign loop中执行唯一首轮真实目标分类，只有模型明确支持VillageNeedsTools目标后才会发出Native动作。若网关状态预检通过但实时请求随后限流/失败，Harness安全停止且不执行Native动作；结果仍算Provider/完整纵切片失败，而非任务成功。`AgentHostProvider`真实模型冒烟保留为单独opt-in诊断阶段，不在同一Quest评测前重复调用。实际运行的模型回复、路由、token、Native后验、连续录像和清理证据由Quest收据统一记录。

W7-L `AgentHostBattleSimulationEvaluation`是独立opt-in真实模型闭环，使用Campaign地图当前原生可见的Bandit目标，不注入敌方Party、MapEvent、胜负或战利品；
没有可用Bandit时Harness保留安全停止证据，不伪造场景。
Host只允许当前目标的普通Native pursue、当前原版可点对话分支（主动接触时`bandit_start_defender_1`；
劫匪主动拦截时`common_encounter_ultimatum`，若原版给出投降接受/拒绝则只开放`common_bandit_surrender_declined`）、当前Encounter的`str_order_attack`，随后Native `battleSkip`/`battleFinish`与可见Party/Inventory战后收尾；
“算了，你走吧”(`common_encounter_fight`)、过路费和接受投降均不属于战斗路线。
模型通过当前配置的OpenAI兼容Provider运行；
FreeLLMAPI只在其被配置为Provider时使用。
验收必须以真实模型/Provider路由、Native战斗及所有打开的Loot界面关闭、回Map、前后Renown/队伍/Gold/Influence的真实值（Renown可不变）、0个显式时钟动作、源存档hash不变、完整画面和进程/session清理为证据。
该切片只验证一次Native坐镇战斗，不等于获得50 Renown或完成StoryMode四目标；
实时Mission战斗与其它遭遇矩阵仍未覆盖。

W7-M `AgentHostBattleAndCaptivityEvaluation`是W7-L之后的独立opt-in真实模型纵切片，不扩大W7-L的验收范围。
它仍从一个真实Native可见Bandit地图遭遇开始；
如果Send Troops最终使MainHero进入`prisoner_wait`，Host不将被俘等待判作`done`，而是在游戏原生Captivity状态下被动重观察，不调用时钟动作；
出现当前Native Wilderness赎金Offer时，仅将当前启用的Accept/Reject `menuSelect`交给FreeLLMAPI模型，并按当轮可见金额、金币及Campaign目标决策。
赎金被拒或尚无选项时继续自然等待；
结束只有在Native验证主角已不再被囚禁、回到无俘虏菜单的MapState且MainParty有成员时成立。
暂不支持Settlement监禁、其它Captivity菜单、Escape Mission或俘虏Hero。
该试验必须使用真实FreeLLMAPI、从实战Native结果而非捕获状态注入开始；
用户已确认赎金提示显示金额与接受/拒绝选项。
若无真实Captor/报价/释放结果，此卡应诚实失败或超时，不以Harness Test-CaptivityOutcome单独代替产品验收。

`TestResults/20261016-070120`实测：移除重复模型冒烟后，真实Campaign首轮goal classifier仍于Native动作前失败，0个决策/0个游戏动作；FreeLLMAPI原始本机日志显示OVH `gpt-oss-20b`上游返回HTTP 422，随后路由冷却，Host收到429。测试画面已到达卡利奥克村庄菜单且蓝色工具委托标记可见；来源存档未变，派生存档/游戏进程与CLI session清理通过。原schema使用根`oneOf`及可选约束，与OVH文档的JSON Schema子集不一致；已改成对象根、必需`decision`包装和嵌套`anyOf`，由Host解包后仍按Native目录完整校验。

后续`TestResults/20261016-071436`表明上述形状修正仍不足：FreeLLMAPI日志再次记录OVH上游422，之后请求因冷却返回socket hang up/长Retry-After，仍为0决策/0动作，测试存档与进程清理通过。
进一步对照OpenAI-compatible Chat Completions约定，发现`json_schema`载荷还缺少`name`与`strict`字段；
已补为稳定schema名及`strict: true`，并在无模型自包含回归中核验。
`TestResults/20261016-072156`的AgentHostPackage通过；
此项修正能否解决上游422、恢复后真实Campaign能否继续，仍须新的实际FreeLLMAPI请求证明。
不得将本地合同测试写成真实模型通过。
[OVHcloud Structured Output](https://docs.ovhcloud.com/en/guides/public-cloud/ai-machine-learning/ai-endpoints-structured-output) · [OVHcloud gpt-oss-20b API](https://www.ovhcloud.com/en/public-cloud/ai-endpoints/catalog/gpt-oss-20b/) · [OpenAI Structured Outputs supported schemas](https://developers.openai.com/api/docs/guides/structured-outputs)

`TestResults/20261016-111724`将该请求送入FreeLLMAPI `auto`路由后，实际选择OVH `Qwen3.5-397B-A17B`；请求返回但恰好用满512 completion tokens，Host以`provider-response-truncated`拒绝，0 Native动作、源档未变、进程/session清理通过。故Live Quest切片的单次输出上限从512提高到1024，Host无显式配置时的OpenAI-compatible默认上限同步提高；这只是允许结构化决策完整返回的上限，不代表每次都会消耗1024 token。`Check-Docs`现锁定Quest评测和Host默认上限一致；下一轮实际模型仍须证明截断消失并执行Native动作。

`TestResults/20261016-113813`的真实`auto`模型运行推进6次决策/5条Native动作，停在卡利奥克任务说明后唯一可点的`issue_alternative_solution_player_response`，玩家任务列表为空、蓝色任务标记仍在。
1.4.8源码表明这不是Alternative接受动作：它只把对话继续到替代方案说明；
说明后才出现最终选择。
无模型原版运行`TestResults/20261016-124045`通过这一节点：测试只选说明入口，未接受任务或派出部队；
最终对话有可点的`issue_offer_player_accept_quest`（“我觉得能亲自处理这件事”），派遣选项因没有同伴而灰显。
该原生状态中任务计数仍为0、CampaignDay未变、关系1、不交战；
8个同类型Issue都处于`OngoingWithoutQuest`，没有同类正由Quest/Alternative解决。
结论是这里不是已接任务，也不是上述玩家条件挡住直接接取；
真正错误是我们把说明页入口误判成最终替代结果，因而Host提前停止。
现已允许这一步说明导航，但只保留最终标准Quest接受，过滤最终Alternative/Lord接受。
`TestResults/20261016-123502`AgentHostPackage回归通过：允许Native说明入口、在最终分支只开放Quest/拒绝选项，并在只剩不支持的最终结果时安全停止。
下一步用真实模型重验并尝试完成完整委托。

更新后真实Campaign复验`TestResults/20261016-124328`使用FreeLLMAPI显式`nvidiallama-3.2-11b-vision`：首轮分类成功，随后模型执行原版`talkToSettlementHero`；第三个模型请求返回HTTP 502（实际路由`custom/nvidia/llama-3.2-11b-vision`，fallback 1次），在读取对话选项前安全终止。累计2决策、1条Native动作、3,611输入/54输出token；Quest仍0、CampaignDay未变化、源fixture未变，5fps画面完整，游戏/Host/CLI/派生存档清理通过。该结果证明模型开始走Native入口，但没有验证说明页→标准接取选项的真实模型行为；502是网关/上游失败信号，不能归咎代码或模型决策。此后`auto`真实模型复验见`TestResults/20261016-140206`。

`TestResults/20261016-140206`（commit `76a30ea`，FreeLLMAPI `auto`）真实模型成功接取`issue_64_quest`并读Journal。它自然抵达萨哥特并打开原版Trade：当前`tradeOptions`目标工具报价为0、Gold 920、尚无交易提交。随后模型在Native目录仅含`tradeCancel`时再次请求`tradeOptions`；Host在发出Native命令前正确拒绝，但当次恢复提示只泛称应选目录中的动作。之后下一次FreeLLMAPI请求收到无Retry-After的HTTP429，模型未能执行取消并寻找另一市场。19次决策、14个Native动作、16次成功回复，累计55,408输入/887输出token；CampaignDay 91077.635→91077.879，Quest仍活动、源档不变，游戏与临时存档清理。contact/timeline完整并已删MP4，共享events.jsonl约0.4MB。

针对两个现场错误分支，Host现在仅当上一个成功Native`tradeOptions`后Journal仍显示有未交付工具、且当前Native目录严格只含`tradeCancel`时，无论模型错误返回额外动作还是`observeAgain`控制，都反馈“取消未修改的Trade，不要等待或重查，随后用新Native观察再决定”；Host不替模型执行。`TestResults/20261016-191531`覆盖错误动作提示；`TestResults/20261016-205258`自包含Host Provider合同自检扩展覆盖错误控制、未完/已完任务分支及Native零副作用。最新控制反馈尚未由真实模型再次重跑。

`TestResults/20261016-163619`是无游戏Provider冒烟：FreeLLMAPI固定路由`qwen2.5-vl-72b`返回Production目标分类，实际由`ovh/Qwen2.5-VL-72B-Instruct`处理，JSON Schema模式416输入/28输出token、0 Native命令。这只证实一次短分类调用成功，不代表长程Quest稳定；下一次真实任务切片固定此直接路由，减少`auto`在多供应商之间切换带来的变量。

`TestResults/20261016-192233`重跑W7-K真实FreeLLMAPI场景时，Harness正常完成Preflight/Build/Smoke/AgentHostPackage，生成自然可见的工具Quest夹具；模型成功分类后调用`talkToSettlementHero`，Native打开对话，当前可见的是NPC首次见面提问与三项自我介绍回复，尚未显示Quest接取选项。随后实际路由`custom/nvidia/llama-3.2-11b-vision`返回HTTP 502，只有2次成功模型回复/1条Native动作、3,615输入/54输出token，CampaignDay保持91077.635，Quest仍未接受；完整联系表和时间线已生成，MP4自动删除，源档/派生档/进程/session清理通过。该运行没有走到无货市场恢复，不能判定新提示效果；失败发生于Provider调用，不是对话动作的Native拒绝。

之后FreeLLMAPI的只读目录显示`auto`可路由，故将`CHRONICLE_LLM_MODEL=auto`仅覆写于单次Harness进程重跑（不改用户设置）。`TestResults/20261016-194222`仍由FreeLLMAPI返回HTTP429：两个模型回复均成功（Mistral Small分类、NVIDIA Llama执行`talkToSettlementHero`），第三个请求未返回；2决策/1 Native动作/3,601输入/67输出token，尚未收到首次问候的模型回复。Preflight、Build、Smoke、AgentHostPackage及所有临时存档/进程/session清理通过，MP4后处理删除；属于动态路由Provider限流，不是产品动作失败。

为隔离动态路由，本轮另以FreeLLMAPI目录标为`ready`且在前轮`auto`中已成功响应的`mistral-small-3.2-24b`做一次完整真实Campaign（只改当前进程）。
`TestResults/20261016-195123`达30分钟Harness上限：25次模型回复/26个决策/20个Native动作，91,787输入/679输出token；
接受Quest并读Journal，在萨哥特无工具报价后选择原生`tradeCancel`，查询地图并自然移动至town_V6（CampaignDay 91077.635→91078.588），然后该市场同样无工具。
第二次`tradeOptions`后受总时限取消，未采购、未交付；
完整收据显示`TaskCanceledException`与1,802.6秒运行，不是HTTP错误或游戏崩溃。
MP4有完整联系表/时间线后删除，源fixture/派生档/进程/session清理通过。
此次暴露两项需继续处理：无货时模型可错误要求`observeAgain`而当前只允许`tradeCancel`；
单场景模型交互成本/时长也使两市场搜索耗尽30分钟门限。

该30分钟运行的本机免费路由调用均成功，并未发生HTTP错误；墙钟主要消耗在25次模型往返（输入累计91,787 token），因此瓶颈是单场景决策/推理时长，而非模型预算扣费或Native动作失败。产品能力仍未证明能在本次有界纵切片内买到并交付。

当`AgentHostCampaignLoop`分类为VillageTools目标并交接给专用Quest loop时，子循环的终态收据必须合并父循环的classifier trace、provider route、token与全局decision编号；不能只显示子循环，遗漏真正的首个模型调用。Provider包回归用合成父收据验证跨循环历史保持，外部模型/Native调用均为0。

W7-K只覆盖标准`VillageNeedsToolsIssueQuest`交付路径。1.4.8 Native先让玩家进入一段说明“让同伴/手下运送”的Alternative Solution对话入口，再在下一屏展示任务接受结果；`issue_alternative_solution_player_response`本身不接受、也不派出任何人。Agent可走这段说明以抵达原版最终选择，但只允许标准`issue_offer_player_accept_quest`，禁止`issue_offer_player_accept_alternative`和`issue_offer_player_accept_lord`。若最终页没有可点的标准Quest选项，应停止并保留证据，不选择别的结果。

`/v1/models?available=true`只说明模型配置/密钥存在，不代表当前可调用。LiveModel预检同时读取`execution_status`：只放行`ready`的显式模型，或者`auto`/`auto:<name>`/`fusion`这类路由入口；显式模型状态为`exhausted`、`needsKey`、未知或缺失时，在游戏启动/Provider推理前快速失败。该状态只是预检瞬间的快照，无法排除之后发生的并发限流；仍以实际模型回包为准。回归覆盖上述各状态与命名路由例外。

Agent Host包测试在restore前以500毫秒上限TCP连接探测本机7890代理，并通过临时回环listener正/负自检；不使用`Test-NetConnection`长等待交互输出。代理不可达仍快速失败，不绕过用户配置的代理。

FreeLLMAPI Provider的单次请求时限覆盖接收响应头、完整响应正文以及模型请求中的限流/上游退避等待；
`ResponseHeadersRead`不能使正文或退避等待脱离该总时限。
每次上游响应都重新分类：HTTP 429优先尊重明确有效的`Retry-After`，最多重试两次；
若该头缺失，仅对FreeLLMAPI loopback返回的JSON错误中严格匹配`All models exhausted`及`Soonest reset ~Ns/~Nm/~Nh`时采用正文ETA，最多重试一次。
只读取最多16KiB、只提取白名单时间字段、不记录错误正文；
模糊/缺失/超360秒提示不重试。
无论头还是正文提示，若等待无法放进本次剩余Provider deadline则立即返回可诊断的429，不空等至超时；
明确临时502仍最多重试两次，429与502使用独立计数。
429的单次等待上限为360秒，来源是本机真实回包315秒。
FreeLLMAPI匿名OVH Mistral每分钟最多两次请求，Host对已命中OVH的请求仍按45秒节奏；
等待不重放已执行Native动作。
退避用同一请求Deadline取消。
429错误只记录安全的重试资格、提示来源、是否为网关池耗尽、deadline可容纳性、实际重试次数与累计等待毫秒，不写响应正文或凭据。
无游戏Provider冒烟缺省超时现为360秒；
OpenAI-compatible/FreeLLMAPI路径默认360秒且上限360秒，本地Ollama协议仍默认60秒、上限240秒。
无效配置回退360秒，显式值限制在5–360秒，避免PowerShell `TryParse`失败时把默认值写成0。
只读模型目录探测仅证明网关可达且模型/路由当前可用，不证明上游推理成功。
实际请求失败先核查FreeLLMAPI路由、密钥健康/免费额度和上游响应，再归因模型或游戏；
相关无模型回归覆盖响应体和退避均受同一Deadline约束。

`CHRONICLE_LLM_TIMEOUT_SECONDS`只控制模型请求及其429等待；Campaign/Supply Host的Native邮箱往返另读`CHRONICLE_NATIVE_MAILBOX_TIMEOUT_SECONDS`（默认180秒、上限240秒），不随模型重试时间延长。这样尊重315秒外部冷却时，仍不会让无响应的游戏命令获得同样长的等待上限。

FreeLLMAPI OVH路由的45秒节流等待必须使用单次Provider请求的取消令牌，不能只受整个Campaign循环令牌约束；否则请求deadline届满后仍可能多等一个完整路由间隔。`AgentHostPackage`回归通过先建立真实OVH路由回执，再以100ms模型请求deadline重试；应在deadline内返回`provider-timeout`且不得发送第二个Provider请求或Native命令。此时限只约束模型/路由等待，不改变Campaign时间。

若最终HTTP错误缺少`X-Routed-Via`，Provider诊断可以附带`lastSuccessfulRoute`，但不得把它写成该失败请求的实际路由；只有当前响应带有`X-Routed-Via`时才能记录`routedVia`。回归覆盖此区分，避免把前一轮成功路径误当成本轮失败根因。

升级/卸载的配置所有权：MCM `AttributeGlobalSettings`拥有`Documents/Mount and Blade II Bannerlord/Configs/ModSettings/Global/ChronicleFramework/ChronicleAgentSettings.json`，Host继续读取原有JSON字段`OllamaBaseUrl`与`ModelId`以兼容既有设置文件；
新默认值指向FreeLLMAPI本机网关并使用`auto`。
FreeLLMAPI统一密钥只通过启动前设置的用户环境变量继承，不写MCM配置。
未知旧字段忽略，缺失或损坏配置报错但不重写/删除。
当前无显式Chronicle配置迁移schema；
新增/删除MCM持久字段前，先用真实旧版配置fixture定义迁移/回滚，然后才引入schemaVersion。
发行包不携带用户配置；
卸载只移除模块拥有的文件，不碰Global MCM目录、FreeLLMAPI数据/密钥或Campaign档。
Host跟随Bannerlord父PID/启动时刻和模块路径，正常停止/模块卸载有界等待，异常退出仅可终止由本Mod创建且PID/启动时刻/可执行路径都匹配的Host；
父游戏进程停止时Host自行退出。

Host控制输入读取放在后台任务：`Console.In`同步Reader的异步接口可能阻塞调用线程。游戏保持stdin打开时，主流程仍必须能收到决策循环终态或父进程退出。自包含包回归以有效父进程身份、故意无效动作目录验证“stdin保持打开，拒绝结果仍按时返回”，不调用模型或Native；旧同步调用方式在该回归超时，修复版通过。

MCM `AttributeGlobalSettings` 是用户配置的唯一写入所有者，发行包和Host都不复制或覆盖其 Global JSON。Host目前只读取`OllamaBaseUrl`/`ModelId`，忽略未知键以保持旧MCM数据兼容；损坏/缺项时只报告错误，不自愈重写/删除。无显式Chronicle schemaVersion，也暂不需要迁移；只有未来真的变更持久字段才先加真实旧档fixture、可回滚备份与双版本迁移测试。自包含Host回归用旧式URL/ModelId、额外字段和schemaVersion=0验证读取兼容，并在成功/失败读取后逐字节hash确认不写回。

W7-J update policy: 当前包不实现热更新；
Bannerlord加载中的Mod DLL不支持安全覆盖，所以替换/回滚/卸载仅在游戏客户端关闭后进行，Release Harness在每次隔离文件操作前拒绝活动客户端。
其版本循环只用一个仅改变manifest版本的v0.1.0→v0.1.1 fixture，再回滚/卸载；
它验证文件所有权和用户配置/存档保留，不等于代码变更或配置schema迁移。
Host退出与父进程监护由W7-H生命周期测试覆盖。
Provider回归`TestResults/20261013-014758`验证不带schemaVersion的旧式URL/模型键及额外旧字段可读、损坏Profile失败且文件hash不变；
`TestResults/20261013-020758`通过隔离安装→manifest版本更新→回滚→卸载，所有步骤保持全局MCM配置/28个正式档与真实安装Mod整树hash不变，其它Required模块仍在，游戏进程关闭且临时目录清理通过。
这里用的v0.1.1是Harness manifest-only fixture，不宣称新二进制兼容或已需要配置迁移。
第三方Mod管理器的具体界面仍留Epic #18验收。

`AgentHostLifecycleEvaluation -LifecycleScenario MissingModel|ServiceUnavailable`复用同一一次性Campaign启停夹具，分别指定确认不在本地目录的模型名、确认没有监听者的loopback端口。两种错误必须在模型生成和任何Host Native命令前退出，控制器只经过Starting→Failed，无Ready事件，脱敏收据分类正确，游戏仍可查询且源档/进程/session干净；不修改或关闭玩家现有模型服务。

同阶段的`ParentExited`使用受限idle Provider，在Native会话/Host Ready与PID、可执行文件路径核对后，仅强制结束本轮disposable游戏进程；不连带杀子进程。Host须在十秒内自行退出，测量发生在外层清理之前，并记录退出码/耗时、零世界动作、源档hash及最终session/config清理。父进程已关闭，不能据此声称游戏内Failed通知显示或终态JSON已被Mod接收；这些字段明确不适用。该场景不生成模型响应，不改正式存档。

`StopTimeout`仅在已授权的临时生命周期/no-model模式下让idle Host忽略停止输入；普通Provider不会进入该分支。游戏仍发送产品Stop协议，至少经过五秒停止等待后由身份校验清理自己的Host，状态Starting→Running→Stopping→Failed；验证游戏仍可查询、没有世界动作或重复行动、源档与会话/进程干净。被强制结束的Host没有终态JSON，不用正常退出收据伪装超时结果。此场景不验证在途非幂等动作或其他同名Host并行隔离。

`NonMap`从同一一次性Campaign通过现有Native库存入口打开InventoryState，再在该状态调用注册Start委托；要求Starting→Failed且零Host进程/Ready事件，库存保持打开。随后经现有Native Cancel回Map，核对Gold/位置、源档与清理。Harness自动Start状态只允许MapState或InventoryState，普通运行不读取该测试启动分支；不新增Agent玩家动作或模拟鼠标点击。

`CampaignRoundtrip`是在同一Bannerlord PID里测新Campaign会话切换：受限idle Host先与测试档旧会话握手；
Harness在该一次性Campaign中通过Native SaveAs生成随机名临时副本，等待原版OnSaveOver成功，并核对其PID/Native Session；
Native `MapScreen.OnExit`结束旧Campaign后，只在Campaign为空、Native处于InitialState且旧Host退出时，加载这个临时副本。
加载仅用SandBox正式 `TryLoadSave → MBSaveLoad.OnStartGame → SandBoxGameManager`链；
先核对存档模块版本一致，版本差异/Native确认Inquiry会让夹具安全停下，不自动确认。
原始 `AgentBridgeLifecycle` 档保留不写，生成的临时存档在测试进程退出并确认目录/随机名归属后删除。
回Map后比较旧/新Native session ID，并以旧ID发送一次原版`move`请求；
要求Native在动作handler前以`native-session-mismatch`拒绝，新会话PID/金币/目标地点/时钟档不变，且旧Host没有重启或重放。
该验证宏只在生命周期Harness/no-model/证据目录限定下运行，不是玩家退出/读档按钮或Agent动作的视觉验收。

Host自包含包发布默认保留NuGet漏洞元数据检查并使用7890代理和D盘缓存。仅当发布失败日志明确为`NU1900`漏洞数据端点传输中断、且Host工程仍无`PackageReference`时，Harness才重新运行正常依赖还原/发布并关闭该次审计元数据请求；包哈希、Self-contained运行库和Host回归仍须通过。其它还原失败不跳过检查、不进入fallback。

Smoke子脚本有独立墙钟上限（启动时限+稳定窗口+30秒收据余量），stdout/stderr写入本次Temp。超过上限时只清理该worker及其直接创建、路径核对过的Bannerlord客户端，保留失败证据；不再无限阻塞整个Harness。结果JSON只序列化一次，`SmokeReceiptStages.log`分别标记序列化开始/完成和写入完成，区分游戏启动与测试收据生成卡点；这些标记不是游戏结果的替代证据。

Smoke的FinishedAll/AssemblyLoaded/CrashDetected必须是Boolean；日志先转换为单一字符串，再做布尔匹配，防止集合匹配把完整日志作为结果。收据经有限层级的纯数据投影，保留空数组/null/数值/文本和快照字段，拒绝未知运行时对象；Windows PowerShell使用Framework JSON serializer，PS7使用规范化后的ConvertTo-Json。两种宿主的离线回归检查带PowerShell扩展属性的字符串、嵌套按钮快照、空数组和null；不把文本附带的运行元数据带进JSON。`191336`曾产生599274字节且两项字段为数组；修复后`191708`的启动收据2533字节，两字段均为Boolean且启动检查通过。

地图移动Host必须先让模型把完整用户目标归入`native-map-arrival-v1`受限能力，才能发布`mapSettlementTargets`/`move`。
分类阶段只看目标所需结果，不因尚未查询地图就误判范围；
此阶段无Native动作，Host仅开放固定的两个分类值。
完成分类后禁止重复分类；
首次地图查询返回安全目标后只开放`move`，移动已被Native接受后只开放被动`observeAgain`，不重复查询/下达移动或调用时钟接口。
缺失/格式错误的动作参数只进入有限重试，不执行Native动作。
完整目标含招聘、任务、贸易、技能、战斗、家族阶层、指定非当前可见地点或其他额外成果时，模型应返回`unsupportedGoal`；
Host以`campaign-goal-unsupported`在Native写入前失败并说明未执行战役行动。
支持声明仍只表示Host执行“到达任一当前可见安全聚落”的有限目标，最终必须再由fresh Native `currentSettlementId`后验通过，不能伪称更广目标完成。
真实游戏内4B证据：`TestResults/20261013-004218`对普通地图移动目标完成分类→地图查询→移动→Native抵达闭环（8次决策、2个Native动作，来源`qwen3.5:4b-q4_K_M`，CampaignDay自然+0.023、源档hash不变、Host/游戏/session清理通过）；
`TestResults/20261013-004434`对`Become clan tier 1 (50 renown).`在一次分类后明确拒绝，0个Native动作、CampaignDay不变、战役仍可查询且进程/session清理通过。
二者仅验证这一种支持与不支持目标样本，不证明分类器能理解所有自然语言；
不确定/格式错误仍安全失败。

## 目标与边界

Chronicle 当前的产品方向是AI自主游玩Bannerlord单机Campaign：AI直接驱动`Hero.MainHero`/`MobileParty.MainParty`，通过原版交互实现目标，玩家可高层督导但不逐步代点。产品北极星是StoryMode `Establish Your Clan`自然完成；纯聊天、单次工具演示或NPC候选扫描均不算通过。产品范围、当前门禁与未决事实见`MAINLINE.md`，工作顺序由GitHub Project维护。

工程同时维护可无人值守验证产品的本地Harness：隔离一次性夹具与正式存档，提供可信原生状态、进程、日志及必要视觉证据。游戏内Bridge负责MainHero/MainParty观察、Native动作分发和会话校验；Agent Host负责真实模型决策、目标循环、结果核验、记忆/checkpoint与运行监护。既有接口以MainHero为主体，正是当前首发身体基础；这不等于完整StoryMode自主能力。NPC Think trace、造景与故障注入只服务验证/未来研究，不能进入普通Agent动作目录或替代产品目标。

`FreshStoryModeSetup`是#130验证前置的测试切片：仅显式`CHRONICLE_FRESH_CAMPAIGN_STORYMODE`标记会从原版`InitialStateOption`目录执行`StoryModeNewGame`，由StoryMode原生委托创建全新Campaign，Native `CharacterCreationManager`走有效文化/经历菜单；
训练场教程跳过只调用兄长对话中可见的`player_answer_skip_tutorial`和`end_tutorial_yes`，并通过`ConversationManager.DoOption`（包含原版选项后果/自动回复处理）提交，不直接ProcessSentence或调用`CompleteTutorialPhase`。
之后等待原版Mission/Quest事件自然激活EYC；
不写入任务/资源或生成进度存档。
每个关键剧情界面同时保留Native Engine截图与窗口录像切片；
若窗口视频帧与引擎截图不一致，以Native截图、游戏状态与RGL事件复核并修工具。
本setup在首个EYC活动MapState即停；
Harness调用官方菜单项委托而非实际鼠标输入，仍需单独验证用户主菜单操作及随后两个自然新战役EYC闭环。

游戏窗口可见性是视觉测试前置条件：从`Start-Process -WindowStyle Minimized`启动后，用不激活焦点的Win32 `ShowWindowAsync(SW_SHOWNOACTIVATE)`与`SetWindowPos(SWP_NOACTIVATE|SWP_SHOWWINDOW)`恢复目标窗口，读取`IsIconic`/`IsWindowVisible`验收；不调用键鼠输入或抢占前台。Engine screenshot、窗口视频与原生状态/事件必须相互核对；若关键帧像素完全相同，不能把文件“存在”当成视觉验证通过。

## 单一事实来源

工程只维护三份根级人工文档：

| 文件 | 唯一职责 |
| --- | --- |
| `DEVELOPMENT.md` | 工程事实、Harness 契约、工具链、验收与维护规则 |
| `DESIGN.md` | 双方确认、准备实施的功能清单 |
| `SYSTEM_INVENTORY.md` | 原版系统总清单与研究路由 |

GitHub Project 是工作项、原生依赖、状态的唯一事实源，最多一个 `In Progress` 卡片。Git是代码及其历史的唯一事实源。`MAINLINE.md` 保存长期有效的工程目标、机制契约、技术事实、未知项、覆盖分母和验收定义，不保存活动Issue、完成数或单次测试快照。`ContextState.json` 是上下文路由器，只保存当前技术焦点路径、hash/复核元数据、默认读取层和按需Research路由；项目目标、当前阶段和Issue状态不在其中重复。`TestResults/latest.json` 仅代表本机最近一次Harness运行及其commit/脏树信息。每个 `Research/<类别>/` 只维护一份权威文档并按需加载，由`ContextState.json`和`SYSTEM_INVENTORY.md`路由；某类首次进入W1研究且无文档时，创建并路由有实际内容的类别文档属于该域研究交付，不预建空文档或流程任务，拆分已有类别文档才需用户确认。`Archive/`默认不读。

GitHub 与 Harness 不互相替代：GitHub Issues/Projects 管理工作项、原生依赖、评审和协作状态；Git记录可审查的源代码历史；本机Harness探测安装的游戏版本/模组、编译并启动游戏、操作disposable fixture、采集崩溃与结构化断言；Agent负责解释目标、研究机制、选择下一步和处理未覆盖异常。这四者之间不复制状态。Harness只输出本次运行的commit、工作树状态和测试收据，不查询或更改GitHub，也不因GitHub未登录/离线而失效。运行收据以run ID保存在本地`TestResults/<run-id>`并由`latest.json`指向最近一次；Agent在工作项达到验收时，将相关commit与简洁测试结论回填到GitHub Issue。大型日志、存档与视频不自动上传或塞进Issue。

Harness产物按可复核价值留存：测试收据、日志和 Native/模型 trace 是运行证据；
录像完整解码且索引、联系表和选中帧都已生成后，MP4即删除；
不完整录像保留供恢复诊断。
`Run-Harness.ps1`收尾仅处理名称严格符合`yyyyMMdd-HHmmss`的顶层运行目录，保留当前运行、文档引用的运行、最近30次运行，以及含未完成录像/partial收据的运行；
其余旧目录整体删除。
文档引用的历史运行继续保留收据、日志、Native/模型 trace 和 timeline index；
但旧于最近30次的索引录像仅保留每个选择的`eventFramePath`，在确认事件帧仍存在并且相邻帧未被文档明确引用后，删除冗余`beforeFramePath`/`afterFramePath`，并在索引中清空对应路径、记录`historical-event-frames-only`策略。
最近30次完整保留相邻关键帧，联系表单独限留最近5次；
旧于最近30次的未引用BMP继续清理。
明确被文档点名的图片、未完成录像/partial、非标准命名目录和`TestResults`根目录文件均保留。
每次删除写入本轮`TestResultsRetention.json`的逐文件清单和回收大小；
`AgentHostPackage`随机包目录则在成功或失败出口清理。

W7-K实时委托单次循环仍有硬上限：最多160次模型决策、单次模型请求最多360秒；Campaign/MCM父循环、Quest子循环和真实Harness共享2小时总预算且仍可由Stop取消。依据：真实运行`TestResults/20261017-035504`以FreeLLMAPI `auto:reliable`完成81次模型响应/63个Native动作、282,346输入/8,327输出tokens；没有Provider错误，但总循环在3602秒因任务Deadline取消，主队仍在向Town移动、Quest未采购/交付。模型与原生行为未重复执行；上一轮完成边界证明当前1小时不足以在本次自然城镇样本完成这条路线。新的2小时/160决策仍是有界试验窗口，不代表完整委托已通过。

延长后的第一次真实运行`TestResults/20261016-214133`并未触及一小时上限：固定Mistral路由在607秒、5次成功回复/4个Native动作后，于NPC Quest对话中返回FreeLLMAPI HTTP502（同一OVH路由的1次fallback亦报错）。源夹具/正式档、CampaignDay和Quest状态未改变；完整录屏关键帧、游戏/Host/CLI清理通过。该结果不能验证一小时门限是否足够，也不能归因于Quest动作或模型选择。

官方FreeLLMAPI API文档定义`auto:reliable`为偏向近期成功率的路由策略；本地catalog不会把内置auto策略作为`/v1/models?available=true`中的普通模型行返回。Harness `Get-FreeLLMAPIProfile.ps1`已修正为接受文档列出的策略别名，同时仍拒绝拼错的profile；纯回归通过。`TestResults/20261016-221920`随后暴露另一处独立的精确名单门禁：`Test-AgentLiveModelLoop.ps1`仍要求配置ModelId必须逐字出现在available rows，因而在Bannerlord/模型调用前拒绝`auto:reliable`。现已改为复用router-aware状态函数，保持未知profile fail-fast；当前Docs会锁定这一条，尚待重新实测网关策略路由。

`TestResults/20261016-220612`在运行游戏前的模型配置预检失败，0次模型请求/0条Native动作；本机FreeLLMAPI目录没有返回策略路由`auto:reliable`这一行，但官方路由文档明确支持该内置策略。根因是Harness的`Get-FreeLLMAPIModelExecutionStatus`在检查空目录前就返回`not-listed`，误把未列出的策略路由当作不存在模型。现已对文档列出的`auto:fast/reliable/...`策略显式判为router；命名的`auto:<profile>`仍必须存在于模型目录，拼错profile仍快速拒绝。纯本地回归验证`auto:reliable`通过、typo profile仍拒绝；此轮没有实际调用模型。参见[FreeLLMAPI路由接口文档](https://github.com/tashfeenahmed/freellmapi/blob/main/docs/en/api/01-rest-api.md)。

Project采用最少任务状态：`Todo`表示尚未开始（是否被阻塞看Issue原生dependency关系），`In Progress`表示唯一当前工作（最多一项），`Done`表示验收标准已满足且Issue附有commit/结果摘要。任务清单只记录本项目内容工作（原版系统研究、玩法设计、Mod能力和面向玩家的验收）；纯Agent/Harness/文档/流程重构是内部维护，不作为产品里程碑或任务卡计数。W1用一个父Issue持有跨域审计和退出标准，子Issue只写独有的系统范围；W2-W8由原生Issue dependencies排序，标题前缀提供阶段标识，不再维护重复的自定义Phase/Gate字段。

Project采用最少任务状态：`Todo`表示尚未开始（是否被阻塞看Issue原生dependency关系），`In Progress`表示唯一当前工作（最多一项），`Done`表示验收标准已满足且Issue附有commit/结果摘要。任务清单只记录本项目内容（原版系统研究、玩法设计、Mod能力和面向玩家的验收）；纯Agent/Harness/文档/流程重构是内部维护，不作为产品里程碑或任务卡计数。W1用一个父Issue持有跨域审计和退出标准，子Issue只写独有的系统范围；W2-W8由原生Issue dependencies排序，标题前缀提供阶段标识，不再维护重复的自定义Phase/Gate字段。

任务工作流由Agent在明确边界点同步，而非由Harness轮询：开始前从Project确认唯一活动Issue、依赖及验收；仅执行该Issue范围；本地Harness验证并记录commit/测试证据；只有验收条件满足时，Agent才更新Issue为Done并附上commit与结果摘要。暂缓、阻塞或范围变化直接更新对应Issue/依赖，不另开状态文档。没有活动Issue时，Agent选择可执行且依赖已解除的下一项后再开始。

源码仓库位于 Bannerlord 安装目录之外；游戏目录只作为 Harness 的运行时目标。被Git忽略的 `harness.local.json` 仅保存本机仓库与游戏路径；GitHub任务板位置只在 `ContextState.json` 记录一次。新工作区用 `Initialize-ChronicleWorkspace.ps1` 生成本地路径设置。源码、模块清单、Harness和工程规则均由同一Git提交追踪；构建将版本化模块清单与DLL部署到本机 `Modules/ChronicleFramework`。Build阶段部署前检查`Bannerlord*`进程；若用户游戏已运行则明确拒绝，Harness不终止该进程也不覆盖正在加载的DLL。大型`TestResults`不提交Git，证据仍按运行号保留在本地。

文档管理优先保证可读性和信息层级，不以总字数或文件总数强迫压缩。
`Check-Docs.ps1` 强制内容文档明确路由、引用目标存在、主线唯一且复核/hash有效；
根目录`AGENTS.md`是直接生效的工作规则，不属于内容文档路由，也不应加入`ContextState.json`或`SYSTEM_INVENTORY.md`。
检查器会验证 SYSTEM_INVENTORY 的126个A-L系统各自至少落到一个显式OBS/ACT/N/A目录行、每条目录记录在来源列引用有效A-L系统编号且全体覆盖126个编号、观察/行为/N/A目录ID唯一且所有交叉引用都有定义；
同时按目录中显式标注的特权ACT分类，核对Mainline声明的ACT总量/核心分母，避免目录增删后分母脱节。
Docs收据记录当前目录行结构计数，供同一分母口径下比较版本变化；
这些计数不代表已核实的玩家行为最终分母。
系统本身不是行为分母；
有真实原因无玩家入口的引擎项必须用带研究来源的N/A行表示。
总文档字节数和默认读取集合的大小只作诊断数据。
主题过长时先按概念边界拆分并调整路由；
过时内容应修订、删除或移入默认不读取的 Archive，不得为了塞进一个任意容量而写成密文。

禁止新增 README、Harness 说明、工具链说明、验证报告、状态记录或索引 Markdown。当前项目完成或主线改变时，默认删除旧 `MAINLINE.md` 内容；只有仍具长期追溯价值时才移入 `Archive/`。Archive 不得进入默认上下文。

## 原版机制假设门禁 / Original Mechanic Assumption Gate

任何会模拟玩家输入、改变 Campaign 状态或推进时间的实现，先在唯一 `MAINLINE.md` 的“原版机制契约”补一行，再写代码。每行必须分清：

1. 玩家实际入口和输入修饰（普通点击、按住某键、菜单项、TAB 屏幕等）；
2. 原版命令造成的自然世界状态变化；
3. 当前 Campaign 时间档位与动作的关系；
4. UI/input handler 相比直接调用原版 API 额外做了什么；
5. 事实来源、运行证据和未知项。

实现前追当前版本玩家入口；反编译出 setter 不等于复现操作。Campaign 时间运行时自然推进，原版地图点击可调档；移动不得暗藏快进/暂停。仅对影响实现且源码未知的玩法事实询问用户。

这不是新增文档：在既有 MAINLINE 契约表中维护事实。`Check-Docs.ps1` 检查契约表、必需字段和当前实现动作是否都有记录；实现范围改变时同步维护该表与 Harness contract version。PowerShell 读取 AGENTS/Markdown/JSON 权威文件时必须显式 UTF-8，中文规则门禁不得依赖系统默认代码页。MAINLINE维护分母定义与验收规则，GitHub维护任务状态，`TestResults`维护单次运行结果；不以动作数量替代自主决策闭环进度。

## 研究就绪门槛

`MAINLINE.md` 的 Research Gate 未就绪时，不实现新的游戏能力。当前MainHero StoryMode纵向门禁须先把自然新战役/教程/Quest激活、四个动态目标、现有Native动作可复用处、实际缺口、时间/失败恢复和Journal/Quest后验核清楚；不得因182个人类玩家ACT已盘点就假定这条StoryMode纵向链已经覆盖。就绪依据是玩家真实入口与相关观察/行为范围已研究到足以界定当前目标覆盖分母，而不是列出多少熟悉案例。`HarnessResearchReadiness.ps1`保留一个精确hash的SubModule审阅基线，用来发现未经复核的额外改动；当已批准的产品生命周期或Harness入口合理需要改SubModule时，先检查实际diff/Build/Smoke，再同步更新该hash，不得用删掉门禁来让检查通过。纯Harness诊断维护不等于新游戏能力。

`CampaignActorThinkTrace`是留存的W8/NPC Actor未来研究专用只读Harness阶段，不属于当前W7 MainHero产品门禁：仅Harness环境变量启用，在Campaign `TickEvent`中按需读取公开`MobileParty.ThinkParamsCache`的一名现存非MainHero Lord非空候选，含行为、目标标识/位置、分数和导航标志；默认用专用Harness `advance`显式推进0.25个Campaign日。它不调用`PartyThinkParams`写方法、不提交Party动作、不进入普通Agent动作目录。该阶段只证明一项Native候选观测，不证明Chronicle控制NPC，也不改变W7 MainHero StoryMode的Research/Implementation Gate。SubModule仍只允许精确审阅哈希的Harness诊断基线；新增玩法代码仍受当前门禁约束。

## 当前版本事实

- 当前可见客户端为 `v1.4.8.119303`。
- 先前 `v1.5.3` 结论来自不同本体状态，不能直接作为当前 API 契约。
- 根目录 `package_info.txt` 不是可靠运行版本来源；以当前官方模块、运行日志和本机 DLL 为准。
- 当前阶段必须重新运行 API Probe、Build、Smoke 和干净战役夹具，旧 PID、旧日志和旧存档只算历史证据。
- 正式整合包模块集、Chronicle 最小模块集和官方基线必须分别记录，不能互相替代。

## 开发入口

Bannerlord Smoke与Agent Native启动共用Steam就绪守卫：Steam未运行时仅以`-silent`从已配置本机安装目录隐藏启动，等待Steam WebHelper进程集合稳定5秒，并读取Steam `connection_log.txt`确认当前用户登录完成后才启动游戏。若Steam由Harness启动，还要求“Logged On”事件晚于本次客户端启动；旧的WebHelper稳定状态不足以证明Steam API已可用。Smoke收据包含登录事件时间、Steam readiness与本轮启动来源，便于区分Steam前置条件故障和Mod启动故障。

`MissionLeave`验收使用一次性Campaign夹具经Town菜单进入真实Location Mission，先保存引擎帧，再用一个限时Mission专属`IInputContext`让本场景的`Mission.Tick`读到Leave Area game key处于按住状态；它继续走原版`Mission.OnEndMissionRequest`、MissionLogic veto/Inquiry与Mission计时，不直接调用`Mission.EndMission`，也不发送OS全局键鼠事件。测试等待真实Mission→Campaign MapState和原Settlement菜单，并保留前后引擎帧/时钟/存档哈希/清理收据。该测试已加入`All`：当前实测证明了Sargot TownCenter路径，不等于所有Town/Village/Tavern和其他Mission条件都已覆盖。用户当前键鼠实测长按Tab约两秒，但产品代码虚拟的是Native Leave Area game action，不硬编码物理键位。

Harness启动Native游戏客户端前确认Steam Client/WebHelper稳定，且Steam `connection_log.txt`中的最新状态为用户“Logged On”；
若Steam由Harness启动，该登录事件还必须晚于本次Steam进程启动。
若Steam未运行，仅从本机安装目录用`-silent`启动，不发送账号凭据/全局键鼠。
`TestResults/20261103-051917`复现了仅靠WebHelper稳定仍会过早启动：Steam登录在Bannerlord出现Steam API警告之后才完成。
`Get-ChronicleSteamLoginState`和Smoke收据现在记录并门控登录事件；
完整阶段Smoke TestResults/20261103-052652随后在已登录Steam会话下通过：Chronicle程序集、Campaign lifecycle、MCM项/按钮/键位均注册，稳定启动37.43秒，声音静音守卫生效。
冷启动Steam后的Smoke仍未实测。
若启动仍需登录或出现`Unable to initialize Steam API`，失败收据保留目标窗口内容，不自动点确认、不伪装成Mod/存档兼容故障。
启动还会把`engine_config.txt`里的`max_framerate`临时限制为30，并使用已核验的840×472非激活窗口布局；
该配置快照放在Agent运行目录，Stop后恢复；
在 visual-capture 模式下，1.4.8 `MapScreen.OnGameWindowFocusChange`会在非激活窗口自动打开Escape菜单，Harness通过Harness-only Harmony前缀抑制该自动Overlay并在地图操作前断言Map/Escape菜单未挡输入；
普通游戏行为与Agent白名单不变。
（保留`safely_exited=1`安全退出标志）。
若测试中异常退出，后续安全启动会先恢复遗留快照；
无Bannerlord进程时也可显式运行`Agent-Cli.ps1 recoverTestConfig`恢复一次性快照；
游戏进程仍在时绝不覆盖配置。
这样减少测试渲染负载但不把低画质设置留给玩家日常游戏。
启动等待只读取Chronicle日志新追加的字节，不再每250毫秒重复解析整份日志；
若协议未就绪，`startup-timeout-<pid>.json`记录Window Title、Steam状态、增量Chronicle遥测、RGL/watchdog末尾和弹窗快照。
UI Automation返回的窗口/控件代理必须先投影为纯文本/数值字段再写收据，避免序列化卡住；
未知警告不被假定为崩溃，也不自动确认。

若Bannerlord已加载模块但未达到Campaign协议就超时，Agent-Cli会在清理进程前保留`startup-timeout-<pid>.json`：窗口标题/句柄、进程是否仍在及CPU秒数、当次Chronicle启动遥测、RGL错误日志/watchdog尾部、已确认的启动弹窗回执和待恢复配置标志。该失败只能判作“协议未就绪”；若日志没有故障信号，不宣称崩溃或兼容性根因。下次安全启动恢复未完成的配置快照。

`VillageToolsDelivery`是W2-AI单项端到端Harness阶段：至多320轮内由确定性Provider只看本轮Native `state`、当前Settlement overlay人物与Issue marker、QuickConversation当前选项、公开QuestJournal任务文本及Trade VM报价；
通用Agent循环的硬上限为400轮。
这个路线需要真实跨城购买、返回委托人并交付。
玩家可见交谈使用`talkToSettlementHero` QuickConversation；
Visit使用分离的`visitSettlementHero`，不混入W2-AI的快速交谈闭环。
任务提示结束后，Provider继续推进原版QuickConversation，验收回到同一村庄Settlement菜单且conversation为空，不把尚未关掉的提示面板当作闭环。
该环节暴露并修复了Agent JSON跨Windows PowerShell进程的中文乱码、单个对话选项被误当成数组、空对话节点未继续、Trade模式从错误字段读取、空市场重复访问、原版`hero_task_given`分层交付入口未继续，以及Provider变量名`$home`碰撞PowerShell只读变量的问题；
AgentLoop回归现用真实Campaign中的中文主角名验证完整往返。
每个市场只查一次、无合适商品才转到下一个已观察市场；
移动订单完成后，Provider另发显式Native `fastForward`以缩短自然行程，不把时间控制藏入`move`动作。
为避免让只有主角一人的测试队伍陷入无法使用Native Send Troops的遭遇，Provider在委托村庄尝试用当前Native志愿兵报价组成最多5人的护卫，同时至少保留450第纳尔；
遇到主动劫匪先选择当前可见的和平方案，战斗菜单仅在原版Send Troops可用时使用BattleSimulation及Native战后界面；
若Send Troops不可用则保留遭遇并停止，不进入实时战场或擅自投降。
Captivity界面只继续单一可见的`mno_continue`阶段；
到达赎金/逃脱等有后果选项时保留状态等待用户的玩家策略事实，不快进、不猜着选择。
以上是该测试Provider的有界策略，不表示产品Agent已实现完整战斗/战后AI。
完成判定基于Native任务从活动Quest列表移除、Turn-in前原生市场可见的工具数量，以及Turn-in后经玩家原生MainHero Inventory VM按需读取的精确Tools/奖励物品ID与数量；
先前的Roster总物品数变化只作交叉检查，不冒充物品类型明细。
由于Native TradeVM的可出售Flax数量可能小于MainParty完整Roster数量，不为二次确认而冒险再次穿越战区。
测试还核验QuickConversation返回同一Settlement菜单、源存档哈希和进程清理；
Provider的`done`只结束循环，不代表成功。
不注入任务/物品/库存，不读取私有Quest字段。
此专项阶段通过前不加入`All`。

`SettlementOverlayQuickTalk`对已确认存在自然Issue marker的可见Settlement运行Native QuickConversation专项回归：通过QuickTalk权限事件与CampaignMapConversation进入地图对话，按当前可见原版选项结束，并验证回到同一Settlement菜单、任务/存档/时间证据和进程清理。测试目标Settlement是已验证的一次性Campaign夹具参数，不是Provider得到的隐藏Quest字段，也不代表全地图自主Issue发现能力。`SettlementOverlayConversation`继续验证不同的Visit/Location Mission路线。

Agent decision provider may terminate a bounded loop with an explicit `{done: true, reason: ...}` response; the loop records this as `provider-stop` and issues no further game action. This only means the provider claims its objective is met, not that the game objective is verified; the owning Harness test must assert the actual native postconditions separately. Reaching the decision budget is recorded as `decision-budget-exhausted`, never as success.

默认入口：

```powershell
pwsh -NoProfile -File .\Dev\ChronicleFramework\harness\Run-Harness.ps1 -Phase All
```

AgentLoop 的 `observeAgain` 是循环调度控制，不属于游戏动作：只允许在 Native `move` 已完成、Campaign Map仍在自然运行、主队仍移动且目标尚未抵达时，请求 1–10 秒的宿主侧等待；
允许的Native时间档是 `StoppablePlay` 或 `UnstoppableFastForward`。
遭遇、菜单、弹窗或停止时间都不能靠宿主等待解决，执行器会拒绝该等待、刷新Native观察并把 `control-unavailable` 反馈给模型，不发送暂停/快进/时间步进命令，也不重复下达移动。
若模型推理期间主队已自然抵达目标，同样将过期等待作为无副作用拒绝反馈；
没有匹配的已完成Move回执则失败关闭。
Native拒绝一个动作后，循环把失败动作和原因放在本步回执/反馈中，但保留上一个已完成的Native回执供重规划使用，不能把失败提案当成最后一次成功游戏状态。
执行器会检查条件，Native `currentSettlementId` 与移动回执的目标一致时，只有“移动到达”这一窄目标会把 `nativeMoveArrival` 送给模型；
循环另可设墙钟总时限，超限失败并留收据。
为了避免无关背包/技能内容和上一回执的完整状态副本挤占短上下文，地图旅行白名单严格为 `mapSettlementTargets,move` 时，模型输入使用 `campaign-map-travel` 字段视图；
地图旅行+招募白名单时使用 `campaign-settlement-recruitment`，只传相关位置、队伍/金币、时间、危险和当前招募菜单入口。
两种视图都将模型侧上一回执压为有限的 `stateSummary`，聚落目标/招募报价也各自摘要；
原生观察/回执、执行器校验和游戏状态不被裁剪。
Provider将UTF-8 JSON作为字节发送；
面对模型输出的 positional array，只在元素数精确等于当前动作参数列表长度时按列表顺序映射，最终仍由执行器检查参数名/值。
缺少模型 rationale 时会明确标为 `rationaleSource=provider-fallback`，不会伪称为模型理由。
`LiveModelArrival`、`LiveModelRecruitment` 与 `LiveModelSafePassageRecruitment` 是显式、耗时的选择性阶段（不进入 `All`），使用真实配置Provider和disposable战役。
`LiveModelSafePassageRecruitment`用视觉Harness专用的Native Bandit fixture，在一次Move后创建当前可观察的hostile party，等待原版`encounter_meeting`真实出现，再让模型通过`dialogueSelect`与Native BarterVM完成和平通行并继续招募；
夹具详情只进Harness收据，不进入模型观察。
`recruitOptions/recruit` 不打开Gauntlet招募窗口、不模拟焦点，因此不能声称已经验证玩家可视招募弹窗路径。
各阶段均验证Campaign自然时间、窗口视频关键帧、源存档hash及进程清理。
LiveModel Harness优先从进程环境读取服务配置，缺项时才继承已有的用户级环境值；
阶段内的超时/输出Token覆盖只作用于测试子进程并在结束恢复。

对于`ollama-native`本地模型，LiveModel在启动Campaign前先访问本机`/api/tags`并确认配置模型已安装；服务未运行、模型名不匹配或端口不可达时，在打开游戏/复制测试存档前即失败，避免把服务离线误判为模型决策失败。

如果模型已选择Native `rest(Days)`且游戏确认请求被接受，AgentLoop按接受回执中的`dailyTickCount + Days`计算目标日结算数。随后Harness每5秒仅读取一次Native状态；仅当原版仍处于活动的Town Wait且Campaign时钟由原版自然运行时继续等待。达到目标日结算、原版等待结束/时钟停止或全局墙钟超时即退出监测，再把最新状态交回模型；这段确定性观察不调用模型、不发出游戏动作，也不调用暂停/快进/时间步进。收据注明目标tick、实际tick、轮询次数、耗时和退出原因，明确`nativeClockControlSent=false`；这样模型不必为每个无变化的五秒窗口重复付费推理。

Campaign Agent checkpoint schema v2把目标、最后一个**已确认**的Native动作回执、完成契约和预算累计快照交给现有`ChronicleCampaignBehavior.SyncData(IDataStore)`随Native Campaign存档保存；
只允许v1/v2，旧v1继续用于没有预算状态的任务，付费预算续跑遇到缺少累计状态的v1则拒绝重置。
checkpoint本体另保存Campaign实例ID，防止错配到不同存档。
`agentCheckpointGet/Set`仅在Campaign Map读写且限定checkpoint最大65,536字节；
Checkpoint只表示游戏存档状态，不替代当前观察。
费用账本另写到Agent Host本地`LocalAppData/ChronicleFramework/ProviderBudgetLedger/<taskId>.json`（Harness以临时TestResults目录覆盖）：内容仅含任务/战役ID、预算profile hash、预留与usage计数/估算金额、请求次数审计状态和待确认调用标记，不存提示词、模型回复或密钥。
账本比恢复的旧存档更先进时，合并保留较大的已消费计数，避免回滚游戏存档复活已花掉的模型额度；
费率/预算profile变化、损坏账本或身份不符均失败关闭。
请求发出前先原子持久化完整预留；
若恢复时发现请求状态未知，则把整次预留保留、将usage与HTTP attempt次数标记为未知，绝不当成零或退回额度。
`-PersistCheckpoint`将预算与已完成Native回执同步保存；
`-ResumeCheckpoint`先获取新的Native `state`、校验Campaign ID和预算指纹，再从同一任务账本/存档快照恢复累计额度。
没有Native完成契约时，Provider的`done`或无参数`action=done`只表示停机提案，不是Evaluator证明成功；
有契约时必须经过本地Native verifier，只有条件满足才记作`verified-complete`，未满足则继续回到模型，不发送游戏动作。
已确认receipt用于避免重放Move/Recruit；
真正的“游戏或Agent在Native副作用提交中途崩溃”尚无Exactly-once保证，本阶段不覆盖。
`CheckpointPersistence`确定性阶段核验Native Save/Load的预算快照；
`AgentLoop`回归核验同一任务恢复后调用额度不会从零开始。
账本可以跨旧存档回退保存预留，但若用户删除对应本地账本文件，本地软件无法约束外部服务账单；
该路径不是服务商账户级硬限额。

Agent决策循环可选接收schema v1的Native完成契约（JSON经Base64参数传入，作为结构化对象交给Provider）。契约限24条条件，只允许当前Native观察中的有限字段与`eq`/`gte`比较，不执行脚本或游戏动作。带契约时，Provider的`done`先由本地Verifier核对：满足才把checkpoint标成`verified-complete`；未满足/字段未知则把逐项条件和当前Native值作为反馈交回同一循环，checkpoint保持`active`，不得声称成功。恢复时从Campaign checkpoint读回原契约并重看Native状态；目标已满足则记录已验证完成，未满足则先反馈缺项。

真实模型Provider返回的用量只记录计数元数据：请求/响应ID、模型、输入/输出/总token、缓存命中/未命中、重试和HTTP body字节；不保存提示词、回复正文或鉴权头。用量缺失标为`unavailable`，不当成0。预算门限制最多20次请求、每次body≤10,000字节、每次输入保守额度10,128 token、累计输入202,560 token、每次输出≤256 token、累计输出≤5,120 token。付费模式关闭自动重试；loopback本地模式只对尚未得到HTTP响应的连接失败重试一次。

Provider默认使用OpenAI-compatible协议；
仅支持Ollama原生`/api/chat`的本地服务可显式设置`CHRONICLE_LLM_PROTOCOL=ollama-native`。
适配器把Ollama的`prompt_eval_count/eval_count`转换成相同用量收据，并在loopback token/body预算下运行，不套用远程服务价格。
一次真实供给切片发现，10KB请求上限会挡在“读取食品报价”之后：模型拿到完整食品报价后，通用系统提示加后续请求超限；
预算门确实阻止了下一次HTTP请求和Native动作。
原始Native观察/回执仍完整保存给执行器和验收层，但模型侧使用`campaign-multiday-supply`专用提示与结构化观察/回执视图。
食品报价保留当前物品ViewModel ID、物品/修饰符ID、名称、库存、Native报价、交易逻辑单价及食品/可交易标记，去掉不影响选择与动作参数的提示类型、重量等字段；
作用域明确，未传字段视为未知。
这样不放宽请求/费用上限，也不裁掉`provision`验证必需数据；
其它任务继续使用通用提示和各自视图。

官方DeepSeek `deepseek-flash`（官方文档当前对应V4.1-Flash）使用有日期/来源的峰值安全费率；汇率暂按8 CNY/USD，输入预留按body字节数加128个消息封装token且一律按缓存未命中计，输出按256 token/次预留。当前配置20次请求的预留上界约¥0.535296，单次任务上限¥0.65；三轮评测预留上界约¥1.605888，三轮总限额¥1.95。响应超出单次或累计Token边界时立即停止，不再执行Native动作或发出后续模型请求。此估算依赖当前费率、服务端遵守输出上限及保守输入换算；它不是DeepSeek账户级消费限额。代理/自托管服务没有经核实的价格时只报告token/body，不借用DeepSeek费率。Harness收据不得包含密钥或完整提示词/回复。

按需阶段以同一命令加单个 `-Phase` 运行；
可选 Docs、Preflight、Api、Build、Smoke、Campaign、FreshCampaign、FreshCampaignProgression、Protocol、AgentHostProvider、AgentHostPackage、AgentHostSupplyEvaluation、AgentHostCampaignLoopEvaluation、AgentHostLifecycleEvaluation、AgentLoop、LiveModel、LiveModelArrival、LiveModelRecruitment、CheckpointPersistence、LiveModelResume、BattleFixture、PostBattle、Observation、MapNotifications、QuickInformation、SceneNotification、MainHeroSkills、CharacterDevelopment、SpendSkillFocus、QuestJournal、PartyRoster、PartyUpgrade、PartyPrisonerRecruitment、PrisonerRansomSale、MissionInteraction、MissionSceneNavigation、AlleyVolunteerBranches、AlleyAttackYield、AlleyAttackFightMission、PersuasionDetails、CompanionHiring、MapPartyTargets、MapPartyQuestMarkers、MapPartyQuestAcceptance、MapEscapeMenu、MapInquiry、AlleyLeaderInquiry、AlleyRosterManagement、AlleyAbandonment、AlleyEntryMenu、MapPartyComposition、MapArmyComposition、MapPartyBehavior、MapSettlementTargets、Movement、MoveToPoint、Recruitment、Rest、Pursuit、EngageVisibility、Conversation、QuestAcceptance、EscortVisibility、TavernMission、TownCenterMission、SettlementOverlayConversation、SettlementOverlayQuestAcceptance、SettlementOverlayQuestGate、BarterTransactions、BarterContexts、BarterFightRoute、BarterSafePassage、VisualCapture、All。
`AgentHostLifecycleEvaluation`先Smoke验证MCM设置按钮注册，再验证自包含Host的游戏内启停；
仅Harness测试模式自动触发按钮处理器，不使用Windows全局键鼠，也不纳入`All`。
`AlleyAttackFightMission`从Native攻击回应对话选择迎战进入专用Mission，再用现有`missionRetreat`撤退action核验失败结果/返回地图；
最新实现改为请求Native `Mission.OnEndMissionRequest()`，在MissionState中暴露当前Inquiry，并由Agent通过`respondInquiry`明确取消或确认；
它不发OS/桌面输入。
`TestResults/20261006-184320`通过并留存“放弃战斗？
”与“好/取消”的引擎帧：取消保持Mission和战斗状态，affirmative按原版结果处理。
具体物理按键/TAB完整HUD仍待玩家观察核实。
由于原版撤退会失去Alley且主角降至1HP，只用disposable Campaign并留存引擎帧；
这项不代表实时战斗自主能力或守住巷子。
`MapNotifications`在disposable Campaign中添加一个Harness专用的有效Native `InformationData`及无效/未注册负向项，产品观察器按原版`MapNotificationVM`注册表生成可见数据并确认无副作用；
全为临时内存信息，不保存。
`QuickInformation`清空一次性测试客户端原有提示，再经Native `MBInformationManager.AddQuickInformation`提交当前与排队提示，核对AI只看到当前Native UI提示而不泄漏未显示队列。
`SceneNotification`用Native非执行型HeroExecution信息弹窗建立一个真实Native SceneNotification画面，检查按钮/文本VM并保留引擎帧；
不点击、不执行、不改正式存档。
三类Notice观察均不模拟Windows键鼠，也不声称覆盖所有类型/实际鼠标焦点。
`EngageVisibility`在临时运行中通过Native `BanditPartyComponent.CreateLooterParty`生成一个弱劫匪Party，并仅为测试强弱差异临时加入普通兵；
要求它先自然出现在`mapPartyTargets`后才执行Engage。
之后目标移动、原版IsVisible、AI选择、遭遇与时钟都由引擎自然运行；
不直接修改可见标志/移动位置，也不在追击中脚本推进/暂停。
关键状态变化时保存游戏引擎截图，并把“探测成功”与“是否复现目标丢失行为”分开记录。
该阶段为慢速1.4.8启动客户端使用240秒启动超时，并将子测试原始stderr/stdout写入失败收据。
临时Party/士兵不写入源存档。
`BarterFightRoute`单独复跑Safe Passage Fight路线；
`BarterSafePassage`单独复跑接受路径并显式跨过非攻击时限。
32小时自然期间可能有其他NPC劫匪触发Encounter，故该长程模拟与不依赖长时间推进的完整`BarterContexts`阶段分开运行；
如果被其他队伍打断，收据应保留实际打断实体，不得把它误报为目标冷却到期。
Settlement overlay阶段可选`-TargetSettlementId`与`-ApproachSettlementId`：两者必须来自当前`mapSettlementTargets`；
Harness若先到Approach聚落，则通过原生Leave返回地图并重新观察后再选目标，不读取隐藏全局ID。
若路线失败，收据会保留结构化观察和MapState游戏引擎截图。
`MapSettlementTargets`负向回归使用一个visual-capture专用全Settlement显隐诊断找测试样本，仅Harness可调用，不在普通Agent观察或决策白名单中。

`PersuasionDetails`用独立窄Harness阶段验证按需观察及原版答复入口。`TestResults/20261006-204936`证明Native PersuasionVM即使在AnswerList为空时也能显示0/2与两个空圈，但隐藏CurOptions候选不输出且误选被拒。之后的`TestResults/20261007-033330`等待真实Native AnswerList显示当前回答，再由Harness仅向现有可见行注入临时PersuasionTask、argument和原版OptionVM；Agent读回success/fail/critical chances并通过原有`dialogueSelect`提交。该次Native随机结果为成功，答复文本及进度圆圈更新为1/2，源存档未改变且进程退出。这验证Native VM/机会模型/option提交链，不声称已走通Quest、求偶或政治场景中的自然Persuasion触发与宿主后果。

`MapNotifications`还在同一disposable Campaign放入`IsValid=false`和未被Native UI注册的负向`InformationData`，确认这些没有进入AI观察；只有原生能够显示的测试通知回传。观察适配器重建的VM是原版类型映射，不等同窗口当前的鼠标焦点或人工视觉操作。

`CaptivityObservation`可单独以`Run-Harness.ps1 -Phase CaptivityObservation`运行，作为额外Harness阶段且不加入All：它用临时Native bandit captor和`TakePrisonerAction`建立只存在于本次进程内的PlayerCaptivity，再打开原版Wilderness Ransom GameMenu；
为核对报价字段只在应显示的页面可见，Harness再经受限Fixture切到原版Wilderness Escape Continue GameMenu，不按任何选项。
Agent仅读取新增的条件性`context.captivity`、当前菜单选项和两张游戏引擎帧，不选择接受/拒绝/逃脱。
测试同时确认非俘虏state中字段为null、Captive赎金报价来自`PlayerCaptivity.CurrentRansomAmount`且与菜单可见金额一致、离开报价页后金额隐藏；
重复读取不改Gold/时间/存档。
Harness通过Native`TakePrisonerAction`和GameMenu阶段切换制作观察Fixture，不伪称覆盖自然战斗失败/定时检查进入这些菜单，也不决定捕俘后的Agent策略。

`MapEscapeMenu`可单独运行，不加入`All`：它用原生`MapScreen.OpenEscapeMenu()`在一次性Campaign中打开地图Escape overlay，核对Observer报告仍是MapState且`escapeMenuOpen=true`，验证被挡住的地图操作在写入前失败，再由产品`closeEscapeMenu`调用原版`MapScreen.CloseEscapeMenu()`恢复地图。关菜单不切换时间档位；测试会在显式暂停后比较CampaignDay、raw时钟档、waiting、金钱/影响力、目标和任务数，保留overlay打开/关闭引擎帧及存档哈希/进程清理回执。此动作只针对Campaign地图顶层Escape overlay，不负责Options、读档/存档、退出、Mission菜单或任意键鼠输入。

`MapInquiry`可单独运行，不加入`All`：在一次性Campaign中通过Native `InformationManager.ShowInquiry`实际生成SingleQueryPopup VM，普通`state`通过1.4.8 `GauntletQueryManager`的当前活动数据映射显示当前 Yes/No 文案、可用性、生命周期token及`pauseGameActiveState`，不把排队项当成可见询问。
Agent必须提供最新token与明确的affirmative/negative choice；
`respondInquiry`调用Native `SingleQueryPopUpVM.Execute*Action`以保留原版“业务回调后关闭/切到下一条”顺序。
测试分别验证两个Native回调、重复/过期token拒绝、弹窗打开时阻止地图移动、时钟/世界/存档不变和前后引擎帧。
额外用Sargot村镇当前Native `recruit_volunteers`入口准备1.4.8 `RecruitmentVM`，在主队恰好满员时调用Native `ExecuteDone`打开本体“Over Limit/超过上限”询问，按当前本体VM分别否定和肯定：拒绝无Roster/Gold变化，接受实际加入1人并扣原价；
原始存档哈希不变。
引擎帧中可以看到聚落菜单下方的原生对话框。
这里调用的是Native VM的玩家按钮处理器，不是桌面鼠标点击，也未覆盖其他业务Inquiry；
任意Yes/No都不代表安全或应接受。

`CaptivityOutcome`是独立可选阶段，不加入`All`：分别在两次隔离游戏进程中从同一个不变的disposable Campaign存档加载，以Native `TakePrisonerAction`建立临时捕获；测试只从当前赎金菜单观察到的启用选项中选择Accept或Reject，并记录前后引擎截图、MainHero金币/囚禁状态、主队成员、Captor囚犯名册、菜单与Campaign时间。Accept须扣除本轮原生报价并让MainHero回归MainParty、从Captor名册移除；Reject须不扣钱/不解囚，且返回`prisoner_wait`。它验证原版当前菜单结算，不代表Chronicle已选择何时赎人、拒绝或尝试逃跑；也不模拟自然战败、关押、绑架或AI政策。

`PrisonCaptivityOutcome`为`CaptivityOutcome`的独立SettlementCaptor分支，只验证`settlement_wait`→`menu_captivity_end_propose_ransom_in_prison`上下文，不加入`All`。
Harness以Native `TakePrisonerAction`把MainHero置入真实Settlement Party PrisonRoster，再由`PlayerCaptivity.CaptorParty`使用当前Settlement对象进入Native `settlement_wait`；
为使原版Captivity检查不会因双方和平而立即释放主角，夹具仅在disposable Campaign内通过Native `DeclareWarAction`建立临时敌对。
测试金币不足报价上限时用Native Gold Action补足到测试下限，金额仅用于确保Accept分支可用，不当作玩家经济事实。
Accept/Reject仍通过当前观察到的Native菜单选项，核验解囚/支付及返回Settlement等待流，并记录自然时钟前后值/完整引擎帧。
此夹具不复现MobileParty押送进城或原版定时检查自然触发赎金Offer。

`EncounterSurrender`是独立可选阶段，不加入`All`：Harness建立当前Native hostility bandit后，通过原版地图导航自然触发Bandit会面，再选择当前可见的Native Fight对话选项进入真正的`encounter`菜单；只在当前MapEvent存在之后，测试夹具才用`Hero.MakeWounded()`和`RecentEventsMorale=-100`满足该版本投降条件。Harness复读当前菜单，只有Native `surrender`确实available/enabled才选择。测试验证`PlayerEncounter.PlayerSurrender`/MapEvent结算到Captor Captivity等待菜单，并截图保留Bandit会面/遭遇/投降后原生画面；不直接设置Surrender flag、MapEvent胜负或Captivity结果。测试性伤病/士气和Bandit均只存在当前Campaign内存。若真实入口或菜单条件未满足则阶段失败留证据，不把API存在当作玩家可用入口。

`EncounterEscape`是独立可选阶段，不加入`All`：Harness在两个独立disposable Campaign进程中，把MainParty填入Native文化新兵/Grain，再以原版Fight会面路径进入MapEvent，观察Native `leave_soldiers_behind`并打开Try-to-get-away warning。Reject进程只能选择Native Think again，并核验回原Encounter且资源/时间不变；Accept进程只能选择Go ahead，核验Native `TroopSacrificeModel`显示的损失、实际伤兵/货物损失、escape debrief及Continue返回流程。测试诊断仅Visual Harness允许读取当前TroopSacrificeModel结果、Roster和Inventory；不会修改BattleEvent胜负或接受后结果。

`JoinEncounterDefenders`是独立可选阶段，不加入`All`。为提供可重复的NPC对NPC在途战斗，Harness-only fixture调用Native `StartBattleAction.Apply`建立一个BattleEvent，并确保MainParty未加入；玩家自身仍经Native地图点移动接近，再由原版Join Encounter菜单决定是否可参与。接着仅选择当前可见的Help Defenders option，并核验MainParty加入同一 MapEvent 的Defender side及后续Encounter菜单；不调用PlayerEncounter.JoinBattle，不攻击或坐镇结算。若NPC battle在玩家抵达前自然结束、join选项因原版过滤被禁或MapEvent ID变化，则记录失败原因而不是改为直接注入玩家入场。

`JoinEncounterEligibility`是独立可选阶段，不加入`All`，作为`JoinEncounterDefenders`的关系筛选补充。fixture只在disposable Campaign用Native战争/和平动作设置玩家关系，分别测“只可帮助攻击方”及“双侧中立不可加入”。攻击方正向必须经过本轮可见`join_encounter`的唯一Help Attackers选项并确认MainParty进入同一MapEvent的AttackerSide；双中立分支绝不提交Help选择，只记录原版到达状态、当前可用选项与Native `CanPartyJoinBattle`结果。如果自然NPC战斗先结束，或测试需要直接构造玩家Encounter才能显示菜单，则作为失败收据保留，不伪造UI路径。

`JoinEncounterAbandonArmy`是独立可选阶段，不加入`All`。玩家先用本轮可见地图目标与原版`pursue`进入真实`join_encounter`；为隔离弃军菜单条件，visual Harness随后在当前活动事件中用Native `Kingdom.CreateArmy`将MainParty准备成非Leader Army成员，再重新激活同一注册菜单让原版条件重算。只提交当前页面Native `join_encounter_abandon`菜单项。收据必须显式说明成员是Harness准备而非玩家点击Army Management界面建立；验收核对MapEvent/PlayerEncounter、Army内部成员/附属Party、主队Hold、资源/关系/影响力、Campaign时间和退出界面；不得用直接清除`Army`引用替代玩家菜单回调。

`MovingArmyJoin`是独立可选阶段，不加入`All`。它仅测试没有MapEvent/SiegeEvent的Campaign行军Army；先由本轮可见目标创建Native Army，disposable fixture内通过Native ChangeKingdomAction让MainParty和Army处于同Faction，再以原版地图目标交互接近。仅在当前Native `army_encounter`菜单确实开放`army_join_army`时提交；不手动触发Army encounter或直接把MainParty写进Army。Army战斗援助/中立离开走G01，围城加入是另一个上下文，均不混进本阶段。政治Faction切换仅为测试前置，收据必须将其与菜单结果/原版副作用分开。

`JoinSiegeEvent`是独立可选阶段，不加入`All`。Harness在disposable Campaign以Native `SiegeEventManager.StartSiegeEvent`和BesiegerCamp/AI目标路径建立当前可见Fortification SiegeEvent；玩家用地图Settlement目标和原版导航进入`join_siege_event`，只提交实际Enabled的“Join the continuing siege”。结果需区分Native `PlayerSiege`/Siege preparation、Active MapEvent分支和之后Mission；围城WaitMenu造成的Campaign自然时钟推进需单独记录，不作为Join命令隐藏快进。Army行军成员加入、Battle help/leave和Siege join保持独立能力/验收。

`TimeControlLoop` 是独立可选阶段，专门验证测试Provider通过Agent循环选择原版时间档；通用 `AgentLoop` 保持只读观察循环，避免Encounter随机状态污染时间控件断言。

`Hold` 是独立可选阶段（`Run-Harness.ps1 -Phase Hold`），验证先执行原版聚落导航、再调用玩家主队停步动作后，目标确实清除，并在没有显式时钟命令的自然观察窗口记录Campaign是否有效暂停。

`Run-Harness.ps1` 顺序执行阶段、首错停止、把原始输出和 JSON 写入 `TestResults/<run-id>`，并更新 `TestResults/latest.json`。

`CompanionHiring`阶段调用的独立PowerShell子测试必须把stdout/stderr合并写入父阶段日志；若子测试返回非零，异常同时携带原始错误内容，不能只留下退出码。这样真实Native交互失败可区分是游戏前置、测试夹具、动作断言还是清理问题。该规则是Harness诊断契约，不改变Mod功能。

Inventory/market专项阶段：`InventoryNavigation`验证玩家Map Inventory入口与Trade之外的原生InventoryState；
`EquipmentTransactions`验证MainHero Native SPInventoryVM装备事务；
`TradeTransactions`验证Town菜单Trade入口、市场买卖/食物筛选、按当前ItemViewModelId读取异地贸易传闻及Native `ItemMenuVM`提示一致性；
`BarterTransactions`走真实Lord对话入口，验证原生BarterVM普通物品/金币谈判草稿、Native Auto Balance、Offer/Cancel结果。
Trade rumor测试传闻仅注入到disposable Campaign内存，比较商品市场/玩家两侧原生tooltip文本，不模拟Windows鼠标；
真实物理悬停视觉仍未覆盖。
Town菜单不允许原版显式时钟控件时，测试不调用pause/resume，而是记录当前档并确认Trade查询/事务不改写它。
Barter的普通、Peace/SafePassage/Defection/Marriage UI共用VM适配层，但各Context的初始Barterable与最终世界效果不可混为一谈；
Diplomatic/Ransom的AI Barter不属于玩家UI接口。

`BarterContexts` 用独立的visual-capture Harness进程验证Bandit Safe Passage。夹具通过本机1.4.8 `BanditPartyComponent.CreateLooterParty`建立临时BanditFaction party，按原版遭遇半径/关系计入附近可加入玩家侧的队伍与`CustomStrength`；逐步增加劫匪编制，直到其强度至少为玩家侧的1.56倍，再调用原生`SetMoveEngageParty(MainParty)`。生成位置须先通过原版导航检查，且`SettlementHelper.FindNearestSettlementToMobileParty`须找到Town/Village，避免无效夹具位置触发原版条件中的空引用。

测试不手动创建Encounter，也不强制`UnstoppablePlay`；玩家经有效地图点使用原生`moveToPoint`，使地图点击按普通规则进入`StoppablePlay`，由主动追击的劫匪自然触发遭遇。默认分支走Native BarterVM、Auto Balance、Offer和接受后结算；Offer后记录原生32小时`DoNotAttackMainPartyUntil`与Hold模式，再使用独立Harness `advance 1.35 days`越过时限并复读队伍。该快进是显式测试动作，不属于普通玩家/Agent移动。第二个`-CancelOnly`临时进程验证Cancel不产生世界效果、Continue回到Encounter菜单；第三个`-FightOnly`进程从威胁选项验证Attack/Send Troops入口，但不启动或结算战斗。`BarterFightRoute`允许只复跑Fight分支，不重跑其他路线。

遭遇等待中单次状态请求限8秒，连续3次超时即失败并进入截图/清理流程；同时保留ButterLib原生崩溃异常，区分游戏崩溃与协议/UI不响应。fixture仅在visual-capture Harness模式可调用，不加入Agent决策工具。运行记录队伍/潜在加入者、有效生成点/最近定居点、地图移动回执、原始存档hash；断言先于stop执行，失败可取游戏引擎末帧，成功则停止进程并核对源存档hash。

UI Harness失败证据：游戏内Agent协议遇到非`InvalidOperationException`异常时，在当前Harness temp里保留首张引擎末帧`protocol-unexpected-failure-frame.bmp`和配套JSON（动作、错误、游戏状态/菜单/时钟）；业务拒绝类`InvalidOperationException`不触发自动截图。带UI转换的测试脚本若在其自身断言失败，则在`finally`清理进程前调用`Capture-HarnessFailureFrame`，该助手只允许对`session.json`中仍存活的Harness进程调用游戏内`captureFrame`，写入`harness-failure-frame.bmp/.json`；若Agent命令通道已卡住，失败收据会回指协议层刚保存的末帧，而不再盲等或伪报“没有截图”。不截Windows桌面、不抢焦点；成功运行不留失败图，失败收据和末帧保留在同一个TestResults run目录供Agent与用户对齐事实。

`tradeOptions`/`foodOptions`只在当前Native Trade InventoryState读取SPItemVM候选；
`tradeRumors(ItemViewModelId, InventorySide)`进一步限定到这次候选，读取Native Goods tooltip实际会显示的异地价格线索，不枚举Campaign全局rumor表。
买卖动作引用最新观察中的`ItemViewModelId + InventorySide + Amount`，以区分同一基础Item在市场侧与玩家侧的重名实例。
`tradeConfirm`通过Native Gauntlet Done提交；
若原生报价高于MainHero当前金币或Native VM拒绝完成，适配器会通过原版Cancel Inquiry清理刚建立的草稿并拒绝该动作，避免挂住不可提交事务。
`tradeCancel`关空白交易页，`tradeCancelChanges`仅在Agent明确选择丢弃草稿时接受原版Inquiry。
食品`provision`是买入方向的食品筛选别名，不另建地图态市场交易旁路。
`TradeTransactions`已用一次性买卖记录同时比对市场侧/玩家侧返回提示和Native `ItemMenuVM`文本，并确认查询不改金币、Roster与时钟。
该证据是原生ViewModel/结构化候选的一致性，不代表真实鼠标悬停的焦点动画或全部语言/Mod覆盖。

Campaign Map普通`state`保持轻量，不默认携带全部可见聚落列表；Agent可按需调用只读`mapSettlementTargets`查询当前本体`IsVisible`的Settlement地图标记，该查询只在MapState有效，不改变游戏状态或Campaign时间。隐藏目标真值仅由visual-capture Harness诊断取得，用于负向安全测试，不送入决策Provider。

地图聚落列表通过只读CLI/Agent工具 `mapSettlementTargets`按需查询，而不重复塞进每次`state`快照；只有Campaign Map状态可以调用。数据只含本体`IsVisible`的活动聚落，并附`IsInspected`以区分地图图标与近距离调查。Harness-only的`harnessMapDiagnostics`可用于正/负向测试，但禁止进入Agent决策白名单。

`Agent-Cli.ps1 load`从存档头部读取该存档创建时的有序模块ID，验证这些模块仍安装后再用同一模块集加载；
不向旧/不同模组集存档擅自附加当前默认模块。
元数据解析在Preflight使用合成存档头回归。
v1.4.8 的“Mod change detected”原版窗口是着色器缓存提示，不足以证明存档模组不兼容。
启动Harness会读取目标游戏进程窗口的UI Automation树；
仅当窗口标题、着色器/缓存正文和唯一明确肯定控件都匹配时，才调用该控件的UIA `InvokePattern`/`LegacyIAccessiblePattern`，或对可验证归属进程的Win32 Button发送`BM_CLICK`，并记录处理回执。
若窗口仍保持同一已验证提示，会重新读取控件后最多再尝试到总计3次；
内容/控件改变、无法安全调用或三次后仍在时快速失败。
它不发送全局键鼠、不激活窗口。
Docs用正向和三种负向样例锁定这个范围。
实测发现RGL提示里的“确定”是Win32 `Button`，但UIA把它标为`Pane`且不提供InvokePattern；
改为校验按钮类、控件名、窗口正文和所属PID后发送单控件`BM_CLICK`。
近期回归发现单次点击后提示仍在，故现在对完全相同的提示做有界再观察/重试，并把尝试次数写入回执；
未知弹窗仍不盲点。
测试结果会保留弹窗处理回执，供后续回归核验。

Provider loop 输入观察及上一动作原始回执，再执行 allowlist 动作并复观察；`advance` 仅 Harness 可用。Test provider 不代表 LLM。CLI 需 state 握手；stop 清理进程树/队列。对话与战斗控制分开。

每次 Harness 将 MSBuild/`Add-Type` 临时文件定向到 `TestResults/<run-id>/Temp`；项目排除 `TestResults/**/*.cs`，防止反编译研究源码污染 Mod Build。

`mainHeroSkills`是固定体量的玩家自我状态，随常规快照读取：只枚举当前Campaign的SkillObject并调用MainHero原生`GetSkillValue`；不混入XP、Focus或Perk预览值。`MainHeroSkills` Harness阶段将对照独立Native读取，证明快照没有写入角色成长状态。用于测试的`harnessPlayerSkillsDiagnostics`仅在visual-capture模式可调用，且不进入Agent动作白名单。

`characterDevelopment`是只在Campaign Map显式请求的只读查询，不扩大常规`state`快照。它向Agent返回MainHero属性、技能进度/Focus/学习率、点数余额与当前等级可见Perk状态；CharacterDeveloperHarness用原生`CharacterDeveloperHeroItemVM`逐项对照，QA诊断仅在visual-capture模式可调用，不进入Agent决策白名单。它不提交成长草稿；Focus/Attribute/Perk投入以及Done/Cancel/Reset须另立产品任务，并先补MAINLINE行为契约。

`spendSkillFocus(SkillId, Count)`只允许Campaign Map调用，要求目标来自最新`characterDevelopment`观察。调用在单个命令内验证技能身份、原生可加点状态、余额与Focus上限；然后用原版`SkillVM.ExecuteAddFocus`建立临时草稿并通过`SkillVM.ApplyChanges`提交，不开角色界面、不保留跨回合草稿、不改时钟。事务测试验证可用Focus实际写入与超额请求的整体拒绝；QA诊断只在visual-capture模式可用，决策环可调用的仅为正式白名单动作。

Campaign `state` schema21把活动Quest期限字段限制为原版QuestsVM显示的整日剩余时间；若Quest声明期限隐藏，返回`null`。Agent可用观察到的QuestId显式查询`questDetails`，取得Quest Journal显示的阶段文本/任务名与进度，不读取内部QuestTask列表、已完成历史或未观察任务。此查询只读，在Campaign Map/Mission均可用；QA用新接受的原版Quest与`QuestItemVM`逐项对照。

`partyRoster`是Campaign Map上的按需只读查询，只列MainParty成员与俘虏的兵种ID/名称、人数、伤员和Hero标志；常规`state.party`继续保持汇总。它不枚举其他阵营Party，不给升级/招募建议或费用，也不改Roster。Harness专用诊断从同一原生TroopRoster但用独立`GetTroopRoster()`枚举路径交叉核对；测试诊断不进决策白名单。

`partyUpgradeOptions`/`upgradeTroop`从MainParty Normal PartyScreen的原生PartyVM读取并提交一个普通兵种升级。`prisonerRecruitmentOptions`/`recruitPrisoner`读Native PartyVM当前可招募的MainParty普通俘虏并提交一个；超PartySize时，选项同时返回完整原版Done确认文案，Agent必须显式传`ConfirmPartySizeWarning`同意超限后果才会调用原生affirmative callback，否则动作拒绝并撤销草稿。两项动作都使用共享MainParty PartyScreen生命周期，临时PartyVM需按原生要求初始化按键回调并调用`OnFinalize`。Harness disposable fixture仅在visual-capture模式下能注入兵种、XP或填满队伍；不会保存这些改动。`PartyUpgrade`/`PartyPrisonerRecruitment`阶段分别核验native结果、拒绝、Campaign时钟和清理。

`missionSceneAgents`只在友好Town/Tavern/Village Location Mission且Campaign Stop时按需列出当前Mission已生成的活动人类Agent及其位置；
它不是相机可见列表，也不查询Campaign全局或其他聚落。
该信息不进入常规`state`快照。
`missionNavigateToAgent(AgentIndex, DurationSeconds)`在12单位内仍接受当前局部Agent；
远目标必须先来自同一Mission、最近60秒内的`missionSceneAgents`观察。
导航读取目标的当前位置，经Native `SandBox.AgentNavigator`和Scene NavMesh实际移动，非传送；
NPC移动后需重查询/重选目标。
导航租约默认8秒、显式限1–20秒，结束恢复MainAgent Player控制权；
有Agent不保证存在可达路径。
`missionInteract(AgentIndex)`仍只接受当前局部`nearbySceneAgents`里的有效人类Agent；
它先验证原生`MissionConversationLogic.IsThereAgentAction`与`Agent.CanInteractWithAgent`，再调用目标的Native `Agent.OnUse`→`Mission.OnAgentInteraction`链，而不直接启动ConversationManager。
对话启动后由既有`dialogue`观察及`dialogueSelect`/`dialogueContinue`处理。
`MissionSceneNavigation`以Assigned Alley Leader为远距目标，先证实无场景观察的远距导航被拒，再查询当前Mission、经有界NavMesh走近、进入局部范围后由现有原生交谈动作开对话；
不选对话选项。

2026-10-27 Natural `FreshStoryModeModelEvaluation` revealed an AgentObserver field mismatch in the Tavern companion route.
The Host exposed `missionInteract` only when `nearbySceneAgents[]` contained `isInteractable=true`, but AgentObserver emitted that field only for `nativeFocus.agent`; the nearby-agent entries omitted it.
The run therefore recorded 12 local-scene reads, 6 Native approaches, selected-target distances of about 1.36–1.43 m, and zero nearby-interactable observations/Native interaction attempts before the Companion subflow exhausted its decision budget.
AgentObserver now adds the same Native `Agent.CanInteractWithAgent(agent, currentCameraElevation)` result to each nearby local agent.
This adds no new game action and does not relax the `missionInteract` Native guards; the focused-camera `nativeFocus.agent` field remains separate.
`TestResults/20261027-074157` passed the existing Tavern `CompanionHiring` integration in both scenarios: a Wanderer at 6.261 m was not interactable, Native `AgentNavigator` reached 1.462 m, then Native `Agent.OnUse` started the correct Hero conversation and hiring; at exact asking Gold 660 the Native offer did not expose acceptance and the decline produced no hire.
The source save hash matched and both game processes stopped.
This verifies the observer/action path for the fixture, not that a natural StoryMode Agent chooses it successfully.

The next natural run `TestResults/20261027-074559` confirmed that the observation fix let the model make progress: PartySize moved 1→9 and the Companion trace records 1 Native interaction plus 1 successful conversation start.
It then consumed 92 decisions/435,059 prompt tokens in the Companion subflow.
The Native UI options were present under `state.context.conversation`, but this loop looked at `state.conversation`; it therefore failed to recognize the actual conversation and kept requesting scene-agent queries.
The loop and fake Native now read `context.conversation`, and its package self-test uses the actual observer schema and requires the active conversation to expose only the current dialogue action.
`TestResults/20261027-075457` AgentHostPackage passed.

Natural run `TestResults/20261027-075756` verified that the model then traversed the real Tavern dialogue: it selected the business response, opened the Native quote, and hired one Companion.
The original Journal showed Companions 1/1.
The next parent objective immediately failed `recruitment-map-unavailable` because the child returned while `GameState=MissionState`, `menuId=town_backstreet`.
The Companion child now keeps the objective complete state pending until it chooses the existing Native `missionLeave` action and observes MapState; only then does it return completed to the parent.
Package self-test expects the hire→Native Leave Area→Map→completed sequence; `TestResults/20261027-080844` Build/AgentHostPackage passed this regression.
This does not automatically leave the settlement or change Campaign time.

Natural run `TestResults/20261027-081126` exercised that exit handoff: after declining a quote, the model finished the hiring dialogue, left the Tavern by Native `missionLeave`, exited the town menu, and revisited another town.
In that later Tavern it reached the Wanderer quote but alternated the Native `player_companion_hire_response_2` decline with `main_option_faction_hire` on the same Hero, despite a currently clickable `player_is_leaving_neutral_or_friendly` exit.
It consumed 96 Companion decisions/412,036 prompt tokens; Journal Companions stayed 0/1 and the run did not complete EYC. The action catalog now adds that visible Native exit and, after a decline, exposes only that exit for the same current Wanderer instead of letting the model reopen hiring.
A narrow fake Native self-test covers the current option catalog and decline state.
The following run `TestResults/20261027-083134` did not reach a Tavern decline; the model safely stopped the Companion child before an action, then completed one battle simulation with the MainHero captured and returned to recruitment.
EYC remained incomplete.
Harness contract 7.345; natural verification of the decline/exit path remains outstanding.

3D `StartUp` Location Mission仍必须通过原版Leave Area游戏键退出，且`menuSelect`不能拿底层`Campaign.Current.CurrentMenuContext`冒充可见菜单。
1.4.8状态层存在残留父菜单：Tavern的`MissionState`中会继续显示`town_backstreet`/`town`等menuId与选项，但画面是3D场景；
2026-10-29我们先在该场景调用`menuSelect town_leave`再尝试missionLeave，约5秒后遇到`0xC0000005`。
时间关系不足以证明native故障由哪一步引起，但现有录像证明该菜单没有显示在玩家屏幕；
因此`AgentObserver`现在只在Native菜单确实可见时暴露`menuId`/选项，`menuSelect`在3D StartUp Mission和正在显示对话UI时被拒。
Conversation UI结束后，若回到用户确认的村庄菜单，仍可在Conversation Mission里看见并选择当前菜单。
`missionLeave`继续对有效的友善Location Mission调用限时原版Leave Area输入，不要求一个已隐藏的GameMenu；
同时支持由`town_enter_arena`进入的友善StartUp `arena_*`场景（实测`arena_empire_a`、menuId空、TournamentVM未激活）。
这让Tavern在menuId为空时仍能用正确的TAB动作离场，并阻止重复调用底层菜单退出。
Native SaveHandler在MissionState被请求后仅返回accepted，19分钟无SaveOver回执/存档文件；
CLI `save`已改为MissionState直接拒绝，须先回Campaign Map。
`missionInteract`现在也允许在该受支持的友善Arena Mission中，与当前本地观察到且Native认定可交互的`tournament_master_empire`交谈；
仍拒绝其他竞技场Agent。
安全存档实测进入竞技场后Native交谈、读取“当前无赛事”分支，再从当前选项正常退出，随后Leave Area返回Campaign Map；
Campaign时间、金币、声望、队伍均未改变。
此为手动原生路径、0模型调用，EYC Host并未因此新增竞技场/锦标赛目标路线。
Build和AgentHostPackage通过；
菜单过滤、ArenaMaster白名单交谈、Tavern/Arena离场和Mission save fail-fast已由结构化状态/Native回执核验，玩家界面完整视觉捕获、竞技场报名/锦标赛VM及奖励仍未验证。

`CompanionHiring`是一项端到端Tavern原版对话验收：测试先读完整当前Native `missionSceneAgents`候选，避免把“周围近距离观察暂时没有旅人”误判成整个Tavern没有可用人选；随后按原版Town→Tavern→导航→交谈→报价流程验证原生对话。Test-only fixture只允许将Gold设到Native报价-63、报价或报价+1，用于验证严格`Gold > price`门槛在报价下方、相等及上方三种结果；该夹具动作不进入Agent决策白名单、不保存存档。验收核对报价文字、接受/拒绝选项、Clan/MainParty成员、金币前后值、源档哈希与进程清理，不直接调用原版Hire动作API。Harness阶段必须把内层PowerShell子测试的stdout/stderr写入阶段失败日志，不能只暴露退出码。

## Harness 架构

职责按事实来源划分，不复制状态：GitHub 项目板回答“做什么/顺序/当前工作项/是否被依赖阻塞”；Git回答“代码变成了什么”；Harness回答“本机游戏与工具实际上发生了什么”；Agent决策层回答“基于证据下一步做什么”。Harness输出不能覆盖GitHub卡片状态，也不能把测试指标当作产品自主能力；Harness不调用GitHub API/CLI。

```text
CLI 启动适配
            ↓
进程、模块集与 disposable save
            ↓
Mod 内状态、命令与事件遥测
            ↓
结构化断言、日志、检查点和 A/B
```

适配器优先级：

1. 原生 CLI/API；
2. 进程、日志和存档；
3. Mod 内遥测与白名单命令；
4. 只读窗口截图，仅在不激活/不前置游戏窗口且确有视觉诊断需要时使用。

TestResults的完整留存和历史清理策略见上文“Harness产物按可复核价值留存”，本节不保留第二份规则。

随包`--provider-self-test`覆盖整个AgentHost合同集，运行超过90秒时曾被旧进程上限误判失败；`Test-AgentHostPackage.ps1`现将该同一自检的等待上限设为180秒，检查范围和断言未变。

共享`AgentRuns/ChronicleAgent/events.jsonl`单文件上限16MiB，超限从新事件重新开始；逐轮trace保存在按上述规则保护的`TestResults`运行目录中。

不使用 Windows Computer Use 向游戏窗口发送鼠标或键盘输入：当前 `@oai/sky` 的窗口定向输入会自动激活目标窗口，不能保证不抢占用户前台或物理键鼠。游戏操作一律走 Mod 内版本化协议和 Harness 白名单动作；截图不是功能真值。若未来要恢复窗口输入，必须先证明后台窗口输入不会激活窗口、移动/占用用户鼠标或截获键盘，并以隔离测试验证，不能只因 API 接收了 window 参数就视为隔离。

## 统一状态与动作

状态至少包含：

```json
{
  "contractVersion": "...",
  "runId": "...",
  "processId": 0,
  "gameVersion": "...",
  "moduleSet": [],
  "screen": "title|campaign|map|menu|error|unknown",
  "campaignTime": null,
  "saveName": null,
  "lastCommand": null,
  "lastEvent": null,
  "lastError": null,
  "timestampUtc": "..."
}
```

环境动作目标为：

```text
start(modules, launcher)
load(save)
observe()
advance(hours|days)
pause()/resume()
save(name)
stop()
```

每个动作必须有命令 ID、前置条件、完成证据、超时、中断、失败分类和幂等边界。命令送达不等于动作成功，动作后必须重新观察。

Agent决策循环的Harness原型使用请求schema v3：每轮把明确Goal、由执行器同一白名单生成的可用动作/参数名、当前结构化观察、上一Native action receipt，以及最多8条只含“模型所选动作/参数与原版执行结果”的近期决策历史发送给Provider。历史不携带过去完整观察或自由文本理由；当前Native观察和最新receipt始终是游戏状态真值。它用于帮助模型跟踪已完成的目标步骤，而不能扩大动作白名单。每步记录Provider响应、原版动作和后验观察的UTC时点与耗时，供真实游戏窗体视频按同一时间轴抽取关键帧。`AllowedActionNames`可选地同时缩窄模型可见目录与执行端许可；W3-A首个真实模型尝试只开放只读`mapSettlementTargets`和原版移动`move`。决定仍在Provider返回后由本地白名单/参数校验，模型不直接调用游戏API；Harness确定性Provider只验证上下文契约，不算模型自主能力，也不是玩家交付运行时。

Agent决策循环的 `allowedControls` 与游戏动作目录分离，但同样按当前Native状态动态生成。只有执行器确认上一条成功移动仍在地图上自然推进、主队仍在移动且目标未到达时，才向模型暴露宿主侧 `observeAgain`；遭遇、对话/菜单、询问弹窗、暂停时间或无有效移动回执时，控制目录为空。执行器仍会在模型返回后重新核验，因此目录是决策约束和清晰反馈，不是安全边界本身。每轮收据同时记录交给模型的动作与控制目录，便于判断模型是选择了错误动作，还是当时根本没有看到可用操作。

移动中的新鲜观察不要求模型专门发起等待：若模型在下一轮直接调用一个允许的只读原版观察动作，且该轮输入明确看到主队仍在目标路上、Campaign时间自然推进，则这是有效的旅途观察；它和宿主侧 `observeAgain` 一样，只读状态、不改变游戏时钟。若短途移动在下一次决策前已到达，则目标Settlement的Native菜单观察与移动期间Campaign时间增量共同构成有效后验观察，不要求再发起多余等待。

在劫匪无选项对话阶段，执行器按状态区分两种转换：当前BarterVM尚未建立时先检查一次原生报价；该检查被Native拒绝后开放 `dialogueContinue`，让原版对话继续建立谈判界面。当前Native BarterOffer已接受后若对话仍暂时没有选项，则直接开放Continue并隐藏过期报价查询，避免在交易已完成后重新探测失效BarterVM。

Provider发现模型选择了当前合法动作、但参数名超出该动作当轮的白名单时，不得静默删掉额外参数，也不应把它伪装成游戏内动作失败。它返回带当前动作目录、合法参数名、非法参数名且明确标注“未发送给Native”的结构化拒绝；循环重新读取原版状态，把拒绝原因交还模型，并限制连续重试次数。其它参数形状错误或缺少必填参数继续失败关闭，直到建立对应的可验证恢复契约。

真实Provider只对尚未收到HTTP响应的TCP连接/名称解析失败自动重试一次，随后停止并记录安全的HTTP状态、主机和内层异常类型；不重试超时或已收到的HTTP错误响应，以免结果不确定时重复生成并产生重复费用。外部服务响应正文、Authorization头和密钥不进入失败日志。`CHRONICLE_LLM_THINKING_MODE`可选地把OpenAI-compatible `thinking.type`设为`enabled`或`disabled`；未配置时不改Provider原来的默认值。DeepSeek Flash默认为Thinking模式，这个选项用于针对结构化动作评测控制推理模式，不更换模型或改游戏动作。

Native Barter目录按当前VM会话和成功回执逐阶段开放：没有当前BarterVM时只允许读取选项；读到当前Safe Passage报价后开放自动平衡，暂不允许提交；自动平衡成功后在同一会话中隐藏重复读取/重复平衡，开放当前可用的Offer。报价编辑、重置、取消或提交会使已平衡标记失效。Offer回执若被Native接受但Encounter仍打开，且当前对白没有可点击选项，Host保留已接受回执并仅开放一次原版`dialogueContinue`显示的“点击继续”；随后重新观察状态，若遭遇仍未清除即安全停止，不重提报价或选择战斗。这样既不会把Barter回执误当成界面已关闭，也不会因重复调用“读取/自动平衡”困在无进展循环。

真实模型验收收据记录配置中的模型标识、Git源码提交、被跟踪文件是否干净、Campaign日区间与运行UTC区间；不记录API密钥或服务端点。用于结束产品Issue的真实模型结果应在已提交源码上复跑，使收据提交号就是实际被测试的代码版本。

时间模式运行时世界自然推进；移动不补发 `advance`。地图点击副作用和 WaitMenu 自管时钟按原版复现。`advance/pause/resume` 仅显式 Harness 时钟工具，不嵌入普通动作。

## 验收阶梯

| 层级 | 必须证明 | 自动证据 |
| --- | --- | --- |
| Docs | 文档路由、主线层级、引用/hash/复核和契约一致 | `Check-Docs.ps1`；Harness收据另记Git commit/脏树 |
| Preflight | 本体、项目、清单和工具存在；存档头模块列表的解析、顺序保留、损坏拒绝 | JSON 清单与合成存档元数据回归 |
| Api | 当前 DLL 存在目标签名 | API Probe 输出 |
| Build | 游戏内Mod针对当前DLL编译；外置本地Agent Host单独构建为.NET 8进程 | Build收据分别保留Mod与Host构建输出/退出码；Bannerlord运行时不编译或覆盖已加载DLL |
| Smoke | 清单、DLL、`OnSubModuleLoad`、`Finished All`与MCM已注册的Chronicle设置定义（模型URL/名称、战役目标、配置检查、启动/停止/状态按钮）；只对严格匹配的着色器缓存弹窗执行有界进程内确认，对未知 Warning 只读采集、不乱点 | 同 PID RGL/错误/Watchdog日志副本、结构化Smoke结果及MCM属性ID/按钮ID；Harness模式从游戏启动/主界面阶段显式传入并核验Start/Stop/Status为Button；Native初始化、程序集生命周期和MCM完整注册均就绪后立即结束启动等待，再单独完成稳定性窗口；收据记录StartupReadySeconds/ElapsedSeconds/超时上限及实际ModuleIds。安全识别的UIA弹窗信息，MCM注册尚未就绪时持续探测至Harness超时，不能在启动视频期间以30秒内未注册提前判缺失；Campaign尚未开始且Native视频允许CanUserSkip时，仅在Smoke/生命周期模式调用原生StopVideo（与ESC同一入口），不发桌面输入。失败时保留子测试输出，超时与实际崩溃分开 |
| Campaign/FreshCampaign | 旧档；FreshCampaign新Sandbox原生创建、跳intro、选+20；Progression用临时存档重载再move/arrival/recruit | 同PID renown20/MapState、非激活840x472；Crash Report仅按明确信号有界重试；已知`Mod change detected`着色器缓存提示仅可经精确匹配的目标进程UIA按钮有界最多3次确认，不用全局输入；临时存档精确清理、非模型Provider |
| Protocol | CLI 启动/重载、状态、Native Pause/Play/FastForward、Harness-only独立推进时钟、Campaign保存/跨进程读档、外置Host只读Native状态握手与Native拒绝回执、停止 | Native时间选择对照`Campaign.SetTimeSpeed(0/1/2)`，检查raw/effective模式和waiting状态；固定advance仅用于Harness测试并按日目标或Encounter返回；存档往返使用唯一测试名，比较Save前与新进程读档后的结构化Campaign指纹及Chronicle SyncData计数、源夹具哈希后删除；外置Host三次读状态须与同一PID/MainHero/Clan/MainParty回执一致，且前后Campaign指纹不变；假邮箱覆盖繁忙/错关联ID/超时；一次故意无效的Native Menu option必须获得严格JSON可读的拒绝回执且不改变Campaign。`AgentProtocol.Escape`转义所有JSON控制字符，避免异常堆栈的CR/LF破坏IPC响应。时间步进不得隐式塞入地图移动/追近命令 |
| AgentHostProvider | 本地Host的IPC邮箱回归、MCM Global Provider profile校验与OpenAI兼容结构化决策Provider | 可单独 opt-in；假Mailbox测繁忙/关联ID/超时，假HTTP Handler覆盖请求schema、格式/解析错误、截断、越权动作、HTTP失败及超时；Host在任何Native动作前以只读`GET /v1/models`区分模型缺失/服务不可达，不生成模型响应；确定性Provider用Campaign与补给目录验证共享决策循环；严格输出schema使用对象根与嵌套`anyOf`，再由Host按当前Native动作目录逐字段归一化/校验；Global profile与Start配置快照共用URL/模型校验；回归检查Host使用当前快照，坏快照被拒后不回退旧profile；不加入`All` |
| AgentHostPackage | 为Windows x64用户打包可在未安装.NET时运行的本地Host | 单独opt-in；从源码发布self-contained win-x64目录到D盘仓库外的暂存目录，避免运行时DLL进入源码树影响Mod编译；NuGet包走7890代理且缓存放D盘；在与publish目录不同的工作目录直接启动Host `--package-health`/`--version`及无模型`--provider-self-test`，核对内嵌运行库、协议/架构、决策循环安全回归、Host父进程PID/启动时刻绑定及退出监护、文件SHA256清单、不含用户配置及进程退出；额外用一次不存在的Bannerlord PID验证拒绝发生在任何Native邮箱写入之前；不启动Bannerlord、不修改正式模块、不加入`All` |
| ReleasePackage | 为管理器安装制作Chronicle模块+自包含Host压缩包并验证隔离更新/回滚/卸载 | 独立opt-in且不运行通用Build阶段；从干净stage编译Mod DLL并发布win-x64 Host，按模块manifest声明Native/SandBox及Harmony/MCM前置依赖版本，写入版本/客户端基线/文件SHA256 manifest与zip校验和。重复构建比较包SHA；解包到D盘隔离游戏根，官方目录以junction复用、发行模块单独复制，运行原Smoke/MCM注册并核对路径确实指向隔离副本；隔离Smoke必须从原始安装根单独继承`CHRONICLE_STEAM_ROOT`，不能从临时overlay推导Steam目录。`TestResults/20261026-170915`通过：归档可重复，模块清单/键位本地化资源和原版选项VM smoke通过，隔离安装/更新/回滚/卸载不改官方模块、全局MCM配置或正式存档。游戏关闭时用仅改变manifest版本的fixture执行v0.1.0→v0.1.1→rollback→uninstall，逐步核验模块hash/Required modules/全局MCM配置/正式档hash。该版本fixture不代表新代码或配置迁移。Host退出及父进程监护由W7-H生命周期测试覆盖；不打包Harness、PDB、用户配置或模型权重；私测包明确未授权公开再分发；不加入`All` |
| AgentHostSupplyEvaluation | C# Agent Host 使用本地Qwen循环控制当前MainHero/MainParty完成固定三日补给切片 | 独立opt-in，复用W5 Native起点/完成门槛；3次同存档起点记录Host决策、Native动作、每日Tick/资源结果、录像覆盖与清理。测试前Prelude只负责建立六人起点；模型决策不得由Harness替代。Harness视觉阶段显式注入用户已有Provider环境配置；产品运行路径改读MCM Global `FormatType=json`本地profile。Native `rest` accepted后Host用只读轮询等待三个自然Campaign Tick，并在当前`wait_leave`可用时提交一次原版菜单选择；不调用显式时钟API，不逐次调用LLM，且超时仅在安全入口可用时尝试停止原版Wait。若等待被中断则基于新Native状态安全返回/停止；若冻结完成条件未满足，Host停止且不重复交易。此阶段不覆盖全Campaign和其他182项行为，不加入`All` |
| AgentHostCampaignLoopEvaluation | C# Agent Host 的通用决策通道与有界地图到达闭环 | 独立opt-in，真实本地模型从原生观察中选取安全可见聚落、经Native `move`前往、移动中只被动重新观察，且只在Native当前位置确认抵达后结束；必须证明Campaign时间由游戏自然推进、不发送时钟动作、行动白名单、录像覆盖及源存档/进程清理。另有无模型回归通过注入假的Native邮箱/Provider跑完整Host循环，覆盖初始只读观察、风险筛选、移动期间唯一观察控制、抵达门槛、超时后动作不重放；Provider/包回归还用地图查询与补给报价两种动作目录核验同一决策通道。属于有限地图切片，不代表182个Campaign行动完整支持，也不加入`All`或替代Epic的最终玩家验收 |
| AgentHostLifecycleEvaluation | MCM目标/启动/停止/状态入口与随包Host生命周期实测 | 单独opt-in；先Smoke核验MCM属性和按钮注册，再打包Host，在一次性Campaign中用独立临时设置验证空/超长目标、外部地址、空模型及缺失Host的五种启动拒绝，然后调用已注册的MCM Start/Stop Action委托并重复Start验证仅一个Host；Host须报告协议/版本/Native PID握手成功后游戏内状态才转为Running，运行期间持续监护发起它的Bannerlord PID及进程启动时刻；Stop在握手后短窗口内触发，使用严格限于本次TestResults临时目录的Harness idle provider，不依赖Ollama服务、不生成模型、不发Native目标动作；核验Start→Running→Stopping→Stopped、父子PID、握手版本/当前Native PID、停止后游戏仍可查询Campaign、过期Native会话请求被拒且金币/位置不变、源档hash与CLI会话清理。实际按钮视觉点击留至Epic验收；不使用Windows桌面键鼠、不写正式存档；不加入`All` |
| AgentHostLifecycleCompletionEvaluation | 游戏内Start启动真实本地模型，先分类目标，再完成有界安全地图行程或拒绝超出范围的目标 | 独立opt-in；Complete场景用现有本地4b模型，要求首轮目标分类后仅开放一次地图查询、选取当前安全目标、经Native `move`前往并在当前settlement后验后Completed；记录模型/来源/决策数/动作数/Token计数、日期及清理摘要，不保存完整Prompt/原始回复/trace。UnsupportedGoal场景用“Become clan tier 1 (50 renown).”，要求一轮分类后`campaign-goal-unsupported`、零Native游戏动作、战役仍可读取；两条路径均要求重复Start仅一进程、错会话拒绝、源档hash及进程/session清理。不得发送时钟动作。这只验证两个目标样本，不证明任意自然语言分类或完整战役；不加入All或替代Epic视觉验收。 |
| AgentLoop | 外部Provider进程接收版本化决策请求，选择白名单动作并重观察 | 请求schema v2含显式测试Goal、由同一执行白名单导出的动作/参数目录、当前观察与上一Native receipt；可选动作子集须同时缩窄模型可见目录与执行端许可；每步记录provider/action/observation的UTC时点和耗时；确定性Provider回归核对上下文续传/动作集合；OpenAI-compatible Provider把配置的`/v1`基础URL解析为`/chat/completions`请求路径，云端默认使用`max_completion_tokens`、`store=false`及JSON response mode（兼容端可显式切换token字段）；可选`CHRONICLE_LLM_REASONING_EFFORT`与`CHRONICLE_LLM_TEMPERATURE`仅在显式配置时转发，供Ollama等思考模型关闭推理并稳定结构化决策；有序目标步骤必须以完成的前序Native receipt为门槛，不能因后续动作看似可行而跳过；大型`mapSettlementTargets`回执仅在模型输入视图中压缩为最近安全候选与少量风险候选，并显式携带总数/省略数，原生回执和Harness追踪不变；本地Ollama兼容Stub核对`max_tokens`别名、推理/温度设置、大型回执压缩、loopback无密钥请求与JSON响应；通用HTTP stub核对鉴权头、结构化输出、越权动作/401/超时失败关闭及secret不回显；随后AgentLoop回归核验时序字段、前序回执、中文主角名往返、超时/无效动作拒绝、fixture哈希与进程退出。所有stub/确定性Provider只验证协议，绝不作为真实模型能力证据。 |
| LiveModel | 显式进行一次真实Provider与Campaign闭环验证，不包含在`All`中 | 要求当前没有已运行的Bannerlord客户端，且本地Provider URL/model已配置；只允许`mapSettlementTargets`和`move`，要求模型先查当前可见的安全聚落，再对本轮观察到的目标发出一次Native移动并主动停止；同一轮记录Provider/动作/后验观察UTC时点，对指定Bannerlord HWND连续录制并按事件抽取真实窗口关键帧，同时保留引擎截图前后对照；验证帧覆盖、目标匹配、测试存档哈希及进程清理。只要联系表、时间线索引和事件关键帧生成完成，无论模型通过还是失败都删除原始MP4；只有采集/解码/索引失败时保留不完整片段和失败引擎帧。Native协议事件日志单文件上限16 MiB，超限时清空旧事件后继续追加；完整任务回执保存到对应TestResults目录。该阶段会向配置服务发送当前Campaign观察并可能产生模型费用；HTTP stub不能替代它。 |
| MapPartyQuestMarkers | Campaign Map当前`mapPartyTargets`观察；visual Harness只在disposable Campaign用Native `IssueManager.CheckForIssues/CreateNewIssue`创建一个合法Issue候选 | 创建前目标无AvailableIssue、创建后AvailableIssue、另一Party空标记负向、未名牌资格目标null；重复读取稳定、无Quest文本、原生前后帧、源档hash和进程清理。Issue fixture不加入产品，也不接取任务 |
| MapPartyQuestAcceptance | 从`mapPartyTargets`可见且有AvailableIssue的Lord Party开始，原生map/Escape菜单未遮挡后，通过Native `pursue`进入`encounter_meeting`；只沿本轮Conversation合法选项启动一条Issue Quest | `TestResults/20261003-110250/Temp/MapPartyQuestAcceptanceResult.json`通过：临时Native TheSpyPartyIssue有效候选进入同一Lord地图会面，动态问候/hero_give_issue/issue说明桥接，最终仅提交Enabled Quest接受选项；`issue_153_quest`为该Hero QuestGiver、活动Quest数0→1/期限16天。Day 91077.378→91077.397为地图行程自然推进，接受时Stop/金币1000不变。原生三帧、源档hash和进程清理通过；Harness初试105312/110002的回执断言缺陷已修复，并保留失败证据 |
| TimeControlLoop | 确定性测试Provider在真实Agent循环内依次选择原生Play、Fast Forward、Pause，再用第二个临时进程验证Hold→Play | 验证动作经CLI/协议调用Native `Campaign.SetTimeSpeed(1/2/0)`、raw/effective档回执；比较各时钟档间的自然CampaignDay推进与Pause稳定性；Hold使主队等待后，显式Play应恢复`UnstoppablePlay`并自然推进而保持waiting；Harness advance隔离、fixture哈希和所有进程清理；与只读AgentLoop分离，避免遭遇状态污染 |
| BattleFixture | disposable save 内造 hostile looter；用原版 pursue 点击语义接敌 | hostile/party ID、自然时间/encounter 回执、fixture 哈希、进程退出；造敌非 Agent 行为 |
| BattleMissionFormationProbe | opt-in StoryMode测试源经Native SaveAs生成一次性副本；走原版Attack→Deployment Ready→Battle/F6，回读MainAgent当前Formation/Detach、主角状态和Native Aftermath | 0模型请求/0手动键鼠；检查源save hash、临时副本hash并仅Hash相同后删除、Campaign Stop、MainAgent control/formation、Native MissionEnd/Aftermath、进程清理；不把单一战斗样本作为通用安全结论 |
| BattleSimulation | 原版 `Send troops` 启动；pause/skip/finish/retreat；Mission TAB retreat | 模拟状态、结算/loot、Mission end、fixture hash；不等同即时战斗 |
| PostBattle | Simulation skip/finish→encounter leave→PartyState transfers→conditional InventoryState loot/Done→MapState | troop/item counts, state timeline screenshots, fixture hash, process cleanup |
| VisualCapture | 引擎单帧参考图 + 按 Bannerlord HWND 连续采集 30fps；只验证采集链，不是玩法真值 | Contact sheet/时间线关键帧、覆盖率、fixture hash、进程清理；事件帧时间戳夹到最后一个实际视频帧，JPEG编码强制full-range像素格式。只要解码与索引完成，不论玩法断言通过或失败都删除源MP4；只有采集/解码/索引中断的片段暂留以便恢复。协议事件日志另有16MiB上限；不录全桌面，不进默认 All |
| Conversation | 观察原版句/选项；`DoOption/ContinueConversation` 需满足原生条件 | 选项/回执/菜单迁移；不预测未开放选项 |
| Observation | 玩家身份、队伍、资源、坐标、移动模式/目标、上下文、附近实体与其移动/定居状态、任务与危险；记录数据来源、原版可见/侦察标记和所采用的情报策略 | 两次暂停快照、稳定 ID/位置、字段新鲜度和 fixture 哈希 |
| CaptivityObservation | Harness-only Native `TakePrisonerAction`置入MainHero Captivity；打开原版Wilderness ransom菜单并将当前Menu切到Native Wilderness Escape Continue屏，两个阶段都只读、不点击选择 | `TestResults/20261002-051747/Temp/CaptivityObservationResult.json`通过：`context.captivity`在Captive为真/非Captive为null；菜单报价188与Native `CurrentRansomAmount`一致、Accept/Decline Option ID匹配；Escape Continue阶段报价为null且唯一`mno_continue`可见；重复读数稳定、菜单切换不改CampaignDay/Gold/Roster，双引擎截图、源存档hash和清理收据；不声称复现自然战败或逃脱概率/结果 |
| CaptivityOutcome | 两个新Campaign进程加载同一个不变fixture；各自先验证无效菜单项被安全拒绝，再从当前Native赎金菜单提交可见的Accept/Reject；核对Gold、MainHero囚禁/主队/Captor roster、菜单与原生时间档、前后引擎截图和清理 | 共用参数化后回归`TestResults/20261002-062355/Temp/CaptivityOutcomeResult.json`通过：两个无效Option均拒绝且菜单/金币/时间未变；Accept报价331使Gold 1000→669、MainHero恢复并回主队/Captor roster归零、日期不变；Reject报价305、Gold不变且仍被Captor拘押，返回`prisoner_wait`后时钟Stop→UnstoppableFastForward并自然推进0.102737日；四张Native引擎帧、原Campaign fixture hash不变、两次进程清理。结果不覆盖自然战败/入狱过程与后续Captor政策 |
| CaptivityOutcome | 两个新Campaign进程加载同一个不变fixture；各自先验证无效菜单项被安全拒绝，再从当前Native赎金菜单提交可见的Accept/Reject；核对Gold、MainHero囚禁/主队/Captor roster、菜单与原生时间档、前后引擎截图和清理 | `TestResults/20261002-055501/Temp/CaptivityOutcomeResult.json`通过：两个无效Option均拒绝且菜单/金币/时间未变；Accept 244报价使Gold 1000→756，MainHero恢复并回主队、Captor roster归零，日期不变；Reject报价244，Gold不变且仍被Captor拘押，回到`prisoner_wait`后时钟Stop→UnstoppableFastForward并自然推进0.104924日；四张Native引擎帧、原Campaign fixture hash不变、两次进程清理。结果不覆盖自然战败/入狱过程与后续Captor政策 |
| PrisonCaptivityOutcome | 同一disposable Campaign源分别启动Accept/Reject两个进程；Native MainHero captive归属Town settlement roster并进入实际Native Prison ransom菜单，当前有效/无效选项、报价、金钱、Party/Captor、Settlement等待时钟、前后引擎截图和清理 | `TestResults/20261002-061905/Temp/PrisonCaptivityOutcomeResult.json`通过：报价菜单原生报价可见，黑暗地牢截图与两条可用选项一致；Accept 2689使fixture Gold 10000→7311并解囚回MainParty；Reject报价2236、不扣钱仍Captive、返回`settlement_wait`，Native时钟Stop→UnstoppableFastForward、日期自然+0.106295。临时战争仅用于使源版captivity检查保持Captor敌对，金币补足仅用于Accept可用；无效Option被拒、4帧、源存档hash不变、进程清理。初试失败已保留在`20261002-061453`，原因是测试Captor与玩家和平导致原版合法释放；自然押送/触发流程未覆盖 |
| EncounterSurrender | Native hostile Bandit meeting→当前可见Fight选项→MapEvent/Encounter菜单→Native条件启用的Surrender；核验前后Party/Captor/Captivity/时间与引擎帧；不调用私有后果或伪造MapEvent结果 | `TestResults/20261002-064814/Temp/EncounterSurrenderResult.json`通过：复用Native Bandit meeting/Fight到`encounter`；在该活动Encounter里Native Hero伤病+Morale=0门槛成立后，真实菜单显示Fight/逃跑/投降并由当前`surrender` option结算；Captured状态结构字段确认MainHero加入Bandit PrisonRoster、主队inactive、Gold未变，屏幕后帧为原生`prisoner_wait`且没有Continue选项；Stop→UnstoppableFastForward为等待阶段自然推进，三张引擎帧（Bandit meeting/Encounter前/ Captivity后）、源存档hash不变、进程退出。测试只覆盖一种原版可用条件/野外Bandit遭遇；没有捕捉瞬态`taken_prisoner`菜单、没有模拟其他条件/围城或逃离失败 |
| EncounterEscape | 两个独立Campaign进程通过Native Bandit fight进入Defender Encounter；从当前`leave_soldiers_behind`和warning屏可用选项分别走Reject/Accept，核验Native TroopSacrificeModel/兵员/商品/时钟/debrief/清理 | `TestResults/20261002-071124/Temp/EncounterEscapeResult.json`通过：原生警告模型预测失去7人；Reject回到当前Encounter且Party 13人/grain20/Gold1000/时钟/日期全无变化；Accept后Native party 13→6、商品grain20→17（15%向下取整为3），debrief画面显示原版脱离说明，按Native Continue后Encounter关闭。风险说明/选项/脱离结果共8引擎帧，两分支均源存档hash不变、进程清理；CampaignDay=91077.378787、TimeControlMode=Stop保持不变。Troop/Grain仅在disposable进程中用Native roster写入，测试未预置loss结果 |
| JoinEncounterDefenders | Harness Native `StartBattleAction`只构造NPC-vs-NPC持续MapEvent；MainParty未加入时以可见Party目标执行原版pursue，选择当前菜单唯一可用Help Defender后核验同一Event的DefenderSide与Encounter菜单，不开始战斗 | `TestResults/20261002-074242/Temp/JoinEncounterDefendersResult.json`通过：当前玩家对Bandit攻击方敌对、对Lord防守方中立；引擎帧显示“帮助防守方/不参与”，无双侧选择。通过原生可见 Party target + `pursue`抵达`join_encounter`；Native `menuSelect`后仍为EventID0，MainParty只在DefenderSide、`IsJoinedBattle=true`，当前回到`encounter`选择Fight/坐镇，未启动BattleSimulation。Gold/成员/日期91077.402347/时钟Stop不变；前后截图、源存档hash、进程清理。NPC对NPC MapEvent只由Harness Native `StartBattleAction`准备，玩家Join本人完整走菜单；第一轮Event因攻守强弱悬殊在到达前自然结束，第二轮将测试双方力量调至接近后通过。中立双方“不可加入”尚只由用户事实与Native CanPartyJoinBattle条件推导，未实跑 |
| JoinEncounterEligibility | 独立disposable进程分别测试Help Attackers与双方Neutral；Native事件和NPC faction关系由Harness fixture准备，玩家以当前可见地图目标和原版pursue接近；仅攻击方正向提交实际可用Help，双中立只观察 | `TestResults/20261002-081603/Temp/JoinEncounterEligibility-HelpAttackers.json`与`...-Neutral.json`通过：攻击方正向UI只开放Help Attackers/Leave，选择后MainParty在同一MapEvent AttackerSide并回通用Encounter菜单；双中立页面只开放Leave，双方Native `CanPartyJoinBattle=false`且MainParty未入场。三张原生游戏帧保留；Campaign时间只在途中自然推进，选项前后Day/Stop不变。两轮源档hash不变、Agent停止且无Bannerlord残留进程 |
| JoinEncounterAbandonArmy | 玩家先经可见地图目标与原版pursue进入JoinEncounter；visual Harness在该原生页面通过Native Kingdom.CreateArmy准备MainParty非Leader成员并刷新同一注册菜单，再提交实际Abandon Army选项 | `TestResults/20261002-090646/Temp/JoinEncounterAbandonArmyResult.json`通过：Army成员页面仅显示Help Defender和Abandon Army、普通Leave被过滤；选择弃军后MainParty从Army成员移除/AttachedTo清空，PlayerEncounter关闭回MapState等待，NPC MapEvent EventID0仍未决且无胜者、主队Hold。Day91077.402299/Stop、Gold与双方Influence/战争关系不变；前后Native帧，存档hash不变且进程退出。成员准备是Harness Native `Kingdom.CreateArmy`，非Army Management视觉流程；先入Army再自然追近未复现，属于未覆盖路径 |
| MovingArmyJoin | 针对用户确认的未交战地图行军Army：Harness用Native ChangeKingdomAction/Kingdom.CreateArmy准备Disposable同Faction Army，玩家经当前可见marker与原版pursue进入`army_encounter`，再提交原版Join Army | `TestResults/20261002-165845/Temp/MovingArmyJoinResult.json`通过：Native Army leader处于GoToPoint行军、无MapEvent/SiegeEvent；`army_encounter`显示Talk/Join Army/Leave，加入后MainParty成为Army member且AttachedTo Leader、PlayerEncounter关闭，回`army_wait`。Join命令即时回执为Stop/Day91077.405；后续原版WaitMenu切`UnstoppableFastForward`，世界日期自然推进至约91077.516。Gold/玩家及Army Leader Influence不变；前后引擎帧、源档hash与进程清理通过。政治加入/Army Management视觉流程和围城Join未覆盖 |
| JoinSiegeEvent | 在disposable Campaign中准备当前可见Town/Castle的Native SiegeEvent；通过`move`到原版`join_siege_event`，只选择当前可用的“Join the continuing siege”；核验PlayerSiege、BesiegerCamp、菜单、资源、时钟、存档hash与清理 | `TestResults/20261003-091025/Temp/JoinSiegeEventResult.json`通过：旧`move`安全策略拒绝所有敌对Settlement，导致第一次尝试在测试夹具的萨哥特原生攻城事件处被拦，失败留据`20261003-090333`；修正为仅当非Blockade、无Settlement MapEvent且Native `CanPartyJoinSide(Attacker)`为真才允许地图导航后，菜单截图显示“加入继续围城/不参与”，选择前状态为SiegeEvent active、双方MapEvent空、MainParty尚未加入；Native选择后进入`menu_siege_strategies`，`PlayerSiege.PlayerSide=Attacker`、主队在BesiegerCamp、PlayerEncounter结束、没有自动启动Mission。途中地图导航将时间档自然变为StoppablePlay；Native围城准备将档置`UnstoppablePlay`，CampaignDay 91077.400375→91077.431638；Gold 1000不变、fixture前后Influence -1不变（入场时政治转换为Battania仅为Harness夹具）。保存before/after游戏引擎帧；源档hash一致、测试进程已停止。加强资源断言后`20261003-091720`第二轮在地图接近中进入`join_encounter`而不是围城页；失败帧显示Native“帮助作战军团/不参与”选项，未提交选择；具体关系/MapEvent细节未单独记录，因此作为可能遭遇分流而非本验收成功。已通过的结果可计算资源不变断言为真。未覆盖已存在Settlement MapEvent的战斗加入、守方Break in、攻营、Blockade、海战及之后围城战斗/Mission |
| Movement | 从原版可见聚落marker观察选择Settlement ID，下达原版路径目标并复现普通地图单击时间档位；Harness独立显式步进至抵达，并复用抵达回执中的原生菜单观察 | 目标/菜单/时钟轨迹、失败拒绝、fixture hash；子测试stdout/stderr原文保存在父Harness阶段失败收据，若游戏仍响应则捕获引擎末帧 |
| Hold | 按原版Map点击语义从正在移动主队切到Hold；动作后不发Pause/Resume/advance，观察Native waiting与CampaignDay | 当前目标清除、defaultBehavior、raw时间档/isWaiting和短自然窗口的日期差；disposable fixture hash、进程清理；失败尽可能留游戏引擎末帧 |
| MoveToPoint | W2-B仅在陆地用Campaign世界坐标请求有效自由地形点导航；适配层验证CampaignVec2/Face与原版导航模型，通过MapState.ProcessTravel而非直接写位置；Harness可显式步进至目的地 | GoToPoint与location.targetPosition对齐、初末坐标变化/到达、无效Face拒绝且不移主队/切时钟、原版点击时钟模式、fixture hash/进程清理；海上/港口另行验收 |
| Recruitment | 仅当当前Settlement菜单有`recruit_volunteers`可用项时，读取/招入指定Native RecruitmentVM offer；通过显式 `ConfirmPartySizeWarning` 选择是否接受原版超限Inquiry；Detached VM按原生Gauntlet hotkey/GetKeyText绑定初始化并在每次查询/事务后Finalize；同一运行复验Town Trade买卖/食物补给 | menu ID/option/Native VM offer、Roster/Gold、原版Over Limit提示及affirmative回调、off-menu/invalid报价无副作用、容量边界的raw time/date、受限Harness fixture/hash/进程清理；不模拟点击焦点；失败收据保留子测试原始stdout/stderr |
| Rest | 通过原版 `town_wait` 进入 native Wait menu（`StartWait` 自行启动时间），观察指定时长后由原版 `wait_leave/EndWait` 退出 | Wait menu/time mode、native 持续时长、离开后 Stop、非法/中断路径和 fixture 哈希 |
| Pursuit | 在大地图对当前可见且可导航Party分别下达原版 `EngageParty`/`EscortParty`；`hold` 复现点击玩家队伍。Escort等价于按住`MapFollowModifier`点击Party；所有有效点击复现同一原版点击时间档位规则 | 正确TargetParty/DefaultBehavior、native click time mode、Escort目标/无效目标和无副作用拒绝、Engage自然前进到遭遇或目标丢失Hold、fixture哈希 |
| EngageVisibility | 在一次性运行中显式暂停Campaign以稳定准备场景；用Native `BanditPartyComponent`生成初始位置有效、原版`IsVisible`自然判定的弱劫匪目标，只为场景测试临时增加主队普通兵力差。确认目标可见并截图后由产品`pursue`发出Engage，观察自然移动、主队Hold及`Campaign.IsMainPartyWaiting`；Hold后再观察稳定窗口，区分原始TimeControlMode与引擎有效暂停 | 目标原生可见性消失前后快照、`isWaiting`、原始时钟档/日期、Hold稳定窗口、前后引擎关键帧和源fixture hash/进程清理；初始位置和兵力差属于明确标注的测试夹具，不在追击中传送/改AI/改`IsVisible`/脚本推进或暂停时钟 |
| Conversation | 从Campaign Map用原版Party追近抵达Lord会面；观察实际开放Sentence/Option并选择一个低副作用自我介绍；invalid option必须拒绝，Continue仅在CurOptions为空时允许 | native Conversation/参与对象/option ID前后状态、时间/遭遇迁移、无效选项无副作用、存档hash/进程退出；不代表Quest、Barter或Persuasion支持 |
| QuestAcceptance | 在真实Lord会面里选当前有效的`hero_give_issue`入口，沿Issue brief/解决方案分支只接受原生开放的Quest解法；不调用IssueManager创建任务API | `issue_offer_player_accept_quest`后的active Quest/Issue状态、Quest ID/标题、费用/关系/时间副作用与失败存活分支；不包含Alternative/Lord Solution和Story/Notable任务 |
| EscortVisibility | 一次性存档选择当前可见范围内最远的活动移动Party，按Follow修饰键语义设置Escort；只观察自然时间窗口，不显式advance/pause；记录目标是否离开Chronicle附近队伍观察集以及原生Escort/时钟终态。离开观察集不等于证明引擎`IsVisible=false` | `AgentPursuitVisibilityResult.json`、目标ID/初末观察/模式、自然时间变化、fixture哈希、进程退出；未触发目标离开时如实记录窗口结果，不伪造目标失明 |
| TavernMission | 从Campaign Map自然抵达城镇，沿`town_backstreet → town_tavern`进入酒馆；确定性Provider根据本地Agent位置和主角朝向计算一次短时移动，并在有候选时试用Sandbox AgentNavigator | 验证实际位移、目标距离缩短、MovementInput lease清零、AgentNavigator的NavMesh路径/Player Controller限时切换与归还、Campaign时钟保持Stop；截图、源存档hash及进程清理。样本不是Notable/委托接取，不代表W2-D完成 |
| TownCenterMission | 从Campaign Map自然抵达城镇，选择`town_streets`进入`center` Location Mission；确定性Provider短步探索，在当前局部Agent出现后尝试复用原版`SandBox.AgentNavigator`路径到该Agent，再试相机指向与Focus | 结构化前后位置、NavMesh路径是否生成/脚本移动是否实际产生位移、当前12单位内Scene Agent清单/Notable标记、相机bearing、原生Focus AgentIndex、Campaign时钟、引擎截图、fixture hash及进程退出；baseline成功不保证已到Notable或Focus命中，不能声称Quest/对话可用，也不扫描整场景给决策器、不传送、不接受Quest |
| Event | 事件按预期且不重复 | 带时间和 PID 的遥测 |
| Save | 自定义状态保存并恢复 | 保存前后结构化快照 |
| World | 原版行为只发生目标变化 | 同夹具 A/B 对照 |

“启动”“主菜单”“加载 DLL”“进入战役”“事件触发”“存档恢复”是不同命题。没有对应层证据只能标记为未验证。

## 原版增强测试

```text
同一 disposable save + 基线模块集
        ↓
记录行为与状态
        ↓
同一存档副本 + Chronicle
        ↓
记录候选结果
        ↓
断言只有目标语义变化
```

一次变更只推进一个验收层或一个消费者。新 API 先 Probe；行为代码先只读；写入原版状态前必须有基线、回滚和回归测试。

## 长时间运行与恢复

- 使用检查点推进，不进行一次性盲等；
- 每个检查点保存状态、最后命令、事件计数、进程健康和 disposable save；
- 异常立即保存最后证据并停止；
- 最多进行一次自动恢复，重复确定性故障转入模块二分或代码定位；
- 测试器主动结束进程不算崩溃；
- 任何正式存档都不得被测试器覆盖。
- Smoke 必须按本次启动新增的诊断行和实际 Bannerlord 子进程 PID 归因；不得用启动器返回 PID 或旧日志推断模块生命周期。失败时持久化`SmokeResult.json`及同PID日志；已知着色器弹窗只允许使用经UIA识别的进程所有控件确认一次，其他警告只读取证据、不通过全局键鼠输入。
- Campaign 阶段必须使用版本化 disposable fixture；第一轮通过必须包含 `campaign-sync mode=save`、每日事件、另存文件、第二进程 `campaign-sync mode=load` 和未改动 fixture 哈希。
- ButterLib DLL 报告含托管栈/模块及可选 MiniDump；Harness 在报告 UI 阻塞前复制异常栈与 MBMusicManager/CampaignMusic 状态。FreshCampaign 等 native music 初始化后再开档；progression skip flag 到 MapState 后不再调用 Issue probe。保留fault-IP映射/关键帧，不点报告窗。
- ButterLib 当前回退到 1.4.7 implementation；同样回退见通过的 `Fresh 215022`，是兼容风险但不是本次根因证据。
- Progression `045339` deterministic provider 验证 Fresh→CampaignTick SaveAs/CLI load→移动→招募1人；保留回执与费用前后值，并确认临时存档清理、原存档哈希未变。
- FreshCampaign日志尾投影DTO，禁直序列化Get-Content。
- P2 原子 JSON；`captureFrame` 仅 visual Harness 可用且输出 BMP。FFmpeg `gfxcapture(hwnd=...)` 只采游戏窗；校验覆盖率并生成状态/动作 JSONL、缩略图和关键帧。所有已完整后处理的 MP4立即删除，不以测试通过/失败决定；仅后处理未完成的片段保留。Agent 按索引看图。Native协议`events.jsonl`单文件限16MiB，超限清空旧记录后继续；本轮完整trace仍存对应TestResults。Loot All/Done 限原生InventoryState，seedVisualLoot不代表自然掉落。
- Continuous MP4 uses fragmented output with an empty `moov` and keyframes at two-second intervals so a forced Harness/session termination still leaves a decodable prefix; a normal stop validates coverage and generates event-aligned keyframes, then deletes the raw MP4 regardless of gameplay outcome. Only an interrupted/unindexable prefix is retained for recovery, and is removed after recovery output is captured.
- Progression证据保留初始Renown、招募回执/净变化、存档周期验证；清理后存档哈希不变。
- Protocol 若暂时无法读取 `.processing` 命令，保留 claim 并延迟重试，不删失/丢弃命令；Docs 检查此恢复契约。
- W7-B 的 `agenthost/` 是目标玩家产品的本地 .NET 8 Host，不属于游戏线程，也不是Harness决策器。当前只提供一次只读 `state` 握手：写入独立关联ID，拒绝覆盖已有`command.json`，只接受关联ID/动作/状态都匹配的Native响应；超时仅删除仍能证明归属自身的未领取命令。它只返回PID、Hero/Clan/MainParty摘要，不输出整份快照、不发送世界动作。Protocol Harness先用假桥验证邮箱繁忙、旧/错响应与超时清理，再在一次性Campaign里连续调用三次Host，并与同一PID的原生CLI只读状态、前后Campaign指纹比较；这证明通信和零世界副作用，不代表模型循环已迁移或玩家入口已交付。
- W7-K 把村庄工具委托接入游戏内 Agent Host 的 Campaign Loop：第一轮模型只分类目标；准确命中“当前可见的VillageNeedsToolsIssue”后转入专用循环，否则不发游戏动作。专用循环每轮读取Native状态，按当前GameState/菜单/对话/可见Issue marker/可见聚落/TradeVM/InventoryVM构建动作目录，并由执行器再次按同一状态核对参数与实体ID。它支持地图查询/移动、当前菜单与聚落人物QuickConversation、当前对话选项、`questDetails`、Native Trade、主角Native Inventory的查询和取消，以及仅限当前Native Bandit Safe Passage的读报价/Auto Balance/复读报价/Offer/Cancel。地图目标必须来自本轮安全可见列表；蓝色任务入口必须是当前Settlement overlay中的匹配任务marker；对话项必须仍可点击且在Bandit遭遇只放行非战斗Option；交易项来自最新VM报价，动作目录约束Native认可的`buy`/`OtherInventory`值和当前Journal所欠的精确工具数量，并仅在该批数量有库存且当前金币足额时开放；原版交易草稿仍需再次确认。成功交易提交后重新读取Journal，不能用过期任务进度继续规划；无工具货/余额不足的市场可经无草稿的原版`tradeCancel`退出。Safe Passage报价必须来自当前BarterVM、只能含让路条款和Denar，重新读取报价与Auto Balance的会话ID/提案指纹必须相同，且Offer时原版handler再执行一次原子比对。金额可支付并留有正余额时才可提交，不开放战斗动作或时钟控制。
- Quest提示另外把会话状态转移显式化：只有对话未打开且当前目录含`talkToSettlementHero`时才能开始接触；成功后对话已经打开，不得重复接触同一人；若最新观察有对话并且目录列出`dialogueSelect`，应从可点击选项中按ID选择；收到`decision-rejected-before-native`后不可重复被拒动作。任务已接取但工具不足时，策略只准点Native离开选项或在无可点击选项时继续对话，不再开放重复交谈；满足工具数且记录交付前Inventory后才重新开放交付对话。该约束由策略与Provider合同自测锁定，真实模型闭环仍须验证。
- W7-K的`AgentHostPackage`无模型回归覆盖Host面对Bandit阻拦时的`dialogueSelect → barterOptions → barterAutoBalance → barterOptions → barterOffer`动作目录和Native后态循环，并拒绝战斗选项、玩家物品、余额不足、party不匹配、谈判会话替换及报价指纹变化。交易目录回归还验证模型只能选择当前有效报价的精确大小写/库存侧、该任务剩余数量，不能买入超额库存或无力支付的批次；成功Confirm后必须重读Journal。`TestResults/20261013-110519`在本机1.4.8 disposable Bandit fixture中验证Host预期值相同才完成原版144 Denar Safe Passage；错误session/指纹在原版handler被拒且Gold/Encounter不变；正确当前值才结束遭遇。AgentHostPackage自测用假Native/假Provider，不是游戏中的LLM通过证据；真实Host+模型仍须完成W7-K的任务验收。
- W7-K的完成门槛不依赖模型自报：任务Journal达到请求数量后，模型先通过Native主角Inventory取得交付前物品数；任务消失后再次读取Inventory，Host只在可见Journal描述可解析奖励数量/物品，且工具净消耗数与任务目标、奖励净增加数与日志完全相等时开放`done`。无法解析、物品同名歧义、无法确定前置库存或当前入口失效均失败关闭，不宣称成功；Inventory以原版Cancel关闭，不提交无关改动。该对照规则的中/英文奖励文本模式和错误计数案例由Host自测覆盖，尚未由真实模型在游戏中验收。
- 参考MineDojo Voyager公开的环境反馈、错误反馈与自验证结构，以及Mineflayer的原生游戏控制API后，当前采用“一次模型动作→Native后态→下一轮重观察”的工具循环，不允许模型生成直接改Campaign的代码。Host/Native传输合同回归覆盖当前动作目录、安全目标过滤、过期/越权参数拒绝、无时钟动作、准确任务物品差异验证和Quest开始切片的假的Native/Provider闭环；这些不是实际游戏任务成功证据。下一项验证仍必须是disposable Campaign中的真实本地模型闭环，保留视觉转场与原生状态收据，禁止正式存档。
- 自动启动用本体 `DisplayMode_0`，840×472 无抢焦点置左上；结构化断言坐标/尺寸，禁止把 `DisplayMode_2` 当窗口模式。
- P3快照来自Campaign API；schema 9含战后InventoryState、双方item数量、遭遇待领取item数和仅在主队GoToPoint时提供的`location.targetPosition{x,y,isOnLand}`。该目标坐标用于恢复Agent移动意图，不是对其他Party/全图隐匿坐标的授权；回执按UTF-8读写。
- W2-B陆地自由地点移动使用`moveToPoint(X,Y,Surface=land)`世界坐标意图，不发送桌面像素。原生`MapState.ProcessTravel`/CampaignVec2校验为准；写入GoToPoint后回执给出实际原生目标，位置自然变化，不传送。Naval/海上过渡是独立未测边界，不由本动作宣称支持。
- P3 分开记录 `IsVisible`/`IsInspected`，不从属性名推断玩家认知。情报策略由产品设计确定；静态面板按需读取。
- P4 `move/pursue/hold` 复现原版目标 setter 与 MapScreen 点击时钟副作用；运行时间自然推进。W2-A进一步接入`follow/escort`并与普通`pursue`分开验收。无效聚落拒绝，抵达以 `CurrentSettlement` 为准；`rest` 只观察原版 WaitMenu 的 `StartWait/EndWait` 时钟。
- Pursuit 夹具在 `hold` 后另取一次稳定观察作为无效追击的前置快照，避免把原版命令刚接受时的瞬时移动模式与下一次观察混比；每次结果写入当前运行 `Temp/AgentPursuitResult.json`，即使阶段失败也可核查每项断言。
- `EscortVisibility`是Pursuit的专项自然观察阶段：只验证Agent附近观察集中的目标离开与Campaign状态联动，不注入隐身、不改变目标位置、不显式步进时钟；它不会把离开观察集等同于原版`IsVisible=false`。
- `TavernMission`保留为酒馆场景的通用移动输入回归；W2-D实际Notable验证只以当前产品工作项指定的Town Center `center` Location Mission为准。
- W2-D的Location观察schema 21会把原版`GameMenuOption.OptionQuestData`作为菜单`questMarkerFlags/questMarkerNames`返回；`GameMenuItemVM`用同一标记生成原版`QuestMarkerVM`。`nearbySceneAgents`仅为主角周围12场景单位内的Agent，不等于视线可见列表；原生`CurrentFocusedObject`同时用`Agent.CanInteractWithAgent`提供原版Focus/交谈可用判定；`settlementOverlayCharacters`复用可见CharacterList和QuestMarkers。`missionNavigateToAgent`在发令时取NPC位置快照，NPC移动后必须重新观察并下达新路径，不能以对旧坐标到达判作追上。
- `harnessMissionDiagnostics`只在Harness `visual-capture`模式与临时run目录同时有效时返回当前Town/Tavern Mission里已激活的Notable Agent、场景里全部已生成的Hero Agent census及当前`CampaignMission.Location`登记的Issue所有者；新增的`activeHeroAgents`只用来核对NPC是否已经生成及其Location/距离，目的是验证测试场景前提，不进入常规观察快照，也不在`Agent-DecisionLoop.ps1`的模型动作白名单中。当任务主人超出主角当前本地观察半径时，Town Center Harness立即保存诊断并清理，不继续跑固定移动步骤；后续应核实原版造访入口。禁止用诊断遥测代替AI玩家的局部观察。
- `MissionSceneNavigation`使用真实`town_streets`入口与内存PlayerAlley fixture；Harness-only `activeHeroAgents`只核NPC确已生成，产品动作必须先请求受支持的当前Mission `missionSceneAgents`观察，再在新鲜同Mission清单中选目标。`missionNavigateToAgent`经Native NavMesh、非传送，限1–20秒lease；抵达附近后只有普通局部观察的Agent才能传给`missionInteract`。`TestResults/20261006-021538`通过：未查询前的远距index导航被拒；当前`vlandia_town_e`场景返回144个活动人类Agent；为Assigned Hero实际执行4段NavMesh lease，249.312→187.746→140.980→60.329→1.417米，每段恢复Player控制；随后Native交谈身份匹配并看到“询问志愿者”选项，但Harness不选项/不提交兵员。CampaignDay/raw Stop/Alley与MainParty roster/Gold/Influence、源存档hash保持，进程正常退出。`TestResults/20261006-021951`Tavern RansomBroker近距移动/对话回归通过。未验证敌对/战斗Mission、相机可视遮挡、所有场景代理及Alley招募结果。
- `AlleyVolunteerBranches`是后续W2-BC分支验收，不在`All`中自动长跑：每次单独启动disposable Campaign，`noVolunteers`以LastRecruitTime=Now保证Native周内暂无分支；`availableVolunteers`只在Harness夹具中挑选一个当前Native seed确实会产生非空志愿Roster的Alley。两个值只供Harness造场景与核断言，不进入Agent输入/决策；产品Agent仍只能基于屏幕实际Native Conversation句子/点击项作选择。前者不得显示招募确认或改变Roster/计时，后者先走“No need”证明无写入、再选择当前可见“Yes”以验证原版提交。
- `AlleyAttackYield`是W2-BE和平交出分支专项：`noAttack`和`peacefulYield`分别用隔离Campaign运行；UnderAttack与攻击方由Harness临时写入原版Alley对象，产品Agent只读真实`manage_alley`选项/Native对话，不调用夹具。正向路径不会选择“Bring it on”，只选择当前可见和平选项并核验Owner/PlayerAlleyData/普通守军返还/关系/Gold/Influence/时钟。专用`AlleyFight` Mission另属后续工作，不纳入该阶段。
- Native Mission `nativeFocus`是玩家当前视线准星的一项结果：本机`MissionMainAgentInteractionComponent.FocusTick`从`MissionScreen.CombatCamera`做约10单位射线并返回当前Focus对象；它不是场景人物枚举。`nearbySceneAgents`则是距离12单位的局部集合。现有`missionAimAt`也仅接受该局部集合里的目标；不要把前两者包装成远处NPC定位能力。
- `settlementOverlayCharacters`是schema 21中的有限视图，只在Settlement Characters overlay当前可见时按本体`MenuLocations + HeroAgentLocationModel.WillBeListedInOverlay`生成，并携带玩家Overlay显示的Issue/Quest标记。用户确认聚落右上人物列表的蓝色感叹号及地图贵族名字蓝标语义；当前Observer只覆盖聚落人物，`mapPartyTargets`的贵族Leader任务标记尚未暴露。`talkToSettlementHero(HeroId)`校验QuickTalkPermission并通过CampaignMapConversation原生QuickConversation在地图上快速交谈；`visitSettlementHero(HeroId)`校验Visit权限并进入NPC Location Mission，不能混称。两者都只接受当前可见overlay名单，不使用Harness全场景Notable诊断里的隐藏ID。
- `SettlementOverlayQuestGate`只验证测试fixture中确实被原版前置拒绝、且Quest/存档不变；该阶段纳入`All`用于回归保护。`SettlementOverlayQuestAcceptance`是另一个正向阶段，必须看到一个新Ongoing Quest及对应原版状态变化才通过；前置拒绝、没有offer、对话返回均为失败，不可用负向结果替代。Harness可跟随原版提供的Alternative方案说明对话节点，但不能点击最终Alternative/Lord接受选项。它要求自然满足条件的disposable Issue fixture，故不纳入通用`All`，直到该fixture稳定存在。
- 聚落移动的标准夹具还要验证抵达后状态切到目标聚落及原版 `town` 菜单；结构化菜单选项按当前 `GameMenuOption.GetConditionsHold` 计算可用性，选择时重验菜单 ID、选项 ID 与 enabled 条件。离开选项作为菜单原语验收；失败夹具对无效 settlement ID 返回结构化拒绝，且世界位置不变。
- 招募必须复用本体 `RecruitmentVM` 的志愿者列表、队伍上限和金钱条件；命令显式指定可用 owner、troop 与 volunteer slot，每次只招募一个。完成以兵力 `+1`、金币按本体价格扣除且来源 volunteer 槽清空为准。
- 食物补给必须经城镇 `InventoryLogic` 交易和 `InventoryListener` 提交市场库存与金币变化；不直接改 roster。动作前检查食品类别、市场库存、交易价格、金币和载重，动作后验证食品库存增长与金币差额。
- 普通交易要分别测试买入与卖出：按原版市场价格执行 `OtherInventory ↔ PlayerInventory` 交易；验收双方库存变化、金币净差和失败无状态变更。仅读市场报价时不应 Push 可视 `InventoryState`；实际购买也应避免无目的地短暂弹出全屏界面。
- W2-U `EquipmentTransactions`用原生SPInventoryVM验证单件equip/unequip、Done/Cancel、occupied-slot交换、旧候选和无效ID/不兼容槽拒绝。非空modifier场景只由`HarnessEquipmentModifierFixture`在visual-capture运行中临时塞入1把Native masterwork sword；测试同时验证同一ItemObject的普通/非空modifier候选具有不同VM ID。测试后先用原生事务将主角装备恢复，再精确移除这件QA物品，最后比较完整Equipment slot fingerprint、主队/经济/位置/时钟与存档hash。夹具seed/clear不进入Agent决策白名单，也不保存测试进度。
- 定居点等待通过原版城镇菜单进入 Wait menu；`GameMenu.SwitchToMenu` 调 `StartWait` 原生启动时间，`wait_leave` 的 `EndWait` 原生停止。`rest(days)` 只观察原版等待时钟达到目标，不能写 `TimeControlMode`；离开等待菜单后的 rest 请求必须拒绝且不改世界状态；`Agent-Cli.ps1 -ReturnWhenAccepted` 用于串行发出后续中断动作。
- 休整验收以 `town_wait_menus → town` 菜单迁移为离开依据。当前 v1.4.8 运行中，返回 `town` 后 `Campaign.IsMainPartyWaiting` 仍为 true；记录此事实并单独核对 API 语义/生命周期，不将属性名直觉作为对功能成功与否的推断。
- UI/VM 验证必须区分“从玩家界面入口走通”和“直接调用相同 VM/逻辑事务”。二者都是真实本体行为，但报告不能互相替代。
- 启动游戏前先告知本轮测试目的、预期界面、是否会打开可视菜单/交易屏幕及主要断言；结束后列出实际执行的入口、结果、证据文件和未覆盖部分。避免 UI 一闪而过却没有可解释的上下文。

## 工具链

| 工具 | 用途 | 采用边界 |
| --- | --- | --- |
| .NET SDK | 编译、探针和辅助工具 | 以本机 DLL 和项目锁定配置为准 |
| PowerShell | 编排、日志、进程和证据 | 不承担游戏状态真值 |
| ILSpy CLI | 只读调用链分析 | 反编译实现不是稳定 API |
| BLSE Standalone | disposable save 自动读档 | 不接管正式存档和模块排序 |
| Bannerlord.Templates | 新模块结构对照 | 当前项目不因模板存在而迁移 |
| Computer Use | 不用于本项目的游戏验证 | 用户要求避免Windows桌面操作；游戏截图和状态只由游戏引擎/Harness采集，不向窗口发键鼠输入 |

不让中文站管理器、官方启动器和 BLSE 同时修改同一模块排序；不直接改官方 DLL；Harmony 只有在公开接口不足且已有 A/B 证据时才进入方案。

## 问题归因顺序

先查 Harness，再查启动器/版本/模块集与生命周期，最后核实战役行为；只有故障证据落在功能层才改功能代码。

FreeLLMAPI/HTTP诊断须分别记录HTTP状态码、可选响应头和网关路由日志：可选头一律用TryGetValues读取，缺头不能被报告成传输失败；429/超时按是否实际尝试上游、候选冷却和Retry-After区分。若Windows curl经代理可通而FreeLLMAPI报TLS断连，在同一时段对同一上游比较传输客户端并核验应用实际proxy source/mode及key级覆盖；请求对照应匹配HTTP方法、目标端点和相关格式参数，GET `/models`成功只证明目录GET通，不代表POST `/chat/completions`推理可用。不能只凭`curl`成功就宣称模型路由可用，也不先改代理协议。诊断不记录统一key或完整错误正文。

Provider 凭据由共享 `SelectApiKey` 按目标端点选取，并用于 MCM、游戏内Host及Harness：FreeLLMAPI loopback优先专用 `FREELLMAPI_API_KEY`，绝不把远程provider的通用 `CHRONICLE_LLM_API_KEY`意外送给本地路由；非FreeLLMAPI端点只用通用provider key。预检只可输出所选变量名，不输出值；Host合同测试须使用合成密钥分别验证两种端点的选择顺序。

Persistent EYC使用DSH时，模型预检必须同时核对本机`/v1/models`精确ID、DSH聚合状态中的provider `enabled/configured`以及该provider的selected model ID；只看Gateway模型目录可能漏掉provider在XD Pool中已被关闭的状态。预检仅使用loopback DSH Gateway API做GET，不调用模型。配置provider时只改明确选定的direct `:free` model，不写API key、不改routing combos；若启用状态、selected models或combo签名不符合预期，停止Campaign启动。

OpenAI-compatible不是可以把任意供应商扩展字段广播给所有服务的许可。
当前`thinking`扩展只对源码/协议已确认支持它的DeepSeek与FreeLLMAPI端点发送；
普通HTTPS或本机OpenAI网关不发送该字段；
对已确认的OpenRouter路由，`CHRONICLE_LLM_THINKING_MODE=disabled`映射为标准`reasoning.enabled=false`，不发送DeepSeek专属扩展。
`required_tool_call`是输出格式选择，不应因非DeepSeek服务没有DeepSeek `thinking`开关而被拒绝。
Host回归覆盖`Thinking=false`时loopback OpenAI网关仍收到严格工具调用、且payload不含`thinking`扩展。
DSH XD Pool的无游戏冒烟仅允许显式命令行opt-in和目录中的直接`xdpool-aggregate/*:free`模型，自动组合/回退链不进入推理路径；
Persistent EYC的model preflight也只对显式启用的直接`:free` ID读本机`/v1/models`，核对ID精确列出后才允许后续游戏阶段，preflight本身0推理请求。
模型目录中的免费标签不能证明每个provider调用会成功；
保留真实响应状态和token用量的证据，不记录完整错误正文或凭据。

一次性Provider smoke若失败，AgentHost CLI应把Provider已经筛选过的HTTP状态、error type/code/param、route、request ID、输出格式、重试/回退字段传给Harness；
Harness把这些白名单字段保存为`ProviderSmokeFailure.json`，错误正文、提示词和凭据不保存。
若它只回通用`invalid_request`且没有route、request ID或param，Harness可针对明确免费直连端点提供一次、无tools、8-token的最小chat-completions对照，请求不重试、不走组合路由，收据只保留状态、路由元数据、token数和是否匹配预期短文本。
这个对照已验证DSH Ling free route得到502/RATE_LIMIT，而Kilo Particle free route的普通文本与Host JSON Schema分类均成功；
后者仍只是模型/协议冒烟，不是Campaign闭环。
对新的HTTP 400/502，先凭这些字段区分请求校验、网关适配和上游失败，再改格式或更换路由；
没有路由/错误分类时不重复猜测推理调用。

Harness 的 `save` 命令只允许 Native `MapState`，并拒绝上一笔 `SaveAs` 尚未收到 `SaveOver` 回调时再次排队。`PartyState/Ransom` 上曾观察到 SaveAs 返回 accepted、180秒内没有完成回执/存档文件，之后同一游戏进程仍可读状态；这是未完成的测试保存，不表示原版手动保存一定失败。不要在不支持的 Native GameState 下重复等待长超时，也不要用强制结束来伪造保存结果。

FreeLLMAPI可用性诊断默认不重复调用自动回退路由：一次请求可能触发多家上游尝试并消耗免费额度。优先用单个明确的免费模型做至多一次小型探测；若失败先读本机网关请求ID及各上游失败记录，区分调用格式、上游限额、模型目录/映射与代理传输问题；只有错误证据表明可恢复且等待在当前deadline内，才重试。目录`ready`或`/api/ping`成功仅代表目录/本地服务可访问，不算推理通过。

工具本应避免却仍然发生的问题必须修工具并增加回归，不能只为功能代码加延时、try/catch 或补丁。

## 技术决策权

产品体验是需求；机制判断和技术建议待验证。用当前源码/运行证据核实，并据此比较成本、风险、替代方案；证据冲突时直说。

## 文档维护契约

- 始终只有一个 `MAINLINE.md`；它维护技术焦点，不记录当前Issue、域完成数或项目阶段状态。工作项状态仅由GitHub Project声明。
- `ContextState.json` 只路由当前MAINLINE、文档默认层、按需Research和复核/hash元数据；不得加入任务ID、活动Issue、阶段或完成百分比。
- MAINLINE焦点改变时直接维护该文件，再运行 `Set-ContextFocus.ps1 -Review` 更新review日期和hash；它不接受或存储任务目标/阶段参数。
- 主线完成或主题切换必须使用 `Complete-ContextFocus.ps1` 原子执行“删除/归档旧MAINLINE + 写入新技术焦点 + 更新路由元数据”；任务Issue另在GitHub关闭或更新，两边不互相复制状态。
- `Get-ContextPack.ps1` 默认只返回Development Contract + Active Focus；`DESIGN.md`仅设计任务读取，`SYSTEM_INVENTORY.md`与Research仅盘点任务按路由加载，Archive只有显式请求才返回。
- `Check-Docs.ps1` 检查层级、唯一主线、hash、复核期限、Reference 单文件规则以及 Archive 不进入默认读取列表。
- OpenSpec 只承载一个当前变更的提案、规格、设计依据和可核验任务；GitHub Project仍是产品事项的排序/状态来源，OpenSpec不复制路线图，`TestResults`仍是完整运行收据。`Get-ContextPack.ps1`向新上下文附上活动变更摘要，`Run-Harness.ps1 -Phase Docs`调用`openspec validate --all`并拒绝多个活动变更；OpenSpec生成的 `.agents/skills/openspec-*` 与 `openspec/` markdown 不加入内容文档路由，OpenSpec CLI负责其结构校验。
- OpenSpec任务完成框必须链接已存在的精确Harness收据；包测试与自然Campaign/模型运行分别标记。模型测试任务在执行前必须注明假设、新信号、调用上限和费用上限。归档变更不等于关闭GitHub产品Issue。
- 文档内容过时直接修改权威段落，不新增“新版”“补充”文件。
- 删除、移动或归档文档时同步修正 `ContextState.json`、根 `AGENTS.md` 和 Docs 检查。
- Harness、验收、工具链或文档拓扑变化时提升 contract version。
- 启动重试只认明确崩溃；RGL存在不等于崩溃。Progression留故障摘要；PostBattle夹具读取并校验奖励遥测，不改结算。
- Harness入口只接收本地游戏路径和仓库路径；不需要GitHub授权、配置、网络或Project字段。
- 每次修改后运行相关Harness阶段；Docs检查文档路由/技术门禁，`TestResults/latest.json`只表示最新本地收据。项目板状态只在Agent开始/结束工作项时更新。

`AlleyLeaderInquiry`是独立可选阶段，不加入`All`：在Sargot原版`town→manage_alley→change_leader_of_alley`菜单链，以内存内Native Alley/Clan Hero夹具补齐玩家巷道数据，然后由Native菜单选项生成正式`MultiSelectionInquiryData`。
夹具调用`AlleyCampaignBehavior.AddPlayerAlleyCharacters`建立旧负责人`LocationCharacter`，因为原版确认回调会将旧负责人移至酒馆；
缺少该对象会令真实Native handler抛出NullReference，不能用直接写AssignedHero/Roster绕过。
测试从Native ViewModel观察候选、启用提示、数量、Done/X与pause标志，保留Town菜单、弹窗、取消、确认四张引擎帧；
非法候选与过期令牌拒绝，退出不改变负责人/Roster/Owner/Gold/Influence，确认则由原版回调更换负责人和驻守Roster。
基线Campaign为Stop，运行内日期/档位稳定，源存档哈希不变。
它验证原版菜单与回调集成，不是自然Alley存档或真实鼠标操作；
本阶段启动互斥和清理检查覆盖`Bannerlord*`进程族。

`AlleyRosterManagement`是独立可选阶段，不加入`All`：在一次性Campaign中走Sargot原版`manage_alley→manage_alley_troops`菜单入口，打开真实`PartyState/TroopsManage`。
Native fixture提供玩家Alley负责人、普通兵和当前MainParty；
Agent只读当前PartyScreen可见左右Roster与 transferability，并通过Native `PartyCharacterVM.ExecuteTransferSingle`逐名转移。
测试先暂存再Native Cancel，确认完全回滚；
然后在Alley `AlleyModel`下限/上限两侧试探Done禁用，恢复边界后用Native `PartyVM.ExecuteDone`提交，检查双方Native roster实际结果。
保留四张引擎帧、Campaign day/raw mode/waiting、源存档hash和游戏进程清理证据。
它不覆盖负责人对话入口或已有Alley Mission中的刷新，不用直接Roster写入冒充玩家事务。

`AlleyAbandonment`是独立可选阶段，不加入`All`：因Native Yes会不可逆移除当前玩家Alley，同一Harness任务分别从相同且不变的disposable Campaign独立加载，测试原版No取消和Yes确认，不能先Yes再通过Fixture假装回滚状态来测取消。仅使用非UnderAttack玩家Alley；记录`manage_alley→manage_alley_abandon_are_you_sure`及两分支引擎帧。Cancel后原Native Ally数据/Owner/负责人/守军/主队不变；源码Yes handler请求`town_outside`，运行观察却显示`town`菜单及放弃通知；与此同时Native数据不存在、owner清空、普通守军回主队。不得把源码菜单ID当成运行后画面证据。同时保存金钱/Influence/CampaignDay/raw mode/waiting、两次源存档hash与进程清理。被袭转交、对话/Clan screen分支不包含在本专项中。

`AlleyEntryMenu`是独立可选阶段，不加入`All`：从到达Town后的Native当前`town`菜单观察启用的`manage_alley`（显示“进入巷子”），通过产品`menuSelect`走真实`GameMenuOption`后果进入`manage_alley`；再观察当前菜单并选择Native `back`返回Town。`20261004-052453`的Native帧与state均显示进入后仍是MapState且没有Mission，背景是Campaign地图上的Alley菜单/图板，不是可走动3D巷道场景；返回时menuId是`town`。两次菜单转换前后`PlayerAlleyData`、Owner/负责人/左右Roster、Gold/Influence、CampaignDay=91077.400065/raw Stop/`isWaiting=true`和存档hash不变；三张引擎帧及进程退出保留。此菜单注册的`MenuLocations`不能代替对Assigned Leader人物对话Scene入口的实测。

`LiveModelRuntimeResume` 是可选的 `Run-Harness.ps1 -Phase LiveModelRuntimeResume` 阶段：它验证Agent决策循环/Provider进程重启时，Bannerlord Campaign仍维持同一PID和Native内存checkpoint；与 `LiveModelResume` 的Native存档重新加载分开记录。两者均不加入 `All`。

`LiveModelActionRecovery`（`Run-Harness.ps1 -Phase LiveModelActionRecovery`）是独立 opt-in 阶段，用一个仅Harness可启用的故障注入点，在Native recruit已提交且CLI回执返回、但DecisionLoop尚未把动作结果写回Campaign checkpoint时终止该loop进程。Campaign保持运行；恢复时只在新Native状态精确满足本次招募人数+1及按Native成本扣金后，才把pending action标为已恢复，否则拒绝重放并保留失败证据。此逻辑目前只实现RecruitmentVM这一已知非幂等动作，不是所有游戏动作的通用事务协议；阶段不进入 `All`。

`CheckpointValidation` 是 opt-in 的 checkpoint输入安全回归：对一个接入于disposable Campaign存档的损坏JSON、未知schema版本和错Campaign身份逐个尝试Resume；每类都应在Provider启动或任何Native写动作前失败，且当前地图/队伍/金币/日期/时间档保持不变。专用seed action只在visual Harness模式可用，不能进入产品白名单。

`RecruitmentBaseline` 是W5的确定性原版对照阶段：它从同一个未修改的Campaign模板分别重载5个Runtime，完成地图移动与招募一人，按Native receipt/Party/Gold/Volunteer slot验证成功，同时记录CampaignDay、raw time mode与墙钟成本。它明确只有同一Campaign起点重复，不是5个独立随机seed，也不测试真实LLM；结果用于冻结后续候选模型评测的重复数和阈值，阶段不进入 `All`。

`MultiDaySupplyBaseline` 是W5-H的确定性Native配对基线，显式opt-in且不进入 `All`：从同一个disposable Campaign模板建立固定MainParty，分别执行无补给/原生市场补给两条支路，在Town Wait Menu通过原版等待跨过至少三个日周期。它记录Food/FoodInventory/FoodChange、日工资字段、Gold、daily tick与原始时间档，判断是否存在可观察的资源压力及Native补给是否缓解；移动只使用当前可见安全Town并让Campaign时间自然推进，等待只调用原版Town Wait/`rest`，不发Harness `advance`。该Native对照先用于校准变量/方差和真实模型阈值，不代表LLM已会规划补给。

`LiveModelSupplyEvaluation` 是W5-I的opt-in真实本地模型测试，默认同一disposable模板重复3次，不加入 `All`：Harness先用原版移动/招募将场景准备到萨哥特的6人主队状态，再把决策交给模型；预处理不计入模型成绩，且必须用Native收据确认固定起点。模型需依当前TradeVM报价补给、使用Town Wait/`rest`自然跨过3个daily tick、再次观察并离开等待菜单。门槛固定为每轮最多24次模型决策/300秒、模型3/3完成、结束Food≥1且Gold>0/队伍6人、录像≥90%并在关键帧/时间线生成后删除成功原片；每轮记录Native交易、等待、资源/时间后果、源档hash和清理。三次运行只是一个相同Campaign模板上的模型重复性，不是跨Seed泛化或完整生涯能力。

`menuSelect` 的模型参数必须引用当前Native观察中启用选项的精确 `id`，不能把参数名或显示文本当作ID。`provision` 则须把最新报价里的 `viewModelItemId` 映射到 `ItemViewModelId`，并提供该报价允许的整数数量；它只创建TradeVM草稿，须再用当前提供的 `tradeConfirm` 提交，才能退出交易并进入后续等待流程。TradeVM取到有效食物报价后，会隐藏重复报价读取，只保留基于该报价的有效交易动作，直至Native事务成功、取消或拒绝。未提交交易期间的 `observeAgain` 会被安全拒绝并反馈，让模型根据当前仅开放的确认/取消动作重新决策。决策或 `observeAgain` 在Native调用/宿主等待前校验失败时，失败收据保留归一化后的模型决策、当时的原版观察以及“未发送Native动作/未开始宿主等待”证明，便于区分模型选值错误与游戏执行错误。

`FreshCampaignBaselineMatrix` 是单独opt-in的多新档Native基线：5次分别走本机1.4.8原版New Campaign/角色创建入口，在相同模块/难度/背景条件下创建全新Campaign；每次记录初始Native状态、可见安全Settlement、RecruitmentVM结果、Campaign实例标识、耗时和清理。`ChronicleCampaignInstanceId` 是Mod Campaign实例身份，不等同Native随机Seed；若本体没有可验证Seed，结果明示Seed未知。每个新进程遇到已识别的“Mod change detected”着色器缓存提示时，FreshCampaign调用同一精确UIA/所属进程按钮处理器并保留回执；不使用全局键鼠，也不把弹窗误认成存档模组不兼容。该基线衡量新档起点和机会变化，不含真实模型通过率，也不能用“5次新档”冒充5个已验证Seed；它不进入 `All`。

`FreshCampaignSupplyBaseline` 是后续单独opt-in的W5-J原版对照矩阵，不进入 `All`：每轮从原版New Campaign创建并验证一个独立Campaign，再仅保留一份由该Campaign实际生成的disposable临时存档。它从两个新加载副本分别执行无补给/一单位当轮最低价可购食物的Native分支，均用原版城镇等待自然推进三个Daily tick；每个分支记录当轮Native报价/资源后果及Campaign运行时ID。运行时ID可能在跨进程重载时重建，所以配对必须核对同一源存档SHA-256和对齐起始资源/日期/tick，不得把ID当作Seed。实际游戏窗口录像保留连续视频用于回看，并由契约工具生成约每4秒一帧的总览联系表和动作边界前/中/后关键帧索引；成功提取后删除MP4，完整覆盖以解码帧数/期望帧数计算。临时存档由外层统一清理并复核既有保存清单；创建、加载、录像或清理任何一步失败均留下分类收据，不代表真实模型自主能力，也不重用W5-I固定模板成功门槛。

`FreshCampaignRecruitmentFallback` 是W5-K的selective Native评测（不进入 `All`）：最多十次原版New Campaign尝试；
从每个新档先在玩家当前Native可见的最近安全城镇检查实际RecruitmentVM名额，若当前槽位耗尽，只查询当轮 `mapSettlementTargets` 返回的可见、安全、未围城聚落，通过普通原版Move与本地RecruitmentVM逐处观察/招募。
它不快进刷新offer，不使用全世界Notable诊断，不修改Party/Roster。
若Native路线达到六人，则必须准确到达安全Town菜单；
之后退出Town回到Campaign MapState再保存一份disposable prepared Campaign，防止把聚落菜单的运行态误当成地图存档。
其两份独立加载副本从原版地图移动到可见安全Town后运行三日无补给/Native补给配对；
已经六人的队伍不要求存在可招募菜单。
运行时Campaign ID只作记录，pair以保存SHA及起点状态判断。
若候选耗尽、路上遭遇或十次未复现名额短缺，都输出明确结果，不以未证明说成全局无路；
每次都保留菜单/offer/行动/日期/资源和窗口关键帧、自动清理临时保存与游戏/session。
若收据的`PreparedMarketTownId`存在，则它来自到Town时验证过的当前settlement id，不能从返回地图后的空`currentSettlementId`反推。

`FreshCampaignLiveModelEvaluation` 是#101 Native基线后的opt-in候选评测：每轮新建Campaign并由真实本地模型从该新档第一条决策观察开始，自行选择当前可见安全Settlement、移动、读取当前RecruitmentVM报价、招募并核验停止。
固定5轮实例，阈值为完整新档到目标≤180秒、自然Campaign推进≤0.1日、每轮恰好一次Native Move/Recruit、无被Native拒绝的动作、录像覆盖≥90%、临时保存与进程清理；
动作未列入当轮目录时可被Native前安全拦截并重新观察，该拦截不计作Native拒绝，但必须记录且不得造成世界副作用。
途中可以是显式有限 `observeAgain`，也可以是安全拦截后的新Native观察；
到达时延迟模型给出的过期等待请求应被反馈处理，不能让已完成的成长路径假阴性。
候选五轮启动前生成当前Tracked/非忽略Harness源文件和本地Harness设置的SHA-256清单；
每轮前后复核，若清单变化就停止/判失败，避免把不同代码版本的运行合并成同一个矩阵。
模型/服务器/模块/源码提交与源清单状态随结果记录。
首轮目标结束后清除测试保存，不改已有正式存档。
该阶段不加入 `All`，结果只证明这一成长切片的五实例重复性。

`LiveModelRecruitmentEvaluation` 是基于该Native基线的真实本地模型opt-in阶段：固定同一seed、真实Provider、五次独立Runtime运行，预先要求5/5成功、每次墙钟≤180秒/CampaignDay≤0.1、一次move与一次recruit、无重复或越权副作用、Visual覆盖≥90%、模板hash不变且进程清理；候选模型结果不得反向改阈值。它只评估当前地图→志愿兵目标，不代表跨seed或整个产品成熟度。

DecisionLoop 的动作白名单仍是产品能力上限，但模型每轮看到的是当前Native观察决定的有效动作目录。
地图状态/无可用Settlement菜单时不暴露 `recruitOptions`/`recruit`；
当前Settlement菜单启用原版 `recruit_volunteers` 后才开放报价读取；
仅上一回执属于同一Settlement的Native报价、且当前主队有容量和可支付选项时才开放 `recruit`。
对话层只在当前Native Conversation有可点击选项时开放 `dialogueSelect`，没有选项时才开放 `dialogueContinue`；
Barter修改/平衡/提交只在最近的`barterOptions`/更新回执对应有效Native VM会话时开放。
提交参数还会与当前菜单、最新报价、Gold及队伍容量二次比对。
模型选了未开放动作时，执行器不把它发给Native，会刷新观察、提供明确反馈并允许有限重规划；
Provider将目录外动作转换成带动作名和目录的结构化拒绝回执，DecisionLoop保留上一条已确认Native回执并安全重规划；
Native自身拒绝同样会记录回执、重新观察再决定，重复拒绝有上限并安全停止。
AgentLoop确定性回归不仅在地图上故意提出不可用招募，也在报价环节故意提交不存在的offer ID；
另在 `StoppablePlay` 的原版地图移动中故意提出目录外 `resume`，确认没有Native时钟命令、Move重复或Campaign时钟档修改，收到拒绝反馈后仅用有限 `observeAgain`继续。
还会在主队已自然抵达目标时故意提出一次过期 `observeAgain`，确认它被安全拒绝、没有宿主等待/Native动作，并将当前抵达状态反馈给Provider。
该目录用于精确表达动作前置条件，不替代Native最终校验。

`LiveModelSafePassageRecruitment` 是独立 opt-in 的真实模型分支评测，不进入 `All`：从一次实际 Native Move 后由 Harness 在视觉测试客户端内创建敌对Looters并等待原版`encounter_meeting`；
夹具回执单独存于Harness trace，不进入模型prompt。
模型仅按当前Conversation选非战斗谈判，通过Native Safe Passage BarterVM当前报价、Auto Balance与Offer流程清除拦截，重新观察地图、继续移动并完成一名志愿兵招募。
遇到没有可点击对话选项的Bandit会面时，先用只读`barterOptions`探测Safe Passage BarterVM；
仅当该VM尚未就绪且Native会话仍处于无选项阶段时才继续一次对话，然后重新探测。
此顺序避免把BarterVM动作误当成Conversation选项或在停止时钟下重复等待。
测试核对敌对强度/本地joiner、选项、Barter金额、移动恢复、Party/Gold变化、Campaign时间、连续视觉关键帧与清理；
这一切不授权Agent在正式游戏创建敌队，也不代表实时战斗能力。

`LiveModelSafePassageRecruitment` 也是一个耗时、需显式指定的独立阶段，不进入 `All`；它验证上述原版劫匪拦截恢复路线。

动作目录会镜像Native入口的前置条件：`move`/`pursue`/`follow`/`hold`/`moveToPoint`只在无Encounter、无当前GameMenu、Escape或Inquiry的Campaign Map出现；Native遭遇期间隐藏`mapSettlementTargets`以避免把地图导航误作当前交互。当前对话没有可点击选项时不暴露`dialogueSelect`。在Bandit无选项过渡句中先探测`barterOptions`；仅当Native表明Safe Passage BarterVM尚未就绪且会话仍无可点击选项时，才放开一次`dialogueContinue`，随后重新探测Barter。Barter修改/自动平衡/Offer只在同一Native BarterVM最近的查询或草稿回执存在时开放；每次Native handler仍复核自己的上下文条件。

遇到遭遇阻塞时，`control-unavailable`反馈另保留上一条`native-action-rejected`的原因；这样模型在同一轮重规划中不会丢失“Barter探测尚未就绪，需要按当前无选项Conversation继续”的信息。

真实模型的三日补给试跑显示：即便 Native 会安全拒绝过期的 foodOptions/menuSelect，静态允许列表仍会反复把模型送进失效上下文。因此决策目录现进一步随当前状态分阶段：menuSelect只让模型传当前 enabled 的OptionId，执行器从同一观察绑定Native context.menuId；食品/交易工具只在Trade InventoryState开放，provision须有当前foodOptions回执，提交后只开放确认/取消；rest只在实际Town Wait菜单与等待状态开放。它们仅缩小Agent可调用工具/参数，并在原生 handler 前核对，不替代、改写或绕开本体菜单、交易或时间后果。相关确定性门禁在AgentLoop阶段验证，真实模型三日目标仍以独立W5-I收据验收。

rest通过Native返回accepted后，AgentLoop不阻塞等待三天，而是以有界observeAgain继续读当前Campaign状态；只有上一条rest已接受、Native Wait菜单仍打开且原版时间正在推进时，才开放此宿主侧短暂等待。rest在同一Wait菜单内只允许提交一次，接受/完成后隐藏重复rest，直到离开Wait菜单。该观察和等待不调用游戏时钟开关；未接受rest、等待菜单已退出或原版游戏时间停止时不开放。

Supply循环的本地Qwen3.5 4B校准在输出上限768和1536时均收到finish_reason=length、未得到完整第二步决策；本轮将上限提高到Provider允许的4096并写入每轮收据。目标文本已缩短以减少不必要推理，但模型仍受决策/墙钟硬预算约束；这只说明该模型/任务目前需要更高输出上限，不能据此推断其他模型都需相同配置或把截断记成Agent失败结果。

本地模型还曾把一个结构化动作的arguments包成JSON字符串或单项嵌套数组，并把单参数rest压成数字；Provider现只解包有限层数的单项string/array包装，且仅在动作 schema 确有一个字段时接受标量作为该字段，之后仍逐字段执行当前工具参数白名单。多字段动作的标量/数组、未知字段和无效JSON仍拒绝，并有本地HTTP回归测试。

campaign-multiday-supply只将当前菜单OptionId、主队人数/粮食/日工资、Gold、当前Settlement/菜单/Inventory模式、Campaign日与tick，以及当前Trade/Wait选项传给模型；不重复放入NPC、邻近队伍、任务标记或角色技能。Native完整状态仍保留在Harness轨迹中，供开发者诊断；模型看到的窄视图是场景所需事实的呈现方式，不代表隐藏的Native状态被改写。

## 当前执行焦点

`ContextState.json.current.path`只定位当前技术焦点；GitHub Project及活动Issue决定工作项和执行次序；`MAINLINE.md`保存跨任务有效的技术约束、机制事实和研究门槛。不得从单个来源推导另外两个来源的动态状态。

Native存档是异步的：`Agent-Cli.ps1 save`默认等待`OnSaveOver`最终`completed`回执；只有显式传`-ReturnWhenAccepted`才提前返回`accepted`。任何需立刻reload或验证落盘文件的Harness步骤必须等待`completed`，不能把`accepted`当成存档已写完。

StoryMode VillagersInNeed is not a generic map-arrival conversation.
Its final dynamic Conversation option IDs must be tied to the current native option list, while safety uses the installed 1.4.8 TextObject IDs: `glarczej` starts the optional Villa Mission and `nhSLTzHk` postpones it.
AgentObserver schema 28 includes each option's `TextObject.GetID()` as `textId`; the PartySize catalog omits and rejects the mission-start ID. Package tests pass, but only a subsequent natural StoryMode run can establish that the game-side ID values match the XML and that postponement returns to the Village menu.
`TestResults/20261027-022658`显示真实Provider可能把整数参数`slot`和`confirmPartySizeWarning`序列化为字符串；旧Host严格按数字读取，因此在Native发送前连续拒绝相同招募决策。AgentHost现在只在这两个特定字段上接受规范十进制整数字符串，将其转为整数后继续按当前offer/party capacity复核；非规范值（如`"00"`）、越界slot及不满足当前VM的交易仍拒绝。Host包合同`TestResults/20261027-023442`通过，真实Campaign招募后验待复测。

Harness visual-capture/lifecycle failure summaries now include an open Campaign conversation's Native Character ID, optional Hero ID, and only each clickable option's dynamic ID, stable TextObject ID, and clickable flag. They omit the displayed dialogue and option text. This distinguishes a StoryMode NPC/quest identity mismatch from action-policy failure without retaining raw conversation content; the schema is exercised by AgentHostPackage.

During PartySize map travel, `stop` is also premature while the only currently listed safe control is `observeAgain`. The Host rejects the first such stop with a bounded passive-wait instruction, then requires a fresh Native state; it never advances or pauses the game's clock and never substitutes another gameplay action. This branch is covered in the Fake Native/Provider VillagersInNeed package route and awaits a natural StoryMode recheck.

Natural DeepSeek StoryMode run `TestResults/20261027-031721` measured 68,584 prompt tokens on one move decision, including the same safe settlement collection duplicated in both the current target field and the previous Native receipt; recruitment prompts similarly repeated the full offers receipt alongside exact candidates in the action catalog.
PartySize observation now sends safe targets once, replaces prior map data with `visibleTargetCount`, gives offer aggregate counts in observation, and retains exact current affordable offers only in the listed `recruit` action.
Fake Native/Provider package tests in `TestResults/20261027-033959` verify those payload boundaries.
Real-token savings and model/Native outcome quality remain unverified until the next natural Campaign run.

Natural StoryMode follow-up `TestResults/20261027-034322` compared the same first village move decision after this change: 68,584 prompt tokens / 305,849 request bytes / 110,659 observation bytes became 25,417 / 107,889 / 52,739.
This verifies the duplicate map target receipt was removed while the current settlement choice list stayed present.
The full-run totals were 346,211 prompt tokens, ¥0.73893197 usage estimate and ¥3.9936312 upper-bound reservation; task/encounter paths differed from the baseline run, so only the same-shaped move request is a direct attribution.
The campaign still did not finish Establish Your Clan.

PartySize additionally projects each safe Native Town/Village candidate to its ID, visible name, type and distance.
Hostility/siege flags have already served the safety filter, and inspection status is unused by this subgoal; no target-count limit is added.
Package tests preserve all 32 dynamic candidates.
Natural run `TestResults/20261027-053836` measured its first move request at 19,733 prompt tokens / 79,553 request bytes, about 22% below the prior deduplicated/unprojected `034322` run; its later VillagersInNeed loading race still stopped the objective.

`TestResults/20261027-053219` stopped before FreshStoryMode because an AgentHostPackage fake map-target fixture omitted the live MapState.
The test fixture was corrected, and package `053521` passed.
Natural `053836` then located a distinct engine transition: on first arrival in `village_ES3_2`, Native had already entered `MissionState` with the VillagersInNeed Quest active but ConversationManager had no Character/options yet.
The Host now waits up to ten passive 500 ms reads only for that exact StoryMode transition, recording before/after Character, option IDs/Text IDs, CampaignDay and native time mode without issuing a gameplay or clock command.
An unrelated Mission, another settlement, or a resolved different Character still fails closed.
Fake transition/package proof passed in `TestResults/20261027-054956`; real post-change transition behavior awaits a fresh StoryMode run.

Natural run `TestResults/20261027-055510` reached the same village with the ConversationManager already ready on its first usable snapshot (the pending-wait count was 0). The model deferred the Villa Mission, returned to the village menu and recruited six volunteers, but the Journal PartySize target and other EYC objectives remained incomplete. Thus the live dialogue→defer→recruit chain is verified for the ready state; the delayed ConversationManager startup branch is still only package-tested.

Host objective-subflow receipts now include a small four-field Journal progress summary (`current`, `target`, `met` for Gold, PartySize, Renown and Companions). This makes model stops directly comparable with the original current target while excluding Journal prose and identifiers; its packaged trace contract is covered at contract version 7.339.

Natural run `TestResults/20261031-021221` showed the no-choice VillagersInNeed route still did not reach the handler: a `MissionState` with `menuId=null` retained the previous settlement `moveTargetId`, so the generic arrival-pending rule removed all mission actions.
PartySize now treats movement and delayed settlement-menu arrival as pending only on `MapState`.
Fake Native mission conversations use the same `menuId=null` shape as the game and verify that the existing bounded no-choice `dialogueContinue` action is reached.
AgentHostPackage `TestResults/20261031-021848` passes; the next natural run must verify the Native continue/answer/defer chain.

2026-10-27: the decision trace also records the same four Journal progress metrics and an allowlisted summary of the Native progression context that the planner received (including Clan Tier and current party capacity).
This lets a real-model run show which progression facts were actually sent with each objective choice, without storing prompts, free-text rationale, or arbitrary observation fields.
AgentHostPackage self-tests the 20-capacity/Tier0 case and rejects unlisted diagnostic fields; Docs checks this contract at version 7.340.

`TestResults/20261027-062055` verifies the packaged Host records a PartySize `3/5, met=false` snapshot without Quest prose or entity IDs.

The read-only objective planner also receives the current native progression context.
In a natural StoryMode receipt, the original Journal required PartySize 25 while the fresh ClanTier0 MainParty limit was 20.
Installed 1.4.8 `DefaultPartySizeLimitModel` adds 25 slots per Clan tier to the player-Clan leader at Tier1 and applies Steward skill through the active Quartermaster; the Native RecruitmentVM has an explicit Over Limit confirmation, with a separate Native 20→21 receipt available at `TestResults/20261022-042203`.
The model prompt compares the current cap and Journal target and may consider the current confirmed recruit offer or Renown/Tier1 progression; it does not change either state or force an objective order.
Package `TestResults/20261027-065553` verifies the capacity/tier context, while live objective ordering remains unverified.

Natural run `TestResults/20261027-084501` exercised the current Native leave response after declining a Tavern Wanderer's price, then returned to the Campaign map.
It later resolved a bandit encounter through Native Send Troops/BattleSimulation and gained Renown 20→22.129, but failed before transferring post-battle loot: the model supplied visible troop class `looter` as `partyTakeAll(TroopType)`.
Native `AgentProtocol` accepts only PartyScreen roster categories `members` and `prisoners`; the prior action catalog did not tell the model those values.
The current catalog now lists only categories with a currently transferable Native roster, the executor verifies that exact value again, and the prompt forbids using a troop class/name.
Package tests cover both current categories and reject `looter`; the natural PartyState/Loot regression remains to run.
Contract version 7.346.

Natural run `TestResults/20261027-093235` exposed a bad Companion navigation retry: the model requested a 12-second AgentNavigator lease, while the live action catalog offered only 8 or 20 seconds.
The Host rejected it before Native execution, but the prior feedback did not restate the legal pair; the model repeated the same invalid request and the subflow stopped.
The Companion prompt now tells the model not to interpolate between catalog values, and rejection feedback returns the current `AgentIndex` and exact `DurationSeconds` choices.
The AgentHostPackage self-test verifies 12 is rejected before Native and that correction feedback names the current values.
Natural compliance remains unverified.
Contract version 7.347.

2026-10-27 harness review: the isolated `AgentHostBattleSimulationEvaluation` currently failed at its provider preflight before the Host/game action ran because `Test-AgentHostCampaignLoopEvaluation.ps1` unconditionally required FreeLLMAPI, even though the product Agent Host supports the configured HTTPS OpenAI-compatible DeepSeek route used by natural StoryMode tests.
The harness now prefers the configured process/user `CHRONICLE_LLM_BASE_URL`, `CHRONICLE_LLM_MODEL`, `CHRONICLE_LLM_PROTOCOL` and API key environment, validates endpoint/key rules, writes only provider URL/model/output mode to the temporary MCM profile, and restores process environment after the run; the prior FreeLLMAPI initializer remains a fallback only when no provider profile is configured.
This is test-tool compatibility, not a product capability change.
The targeted battle slice must pass provider preflight and reach the Native PartyState before the `partyTakeAll` fix can be marked naturally verified.
Contract version 7.348.

The first post-change battle-slice attempt `TestResults/20261027-092940` still failed before model use: the campaign-loop wrapper expected FreeLLMAPI even though the configured provider environment uses DeepSeek.
The wrapper now resolves an existing OpenAI-compatible process/user profile first, validates HTTPS (or loopback HTTP) and a required remote key, writes only ProviderBaseUrl/ModelId/OutputMode into the temporary MCM profile, and restores inherited process values.
The in-game test preflight now queries the configured provider's `/models`; FreeLLMAPI retains its `available=true`/execution-status check, while other OpenAI-compatible providers require the exact model ID in their model list.
This broadens only Harness evaluation, not product API behavior.
The next targeted battle run will test its provider preflight, BattleSimulation and loot aftermath.
Contract version 7.349.

The battle evaluation used a valid saved source but could not guarantee that a visible hostile party remained near the saved map position; `TestResults/20261027-103943` therefore stopped at its read-only target preflight with zero model inference.
The Harness already has a tightly scoped `visual-battle-fixture` mode that seeds one disposable hostile looter party only after loading a byte-for-byte cloned source save, and the battle test now selects that mode.
This gives the model a controlled target to test the real Native action path; the seeded fixture is reported as test setup, never as natural campaign progress or a product capability.

The first disposable battle-fixture attempt after provider-neutral preflight then failed inside Host initialization: the Native MCM start payload always overrode the temporary `CHRONICLE_AGENT_PROFILE_PATH`, leaving the test Host with an empty provider profile.
`AgentHostRuntimeController` now omits the MCM providerConfiguration only when the process is in the explicit `visual-battle-fixture` Harness mode and a Harness-owned profile path is present; normal player starts continue to pass their current MCM provider settings.
Host's existing profile-path boundary still requires that file to remain under the disposable Harness temp root.
Docs statically checks this test-only branch.
Contract version 7.351.

`TestResults/20261027-112511` got past provider setup and seeded one disposable Native-visible bandit, but then safely stopped because its live UI entered the BanditFaction threat dialogue (`common_encounter_ultimatum` / `common_encounter_fight`), while Host only exposed the direct player-initiated `bandit_start_defender_1` response.
The existing ACT-G01-02 contract and 1.4.8 behavior notes already describe the threat branch and its surrender roll, so this was an implementation gap rather than a new vanilla mechanic.
The current catalog now lists only clickable `bandit_start_defender_1`, `common_encounter_ultimatum`, and `common_bandit_surrender_declined` responses; it rejects release/toll/accept-surrender options.
The Host prompt describes the distinction.
`TestResults/20261027-113348`'s real DeepSeek Host loop selected `common_encounter_ultimatum`, continued the Native war response, selected current `str_order_attack`, completed BattleSimulation and every observed Party/Inventory aftermath screen, and returned to Map.
Renown 20→22.562, party members 20→19, wounded 0→2, prisoners 0→9, inventory 0→10; explicit clock actions 0, source fixture hash unchanged, temporary clone removed, game/CLI closed and video frames covered 100% then original clip deleted.
That run's inner loop passed but the aggregate gate correctly rejected a dirty tracked tree.
The wrapper now audits every dialogue choice against that decision's current catalog and clickable Native options and recognizes both verified meeting branches.
A clean-commit rerun `TestResults/20261027-114524` passed the complete opt-in Harness phase: 14 real-model decisions, 12 Native actions, same Renown delta and BattleSimulation/loot chain, source fixture unchanged and removed, no explicit clock actions, 100% video coverage with source video removed, and game/Host/CLI/session cleanup.
This disposable Bandit battle fixture is not StoryMode progress or full EYC completion.
Contract version 7.352.

In fresh StoryMode run `TestResults/20261027-115510`, the model completed original Clan name/Banner setup and hired a Companion (Native Journal Companion 1/1; Party 1→5), then stopped during further Gold search when its conservative reservation reached ¥4.991 of the ¥5.00 ceiling (reported usage estimate ¥0.913). 63 of its 142 real-model decisions were `observeAgain(waitSeconds=1)` while a Native Map move was active; those waits accounted for many repeated full-state requests even though game time was already flowing naturally.
The Gold-sale subloop now keeps one 1-second poll only for the immediate Native move-start transition, then requires 5–10 second Host-side observations during active travel (prompt recommends 8–10 when far away), without calling any Campaign clock action.
Both the request schema and runtime validator enforce the same interval, so 1-second active-travel polling cannot proceed even if the model ignores the prompt.
A provider self-test verifies the 1-second active wait is rejected and an 8-second passive wait is accepted.
The fresh follow-up `TestResults/20261027-122748` did not reach the Gold-sale movement route, so it does not yet measure this cadence change.
It did naturally enter a hostile Bandit encounter and exercise direct Fight→Send Troops→BattleSimulation; the MainHero was captured, Renown stayed 20, and EYC remained active/unmet after the Native captivity continuation.
Its 89 model decisions used four 2–3 second waits outside the Gold movement subflow, so those figures are not a before/after test of the new 5–10 second policy.
Contract version 7.354.
In fresh StoryMode run `TestResults/20261027-115510`, the model completed original Clan name/Banner setup and hired a Companion (Native Journal Companion 1/1; Party 1→5), then stopped during further Gold search when its conservative reservation reached ¥4.991 of the ¥5.00 ceiling (reported usage estimate ¥0.913). 63 of its 142 real-model decisions were `observeAgain(waitSeconds=1)` while a Native Map move was active; those waits accounted for many repeated full-state requests even though game time was already flowing naturally.
The Gold-sale subloop now keeps one 1-second poll only for the immediate Native move-start transition, then requires 5–10 second Host-side observations during active travel (prompt recommends 8–10 when far away), without calling any Campaign clock action.
Both the request schema and runtime validator enforce the same interval, so 1-second active-travel polling cannot proceed even if the model ignores the prompt.
A provider self-test verifies the 1-second active wait is rejected and an 8-second passive wait is accepted.
The fresh follow-up `TestResults/20261027-122748` did not reach the Gold-sale movement route, so it does not yet measure this cadence change.
It did naturally enter a hostile Bandit encounter and exercise direct Fight→Send Troops→BattleSimulation; the MainHero was captured, Renown stayed 20, and EYC remained active/unmet after the Native captivity continuation.
Its 89 model decisions used four 2–3 second waits outside the Gold movement subflow, so those figures are not a before/after test of the new 5–10 second policy.
Contract version 7.355.

The targeted real-model Gold evaluation `TestResults/20261027-124523` exercised active map movement after the 5-second minimum was added: the model made three passive waits of 8, 9 and 8 seconds, then arrived at `town_ES3` and sold one Native PlayerInventory grain for 30 Denars; Journal Gold increased 32→62, and no clock action was embedded in movement or sale.
Its inner `LiveModelLoopResult` passed with unchanged source hash, disposable clone removal, full visual frame coverage and cleanup, but the outer evaluator falsely failed because it read nonexistent flat `journalGoldBefore/journalGoldAfter/journalGoldTarget` fields.
Native evidence actually stores the values under `objectiveJournalBefore.JournalGoldCurrent` and `objectiveJournalAfter.current/target`.
I corrected the evaluator to use that exact recorded shape and removed an unreachable duplicate GoldSale evaluation branch.
The clean rerun `TestResults/20261027-130429` passed the complete phase: 14 decisions, 8 Native actions, one grain sale (Gold 32→62; Journal 32→62/2000), movement waits 8/9/8 seconds, native trade time unchanged, only the captivity prelude's explicit `resume`, source hash unchanged, temporary clone removed, 100% frame coverage with source video deleted, and process/session cleanup.
The Gold sale moved the objective forward but did not complete EYC. Contract version 7.356.

Natural run `TestResults/20261027-131414` exposed a companion strategy loop: the model twice opened the same Tavern Wanderer offer, saw the current Native hire acceptance was clickable, but chose decline at Gold 840 and again after a sale at Gold 870.
The first recorded frame showed the offer at 468 Denars, so acceptance was within current funds; the model was preserving cash for the separate Gold target while the active Companion Journal target remained unmet.
The Host already exposed the current Native acceptance/decline choices and same-Hero exit, so this was not a missing action.
The Companion prompt now treats hiring one Companion as required progress and tells the model to prefer the current enabled acceptance rather than decline only to reserve Gold for later; it still requires the exact current Native option and leaves the decision with the model.
This strategy change has not been live-verified yet.
Contract version 7.357.

Fresh run `TestResults/20261027-133405` then confirmed the updated Companion guidance: Native Journal Companion moved 0/1→1/1 and MainParty grew 1→10.
It still did not complete EYC: Gold 239/2000 and PartySize 10/25 remained unmet; the current Renown route had no visible hostile bandit.
The child PartySize route reported `decision-budget-exhausted` at decision 64 while the shared parent had a 160-decision and 2-hour budget.
Provider reservation was about ¥2.854 of ¥5 with usage estimate ¥0.542, so the child cap—not the run-level spend ceiling—ended that subflow early.
Recruitment now shares the parent’s 160-decision/2-hour limit.
This removes the old early cutoff; its longer natural run remains to be tested.
Contract version 7.358.

Fresh StoryMode rerun `TestResults/20261027-135719` verifies the PartySize child no longer terminates at decision 64.
It ran 128 model decisions; PartySize reached 9, Companion Journal reached 1/1, Gold reached 109, and Renown remained 20.
The shared ¥5 reservation ended at ¥4.996 (usage estimate ¥0.922) while searching for further sale opportunities; the EYC Journal remained active and unfinished.
Of 27 passive waits, 24 used 8–10 seconds under the Gold map-travel cadence.
The result confirms the child-budget correction removed the earlier local cap, but final recruitment/Gold/renown work still exceeds the current per-run reserve.
The full two-campaign acceptance is not met.

2026-10-27：FreshStoryMode在TestResults/20261027-143132遇到一个人类主角对十名劫匪的原版Encounter：ttack与leave可用、str_order_attack不可用。先前Host正确拒绝了会进入实时Mission的ttack，但因此停在
o-safe-action。现在当坐镇选项确实禁用、Native leave当轮启用时，动作目录才允许选它；执行后须观察到无遭遇的Campaign Map或无选项prisoner_wait，结果标为interrupted/left-encounter-without-battle或captured，父循环仅在Map和原版EYC仍活动时重新规划，不把这条原版Leave误记作战斗胜利或Renown进度。TestResults/20261027-150754的AgentHostPackage通过，含249个Provider合同、16个Campaign loop与11个BattleSimulation loop场景，0次模型调用/0条Native命令。仍需一次目标性Campaign runtime确认Leave的实际返回、CampaignDay及可能的伤亡/俘虏影响；当前自然测试只看到菜单，未执行Leave。Harness contract 7.359。
Fresh StoryMode model run `TestResults/20261027-151233` used `deepseek-flash` and completed 81 model decisions and 66 Native actions before stopping. The original EYC remained active and incomplete at Gold 349/2000, PartySize 11/25, Renown 20/50, Companions 1/1. Provider usage was 302,787 prompt and 4,749 completion tokens, with ¥0.649 estimated and ¥3.495 reserved under the ¥5 cap. No crash occurred; game audio stayed muted, 234 timeline frames were indexed, and the source MP4 was removed.

That run exposed a shared-decision-budget wiring bug: each nested objective received `160 - priorDecisions` as `maxDecisions`, while the child also began counting at `priorDecisions`.
Replanning therefore lowered the effective ceiling.
The child now receives the absolute parent ceiling and carries the prior decision count separately.
`TestResults/20261027-152953` passed the AgentHostPackage run: 250 Provider, 17 Campaign-loop, and 11 Battle-loop self-test scenarios, with zero model calls and zero Native game commands.
Docs passed in `TestResults/20261027-153148`.

Fresh StoryMode rerun `TestResults/20261027-153542` reconfirmed tutorial skip and natural EYC activation with muted audio, no crash, unchanged save-directory metadata, and clean game-process cleanup.
The Agent Host exited with code 1 before readiness, with zero model decisions and zero Native actions; the provider `/models` preflight had succeeded.
The receipt path was gated to `agent-host-lifecycle-test`, while the live StoryMode run uses `fresh-campaign-renown`, so only a generic exit status was available.
The receipt now captures an allowlisted error code and short diagnostic for both modes, redacting Bearer and API-key patterns without writing prompts, model replies, or credentials.
AgentHostPackage passed at `TestResults/20261027-154624`; Docs passed at `TestResults/20261027-155209`.
A fresh live rerun is still needed to identify the Host exit and validate the budget fix.

Harness contract version 7.362.
Fresh StoryMode run `TestResults/20261027-155530` provides the first natural regression of the cumulative-decision fix: Host handshake succeeded, the run passed 81 decisions and ended at 120 instead of the former early PartySize budget stop.
It made 88 Native actions, completed the Companion Journal target, sold one item, resolved a hostile Bandit encounter through Native BattleSimulation, and stopped before EYC completion when the reserved-cost guard reached ¥4.992/¥5.00.
Actual provider usage estimate was ¥0.929 (434,395 prompt / 7,032 completion tokens); this is one run, so the 5.37x reserve gap is a measured case, not a universal multiplier.
Capture produced 4,189/4,189 game frames, indexed keyframes, removed the source MP4, and verified muted audio, unchanged save manifest, no crash, clean processes, and no credential-like text in receipts.
The previous Host exit before readiness in `TestResults/20261027-153542` was not reproduced; its root cause remains unknown because no error receipt existed then.
The new receipt path recorded `provider-budget-exhausted` for this run.
The official-tokenizer cost estimator is packaged.
One synthetic DeepSeek request measured 16,452 JSON bytes; raw-body BPE counted 7,314 tokens, rendered chat plus tool metadata counted 4,160, and the provider reported 4,376 prompt tokens / 64 output tokens.
The new reserve was 5,040 input tokens after the 15% margin and 256-token wrapper allowance.
This synthetic request validates the estimate shape only; the next natural StoryMode run must compare per-request reservation estimates with provider usage.

Natural StoryMode evaluation `TestResults/20261027-174638` then exposed a Campaign interruption gap: while moving toward a Town, the Native MapState opened a 3D conversation with Klas; the visible line had one clickable response.
The Host treated it as ordinary travel and sent 89 waits after its initial conversation choices, while the visible option remained unchanged and CampaignDay stayed at 91081.398.
The user is unsure whether this conversation normally leads back to Map or opens a mission, so that outcome remains unknown.
To avoid more billable no-progress calls, the test-only Host was stopped; Native logged exit code -1 and returned input ownership, then Harness cleaned up Bannerlord, indexed 276 timeline keyframes across 92 events, and deleted the 535MB source video.
This was a deliberate Host stop, not a Bannerlord crash or a successful objective run.
Gold-sale now gives active MapState conversations priority over travel waits, exposes only current clickable options (or Continue when there are no options), rejects stale option IDs, and re-queries Town targets if the dialogue cleared the old move.
The existing adapter only permits these existing Native dialogue actions and does not add game mechanics.
`TestResults/20261027-183534` passed AgentHostPackage with zero model calls and zero Native commands; the regression tests also cover resuming a still-active Native move versus re-querying after it is cleared.
Real-model handling and resuming movement still require a natural StoryMode run.
Contract version 7.365.

自然StoryMode复跑 `TestResults/20261027-184313` 的外层 Harness 阶段为 Passed，但 Host 生命周期收据明确为 Failed，EYC未完成。
真实模型共201次决策/113条Native动作，模型费用估算约¥1.481、保守预留约¥2.458；
Gold 1000→0、Renown 20→21.853、MainParty 1→6。
旅行中出现敌对劫掠者后，Autonomy父循环正确识别Hostile Bandit并调用现有BattleSimulation子流程，但前置子流程已把绝对决策计数推至201，而Battle loop按maxDecisions=160执行，因此没有发出一条战斗决策。
证据在`AgentHostLifecycleHostReceipt.json`：`incidentBattleSimulation`因`decision-budget-exhausted`失败，现Native状态仍在`encounter_meeting`，原版EYC仍active。
另发现GoldSale与Captivity循环把`priorDecisions`从计数中扣除后又使用完整`maxDecisions`，导致子流程绕过父级累计限制。
主角自主战役统一上限现提高至320；
相关子循环改为按绝对累计计数停止，BattleSimulation回归覆盖已有201次决定时仍可完成14步既有坐镇战斗处理。
预留2小时与DeepSeek ¥5预留阈值不变。
此修复尚未通过包测试或自然战役复测，不能用外层Harness Passed标记代替Host/EYC成功。
Harness contract version 7.366。

预算修复的定向回归 `TestResults/20261027-192408` 通过：Host包自检模拟先累积201次父级决定，再从BattleSimulation继续完成14个战斗决定、12个Native动作和原版战后核验；累计trace/route仍为215项。Provider调用0、真实Native命令0。此次只证明共享计数不再把已启动的遭遇战饿死，不证明自然EYC任务完成。Docs与下一轮真实StoryMode复测仍待执行。
自适应决策预算修复 `TestResults/20261027-192408` 的Host包测试通过；其BattleSimulation回归预先计入201个父级决策，仍完成14个模型决定和12条原版动作，并保留215项累计trace与route。`Check-Docs.ps1`发现新的预算门禁误引用了autonomy源变量名，已修正并通过直接门禁运行；完整Harness Docs记录将在本次收尾前复验。新鲜自然StoryMode运行仍待验证是否能处理完整Gold/Party/战斗切换并完成EYC。Contract version 7.367。
StoryMode复跑 `TestResults/20261027-193328` 在 EYC 仍未达成时进入真实Native `encounter` 菜单。
AgentHost确实成功选择了敌对Bandit的原版“动手”对话并推进无选项回应，但最终状态中`attack`/`surrender`启用，`str_order_attack`/`leave`禁用，故BattleSimulation没有合规动作并以`no-safe-action`终止；
Host实际29次模型决定/27条Native动作，运行花费约¥0.182估算/¥0.330预留，CampaignDay=91078.428，Gold1000/Renown20/MainParty1未变。
Harness外层仍Passed仅表示新战役流程、静音、录屏与清理完成；
原版EYC没有完成。
该次证据纠正了“Encounter菜单尚未出现”的猜测：菜单已出现，关键分歧是唯一非Mission退出项`surrender`是否可作为自治的被俘/恢复兜底。
源码与既有Native fixture `TestResults/20261002-064814/Temp/EncounterSurrenderResult.json`证实它会将MainHero加入Bandit PrisonRoster并停用MainParty，随后进入`prisoner_wait`；
用户已确认可在坐镇/Leave都不可用时，让Agent使用原版投降作为最后保命兜底并走俘虏恢复。
`attack`仍是实时战斗Mission，保持在本目标的Agent动作目录之外。
原版投降兜底策略已由用户确认。只在自然途中遭遇/恢复模式且当前Native `str_order_attack`与`leave`均Disabled、`surrender`明确Enabled时，给模型呈现原版投降；随后以`recoverPlayerCaptivity`继续原版俘虏流程。结果必须标记为被俘/恢复，不得称战斗胜利、Renown增长或保留主队。普通Renown BattleSimulation模式仍不允许投降；也不会选择`attack`进入3D Mission。既有源码与Native运行fixture显示投降会把MainHero放入Captor PrisonRoster、停用MainParty、进入`prisoner_wait`，并在Captivity阶段由原版时钟自然推进；投降按钮本身不会被用作时钟命令。当前条件目录/协议适配、Captivity循环接管和StoryMode真实复测尚未完成。

原版投降恢复的条件化执行代码已通过`TestResults/20261027-200554` AgentHostPackage：测试确认只有`recoverPlayerCaptivity`模式且`str_order_attack`、`leave`均不可用、Native `surrender`当前Enabled时才列出该动作；普通Renown模式仍拒绝，Send Troops/Leave优先。假Native验证动作目录与参数边界，不发LLM请求和游戏命令。BattleAndCaptivity提示要求将结果标记为capture并走Captivity恢复，不可称为Battle胜利/Renown；Host incident BattleSimulation调用已打开该恢复模式。真实Native菜单投降→俘虏恢复尚需Natural StoryMode测试。

自然StoryMode运行 `TestResults/20261027-202355` 首次真正使用了用户批准的投降兜底：MainHero通过原版Encounter `surrender` 被俘，Native Captivity出现赎金选项，模型接受当前Native报价后回到Map，Host继续重规划；
全程没有把它报作Battle胜利或Renown增长。
该次最终EYC仍失败：Host receipt为`no-current-integrated-route-available`，未完成任务。
追溯发现PartySize子流程已将原版Journal进度从1提高至5/25后因模型停止而退出；
Autonomy父循环仍永久标记PartySize unavailable，后续其余子目标没带来Journal增长，因而四条路线全被屏蔽。
现在父循环只在失败子目标返回的权威Journal current/target确有进步时重开该路线；
其它临时blocked路线另保存Native状态指纹，只有CampaignDay/时钟档、地图/菜单、主队/经济/俘虏或可见敌对队伍等状态变化后才重开。
`mapSettlementTargets`、`recruitOptions`等纯查询不会反复重开同一条停滞路线。
Journal未进步且Native上下文未改变的失败路线继续临时blocked。
`TestResults/20261027-205657` AgentHostPackage通过，包含“child失败但Journal进度增加后重新开放路线”的回归；
这条再规划逻辑尚需下一局真实模型验证。
`FreshStoryModeModelEvaluation`外层Passed仍只代表Harness创建/运行/清理成功，不代表Host或EYC完成。
Harness contract version 7.372。

自然StoryMode重跑 `TestResults/20261027-212720` 确认用户批准的恢复路径：真实模型遇到一个Send Troops被禁用但Native surrender启用的劫掠者遭遇，选择原版投降并接受赎金，随后回Campaign Map继续规划；
Companion Journal到1/1、MainParty最高13人。
运行以`no-current-integrated-route-available`结束，EYC仍未完成，Renown保持20；
Host收据汇总193个真实模型决定、121条Native动作、约¥1.498 usage / ¥2.431 reservation。
外层Harness Passed只证明测试运行/清理完成。
前一次重试修复确实让PartySize从5提高到13并完成同伴，但仍在部分目标停滞后屏蔽所有路由。
现在新增路由状态指纹：暂时blocked的目标只在CampaignDay/时钟、地图目标、结算/菜单、Party/Economy/Captivity或可见附近Party变化后重新开放；
Journal快照进度仍可直接重开，单纯读取Offers/targets不重置。
该指纹机制的包测试通过后，还需新鲜StoryMode确认不会原地重试并能把剩余目标推进到EYC完成。
Contract version 7.376。

`TestResults/20261027-223905`用DeepSeek在隔离StoryMode Quest存档上验证路线指纹后的自治切片，但Host失败：Gold子目标160次模型决策、87次Native动作、约¥1.327实际估算/¥3.302预留，Gold仍12、主队1人、Renown 5。
Native报价在四个市场没有可卖的玩家Goods；
唯一玩家物品是不可转让龙旗部件。
由此修正两项策略：自然Campaign时间和时钟档变化不再单独重开暂时blocked路线，主队物品数量纳入指纹；
完整Native报价证明没有任何可转让Goods后，GoldSale返回地图即以`gold-sale-no-transferable-goods`停止，不再逐城消耗模型预算；
可转让但当前报价为0的Goods仍可去其他市场核价。
`TestResults/20261027-234500`暴露回归样本漏写`party.itemCount`，导致假失败；
修正样本后，`TestResults/20261027-234813`AgentHostPackage通过，覆盖时间/时钟变化不重开，以及地图/队伍/物品/经济变化重开和“不可转让旗帜 vs 零价可转让Goods”的区分；
Docs `20261027-235134`通过。
该轮不是自然新战役验收，未完成EYC；
自然StoryMode复测仍待核验。
Autonomy live evaluation失败不可因Harness清理成功而称作目标成功。
Contract version 7.377。
`TestResults/20261027-223905`用DeepSeek在隔离StoryMode Quest存档上验证路线指纹后的自治切片，但Host失败：Gold子目标160次模型决策、87次Native动作、约¥1.327实际估算/¥3.302预留，Gold仍12、主队1人、Renown 5。
Native报价在四个市场没有可卖的玩家Goods；
唯一玩家物品是不可转让龙旗部件。
由此修正两项策略：自然Campaign时间和时钟档变化不再单独重开暂时blocked路线，主队物品数量纳入指纹；
完整Native报价证明没有任何可转让Goods后，GoldSale返回地图即以`gold-sale-no-transferable-goods`停止，不再逐城消耗模型预算；
可转让但当前报价为0的Goods仍可去其他市场核价。
`TestResults/20261027-234500`暴露回归样本漏写`party.itemCount`，导致假失败；
修正样本后，`TestResults/20261027-234813`AgentHostPackage通过；
Docs `20261027-235342`通过。

`TestResults/20261027-235641`又从原版新战役开始并无崩溃地完成了同伴目标、队伍1→12人和一笔原版商品销售；金币360→389、声望仍20。真实Host最后报告所有当前集成路线暂时不可用，EYC仍active，故这一轮未通关。失败画面是返回玩家控制的大地图。它证实了“短期路线跑通”与“长程Campaign能持续”之间有一个Harness/Host断点。

开发用的`PersistentEycCampaign`现沿用本机Native `SaveAs`和`load`：首次走原版StoryMode新战役并保存到唯一前缀`ChronicleEycDev-*`，之后每次从同一Campaign instance读取并续跑；Host退出后只在稳定Campaign MapState或无战斗/模态UI的安全聚落菜单保存新检查点，先核hash/存档身份，再更新机器用的续跑manifest。保留当前与前一个有效检查点，孤立旧文件仅按该专用前缀清理。当前自然战役已跨多轮使用同一Campaign ID续跑，但EYC尚未完成；若Host停在进行中的对话/遭遇，检查点会被拒绝，旧检查点保持有效。短测仅用于定位单项故障，不能计作战役门禁通过。最终产品验收仍是Issue #18规定的独立新战役复验；开发中的连续检查点不能替代它们。

为在“所有目标子路线暂时blocked”时保持游戏目标循环，EYC父循环现复用既有`AgentHostCampaignLoop`，将唯一可选动作收窄为当前可见、安全聚落的Native Map arrival。走到新聚落后父循环重新读原版Journal与状态，再决定下个未完成目标；移动本身不加时钟命令，Campaign时间仅按Native移动自然流动。共享原模型provider、决策/Token预算和同一条trace，控制器不把这次旅行称为EYC进度。`TestResults/20261028-010824` Build/AgentHostPackage通过，包含嵌套共享预算/trace和地图到达分类回归；自然持续战役中是否能凭它解除停滞尚未实测。Harness contract version 7.380。

`TestResults/20261028-013058`证明构建失败来自NuGet漏洞索引TLS不可达（NU1900），不是代码。Harness现在只在该错误出现时确认Host依赖仍是单一锁定的Microsoft.ML.Tokenizers 2.0.1，然后用locked restore并跳过不可达的审计端点；Build重试通过，未升级依赖，未启动游戏。7890代理能连端口但TLS握手到NuGet/GitHub失败，提交d832f79已本地提交、等待推送。Persistent EYC Campaign仍待首次连续运行。

`TestResults/20261028-013950`首轮续跑尝试失败在种子存档前：Harness中同一`PersistentEycCampaign`阶段意外注册了两次，因而重复启动了两次种子流程；StoryMode seed readiness随后退出，未创建`ChronicleEycDev-*`存档，测试进程已清理。现已删除重复分支，并将准备失败中的教程/Quest/Host readiness细节写入错误收据；接下来只重试一次，确认原版开局Seed能保存后才继续长测。

`TestResults/20261028-015136`已证明新档教程跳过、Quest自然激活和MapState截图都通过，但首轮检查点保存失败：新战役由Harness的Host自动启动，进程没有Agent CLI session，故在保存时误走了需要该session的CLI路径；没有`ChronicleEycDev-*`存档，进程已退出。现在保存不再调用CLI：FreshCampaign收到Host结束且MapState稳定的Harness ready signal后，由Native `SubModule`在ApplicationTick触发`SaveHandler.SaveAs`，要求无Inquiry/ESC，记录Campaign ID、时间和时钟档前后值。Build `TestResults/20261028-021628`已通过，ready-signal运行实测仍待执行。Contract version 7.380。

`TestResults/20261028-035939`首次证明自然StoryMode可由真实模型处理教程后的原版界面与成长操作；
EYC仍active。
Native SaveAs存档`ChronicleEycDev-20261028040254-f58ab252.sav`由FreshCampaign receipt证明SHA-256 `31EF26AE...710A5EA`、Campaign instance `05896845153e4f019caeb20ebb3603c1`、教程跳过/EYC激活、无崩溃且进程清理；
约133次模型决策/117条Native动作/¥1.264。
模型完成姓名/旗帜设置、训练场离开、移动、酒馆场景交互与招募；
中途Party到13人、Gold曾降至272，最终EYC未完成。
父Harness漏读子脚本的结果文件名，manifest未写。
`TestResults/20261028-042208`已用唯一匹配receipt/hash/Campaign ID恢复manifest，并从同一存档continuesave；
模型继续执行4个父决策/57条Native动作，以`objective-or-decision-budget-exhausted`结束，Party 13、Gold 272、Renown 20，Native已到泽翁尼卡Town菜单。
Checkpoint保存被过宽的`encounterActive`条件拒绝；
实际Native状态为当前Settlement Town菜单、encounteredParty/currentSettlement ID一致、无BattleSimulation/对话/模态UI。
现白名单仅包括非围城town/village/castle对应的安全菜单状态，其它遭遇仍拒绝。
新保存边界Build/Docs/实机待验；
manifest仍指向原Seed，下一轮仍从该Campaign继续。
Harness contract version 7.391。

续跑 `TestResults/20261028-042208` 用收据/hash恢复原Campaign manifest，并从 `/continuesave ChronicleEycDev-20261028040254-f58ab252` 加载同一Campaign ID，没有新建战役。
Host再次选择PartySize，招募路线未继续后切到Renown，再走受限地图到达；
稳定停在原版`town`菜单，位置和遇到对象都为`town_EW2`、无战斗模拟/对话/战利品/ESC/Inquiry。
Native checkpoint guard把所有`encounterActive`一刀切，误把该安全的聚落菜单当作战斗，故Native SaveAs没写出，旧checkpoint仍完整有效。
现将checkpoint条件收窄为：无活动遭遇的稳定MapState，或本轮观察到的当前聚落菜单（`town`/`village`/`castle`、encounteredPartyId=currentSettlementId、非围城、无战斗/模态UI）；
其它遭遇仍拒绝。
该规则仅允许在原版聚落菜单保存，不改玩法动作或时间。
Docs `TestResults/20261028-043812`通过，Build和该保存行为待实机核验，之后继续从同一campaign复跑。
Contract version 7.393。

`TestResults/20261028-044954`从同一检查点继续，Native SaveAs成功并更新manifest哈希。
Host仍未推进EYC Journal：一次运行5次safe-settlement refresh都反复抵达泽翁尼卡Town，模型在招募/交易子路线停止，成本约¥0.31。
AgentHostProgress证明这是真实模型/Native轨迹。
父循环现在记住本Host已访问的安全聚落，并在后续刷新中过滤已访问ID；
若启动时正位于聚落菜单，也先排除当前聚落。
Checkpoint守门现在允许与当前Settlement ID匹配、非围城、无战斗/模态的原版聚落菜单保存。
Docs `TestResults/20261028-050918`、Build `20261028-051001`通过；
新循环/新保存条件的同档运行待验证。
manifest仍选择`ChronicleEycDev-20261028045206-abac5517`，下一次必须从它继续。
manifest原把外层循环次数当模型决策而低估累计用量；
现改为统计AgentHostProgress的provider-decision、prompt/completion tokens及估算成本，并在旧manifest启动时按匹配Campaign receipt回算。
Docs `TestResults/20261028-052308`与Build `20261028-052357`通过。
`052652`未启动游戏：manifest迁移试图给旧PSCustomObject新增属性导致Run-Harness失败。
现通过Add-Member为v1 manifest创建usageMetric字段，再用progress receipts重算；
此修正及迁移结果尚待Docs/复测。
原checkpoint仍为045206，累计成本目前仍是旧低估值。
Contract version 7.397。

2026-10-28: EYC Gold routes now reuse Native BattleSimulation as a bounded loot-acquisition fallback only after Trade verifies no transferable Goods and confirms a free MapState.
Provider/network failures, active encounters, captivity, missions and modals do not trigger it.
The fallback never claims Gold progress; the parent re-reads the original StoryMode Journal.
TestResults/20261028-061056 Build/AgentHostPackage passes the predicate tests; same-Campaign runtime evidence is pending.
Harness contract 7.398.

2026-10-28: the EYC Gold objective composes a Native Trade attempt, a current visible `LandlordTrainingForRetainersIssue` path, and a final current-visible-Bandit BattleSimulation fallback.
The training path accepts only the source-identified direct Quest option, reads the current EYC/Issue Journals and Native PartyVM quote, submits one borrowed-retainer upgrade at a time through the existing adapter, and resolves only the visible return-borrowed-troops Inquiry.
It adds no direct roster or Gold mutation and no hidden clock control.
Contract version 7.399; `TestResults/20261028-070650` AgentHostPackage passed, natural same-Campaign verification pending.
2026-10-28 contract 7.403: the EYC Gold child filters visible `AvailableIssue` givers by the retainer-training marker before it opens dialogue.
`TestResults/20261028-072610` exposed the previous defect: the route entered a hostile-gang quest and repeated four conversation choices for 160 decisions.
The follow-up same-Campaign run `20261028-131010` confirmed it no longer enters that unrelated issue, but exposed a second model-input defect: visited settlement IDs were excluded from `allowedActions` yet remained in the raw map-target receipt/nearby-settlement observation.
DeepSeek repeatedly selected one stale target, causing bounded `training-issue-action-rejection-limit` failures; the run still retained a verified same-Campaign checkpoint and preserved visual/process evidence.
The model-only observation now filters both the copied Native target receipt and settlement list to exactly the current safe action candidates, without changing the Native observation or action execution.
Contract tests cover that stale IDs disappear from both input fields while the underlying Native receipt remains unchanged.
Failed-run usage is retained separately from checkpoint identity; after `131010`, manifest totals were 1,079 decisions and estimated ¥9.08718, with the newly checkpointed Campaign hash selected.
Build, AgentHostPackage and Docs results for this fix are pending.
2026-10-28 contract 7.404: the same-Campaign run `TestResults/20261028-132759` reached the actual retainer-training marker after the previous model-input fix.
The current Native/Host action catalog at the final offer exposed only `issue_offer_player_response_reject`; the real model then repeated reject → reopen giver → same offer until 160 decisions/129 Native actions (estimated ¥1.247), with Gold 0, Renown 20 and Party 13.
This is not evidence that the direct offer was clickable; the Host evidence shows it was not in the currently allowed actions.
The run ended in an active settlement conversation, so no checkpoint was saved; the previously verified 131233 checkpoint remains selected, while failed-run token/cost totals were retained.
The 7.404 policy now permits one Native rejection, then exposes only the visible neutral exit, reports the issue route unavailable/rejected after reaching the free Map, and lets the parent replan/fall back.
Search for issue givers and safe-settlement refresh now excludes non-settlement destinations such as `tutorial_training_field`.
`TestResults/20261028-134634` Build/AgentHostPackage passed (269 provider contract, 22 Campaign loop and 13 battle scenarios; no live model/native calls).
Runtime retest remains pending.
2026-10-28 contract 7.405: following the 7.404 same-checkpoint run, a natural hostile looter intercept with MainParty=1 produced the Native `encounter_meeting` UI containing only “我们已无力再战，全凭你的处置。
” (`bandit_start_defender_3`, TextObject `LLEffOga`) and “也许我们可以找个两全其美的办法。
” (`bandit_start_defender_2`, TextObject `aQYMefHU`); both were clickable, time mode Stop.
Existing normal Renown BattleSimulation correctly had no safe fight action.
The current user-approved survival rule covers this case in `recoverPlayerCaptivity` only when no Fight option is available: the Host may select the exact Native mercy/surrender option and then use the existing Captivity recovery loop; it cannot claim victory or Renown.
Negotiation/barter remains outside the battle route.
The source locale XML proves visible text/IDs; exact callback outcome still needs runtime verification.
`TestResults/20261028-135226` ended in this encounter after Host `incidentBattleSimulation=no-safe-action`; campaign processes were clean and the game frame was captured/indexed.
Code/build/package and same-checkpoint runtime verification for contract 7.405 are pending.
2026-10-28 runtime follow-up (`TestResults/20261028-142740`) verified the weak-party threat branch in the same natural Campaign: with MainParty=1, Host selected the current visible `bandit_start_defender_3` option whose text ID is `LLEffOga`, then the original no-choice response and Native Encounter `surrender` menu action.
The Hero entered `menu_captivity_end_wilderness_escape` and returned via original `mno_continue` to a free Map with MainParty=1; Gold remained 0, Renown 20.
A previous 13-member encounter also went through Fight, found Send Troops/Leave unavailable, surrendered and recovered to MainParty=1.
These are captured survival outcomes, never battle wins/renown credit.
Persistent run result: same Campaign ID; 160 model decisions, 91 Native actions, estimated ¥1.177671; saved checkpoint `ChronicleEycDev-20261028142951-129c0ea8` with SHA-256 `1155769786F7202A5F17A289BC0C27E887788CCA4748E8E697EE9E7A206BA228`, GameProcessesClean=true, visual evidence passed; EYC still active/unmet.
Build/AgentHostPackage `20261028-142259` and Docs `142558` passed.
Contract version 7.405.
2026-10-28 runtime verification of 7.405 (`TestResults/20261028-142740`): from the same natural Campaign checkpoint, the weak-party Native mercy response now goes through `bandit_start_defender_3` → original Encounter `surrender` → `menu_captivity_end_wilderness_escape` → original `mno_continue` → fresh Map.
MainParty=13 on the earlier surrender became 0 in captivity and returned as 1; a later one-person surrender returned to Map with 1.
Gold remained 0 and Renown 20; neither event is counted as a battle win.
The long run retained a verified checkpoint `ChronicleEycDev-20261028142951-129c0ea8` (SHA-256 `1155769786F7202A5F17A289BC0C27E887788CCA4748E8E697EE9E7A206BA228`), same Campaign ID, 160 decisions, estimated ¥1.177671, normal process cleanup and passed visual evidence.
EYC remains active and incomplete.
Build/AgentHostPackage `TestResults/20261028-142259` and Docs `TestResults/20261028-142558` passed before the final formatting-only cleanup; the package must be rerun before commit.
2026-10-28 contract 7.406: a long Campaign run had 160 real model decisions but no objective progress because the Native state stayed `timeControlMode=Stop`, `isMoving=true`, campaign day unchanged at 91092.849, target castle `castle_EW7`, no active encounter/modal; the valid persistent save was retained.
The user's installed `BannerlordConfig.txt` had `StopGameOnFocusLost=True`, matching the failure when Codex held focus while Bannerlord ran in the background.
`PersistentEycCampaign` now temporarily sets only this Native setting to False before starting its game client, records a disposable config toggle/restore contract test, and restores the exact prior value after the game process is clean.
It leaves movement/time behavior inside Bannerlord and does not issue any additional pause/play commands; if the setting is missing/duplicated, or changed by the user during the run, it fails/declines to overwrite instead of guessing.
Same-checkpoint runtime must confirm CampaignDay advances during observed Native movement while Bannerlord lacks focus, then verify user setting restored.
No product gameplay action or EYC completion is claimed by the config helper.
2026-10-28 contract 7.407: focus-loss isolation works and restores the user's setting, but the latest same-Campaign resume exposed a separate startup state: the valid saved MapState already had `timeControlMode=Stop` while MainParty still reported `isMoving=true` toward `castle_EW7`.
With `StopGameOnFocusLost` temporarily false, the Host still had no immediate Gold action and stopped after two decisions; the Manifest safely checkpointed the same Campaign, not a new seed.
The EYC parent now detects only a free MapState with an in-flight settlement target and Stop mode, re-observes current safe map targets, and once reissues the same destination through existing Native `move` (the handler applies the original map-click time behavior).
It verifies StoppablePlay/FastForward, native arrival or a fresh encounter/modal; if the target is hidden or the same move remains stopped after that one click, it stops with a specific failure and never issues a clock action.
The reissue preserves the target the AI previously selected; it does not choose a new destination.
Same-checkpoint runtime verification remains pending.

Natural run `TestResults/20261031-022244` supplied a second pursuit-specific Harness failure: the model chose Native `pursue` for visible `looters_383`, and Bannerlord changed time from Stop to StoppablePlay with `defaultBehavior=EngageParty`.
A second bandit entered the visible list, so `ShouldPauseForVisibleHostileDecision` issued its separate Pause; afterwards the active target was still visible, but time was Stop and MainParty was not moving, while the loop kept requesting `observeAgain`.
The pause policy now checks the live `EngageParty` target before reacting to additional bandits; a currently visible active pursuit is allowed to keep running.
AgentHostPackage `TestResults/20261031-024117` covers the two-bandit classification.
The test was interrupted before an overall Campaign result; no save was produced, and the AutoSave backup guard was explicitly restored afterward.
Natural verification still needs to show resumed pursuit, then encounter or a fresh post-loss plan.

Detached PowerShell 7 run `TestResults/20261031-031135` survived beyond the previous command-session lifetime and recorded 306 model decisions before the Host exited with code -1 and no terminal receipt; Campaign/EYC completion was not verified.
Its Native progress proves EYC Companion 1/1, PartySize16, and one Gold Journal increase.
The last observed state contained an active MapState ConversationManager (`CharacterObject_2092`) with no options; BattleSimulation did not list any conversation action, so the model polled `observeAgain` while the pursuit target remained visible.
The full Native state and exit details are in `MAINLINE.md`.
A bounded Native Map Conversation handler now calls original `dialogueContinue` only when the active Native manager has no options and rereads state; if options appear, only current Native option IDs are listed.
The first package test exposed a Bridge routing mismatch; `TestResults/20261031-042250` Build/AgentHostPackage now verifies the action uses the BattleSimulation Native adapter and the following model request sees the refreshed Map state.
Natural runtime verification is pending.

2026-10-31 pursuit visibility regression: `TestResults/20261031-150443/Temp/AgentEngageVisibilityResult.json` uses a disposable Native fixture (explicit pause for setup, MainParty 1→101, five hostile Looters at range 6), then issues the existing original `pursue` order and observes native movement without additional clock macros.
On loss of the map marker and nearby-party record, the engine clears the target and changes MainParty to waiting `Hold`.
`TimeControlMode` remains `StoppablePlay`, but CampaignDay does not advance for 8.43 seconds after the loss; source save hash and game-process cleanup pass.
This is fixture evidence of the Native visibility-loss state transition, not evidence that natural bandits always flee or that Chronicle can trap them.
The Host catalog then allows a fresh `mapPartyTargets` query and no `observeAgain` control for the stale target; an AgentHostPackage contract self-test locks this replan boundary.
The user is unsure of the visual affordance for the exact map-farewell sentence and for a nearby-but-nonconversational Tavern NPC; no UI cue is asserted from these unknowns.

2026-11-03 affordability baseline: EYC attempts cost ¥0.888657792/126 receipts (034735), ¥0.243306624/30 (052652), ¥1.082892768/159 (054448), ¥1.842125664/247 (061702) and ¥2.73175728/396 (071342).
The 071342 run used the player MCM 256-token ceiling and reached the ¥5 reservation limit without finishing.
Fresh natural StoryMode run TestResults/20261103-075028 cost ¥1.042/141 receipts; it completed the Companion Journal target and advanced Gold via one Native sale, then failed at a visible-bandit interruption.
This is real early progress, not an EYC completion or a cost-per-completion estimate.
Persistent exploratory receipts total ¥24.061092 across 21 runs, separate from the fresh-campaign sample.

2026-11-03 MCM token/cost diagnostics: normal product Host runs write bounded per-decision JSONL under Documents/Mount and Blade II Bannerlord/Configs/ModLogs/AgentRuns.
Events include provider/route, input/output/cache tokens, estimated cost and reservation cap, safe action/control names, compact Native state, provider failures, objective subflows and summary.
Battle Inquiry subruns aggregate into the parent file.
Prompts, responses, rationale, argument values, goals and credentials are omitted.
Each run caps at 8 MiB; 10 owned logs are retained.
View Agent Status shows current-session usage.
The no-game DeepSeek smoke persisted a sanitized cost event.
Training Issue discovery has a 32-decision no-offer budget, and EYC Harness output tokens now match player default 256.
The Host also replans after an incidental battle target disappears, but only when Native verifies safe free Map and the original quest.
AgentHostPackage TestResults/20261103-081923 passed 327 Provider, 24 CampaignLoop and 24 BattleSimulation scenarios with zero model/game commands.
Real MCM rendering, natural replay of lost-target recovery, and cost per full EYC remain unverified.
Contract version 7.512.

DeepSeek routing correction and trace context: the latest natural StoryMode run `TestResults/20261103-082433` used the user's direct DeepSeek API profile (`deepseek-flash`, `FreeLLMAPI=false`), not FreeLLMAPI. It made 265 provider decisions, 1,008,234 prompt / 16,295 completion tokens (246,656 cache-hit / 761,578 cache-miss), with estimated spend ¥1.996058688; the Clan quest remained active and the run ended at `recruitment-rejection-limit` (Companion 1/1, Party 13/25, Gold 602/2000, Renown 21.576/50).
This is a failed partial natural run, not a completed-play cost.
The product progress log and visual-capture trace now additionally preserve Native encounter/target and party movement/survival context (healthy, wounded, prisoners, morale, food and food change) so later diagnosis can compare decisions with the state the model actually saw.
The bounded schema/privacy regression passed in `TestResults/20261103-092010` AgentHostPackage after its initial run caught and corrected an invalid JSON fixture.
Docs verification passed at `TestResults/20261103-092524`.
Contract version 7.513.

DeepSeek prisoner-recruitment rejection root cause: the same failed run's last three `recruitPrisoner` decisions consistently returned `ConfirmPartySizeWarning=false` (JSON boolean) and `ConfirmPrisonerLimitWarning="0"` (JSON string), while the current Native catalog exposed integer enums `[0,1]` and `[1]`; Host correctly rejected them before Native.
`OllamaNativeProvider.BuildDecisionSchema` had hardcoded the first as boolean and defaulted the second to string despite integer catalog values.
The schema now infers a homogeneous argument type from the exact current Native `argumentValues` and attaches that enum, with an explicit integer fallback for these fields.
Provider package regression now verifies the exact three-field prisoner action schema.
`TestResults/20261103-093426` AgentHostPackage passed with zero model calls and zero Native actions.
A bounded real DeepSeek one-shot against the exact prisoner action schema returned `recruitPrisoner` with both confirmation arguments as JSON integers (0 and 1): 1,342 prompt / 99 completion tokens, 640 cache-hit / 702 cache-miss, estimated ¥0.00266592, zero Native actions.
This validates API schema compliance, not the in-game transaction; natural campaign replay is next.
Contract version 7.514.

2026-11-03 Natural EYC replay and Harness evidence gap: `TestResults/20261103-094347` ran 299 successful DeepSeek Flash decisions (1,149,753 prompt / 18,742 completion, 280,064 cache hit / 869,689 cache miss, estimated observed cost ¥2.28061987; the last recorded cumulative reservation was ¥3.8830608).
The corrected integer prisoner confirmations were accepted and the Native party count advanced 17→18→19; subsequent Native volunteer recruiting reached Party21, Gold5, with the last observed Renown22.075.
The EYC quest did not complete.
Host exited with code1 and generic terminal text; no structured lifecycle receipt was captured, so exact terminal cause and any final failed request cost remain unknown.
The no-save test left the save manifest unchanged, reported no game crash and cleaned all Bannerlord processes.
The Harness now aggregates observed provider decisions when the lifecycle receipt is absent, reports whether every captured provider-decision row has an estimate (without implying uncaptured final failures cost zero), and recognizes Native action evidence from completed subflow receipts without inventing an aggregate action count.
The Host receipt reader scans JSON lines in stdout/stderr and records the exit code plus safe structured fields, while never writing raw output.
`Test-AgentFreshCampaign.ps1 -TestAgentUsageTraceSummary` passed with synthetic 2-call totals; Build passed at `TestResults/20261103-114024` and Docs at `TestResults/20261103-120602`.
Contract version 7.515.


2026-11-03 Fresh StoryMode replay with usage fallback `TestResults/20261103-121259`: 323 completed provider-decision rows, 1,151,843 prompt / 20,865 completion tokens, 305,408 cache hits / 846,435 misses, estimated observed response cost ¥2.24640758; every captured decision row had an estimate, but this cannot account for an uncaptured final failed request.
Last cumulative reservation ¥3.9528624.
Native subflow receipts prove actual actions; Party peaked at 17 then fell to15, Gold reached0 and Renown remained20.
The terminal failure was still generic `Host未能完成目标（退出码1）` and no receipt file appeared, so the code/root cause remained unknown.
The full Campaign result JSON can exceed the old 4 MiB receipt-reader ceiling because it includes decision/action traces.
The Campaign Host now emits a compact terminal receipt containing only provider/status/count/token/cache/cost/failure fields and a small termination object; the detailed run trace remains in its owned logs.
A provider contract test verifies the compact receipt excludes full traces and free game text; Build/AgentHostPackage passed at `TestResults/20261103-123730` and Docs at `TestResults/20261103-124507`.
The previous run's MCM/Host receipt is still missing; a new natural run must verify this compact protocol recovers the precise terminal code.
Contract version 7.516.

2026-11-03 PartyState negative/Done loop: the disposable fresh StoryMode replay `TestResults/20261103-125202` was stopped after 438 provider decisions (observed cost ¥2.1549911) because the last 357 decisions were on the same PartyState: 238 `respondInquiry(negative)` and 119 `partyScreenDone`, with no roster/resource change from MainParty5, Gold491, Renown21.922.
Autosave was disabled/restored, the save manifest stayed unchanged, and all Bannerlord processes exited.
This is a confirmed no-progress loop; the exact Native inquiry title/body and action catalog were absent from the old trace.
The product and Harness logs now capture bounded Native Inquiry title/body/button labels, PartyScreen mode/done reason and left/right roster counts/transferability, and the actual allowed action names, while omitting one-use tokens, troop IDs and model rationale.
For EYC when PartySize remains unmet, the Host remembers a negative PartyScreen Done Inquiry and temporarily removes Done from the catalog while a current partyTakeAll/partyLootTransferOne can advance the unmet target; the model must transfer or stop instead of cycling.
If no transfer is available, two unchanged negative cycles terminate with a specific failure.
The bounded decision-rejection counter also no longer resets just because another model response arrived.
AgentHostPackage `TestResults/20261103-141627` passed, including a fake Native regression that forces a second Done after a negative Inquiry and verifies the duplicate Done never reaches Native.
Natural replay of this guard and the live UI summary remains next.
Contract version 7.517.

2026-11-03 BattleSimulation PartyScreen loop protection: a bounded postbattle regression now forces a model to press `partyScreenDone` again after declining the Native Leaving Troops Inquiry.
When the same roster remains and the EYC PartySize target is still unmet, the Host temporarily removes Done while the current Native catalog offers a transferable member/prisoner action; it sends feedback, and the model must transfer a useful currently listed row before returning to Done.
If no roster transfer exists, two unchanged negative cycles stop with a specific no-progress result.
The cumulative invalid-decision counter also no longer resets on each provider response; it resets after a successful Native action or valid wait.
`TestResults/20261103-141627` AgentHostPackage passed this forced-cycle scenario.
The previous live cost run (125202) remained a manually ended diagnostic slice, not a completed Campaign.
Natural replay and Docs validation are pending.
Contract version 7.518.

2026-11-03 Inquiry token overcount root cause: in `TestResults/20261103-125202`, 122 unique `-battle-inquiry-` run IDs each appeared twice with the same provider response, adding 122 false decision rows and ¥0.48107136 to the trace.
The observed call total was 316 unique responses and the corresponding estimated cost ¥1.67391974, versus the raw duplicate trace's 438 rows/¥2.1549911.
`AgentHostDecisionCycle.DecideAsync` already logs each model response; `AgentHostNativeInquiryResolution` was manually logging the same response again for both Yes/No and StoryMode name inquiries, also doubling the normal MCM usage signal/UI accounting.
Removed those duplicate writes and added a regression that one fake Native Inquiry provider call creates exactly one cost-log row.
`TestResults/20261103-141627` predates this dedupe and passed the prior PartyState guard; the new dedupe regression still needs AgentHostPackage.
This is a measurement/logging bug only; it did not issue a second model/API call or increase DeepSeek billing.
Contract version 7.519.

2026-11-03 per-Inquiry usage double logging fix: the disposable run `TestResults/20261103-125202` contained 122 unique Battle Inquiry request IDs, each with the exact same model result logged twice by two adjacent call sites.
The extra rows inflated the observed trace by 122 decisions and estimated ¥0.48107136 (the 438-row trace estimated ¥2.1549911; removing duplicates yields 316 unique replies/¥1.67391974).
This was local MCM progress/usage-signal duplication, not extra API requests or billable tokens.
`AgentHostNativeInquiryResolution` now relies on the single centralized `AgentHostDecisionCycle.DecideAsync` record; provider package self-test asserts one Inquiry API decision writes exactly one trace row.
`TestResults/20261103-151633` AgentHostPackage passed with zero live model calls/zero Native commands.
Contract version 7.520.

2026-11-03 run-cost diagnostics: disposable fresh StoryMode run `TestResults/20261103-143352` received 409 successful provider responses across the campaign/setup calls (1,437,294 prompt / 25,831 completion tokens; 409,088 cache hits / 1,028,206 misses).
Summing per-response DeepSeek peak-rate estimates gives ¥2.735308224; the main Host terminal counters show ¥2.72595012, leaving a visible ¥0.009358104 reconciliation gap that must not be mislabeled as exact billing.
The provider stopped before another request because the current ¥5 cap's worst-case reservation had reached ¥4.9526592; no additional model request or Native action was sent for that rejected reservation.
The run's reported loop decision count (73) did not represent all 409 logged responses.
Player run-summary JSONL now independently aggregates accepted response rows, token/cache totals, cache-hit ratio and cost deltas versus Host counters, and counts provider failures whose usage is absent; every budget refusal records the existing reserve, rejected next-request bound, configured cap, input-token estimate and output ceiling, without prompt contents or credentials.
The same refusal event is captured in Harness progress traces, and each model response carries its current objective/scope tags when supplied by the Host so future reports can group token spend by gameplay route.
`TestResults/20261103-162202` AgentHostPackage passed with fake-provider/no-live-model cost-reconciliation and budget-rejection privacy checks; `Run-Harness -Phase Docs` passed after the MAINLINE update.
Preliminary action-level grouping from this trace assigns 45 `move` responses / ¥0.732479424, 58 `menuSelect` responses / ¥0.40960848, and 107 control/no-action responses / ¥0.521782176 (mostly observeAgain/stop); these are investigation targets, not proof the calls were unnecessary.
This improves diagnostics only; affordability is not yet solved.
The next optimization should use the new ledger to find repeated decisions and oversized observation fields before changing model settings or relaxing the safety cap.
Contract version 7.522.

2026-11-03 HTTP failure observability: fresh StoryMode run `TestResults/20261103-165050` completed the native Tutorial-skip/name/banner setup and activated Establish Your Clan, but its first DeepSeek inference failed with `provider-http-error` before any accepted response, token count or Native action; reservation was ¥0.0065808, no formal save was written, and game cleanup passed.
The Host receipt omitted the HTTP status, leaving 400/401/429/transient gateway causes indistinguishable.
`AgentHostException` now carries safe provider HTTP status, route, output format and bounded retry counters into the player JSONL and Harness event log; response bodies and credentials remain excluded.
`TestResults/20261103-170717/ProviderSmoke.json` then passed a provider-only required-tool-call classification (780 prompt / 64 completion tokens, 640 cache-hit tokens, estimated ¥0.00098112, 0 Native commands, 128 output-token cap).
This proves the current DeepSeek route can answer now; the failed 165050 request status remains unknown because that run predates status logging.
The next natural Campaign replay should use the new per-run failure diagnostics and avoid claiming affordability or EYC progress from the smoke.
`TestResults/20261103-170329` AgentHostPackage passed with the HTTP-failure privacy regression.
Contract version 7.523.

2026-11-03 provider timeout stage diagnostics: fresh natural run `TestResults/20261103-171254` activated EYC, then completed 3 DeepSeek responses and 2 Native actions before a provider timeout; estimated response usage ¥0.00987696, no EYC completion, no crash or formal save, and processes cleaned.
The run predates the new stage fields, so its final timeout cannot identify whether it was waiting for rate scheduling, HTTP response headers, response body, or retry backoff.
While the Host was alive an established TCP connection to local port 7890 was observed; that alone cannot identify whether the upstream, proxy, or response path stalled.
Provider failure events now persist the internal stage, proxy-selection source, timeout, request body byte count and safe transport exception type alongside any HTTP status/retry fields.
`TestResults/20261103-172820` AgentHostPackage passed serialization/privacy regressions; Docs follows after MAINLINE update.
A natural retry is still required to obtain the stage of an actual timeout, then use that evidence to choose the network or request fix.
Contract version 7.524.

2026-11-03 provider-route correlation: natural run `TestResults/20261103-173432` failed on its first DeepSeek call with HTTP 503 (`required_tool_call`, 9,504-byte request, zero retry); it had 1 accepted decision, zero Native actions and estimated usage ¥0.0015577, no save/crash and clean game exit.
The game-side diagnostic independently records the effective proxy as `local-listener` at 127.0.0.1:7890; the Host log previously called the same inherited setting `configured-proxy-environment`, which obscured that both were the same route.
RuntimeController now passes the effective source into the Host, the Host applies NO_PROXY consistently when selecting a fallback, and run/failure rows store only proxy host:port, not credentials.
On HTTP failures it also captures allowlisted Server/Via/request-ID/Retry-After headers, if present, without response body.
`TestResults/20261103-175746` AgentHostPackage passed the proxy/HTTP diagnostic contracts with zero live model calls/zero Native gameplay commands.
Current evidence establishes a 503 through the local listener; it does not identify whether the response originated from the local proxy or DeepSeek upstream.
Next natural attempt must use these headers to distinguish the hop before any route changes.
Contract version 7.525.

2026-11-03 effective proxy hop correlation: the first-call 503 at `TestResults/20261103-173432` had `Server=openresty`, no Via/request-ID/Retry-After, 9,504 request bytes and zero retries.
The same Campaign run was independently recorded by ChronicleDiagnostics as `source=local-listener, host=127.0.0.1, port=7890`; a provider-only DeepSeek smoke at `TestResults/20261103-170717` had also succeeded, so the single 503 does not prove a persistent local proxy or DeepSeek outage.
Parent selection metadata now passes into the child Host so cost/failure rows report the effective local-listener source and endpoint, not the child's inherited environment variable as if it were an external proxy.
Parent proxy selection now respects `NO_PROXY` consistently.
Provider failures retain safe response Server/Via/request-ID/Retry-After headers when present.
`TestResults/20261103-181528` AgentHostPackage passed the source propagation/header privacy contract; Docs follows after MAINLINE update.
Another natural run is needed to collect response-stage evidence and advance EYC. Contract version 7.526.

2026-11-03 bounded provider error-envelope classification: the observed 503 from `TestResults/20261103-173432` had `Server=openresty`, a local-listener proxy and no retry/header request ID; its response body metadata was not captured.
On a later HTTP failure, Host now reads at most 8 KiB/2 seconds only when the media type is JSON and persists the content type plus allowlisted `error.type`, `error.code`, and request ID; non-JSON, empty, oversized, timeout and parse-failed bodies are classified without logging content.
This is meant to distinguish an API JSON `server_error` from a proxy HTML page while keeping prompt/key/body data out of logs.
AgentHostPackage must validate synthetic envelope parsing and privacy before the next live run.
Contract version 7.527.

2026-11-03 EYC model decision ceiling was binding: natural run `TestResults/20261103-183823` stopped at exactly 320 provider responses with `companion-decision-budget-exhausted`, despite only ¥2.360739 estimated response cost and ¥4.136294 reserved under the ¥5 cap.
PartySize reached its Native Journal target during the run, but later battles/losses and the companion path remained unresolved; the original Quest did not complete.
Raise the shared Host cumulative response allowance from320 to2048 while keeping the 2-hour guard and per-request DeepSeek cost reservation unchanged.
Under the default 256 output-token ceiling, output reservation alone is ¥0.0024576/request, so the ¥5 cap should bind at or before about2035 calls; input reservation can stop earlier.
This removes the old 320 ceiling for a cost-bounded DeepSeek run, without changing any Native action or route.
The Campaign-loop fake regression now runs321 cumulative decisions to verify the old ceiling is passed; it does not count as EYC gameplay success.
Package and Docs evidence follow.
Contract version 7.528.

2026-11-03 per-scope cost attribution: the decision-cap replay `TestResults/20261103-191422` recorded 408 successful provider responses, approximately ¥2.77 estimated response cost and ¥4.995 reserved; EYC remained incomplete after bandit interruptions. 227 accepted responses had no scope tag and accounted for about ¥1.36, so we could only classify them as generic loop decisions.
MCM run-summary now supplies `campaign-agent-loop` for those responses and aggregates provider-call count, tokens, cache and estimated cost by each scope; a fake log contract checks two distinct routes reconcile independently.
This does not hide failures or alter model behavior.
Contract version 7.529.

2026-11-03 no-progress loop identified in Gold training route: the process-only ¥10 natural replay `TestResults/20261103-201217` made 629 provider responses / 647 Native actions, estimated ¥6.5907 with ¥9.9913 reserved, but EYC remained incomplete.
Action-level grouping counted 255 `partyUpgradeOptions` calls (¥2.84) and 267 `mapSettlementTargets` calls (¥2.95) in the same unchanged MapState window; the trace shows them alternating while campaign day, party, Gold and Renown stayed unchanged.
Source review found the cause in `AgentHostEstablishClanTrainingIssueLoop`: after a no-upgrade query, its cached receipt was cleared after every map-target query, so the catalog immediately demanded `partyUpgradeOptions` again.
The loop now retains a completed no-upgrade receipt across map target lookup, offers a safe `move` if a target exists (otherwise exits to parent replan), and refreshes after a move or troop upgrade.
This is a product-route cost fix, not a gameplay mechanic change.
A fake regression forces the exact no-upgrade→target-query sequence and verifies it does not repeat the query; next natural run must show reduced calls and continued EYC progress.
Contract version 7.530.

2026-11-03 no-upgrade query loop validation and new runtime failure: `TestResults/20261103-210804` is the first natural EYC run after the training-route cache fix.
The trace shows 275 provider responses, 0 `partyUpgradeOptions` actions, 30 `mapSettlementTargets`, estimated ¥1.99844422, Party peaked at safe ongoing play, and no game crash/formal save; the previous 255/267 query alternation was removed.
EYC nevertheless stopped with `establish-clan-autonomy-unexpected-error` before Journal completion.
The safe Host terminal receipt now includes only the exception type and target method (no raw exception text/stack); `Test-AgentFreshCampaign` surfaces those fields so the unexpected boundary can be fixed.
`AgentHostPackage` and Docs evidence follow.
Contract version 7.532.

2026-11-05 recruitment-call cost increment: `TestResults/20261105-011815` was a fresh natural DeepSeek run interrupted before its intended safe-settlement diagnostic; its receipt proves 7 volunteer hires and 8 offer queries were made as separate model decisions, but does not prove those decisions redundant.
Installed 1.4.8 `RecruitmentVM.ExecuteRecruitAll` is the Native Take All handler.
PartySize now exposes `recruitAll` only when the exact current offer set fits the Journal target, current party capacity and total Gold; it submits the current offer fingerprint and verifies the full Native roster/Gold result after the native handler.
Single-offer recruitment remains available for selective spending.
Build `TestResults/20261105-015358` and AgentHostPackage `TestResults/20261105-015422` passed; the package self-tests make zero model calls and zero Native gameplay commands.
The first attempt (`TestResults/20261105-020837`) placed the bulk probe before the existing capacity-warning check, consumed all local volunteer slots, and then failed the later test precondition; this was invalid test ordering, not a product failure or an LLM run.
The probe now runs in an isolated `-RecruitmentBulkOnly` mode.
`TestResults/20261105-022759` verified one real Native RecruitmentVM Take All transaction without a model: 8 current volunteers, cost160, MainParty 1→9, Gold1000→840, CampaignDay/raw Stop unchanged, exact offer-set hash matched, source save hash unchanged and process cleaned.
This verifies only the Native transaction, not Host EYC catalog selection or natural-model cost savings.
Contract version 7.536.
`TestResults/20261105-023448` also passed a no-model Fake Native/Provider end-to-end PartySize route (quote→recruitAll→Journal target), with 339 Provider contract scenarios and zero real model calls/Native gameplay commands; this verifies Host wiring, not natural model selection.

2026-11-05 over-capacity EYC route guard: `TestResults/20261105-024327` natural-model evidence showed four accepted `ConfirmPartySizeWarning=1` hires at 20/20 capacity, then MainParty fell as low as 1 alongside Gold0/Food negative; this is correlational evidence for severe unsustainable recruitment, not an isolated causal experiment.
The PartySize Host now returns control to the parent planner at Native capacity until Journal Renown is met, with no recruit/query/provider call from that blocked child.
`TestResults/20261105-032903` AgentHostPackage passed a fake state test for this route, zero real model/Native gameplay calls.
The new safety policy is not yet confirmed in another natural run.
Contract version 7.538.
2026-11-05 natural EYC budget run `TestResults/20261105-024327`: 229 DeepSeek responses / 323 Native actions, 695,047 prompt / 15,480 completion tokens, returned-usage estimate ¥1.38315052 and ¥2.495976 reserved; it stopped at `provider-budget-exhausted`, with the original EYC incomplete, no crash/save/autosave and game/autosave cleanup verified.
The model did select `recruitAll` twice (3 and 6 volunteers) but later made four over-capacity individual hires; the campaign then showed Gold 0, negative food and severe roster/morale loss.
This is evidence for the EYC capacity guard, not an isolated proof of what caused each desertion.

2026-11-05 map travel cost change: that same run logged 42 DeepSeek `observeAgain` decisions at 5 seconds during the Gold training-Issue route, estimated ¥0.21294, while ordinary Native map movement continued.
The loop now requires a 10-second observe request and delegates it to the shared Host movement monitor, which polls Native map targets once per second and returns early on arrival, a visible hostile Bandit, a stopped move, dialogue or a modal; it issues no clock action except the separately logged Native pause on a visible hostile.
`TestResults/20261105-035446` AgentHostPackage covers one fake-provider movement decision and one fake map poll, with zero real-model calls, zero Native gameplay commands and zero clock actions; runtime verification is still pending.
Contract version 7.539.
2026-11-05 capacity and travel-poll safeguards: the natural run `TestResults/20261105-024327` supplied the over-limit/attrition evidence recorded in MAINLINE. PartySize now exits before any further model call or recruitment command when MainParty has reached its Native size limit, the Journal PartySize target is still unmet and Journal Renown is below target; the parent blocks only this route on the current free-Map fingerprint.
The parent planner explicitly prefers feasible Renown/income alternatives; it does not override Native roster/Gold.
The same run's training-income travel emitted 42 five-second `observeAgain` calls (~¥0.21294).
That route now requires one 10-second request and delegates to the existing per-second movement monitor, which returns early on arrival/modal/conversation/stopped move or a visible hostile Bandit.
Build `TestResults/20261105-035117`, AgentHostPackage `TestResults/20261105-035446` (341 Provider scenarios; zero real model calls and zero Native gameplay commands), and Docs `TestResults/20261105-035954` passed.
Neither the capacity gate nor passive travel window has yet been re-observed in another natural model campaign.
Contract version 7.539.

2026-11-05 TrainingIssue cross-route failure/fix: natural StoryMode run `TestResults/20261105-040417` reached the original `village_ES3_2` VillagersInNeed ConversationMission during TrainingIssue settlement travel.
The Host mislabeled that `MissionState` as hostile encounter and terminated with `training-issue-interrupted-by-encounter` before continuing the known native dialogue.
Run cost estimate ¥0.73116215 / 104 model decisions, EYC incomplete; no crash, save or autosave, cleanup succeeded.
TrainingIssue now reuses the exact existing VillagersInNeed predicate and safe action catalog: bounded startup settle, current no-choice Continue, and a visible non-starting answer, while omitting the villa-start option.
Fake Host integration is covered by AgentHostPackage `TestResults/20261105-045617`: 342 Provider and 25 CampaignLoop scenarios, with zero real-model calls and zero Native gameplay commands; the scenario asserts Continue→defer→Village MapState, no villa Mission start or time action.
A real-model retest remains outstanding; contract version 7.540.

2026-11-05 natural EYC trace exposed a stale stalled-move retry budget: `TestResults/20261105-043958` selected the same Native settlement target `town_ES4` on Campaign days 91080.113 and 91082.745.
The autonomous Host had a run-wide set keyed only by settlement ID, so after a previous Native Move re-click it terminated a later, naturally progressed move as `native-stalled-move-retry-exhausted`.
The retry guard now keys its one-attempt circuit breaker to Campaign-day progress since the prior Native Move re-click: same target/same day stops without another re-click; same target after Campaign time advances may be retried; a missing/nonfinite Campaign day fails closed.
It never changes the clock.
AgentHostPackage `TestResults/20261105-051537` passed the deterministic same-day/no-day-advance/advanced-day cases (343 Provider-contract and 25 CampaignLoop scenarios; zero model calls and zero Native gameplay commands); Build `TestResults/20261105-051514` passed.
The original natural trace's retry-exhausted outcome is not a success signal; a future capped live evaluation must verify this exact path after unrelated fixes are integrated.
Contract version 7.541.

2026-11-05 cost-capped natural StoryMode run `TestResults/20261105-052535`: DeepSeek-flash made 86 decisions/123 Native actions, 279,126 prompt and 5,438 completion tokens; returned-usage cost estimate ¥0.54683605, reserved upper bound ¥0.9937872 against the configured ¥1 cap.
The original EYC remained incomplete; the party reached 18/20 native capacity, Gold 2, Renown 20.
The provider stopped before limit violations or the movement-stall regression was encountered; therefore this run verifies bounded cost-stop behavior and some natural PartySize progress, not those fixes.
No new save/autosave, crash or surviving game process; unseeded disposable campaign was cleaned.
A follow-up attempt to resume the existing long-lived native campaign, `TestResults/20261105-053612`, failed before model/game startup: `PersistentEycCampaign` passed 86400 seconds but `Test-AgentLiveModelLoop.ps1` rejected it because its argument validator allowed only 7200.
The existing manifest and hash-verified save were unchanged.
The child limit now matches the persistent 24-hour contract and Docs checks both sides; contract version 7.542.

2026-11-05 Persistent EYC continuation `TestResults/20261105-054753` resumed the existing Campaign ID `05896845153e4f019caeb20ebb3603c1` with `deepseek-flash`; one run used 96 decisions, 304,922 prompt/6,540 completion tokens, estimated ¥0.581148.
The verified checkpoint started with MainParty 1, Gold 0 and Renown 20.
Host repeatedly chose 10-second `observeAgain` while Native still reported `timeControlMode=Stop`, `party.isMoving=true`, target `village_V2_1`, and CampaignDay 91120.150 unchanged.
The calls were not advancing the campaign; I sent the Harness `stop` command instead of letting them continue to burn the ¥2.50 session cap.
Native stop receipt completed, Bannerlord PID 39072 was stopped and the temporary engine config was restored.
Harness did not produce a new verified checkpoint; the previous hash-verified source save remains selected.
This is evidence of a no-progress observation-loop defect, not a completed test.

2026-11-05 FreeLLMAPI one-shot Provider test `TestResults/20261105-140745`: FreeLLMAPI started hidden with its existing proxy bootstrap, `/v1/models?available=true` listed 197 routes, and `free-router` was marked ready.
The single required-tool-call request (128 output-token cap, 30-second deadline, ¥0.10 run limit) reached FreeLLMAPI and returned HTTP 429 with `Retry-After: 85`; the Provider made zero retries and received no usage-bearing model completion.
No Bannerlord process or game action was involved.
This verifies endpoint reachability and the current route's rate limit only; it does not establish that another FreeLLMAPI route works or that the rejected request incurred no upstream charge.

Follow-up FreeLLMAPI single-call route probes `TestResults/20261105-164619` (`auto:noema-free`) and `TestResults/20261105-170335` (`gpt-oss-20b`) also failed the Host's `required_tool_call` contract: no decision tool call was returned.
The local FreeLLMAPI SQLite request log shows the first route attempted six upstreams: five failures each recorded 777 input/0 output tokens, then a custom NVIDIA route succeeded with 957 input/128 output tokens (requested Nemotron Ultra, served Super 120B).
A preceding NVIDIA fallback reported free capacity exhausted and advertised paid requests from $0.002.
The `gpt-oss-20b` call through OVH succeeded with 602 input/128 output tokens but still no tool call.
Together the gateway logged 6,221 input/256 output tokens across the three routes, but these are request counters, not a billing receipt; exact charge is unknown.
Installed FreeLLMAPI is 0.16.16; official repo release v0.16.19 exists, but no inspected release note proves it fixes this exact route.
Do not use `auto:noema-free` for another test because its fallback reached a custom route; first compare the provider request/response contract and app version at zero inference cost.
No game launched.

2026-11-05 no-progress map wait fix: persistent EYC run `TestResults/20261105-054753` repeated 10-second `observeAgain` decisions while `timeControlMode=Stop`, `party.isMoving=true` and CampaignDay stayed 91120.150.
TrainingIssue, PartySize and generic map travel now expose movement observation only while Native time advances; the shared monitor returns a stopped in-flight settlement Move immediately, and child loops yield it to the EYC parent.
The parent reissues only the currently observed Native Move under its existing same-day retry circuit breaker; no clock action is hidden.
AgentHostPackage `TestResults/20261105-160639` passed 345 Provider-contract and 25 CampaignLoop scenarios with zero model calls and zero Native gameplay commands.
A persistent live run is required to verify natural movement recovery; the full EYC quest remains incomplete.
Contract version 7.543.
2026-11-05 Provider failure diagnosis improvement: the FreeLLMAPI calls returning `provider-tool-call-missing` did not provide enough evidence to distinguish a plain-text model answer from an adapter/format mismatch.
`OllamaNativeProvider` now logs only tool-call presence/count, content type/character count, finish reason, response model, routed-via and returned input/output tokens when a required tool call is absent.
It never records prompt/response text, tool IDs or arguments.
A deterministic ProviderContractSelfTest feeds a private fake response and verifies the metadata/redaction.
This adds diagnostics only; it does not accept plain text as a Native action.
AgentHostPackage `TestResults/20261105-232133` passed with 346 Provider-contract/25 CampaignLoop scenarios and zero real-model calls/zero Native gameplay commands; contract version 7.544.
2026-11-06 single structured-output FreeLLMAPI smoke `TestResults/20261106-001534` succeeded without launching Bannerlord: pinned `gpt-oss-20b` routed via OVH and classified the goal as `supported-village-tools-quest` (529 prompt / 126 completion tokens, `NativeCommands=0`).
The initial JSON-Schema attempt truncated at the 128-token cap (552 input / 0 output); the Host's JSON-object fallback made a second request and succeeded.
FreeLLMAPI's local DB confirms both upstream attempts used OVH. For the next real Campaign continuation, use explicit `json_object` mode to avoid that extra failed request, keep the same hash-verified Campaign save, and run a bounded session; no additional route smoke is needed.
This proves only one provider decision, not EYC progress.

2026-11-06 model-call guard: persistent StoryMode continuations default to one provider decision, and live Campaign model tests require `-FreshStoryModeModel` explicitly; there is no implicit DeepSeek or other route. Choosing a larger decision budget also requires an explicit command-line override. The selected route is checked before inference, but catalog readiness alone does not guarantee an upstream response. Contract version 7.546.

2026-11-06 EYC output cap correction: `Test-AgentLiveModelLoop.ps1` keeps its 256-token default when the caller provides no override, but now preserves an explicit `CHRONICLE_LLM_MAX_TOKENS`. Contract version 7.547.

2026-11-06 provider-failure trace: the live StoryMode receipt now correlates Host failure request IDs with FreeLLMAPI's local `[Proxy]` log lines and projects only timestamp, provider, model, latency and a coarse failure class. It omits key IDs, prompts, raw upstream messages and response bodies. A synthetic request/log self-test verifies prefix and time matching without model calls. Contract version 7.548.

2026-11-06 LLM7 free-route preparation: the live StoryMode model allowlist accepts `llm7-fast-router`, but no route is selected by default; it still requires an explicit `-FreshStoryModeModel` and FreeLLMAPI must report it ready before game startup. Free-plan tests use prompt-only JSON validation, not forced tool calling. Contract version 7.549.

2026-11-06 configured-provider preflight: the early read-only model check supports either FreeLLMAPI or an explicitly configured remote OpenAI-compatible HTTPS endpoint, including DeepSeek. It checks `/models` and the exact selected model before Build/Smoke; it sends no inference request. Contract version 7.552.

`TestResults/20261107-073719`在同一Campaign中完成19次DeepSeek决策，实际估算¥0.090696288（52581输入 / 1069输出token）。
Agent通过原版劫匪遭遇的俘虏/赎金路径恢复，金币670→424，主队一度不可用，随后Native恢复。
Companion记忆trace先显示资源下降后复用，再显示Journal PartySize 0→1的正向变化后清除旧Town排除，两个Native checkpoint写回均确认成功。
这验证了资源下降与正向Journal进度的区别；
由于日志有意省略Town ID，不声称它证明某个具体城镇未被重访。
EYC没有净进度，最终Gold 424、PartySize 1、Renown 20、Companion 0。
Native地图存档`ChronicleEycDev-freshB-20261107073947-178ae0f7`（SHA-256 `290434B413E7BF260B83C933F4654D09724EBD9DC457A562DCBCD3DC4C0EB35C`）同Campaign身份与进程清理通过，当前地图移动目标为EW6；
后续单轮计划见OpenSpec 3.1d。
`TestResults/20261107-075155`同一Campaign续跑26决策（最多30）、估算¥0.150504768。模型选择Companion并复用EW3→EW6地图路线，遭遇劫匪后经过俘虏/恢复，随后仍未达到Journal目标；EYC最终Gold424 / PartySize1 / Renown20 / Companion0，任务没有增长。安全Native Campaign Map检查点`ChronicleEycDev-freshB-20261107075501-f79da9ba`（SHA-256 `06C5FA932950CF6581336F521D53F20565E7624FBAED7C451D3C6898D47267D1`）和进程清理通过。已连续多轮看到模型反复选择Companion、遭遇/恢复、再回到同伴或队伍路线但未提升EYC Journal；若下一次相同循环重现，应暂停重复Live调用，先改父级目标重选/失败反馈链，不能把存档自然进度误报为完成。
`TestResults/20261107-080214`在同一Campaign中运行27次模型决策，估算¥0.142665696（79553输入 / 1527输出token），费用保护在下一次请求前停止。Agent从主线选择PartySize并调用原版`recruitOptions`；Sargot志愿者界面显示27个候选，其中16个当前可负担，最低20金币，队伍容量20。模型尚未选择具体兵员，Journal没有变化。安全Native SaveAs检查点`ChronicleEycDev-freshB-20261107080443-0a5b1e2b`（SHA-256 `985393AEBF350AA0A23D8CE22D83DC4F3891E67CC32F35A175E2C412ACEA44AA`）与进程清理通过。该切片第一次真实走到原版志愿兵报价列表；下一轮最多8决策 / ¥0.10，从当前稳定招募菜单确认是否能完成一次招募并反映到Journal。
`TestResults/20261107-081552`作为一次8决策 / ¥0.10的有界续跑从`080214`安全存档重新启动，模型又选了Companion；遇到劫匪后费用保护在下一步前停止，实际¥0.037412352（20964输入 / 475输出token）。无EYC Journal进展，也没有新安全SaveAs，原安全检查点`ChronicleEycDev-freshB-20261107080443-0a5b1e2b`仍是当前源。它证明重启Host后模型没有“上次选Companion没有招募”的上下文，仍可能重复选同一子目标。为避免继续花费模型费做重复路径测试，下一阶段先针对原版Campaign checkpoint中的子目标尝试结果做可测量设计与无模型回归，再恢复Live测试；本次不是EYC完成。

2026-11-07 Visual capture refinement: `LiveModelWindow` previously produced only capture-start/failure frames for a real AgentHost run with 8 same-target Tavern navigation decisions; the index showed 2 events despite a 67.2-second clip, because the live loop only fed legacy `$steps` into the event timeline.
The capture Harness now converts sanitized `AgentHostProgress.jsonl` provider-decision timestamps/actions into timeline events and samples long clips at a five-second overview cadence (max 24 contact-sheet samples).
Repeated `missionNavigateToAgent` decisions get individual event keyframes with no raw prompt/rationale, while mode-changing Native decisions keep before/event/after frames.
`Check-Docs` runs the pure projection/interval self-test without a game or LLM; the prior clip was already deleted after compaction, so the new path still needs one new visual run before claiming runtime capture coverage.
Contract version 7.558.

2026-11-07 Native checkpoint readback Harness phase: the bounded `freshB` continuation saved a verified new Campaign checkpoint with an EYC objective attempt, but the long-running gate does not reload a newly written save in the same test.
The opt-in `Run-Harness.ps1 -Phase EycObjectiveCheckpointReadback -PersistentEycCampaignKey freshB` checks the branch manifest/hash, loads that exact save in a fresh Native process, reads `agentCheckpointGet`, verifies Campaign identity and reports the count/content of any structured pending/blocked EYC attempts (including zero), then calls Native `questDetails` for the original EYC Journal.
It reports the four original Journal goals plus MainParty membership/capacity, Clan tier/renown, and only the count of checkpointed unaffordable Wanderer records (never their Hero IDs), with 0 model calls/cost and an unchanged source file.
`TestResults/20261110-184422` passed: same Campaign ID, Gold64/2000, PartySize19/25, Renown20/50, Companions0/1; `companions=blocked`, `partySize=pending`, process clean.
Contract version 7.563.

2026-11-07 EYC settlement-checkpoint restart gap: real run `TestResults/20261107-103723` resumed `freshB` from the verified `town_backstreet` save, but the new Host re-called `selectEstablishYourClanObjective` before reading its pending Companion attempt.
The run stopped at 16 provider decisions (¥0.100015872 estimated spend) when its next conservative reservation would exceed the ¥0.20 ceiling.
The overall route then returned through Native Tavern dialogue and pursued a looter; its final moving state was not safely saveable, so the prior verified checkpoint remains authoritative.
Review found a safety-rule mismatch: SaveAs permits this exact non-sieged settlement menu when the current Back/Leave option is enabled, but objective-memory read/write rejected all `encounterActive=true`, including the Native settlement context.
`IsSafeObjectiveAttemptCheckpointState` now admits only current Town/Village/Castle menus whose settlement identity matches the encounter and current settlement record, rejects siege/modal/party/inventory/captivity state, and additionally requires Native Back/Leave on `town_backstreet`; genuine hostile Party encounters stay unsafe.
Package Build + AgentHostPackage passed at `TestResults/20261107-105306` with zero live model calls and zero Native gameplay commands.
Its fresh-Host fake regression proves the child resumes without an objective-planner call from a saved Backstreet state.
Bounded same-Campaign confirmation `TestResults/20261110-172629` then verified the production Host path: after one goal classification, the next model response was already in the Companion subgoal, with no EYC objective-selection request.
It made 11 decisions / 20 Native actions, estimated ¥0.110897952 with ¥0.1842696 reserved against the ¥0.20 cap.
The model opened the Tavern scene but repeated the same Wanderer navigation nine times (8 same-target repeats); selected distance plateaued near1.363, zero targets became interactable and no conversation/Journal progress followed.
It pursued a looter, stopped on the cost ceiling, and could not SaveAs from Mission/active movement, so the original `freshB` source remains authoritative.
Visual capture covered 166/166 frames, kept 21 indexed keyframes, removed the MP4, and all processes were cleaned.
This confirms checkpoint resume but identifies a distinct Companion route defect: the post-navigation scene observation is automatic and bypasses the existing no-progress evaluator, so the model can repeatedly reissue the same navigation.
That repair is tracked separately; the two-campaign #130 gate remains unmet.

The settlement-checkpoint correction was verified by the `TestResults/20261110-172629` continuation and archived at `openspec/changes/archive/2026-11-10-eyc-attempt-checkpoint-settlement-eligibility`; the stable spec now records its safe settlement-menu boundary. `TestResults/20261110-175719` passed Docs/OpenSpec validation after that archive.

2026-11-10 Companion automatic-scene navigation stall: `missionSceneAgents` after a completed `missionNavigateToAgent` was generated by the Host itself, so it did not pass through the older model-action handler containing `EvaluateNavigationNoProgress`.
The shared `ReconcileNavigationProgress` now runs for both automatic and explicit scene scans.
A fake Native/Provider regression simulates 10.201→1.365 followed by two unchanged, non-interactable scans and verifies the target is excluded after three total navigation attempts and Native `missionLeave` is used before a safe Map stop.
Build/AgentHostPackage passed at `TestResults/20261110-181859` with 0 live model calls and 0 Native gameplay commands; Docs/OpenSpec passed at `20261110-182448`.

The bounded same-Campaign confirmation `TestResults/20261110-182841` kept Campaign ID `683a2e21c4a64cfd8a1bb4f3392afc3d`.
The fresh Host used 14 provider decisions and 20 Native actions; the current Wanderer became interactable after one navigation and original `missionInteract` started the conversation.
Its Native quote was 432 Denars while the player had 424, so the model chose the current “cannot pay” option and left.
It then selected PartySize and submitted Native `recruitAll`: MainParty members 1→19, Gold 424→64.
The run reserved ¥0.1881624 against the ¥0.20 cap and estimated actual spend ¥0.104729088; the next request was rejected before dispatch.
Safe settlement checkpoint `ChronicleEycDev-freshB-20261110183132-08783004` was retained with SHA-256 `A393432750AF30065F1BD9E521DA66911A18BC66891DC285D19D0340617D7308`, and game/Host/session cleanup passed.
Video coverage was 269/269 frames; indexed keyframes remain and the source MP4 was removed.
The generalized Native-only readback `TestResults/20261110-184422` then confirmed Journal Gold64/2000, PartySize19/25, Renown20/50, Companions0/1 and checkpoint entries `companions=blocked`, `partySize=pending` with zero model calls/cost.
EYC remains active and incomplete; the next continuation should address the blocked Companion route's 432-denar affordability and continue PartySize from the saved state.
最后一次短续跑`TestResults/20261107-081552`仅给8个模型决策、¥0.10上限，模型又选择Companion并被劫匪遭遇中断；第8次请求预算保护后停止，实际¥0.037412352，没有Journal进度，也没有新的安全存档。当前仍使用`ChronicleEycDev-freshB-20261107081300-dd5fe3a8`（Campaign ID `683a2e21c4a64cfd8a1bb4f3392afc3d`）；该分支累计483次provider决策，估算¥2.495247。当前证据只证明独立续跑重启后会再次让模型选择，不足以证明连续运行中的真实Agent会同样循环。Companion记忆OpenSpec已完成归档，稳定能力规格同步到了`openspec/specs/companion-search-recovery/spec.md`。下一步是在#130下处理可保存的最近目标尝试摘要，给重启后的planner提供上次失败/无进展的证据，但仍让模型决定目标；先做无模型Host回归，再重新实测，避免继续用低预算反复走同一条路线。
2026-11-07的EYC attempt-memory重构已归档为`openspec/changes/archive/2026-11-07-eyc-objective-attempt-continuity`，稳定规格为`openspec/specs/eyc-objective-continuation-memory/spec.md`。其后在#130下完成并归档settlement checkpoint eligibility：同一`freshB`存档中的`companions=pending`在新Native进程里验证读回，实际Host随后无需重新选择EYC子目标即可恢复到Companion子流程。两者都没有完成原版EYC Journal。

Companion自动导航停滞变更`eyc-companion-navigation-stall-recovery`已实现并归档，稳定规格已同步到`openspec/specs/companion-search-recovery/spec.md`。
`TestResults/20261110-181859`包测试通过：模拟一次测得接近，随后两次无进展，Host在自动场景扫描后排除目标并走原版离开，0真实模型调用、0Native游戏命令；
Docs/OpenSpec验证`TestResults/20261110-185258`通过。
实测`TestResults/20261110-182841`未自然触发停滞：新Host恢复Companion，Wanderer经一次导航后可交谈，但报价432高于424金币，模型按原版拒绝并离开；
随后真实招募18人，MainParty1→19，Gold424→64。
14次决策 / 20条Native动作，估算¥0.104729088，保守预留¥0.1881624；
下一请求在发给模型前被¥0.20上限拦截。
安全镇菜单存档保留，视频完整覆盖269/269帧，事件索引16项/46张关键帧，21张概览采样，无提取失败，原MP4已删除，游戏/Host清理通过。
零模型存档读回`TestResults/20261110-184422`确认原版Journal Gold64/2000、PartySize19/25、Renown20/50、Companions0/1，以及同一Campaign尝试记忆`companions=blocked`、`partySize=pending`。
原版EYC仍未完成；
下一步从当前Journal和存档继续，核对PartySize容量门槛及Renown路线，不重复尝试已经证明支付不起的同一同伴报价。

2026-11-11 Battle Mission formation probe：新增opt-in Run-Harness.ps1 -Phase BattleMissionFormationProbe -BattleSimulationSourceSaveName <owned-disposable-save>，先用Native SaveAs创建临时副本并验证源哈希，再记录原版attack→OrderOfBattleVM Ready→Battle→F6等价委派、MainAgent Formation/Detach与健康状态、Mission结束及Native aftermath；不调用模型、不用Windows全局输入；仅在副本测试后哈希未变时删除副本。该探针仅用于解决F6后主角缺乏行动的问题，不等于已证明主角安全。Contract version 7.564。

2026-11-11 Native Deployment/Host integration proof: the packaged Host now uses the game-owned Auto Deploy route when the Order of Battle Ready callback is missing, validates the Native Battle/aftermath state before continuing after a late Native UI exception, delegates troop control once, hands MainHero to Native AI, and returns to PartyState.
TestResults/20261111-191252 passed with 0 model calls, Campaign Stop, MainHero health 100→100, MainParty 20→18, Renown 20→22.292, source save unchanged, disposable clone removed, and game stopped.
The native UI callback reported a NullReferenceException after Mission had already entered Battle; the Host accepted the result only after Native state readback confirmed Battle and deployment finished.
This is one field-battle sample, not evidence of safety across battles or siege/mission types.
Contract version 7.576.

2026-11-11 Solo MainHero battle repro harness: `Run-Harness.ps1 -Phase BattleMissionHostNativeAiAutopilotProbe -BattleMissionSoloMainHeroProbe -BattleSimulationSourceSaveName <owned-disposable-save>` selects a test-only Native fixture that preserves a one-member MainParty and spawns one stationary hostile looter five map units away; only this solo fixture disables the test opponent's map AI so the MainHero's Native pursuit initiates contact.
It issues a separately logged Native `resume` only when the fixture clock is still Stop after `pursue`; target pursuit and clock control remain distinct actions.
The real Native solo probe `TestResults/20261112-000251` passes: Host reconciles the Native Deployment→Battle transition, skips `missionFinishDeployment`, skips F6 because `PlayerTeam.FormationCount=0`, hands MainHero to Native AI and returns to the Native `prisoner_wait` aftermath after a real defeat/capture (health 66→11, Party 1→0, Renown 20 unchanged), with Campaign Stop, 0 model calls, unchanged source hash, verified disposable-copy deletion and stopped game.
This verifies the Host subflow for one solo field battle; it does not prove the real-model EYC planner recovers from captivity or completes the quest.
Contract version 7.577.
2026-11-12 FreeLLMAPI missing-tool response diagnostics: bounded natural continuation `TestResults/20261112-001739` received an `auto:reliable` goal-classification tool call via `ovh/Mistral-Small-3.2-24B-Instruct-2506` (1385 input/40 output tokens), but its next response failed `provider-tool-call-missing` before Native actions; the run safely checkpointed, used no reported paid cost and cleaned processes.
The previous failure event contained only the code, although the Provider already had safe route/shape/usage fields.
`AgentHostException` now carries only a whitelist (tool-call presence/count, content kind/length, finish reason, response model, routed-via and usage) into the failure event; it never stores response text, prompt, tool arguments or credentials.
AgentHostPackage covers the allowlisted fields and redaction.
AgentHostPackage `TestResults/20261112-004058` passed with a synthetic Mistral-shaped missing-tool response and verifies these safe fields and redaction.
This is observability only: it does not accept plain text as a decision or establish EYC progress.
A bounded 1.4.8 retry at `TestResults/20261117-210725` used the new fields: goal classification came via `ovh/Qwen3.6-27B` (1536/335 tokens), then the free Kilo/Nemotron action route returned String content (2457 chars) with finish_reason=length at the 512-token cap.
Raising that cap to 1024 in `TestResults/20261117-212136` produced two structured decisions (free Dots classification and OVH Qwen3.5 objective selection `companions`), but the 2-decision run budget expired before its companion subflow could act.
Both continuations made 0 Native actions, estimated cost 0, and safely saved same-Campaign checkpoints.
The follow-up used gpt-oss-20b with JSON Schema after a zero-call capability check; four structured decisions were accepted, ending at a mapPartyTargets read-only observation when the 4-decision cap expired, with no Native action or EYC progress.
Host cost estimate was 0 (upstream billing is not separately reported).
The next bounded run retains JSON Schema and raises the cap to 6 under ¥0.20; DeepSeek and local models remain unused.
Contract version 7.579.

2026-11-17 provider cooldown note: the `gpt-oss-20b` JSON-Schema continuation reached `mapPartyTargets`, then the OVH upstream returned HTTP 429 / Retry-After 82,721 seconds before an action response.
The campaign checkpoint and cleanup succeeded; no model route retry was sent.
The next bounded test uses the FreeLLMAPI catalog model `dots3-note-preview` (ready; advertises tools and tool_choice; previously returned one real structured decision via Kilo/free) to avoid the OVH cooldown.
Local Host cost estimate was zero, but FreeLLMAPI did not provide a separate billing receipt.

- 2026-11-18 required-tool truncation recovery: `TestResults/20261118-194401` resumed from the Town Backstreet checkpoint and the explicit Dots route returned a 4,801-character string at the 1,024-token output limit with zero tool calls while only `menuSelect`/`stop` were listed. No Companion action ran; Native SaveAs wrote checkpoint `ChronicleEycDev-freshB-20261118194642-422a3b16` (SHA-256 `81B34C7C33EF3D2400DDC0640C7597C9D0BA4574D33E7EB7A2BED667C81CE50`), the same Campaign continued, and EYC stayed incomplete. The parser previously classified this as `provider-tool-call-missing` before considering finish_reason; it now classifies `length`/`max_tokens` with zero tool calls as `provider-response-truncated`. That shape receives one bounded same-catalog correction, with no Native action before a valid single tool call; repeat failure stops. Recovery self-test, AgentHostPackage `TestResults/20261118-195624` and Docs `TestResults/20261118-200011` pass. The correction has not yet been live-tested; next continue from the new checkpoint with up to 20 decisions, 1 HTTP per decision and 1,024 output tokens. No model size increase.
- 2026-11-18 dynamic EYC planner prompt: the follow-up `TestResults/20261118-200756` showed the read-only goal planner's fixed 3,686-byte system prompt also truncated at 1,024 completion tokens twice; no Native action was issued and EYC stayed unchanged. The planner now builds guidance only for objective IDs currently present in the Native unmet-objective action catalog (all-four prompt 2,115 characters; Companion-only under 1,250), while retaining the Journal authority, party-limit/Tier1 dependency, volatility of current Gold, Renown route, and current Native hire-acceptance constraints as applicable. Package self-tests passed at `TestResults/20261118-204141`. Docs initially caught a stale source-string assertion after the planner test identifier changed; `Check-Docs.ps1` now checks the new exact assertion and Docs pass at `TestResults/20261118-204731`. Next: one bounded same-Campaign continuation from `ChronicleEycDev-freshB-20261118201027-ddc673e2` (SHA-256 `DE7AB5A0F75DCB4A420D53D6EBB7298E7E2BE337AE7FD29D742C86D8BB84C3E5`), explicit `dots3-note-preview`, up to 20 decisions, one HTTP request per decision, 1,024 output tokens and ¥0.20 ceiling; inspect prompt/failure telemetry and Journal changes before deciding another increment. The known cost remains a lower bound; EYC remains incomplete.
- 2026-11-18 recovery follow-up: `TestResults/20261118-205556` did not send a request or launch Bannerlord because the test process inherited the user-level DeepSeek endpoint while explicitly selecting the FreeLLMAPI Dots model. A process-only FreeLLMAPI override passed read-only catalog preflight. The next run (`TestResults/20261118-210046`) then exposed the separate user-level `CHRONICLE_LLM_MAX_TOKENS=256` cap: goal classification returned `finish_reason=length` at 939/256 tokens with no Native action. Using process-only `max_tokens=1024`, classification succeeded in `TestResults/20261118-211102`, but the dynamic EYC planner still produced two truncated required-tool responses at 1,024 completion tokens (system/user payload 1,784/2,923 then 1,784/3,386 bytes); no objective action executed. It safely checkpointed the same Campaign as `ChronicleEycDev-freshB-20261118211319-2932b681` (SHA-256 `7A3541E1CFCE44946596E49A19954DBD96C404900B64335EB64FBE8BD4ACAB23`). To test the planner rather than increase the model cap, its per-objective instructions were further reduced while retaining Journal authority, current party limit/desertion, native Send Troops, current-balance Gold, and currently clickable Companion acceptance constraints. Build and AgentHostPackage passed at `TestResults/20261118-211758`; the next run must use process-only FreeLLMAPI routing and 1,024 output tokens, from this safe checkpoint, ≤20 provider decisions, ≤1 HTTP request/decision. FreeLLMAPI reports no price for this route, so cost coverage remains incomplete despite its free-tier designation; EYC remains incomplete.

2026-11-18 bounded freshB continuation `TestResults/20261118-212953` resumed from the hash-verified same-Campaign checkpoint `ChronicleEycDev-freshB-20261118211319-2932b681` (SHA-256 `7A3541E1CFCE44946596E49A19954DBD96C404900B64335EB64FBE8BD4ACAB23`).
The shortened read-only planner now returned valid tool calls: it chose Renown, then reconsidered to Gold, then Companion after the Native child routes reported no safe action/truncated output/budget exhaustion.
No EYC Journal target changed (Gold 0/2000, PartySize 1/25, Renown 20/50, Companions 0/1); it saved same Campaign checkpoint `ChronicleEycDev-freshB-20261118213210-6944a15c` (SHA-256 `FCC2A5E1F2A16170EA3121F213C8AC443CDF6F156D4966EFAA36B33CC7ACB9AC`) and all game/Host processes exited.
The run used 16 accepted decisions and 21 requests (5 failures), 81,045 prompt and 11,700 completion tokens; FreeLLMAPI gave no price receipt, so the apparent ¥0 is not complete billing evidence.

Token telemetry identified an outlier during the Gold route: a `tradeCancel` decision sent 46,781 user-payload bytes and 16,316 prompt tokens after a `tradeOptions` read, although the current Native observation was 4,461 bytes.
Source inspection shows the model request includes the previous full receipt; attributing the excess specifically to unrelated quoted offers is strongly supported by that request sequence and data size but not separately byte-attributed in the trace.
The model-facing receipt now filters that read to currently transferable, positive-stock, positive-price Goods in MainHero's PlayerInventory; the Host keeps the full Native receipt for execution validation.
A package self-test constructs 517 offers and requires over 4× payload reduction while preserving all source rows.
The Gold-sale prompt also fell from the 3,197-byte system prompt observed in this run to 1,777 source characters and is capped at 1,800 in its contract self-test.
`AgentHostPackage` passed at `TestResults/20261118-220146`; the compact receipt and prompt have not yet been measured in a post-change real-model run.
Next use one same-Campaign bounded continuation from `ChronicleEycDev-freshB-20261118213210-6944a15c`, `dots3-note-preview` through the process-scoped FreeLLMAPI endpoint, `max_tokens=1024`, ≤8 provider decisions and ≤1 HTTP request/decision; compare request-byte/token telemetry before extending the run.
EYC remains incomplete.
2026-11-18 short free-route continuation `TestResults/20261118-220801` resumed from `ChronicleEycDev-freshB-20261118213210-6944a15c` with an 8-decision cap, process-only FreeLLMAPI endpoint and 1,024 output tokens.
Goal classification succeeded; the planner selected Companion and the Native route moved into a Town Mission, but the 8-decision budget expired after local navigation before any interaction.
It made 8 provider requests (one truncated Companion response then one successful retry), 24,927 prompt / 2,614 completion tokens and no EYC Journal progress.
The run ended in MissionState, so the harness could not verify a new save hash and retained the previous safe checkpoint.
This run did not enter Native Trade, so it does not live-verify the compact trade receipt.
The receipt projection and shorter Gold-sale prompt pass AgentHostPackage at `TestResults/20261118-220146`; Docs pass at `TestResults/20261118-220611`.
Current provider cost remains unpriced; do not label the measured zero as complete cost.

2026-11-18 Native encounter interruption `TestResults/20261118-222315`: the free Dots continuation resumed the prior safe Campaign, selected Companion, and naturally encountered 11 looters while MainParty had 0 healthy troops.
The engine frame showed the Native text “you cannot fight; surrender is the only option”; the current encounter catalog exposed only `menuSelect`.
The first required-tool response truncated at 1,024 completion tokens; `AgentHostBattleSimulationLoop` had no truncation retry, so no Native choice was made and the child returned `provider-response-truncated`.
The run produced no hash-verified checkpoint, leaving `ChronicleEycDev-freshB-20261118213210-6944a15c` as source; all game processes exited.
The battle loop now uses the shared bounded provider-recovery policy for `provider-response-truncated` and `provider-multiple-tool-calls`: one same-catalog correction with an explicit “single compact current action” directive, before any Native action; existing argument-recovery bounds remain.
Its contract self-test checks exactly one truncation/multi-call retry and rejects transport/quota retries.
AgentHostPackage passed at `TestResults/20261118-223330`; no live test of this recovery yet.
Next continue from the safe source with `dots3-note-preview`, process-scoped FreeLLMAPI and `max_tokens=1024`, ≤12 decisions and ≤1 request/decision; inspect encounter menu recovery and the next safe checkpoint.
The visible current state permits Native surrender; the user previously authorized Native surrender/recovery when no safe battle action exists.
EYC remains incomplete and FreeLLMAPI usage is unpriced.

2026-11-18 battle-response replay after the retry hook `TestResults/20261118-223955`: the model again selected Companion, pursued its local route, and met the surrender-only 11-looter encounter.
It used 6 accepted decisions / 7 requests, 15,798 prompt / 3,076 completion tokens, then stopped on a truncated required-tool response; no Native surrender action occurred, no EYC Journal value changed, and no verified checkpoint was written.
This run used the first recovery patch but exposed that `DecideBattleAndCaptivityAsync` did not append the shared correction directive to the retry prompt.
The user-facing frame and Native catalog were correct; the issue was the prompt recovery path.
That method now attaches the exact same-catalog recovery directive for one rejected response.
The fake battle loop now tests a truncated response at the surrender-only menu, the retry prompt, exactly one Native surrender, and subsequent Native ransom recovery; AgentHostPackage passes at `TestResults/20261118-225935`, Docs at `TestResults/20261118-223742` before the final prompt-routing patch and must be rerun.
Next: one bounded same-Campaign live attempt from the last safe source with FreeLLMAPI Dots and 1,024 tokens, ≤12 decisions / ≤1 request per decision; verify the response retry and safe checkpoint.
EYC remains incomplete.
2026-11-18 12-decision same-source continuation `TestResults/20261118-230757` again began from the safe `6944a15c` checkpoint.
It followed the Companion route, completed 2 local navigation attempts (distance fell to 1.363), made 2 interaction attempts, and opened the Wanderer's Native conversation.
The final visible options were `main_option_faction_hire` and leave; the decision budget ended before the subsequent quote/acceptance result and return-to-Map save.
Companion remains 0/1 and other EYC values remain unchanged.
It used 11 accepted decisions / 12 requests, 39,079 prompt / 3,577 completion tokens; one truncated response received one correction.
MissionState could not be checkpointed, so the persistent manifest still selects `6944a15c` (the proposed `e7851eb8` save has no verified hash and is not selected).
The previously added surrender-only battle recovery code was not exercised because no battle interrupted this route.
Next resume the verified source with 16 decisions to finish this Native dialogue branch, observe whether hiring is affordable/clickable, leave or complete it through Native responses, and return to a hash-verified Campaign Map checkpoint.
EYC remains incomplete; FreeLLMAPI pricing remains unavailable.
2026-11-18 16-decision continuation `TestResults/20261118-232028` reached the original Companion hire conversation and then returned to the Sargot Backstreet Native menu, which displayed the 3,600-denar six-troop hire offer and the current return/leave options.
The model did not complete a Companion hire; all EYC Journal values remained Gold 0/2000, PartySize 1/25, Renown 20/50, Companions 0/1.
The run used 14 accepted decisions / 16 requests, 51,200 prompt / 7,533 completion tokens and two failed responses; cost coverage remained incomplete.
Native SaveAs produced verified same-Campaign checkpoint `ChronicleEycDev-freshB-20261118232255-b8ad45b2` (SHA-256 `572D70AD6822B1DED2CEBE3BDC8B9A05E102CA18BA8ABE53697ADF503AE1E3DC`); all game/Host processes stopped.
The failed prompt occurred while reasoning from the Backstreet menu after the interaction; no trade receipt or hostile-battle route was exercised, so the new token projection and battle recovery lack live confirmation.
Next resume from this exact menu checkpoint with ≤8 provider decisions and ≤1 request/decision, explicit free Dots route and process-only 1,024 output tokens; first resolve the current Native menu using its currently enabled options and then replan.
EYC remains incomplete.
2026-11-18 short continuation `TestResults/20261118-233458` resumed from the safe Sargot Backstreet checkpoint `b8ad45b2`.
The top-level planner selected Companion, whose child found no safe action; it then tried Renown (3 Native actions, no safe battle route) and Gold (budget exhausted before an action).
No Journal objective advanced.
Eight provider requests used 17,394 prompt/2,366 completion tokens and produced a hash-verified same-Campaign checkpoint `ChronicleEycDev-freshB-20261118233721-18ffe325` (SHA-256 `4E4BAB32788ACF10CB3527C29DE64EDEC075557F3CDCC509A430DCB1C5E3642D`).
This short slice did not exercise the trade receipt compaction or battle recovery.
Next run from the new safe checkpoint with the existing 20-decision cap so the model has room to complete one useful objective subflow, then inspect Native Journal and checkpoint before continuing.
FreeLLMAPI remains unpriced; EYC incomplete.

2026-11-19 same-Campaign Gold route inspection (source run `TestResults/20261118-234352`) showed a repeated empty-market cycle: Native Trade reported no sellable player goods, the model selected `tradeCancel`, returned to the Town menu, then selected `trade` again; this happened five times and produced 53–54KB model payloads / about 18.5K prompt tokens per trade-cancel decision.
Source confirmed two separate gaps: the model-side receipt filter retained the large `buyOffers` list and other Native trade metadata, and `TryResolveAction(menuSelect)` trusted any visible Town Trade option without requiring it to appear in the current action catalog after an empty-trade cancellation.
The provider view now rebuilds Trade receipt data from only currently sellable `PlayerInventory` Goods plus candidate scope/count; the full Native quote remains unchanged for Host validation.
Menu selection now requires the exact MenuId/OptionId in the current action catalog and disallows reopening Trade after `tradeCancel`; a 517-sell-offer/512-buy-offer fixture asserts >4× model-payload reduction and the no-loop exit choice.
Build and AgentHostPackage passed at `TestResults/20261119-000506`.
This is a source/self-test proof, not yet a real-model measurement.
Next: one ≤8-decision continuation from safe checkpoint `ChronicleEycDev-freshB-20261118234612-a709651a` with free Dots, `max_tokens=1024`, and ≤1 request/decision; verify one empty Trade cancel leads to a currently listed exit or safe stop, and compare `userPayloadBytes` on any subsequent Trade request before continuing.
EYC remains incomplete; provider price remains unknown.

2026-11-19 EYC Gold-route live verification `TestResults/20261119-001100` resumed from `a709651a`.
It queried the original Trade VM, found no sellable player Goods, made one Native TradeCancel, then chose the currently listed Town Leave and returned to Map; no repeated Market entry occurred.
The model payload after TradeOptions was 4,637 user bytes / 2,197 prompt tokens versus the earlier 53,665 / 18,483; this is direct live evidence that the model-facing receipt projection and menu catalog guard cut the empty-market loop.
The parent continued into the training-issue income route, where the model response truncated at 1,024 tokens before a decision; no EYC Journal value advanced.
The run made 8 accepted decisions / 9 requests and 26,833 prompt / 3,572 completion tokens; no priced receipt was returned.
It saved the same Campaign checkpoint `ChronicleEycDev-freshB-20261119001324-6bc214a5` (SHA-256 `862ED157513B942AC696F3F3A3052ECA572932A554DD08787F1281A5E85B74F7`).
The training-issue loop now allows one bounded retry for truncated/multiple-tool responses, passes the exact current catalog correction, and has a no-model contract test.
AgentHostPackage passed at `TestResults/20261119-002955`; Docs passed at `TestResults/20261119-005831` after the source/doc update.
Next resume from this exact safe checkpoint with ≤8 decisions, free Dots and process-only `max_tokens=1024`, to verify the training-issue correction and produce another safe checkpoint.
EYC remains incomplete; route pricing remains unknown.

2026-11-19 battle-recovery live verification `TestResults/20261119-010246` resumed from hash-verified save `ChronicleEycDev-freshB-20261119003736-be8d2c2b` (SHA-256 `FF9A83F1D14AE8A431993EDB1F634B3507E44287D34767DA54D840588E927AE3`).
The model met a Native encounter with no healthy MainParty troops; after a required-tool response failed, the new same-catalog correction was issued and the model selected the currently enabled surrender option.
The original captivity recovery then completed and returned the MainHero to the Campaign Map (`incidentBattleSimulation`: completed, `native-captivity-recovered-without-battle`, 7 Native actions / 8 local decisions).
The parent subsequently tried Renown again and exhausted its 12-decision budget in a new Mission before a checkpoint could be written, so no EYC Journal objective advanced and the prior safe source remains selected.
Run usage: 33,012 prompt / 5,346 completion tokens, 12 requests / 1 failed, with FreeLLMAPI pricing unreported.
This is live proof that the previously blocked surrender-only encounter now recovers through Native menus; it is not EYC completion.
Next: continue from the safe save with a 20-decision cap to leave room for the post-recovery objective loop, then verify Native Journal and a new hash checkpoint.
EYC remains incomplete.
2026-11-19 extended natural-route continuation `TestResults/20261119-051958` resumed from `be8d2c2b` on the same Campaign.
Native Bandit encounter interrupted the Companion move; two Campaign-loop replies and one Companion reply were truncated at 1,024 tokens, each corrected once under the bounded recovery contract.
The model then selected the Native surrender-only path and completed captivity recovery to the Map (`incidentBattleSimulation` completed, 7 Native actions/8 decisions), proving the battle recovery fix in live runtime.
Renown, Companion and Gold follow-up subflows still found no completed EYC target in that 20-decision window; no Journal values changed.
It saved verified checkpoint `ChronicleEycDev-freshB-20261119052235-19bbe163` (SHA-256 `2698BC8FF401784000EDFF73E86989A972FFAE6DE0BEE16B8E6920955B881B53`).
Run usage was 52,633 prompt / 11,186 completion tokens across 21 requests and 4 provider failures; cost is unpriced.
Next continue from this same Campaign checkpoint with a full bounded 20 decisions, inspect objective-attempt memory and Journal changes, and checkpoint at a safe Map state.
Two independent natural Campaign completions remain unverified.

2026-11-19 post-exit 8-decision continuation `TestResults/20261119-163157` resumed from verified `19bbe163`.
The model exited the empty-market Town Trade once, then pursued Renown and moved toward the EYC Gold training-issue route; the training-issue model response truncated before the next Native choice.
The corrected trade Cancel/leave gate prevented a repeat market loop in live execution.
Request telemetry: the decisive `tradeOptions` input was 4,544 user bytes / 2,181 tokens; `tradeCancel` was 4,637 / 2,199, down from the old 53KB / 18.5K-token cancellation.
The later Native Town-menu `menuSelect` still produced a long truncated response (two same-catalog attempts), so we added a short state-specific prompt for the sole `town_leave` after a completed empty Trade cancel.
This prompt is guarded by current menu, prior receipt and exact one-option catalog; a no-model self-test covers the branch.
AgentHostPackage/Docs pass at `TestResults/20261119-164939` / `20261119-165253`.
This new state-specific menu prompt has not yet been live measured.
Next resume from safe checkpoint `ChronicleEycDev-freshB-20261119163440-05c7021a` using ≤8 decisions, process-scoped FreeLLMAPI Dots and `max_tokens=1024`; inspect whether the action leaves Sargot without reopening Trade and whether the training-issue recovery returns a Native tool call.
EYC remains incomplete.
2026-11-19 empty-market exit prompt live verification `TestResults/20261119-165738` resumed from `05c7021a`; the fresh Native EYC Gold planner selected a safe Town, opened Trade, read current quotes, and found no sellable PlayerInventory Goods.
The Host cancelled the Native draft; its scoped 316-byte system prompt plus one-option catalog caused the model to select `town_leave` immediately, with no Trade re-entry.
This directly verifies both the no-loop validator and the short exact-menu prompt.
The 8-request run used 19,520 prompt / 1,779 completion tokens, no failed responses, and no Journal progress.
It saved safe checkpoint `ChronicleEycDev-freshB-20261119001700-7c2b8a6a` (SHA-256 `D60FE6A38C0C7E3D41384D941CE8F12F3FF3C6AFBE218787CAA2D23FC6D16CB4`).
The route reached one market with no stock; the next continuation must discover a different safe income source rather than reopening the same Town.
Continue from this checkpoint with ≤12 decisions, free Dots and process-only 1,024 output tokens; record Journal progress and next checkpoint.
EYC remains incomplete and provider price unreported.

2026-11-21 EYC planner and provider results: The EYC objective selector now receives one compact progress snapshot and Native feasibility context instead of duplicated Journal descriptions/metrics.
Its no-model contract enforces under 1,800 request bytes.
Live free Dots at the previous 1,024-token cap still truncated the planner and selected an unavailable `renown` option after correction; no Native action was sent.
A process-only 2,048-token output cap then produced a valid compact planner response selecting Gold.
In `TestResults/20261121-091936`, the real Dots provider returned three calls for one `pursue` step; Host validated the first, discarded two stale/unneeded calls, executed only the first and reobserved.
This directly verifies the safe batch-serialization path live.
The campaign did not advance an EYC Journal target: the Town market had no saleable inventory, the chosen village was looted, the weak party could not produce Renown in the encountered route, and the free Dots run ended after 39 decisions/40 requests.
Safe same-Campaign checkpoint `83c570e4` (`461F736AAAA965CADB5C371A2709ADEDC190D2A8BE1B9C4317694F2680F261F5`) passed zero-model readback at `TestResults/20261121-093524`; it remains Gold0/2000, Party1/25, Renown20/50, Companion0/1, Tier0.
A read-only FreeLLMAPI usage snapshot shows 434 monthly requests/1.355M tokens, unchanged from before the 40-request run; provider pricing is still unreported, so the apparent zero known cost is not a billing proof.
2026-11-21 planner-recovery and live Dots evidence: Prompt compaction is now verified at 1,078 planner-user bytes and the process-only 2,048-token cap produced a valid Gold selection on `TestResults/20261121-091936`; model size was unchanged.
The run then made real Native progress through the Town Trade UI, cancelled an empty market and entered a training-Issue search, but the selected village was looted and a hostile party interrupted the route.
It autonomously recovered the weak party via original surrender/captivity recovery, and later pursued a looter.
When Dots returned three tool calls for that single pursuit, the Host used the first valid current call only (`providerToolCallsDiscarded=2`) and reobserved; no stale menu batch was replayed.
The model later chose ultimatum/Leave and the Native encounter ended without battle; Gold and Renown Journal values remained unchanged.
Checkpoint `83c570e4` (`461F736AAAA965CADB5C371A2709ADEDC190D2A8BE1B9C4317694F2680F261F5`) passed zero-model readback at `TestResults/20261121-093524`; the route remains incomplete.
The run used 39 accepted decisions/40 requests, 102,911 prompt/16,267 completion tokens; FreeLLMAPI provided no price receipts.

A loopback FreeLLMAPI `/v1/usage` snapshot after this run reported the same November aggregate as the pre-run snapshot: 434 requests and 1,355,263 tokens, mostly Kilo. It did not reflect this run's 40 requests; treat it as a gateway-wide ledger with incomplete coverage, not proof of zero cost. Separate JSON-object fallback at `TestResults/20261121-083638` received HTTP 429 before inference; there was no retry hint or correlated FreeLLMAPI proxy entry, so no network/proxy cause is asserted.
