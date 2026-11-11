# Tasks

## 1. Native controller lease

- [x] 1.1 Add a guarded Host-only Native AI handoff command for ordinary Campaign field Battle Missions; verify Build rejects unsupported state and restores captured controller/agent/formation/controller-view fields on stop, timeout, and partial failure. Verified by Native lease probes and packaged Host tests.
- [x] 1.2 Expose MainAgent controller and Native player-input controller activation in battle status; verify Build/Docs preserve the existing observation shape and keep the command out of model action catalogs. `AgentHostPackage` and Docs pass; both handoff and auto-deploy controls remain outside the model action catalog.

## 2. Host mission loop

- [x] 2.1 Invoke the handoff once after the existing F6 order; update `AgentHostBattleMissionLoop` postconditions and result fields to expect Native AI control, observe health loss, and return only after Native aftermath. Fake Native scenarios cover success, rejection, control loss, defeat/captivity, timeout, and Stop without model/clock calls.
- [x] 2.2 Run `AgentHostPackage` and `Docs`; record the exact receipt and update the existing OpenSpec delta/MAINLINE/DEVELOPMENT. Final verification is in `TestResults/20261111-191252` and `TestResults/20261111-193222`.

## 3. Native integration

- [x] 3.1 On a hash-verified disposable EYC clone, run the Host attack→Native Auto Deploy/Ready→F6→Native MainHero AI handoff→Mission end→aftermath sequence with zero model calls; verify source unchanged, clone cleanup and process stop. One ordinary field battle passed at `TestResults/20261111-191252`.
- [x] 3.2 Sync issue #132 with the completed scoped acceptance and close it only after the gate passes; issue #132 is completed, parent #130 is now the only In Progress product issue, and the final OpenSpec archive/Docs sequence follows.
