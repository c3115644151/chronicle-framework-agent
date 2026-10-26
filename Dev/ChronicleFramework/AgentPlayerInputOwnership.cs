using System;
using System.Collections;
using System.Linq;
using System.Reflection;
using HarmonyLib;
using SandBox.View.Map;
using TaleWorlds.CampaignSystem;
using TaleWorlds.CampaignSystem.GameState;
using TaleWorlds.Core;
using TaleWorlds.InputSystem;
using TaleWorlds.Library;
using TaleWorlds.Localization;
using TaleWorlds.MountAndBlade;
using TaleWorlds.MountAndBlade.ViewModelCollection.GameOptions.GameKeys;
using TaleWorlds.ScreenSystem;

namespace ChronicleFramework;

internal static class ChroniclePlayerInputOwnership
{
    private static readonly Harmony FocusGuardHarmony = new Harmony("ChronicleFramework.AgentPlayerInputOwnership");
    private static ChronicleAgentControlGameKeyContext _gameKeyContext;
    private static ChronicleInputOwnershipGlobalLayer _globalLayer;
    private static bool _focusGuardInstalled;
    private static bool _locked;
    private static Mission _missionWithBlockedInput;
    private static IInputContext _missionOriginalInput;
    private static EmptyInputContext _missionBlockedInput;
    private static bool _conflictWarningShown;
    private static bool _initializationFailureLogged;
    private static bool _keyDisplayTextLogged;
    private static bool _focusProbeBaselineCaptured;
    private static bool _focusProbeBaselineAttempted;
    private static bool _focusProbeBaselineAllowed;
    private static bool _focusLossProbeCompleted;
    private static bool _focusRestoreProbeCompleted;
    private static int _inputRoutingProbeStage;
    private static int _inputRoutingProbeWaitTicks;
    private static bool _syntheticMouseRoutePassed;
    private static bool _syntheticEscapeRoutePassed;
    private static bool _syntheticMouseProbeActive;
    private static int _ownershipToggleHarnessProbeStage;
    private static bool _toggleKeyWasDown;

    internal static bool IsLocked => _locked;

    internal static bool TryPrepareForAgentStart()
    {
        if (!TryInitialize())
        {
            ChronicleDiagnostics.Write("agent-input-start-rejected|reason=screen-or-focus-guard-unavailable|layer=" + (_globalLayer != null) + "|focusGuard=" + _focusGuardInstalled);
            ShowSafetyMessage("AI控制未启动：游戏输入保护初始化失败。");
            return false;
        }
        var conflict = FindToggleBindingConflict();
        if (conflict != null && TryRepairDefaultToggleBinding(conflict)) conflict = FindToggleBindingConflict();
        if (!HasUsableToggleBinding() || conflict != null)
        {
            var gameKey = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl);
            var keyboardKey = gameKey?.KeyboardKey?.InputKey.ToString() ?? "missing";
            var controllerKey = gameKey?.ControllerKey?.InputKey.ToString() ?? "missing";
            ChronicleDiagnostics.Write("agent-input-start-rejected|reason=toggle-key-unavailable-or-conflicting|keyboard=" + keyboardKey + "|controller=" + controllerKey + "|conflict=" + (conflict ?? "none"));
            ShowSafetyMessage("AI控制未启动：请在游戏的按键设置中为 Chronicle 的控制权切换键设置一个未占用按键。");
            return false;
        }

        SetLocked(true);
        return true;
    }

    internal static void Tick()
    {
        TryInitialize();
        TryInstallFocusGuard();

        var shouldLock = ChronicleAgentRuntimeController.ShouldOwnPlayerInput;
        var runFocusProbe = Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_INPUT_FOCUS_TEST") == "1";
        if (runFocusProbe && !shouldLock && !_focusProbeBaselineCaptured)
            TryCaptureNativeFocusPermissionBaseline();
        if (shouldLock && (!HasUsableToggleBinding() || HasToggleBindingConflict()))
        {
            var conflict = FindToggleBindingConflict();
            if (conflict != null && TryRepairDefaultToggleBinding(conflict))
            {
                _conflictWarningShown = false;
                SetLocked(ChronicleAgentRuntimeController.ShouldOwnPlayerInput);
                SyncMissionInput(ChronicleAgentRuntimeController.ShouldOwnPlayerInput);
                return;
            }
            if (!_conflictWarningShown)
            {
                _conflictWarningShown = true;
                ChronicleDiagnostics.Write("agent-input-lock-releasing|reason=toggle-key-unavailable-or-conflicting");
                ShowSafetyMessage("控制权切换键不可用或与其他按键冲突，正在安全停止AI并恢复玩家控制。");
            }
            ChronicleAgentRuntimeController.RequestStop();
        }
        else if (!shouldLock)
        {
            _conflictWarningShown = false;
        }

        SetLocked(ChronicleAgentRuntimeController.ShouldOwnPlayerInput);
        SyncMissionInput(ChronicleAgentRuntimeController.ShouldOwnPlayerInput);
        if (runFocusProbe && ChronicleAgentRuntimeController.ShouldOwnPlayerInput && !_focusLossProbeCompleted)
            TryRunFocusLossProbe();
        else if (runFocusProbe && !ChronicleAgentRuntimeController.ShouldOwnPlayerInput && _focusLossProbeCompleted && !_focusRestoreProbeCompleted)
            TryRunFocusRestoreProbe();
        if (runFocusProbe && ChronicleAgentRuntimeController.ShouldOwnPlayerInput && _focusLossProbeCompleted)
            AdvanceSyntheticInputRoutingProbe();
        if (Environment.GetEnvironmentVariable("CHRONICLE_HARNESS_AGENT_INPUT_TOGGLE_TEST") == "1")
            AdvanceOwnershipToggleHarnessProbe();
    }

    internal static void Release()
    {
        SetLocked(false, notifyPlayer: false);
        RestoreMissionInput();
        if (_globalLayer == null) return;
        try
        {
            ScreenManager.RemoveGlobalLayer(_globalLayer);
            ChronicleDiagnostics.Write("agent-input-layer-removed");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-layer-remove-failed|type=" + exception.GetType().Name);
        }
        _globalLayer = null;
    }

    private static bool TryInitialize()
    {
        try
        {
            RegisterGameKeyContext();
            TryLogKeyDisplayText();
            if (_globalLayer == null)
            {
                var globalLayer = new ChronicleInputOwnershipGlobalLayer(_gameKeyContext);
                ScreenManager.AddGlobalLayer(globalLayer, isFocusable: true);
                _globalLayer = globalLayer;
                ChronicleDiagnostics.Write("agent-input-layer-installed|scope=screen-manager-global-layer");
            }
            TryInstallFocusGuard();
            return _globalLayer != null && _focusGuardInstalled;
        }
        catch (Exception exception)
        {
            if (!_initializationFailureLogged)
            {
                _initializationFailureLogged = true;
                ChronicleDiagnostics.Write("agent-input-initialize-failed|type=" + exception.GetType().Name + "|message=" + exception.Message);
            }
            return false;
        }
    }

    private static void RegisterGameKeyContext()
    {
        var existing = HotKeyManager.GetAllCategories().FirstOrDefault(category =>
            string.Equals(category.GameKeyCategoryId, ChronicleAgentControlGameKeyContext.CategoryId, StringComparison.Ordinal));
        if (existing != null)
        {
            _gameKeyContext = existing as ChronicleAgentControlGameKeyContext;
            if (_gameKeyContext == null)
                throw new InvalidOperationException("Chronicle control key category is already registered by another type.");
            return;
        }

        _gameKeyContext ??= new ChronicleAgentControlGameKeyContext();
        HotKeyManager.RegisterContext(_gameKeyContext);
    }

    private static void TryLogKeyDisplayText()
    {
        if (_keyDisplayTextLogged || TaleWorlds.MountAndBlade.Module.CurrentModule?.GlobalTextManager == null) return;
        _keyDisplayTextLogged = true;
        try
        {
            var textManager = TaleWorlds.MountAndBlade.Module.CurrentModule.GlobalTextManager;
            var category = textManager.FindText("str_key_category_name", ChronicleAgentControlGameKeyContext.CategoryId)?.ToString();
            var keyTextId = ChronicleAgentControlGameKeyContext.CategoryId + "_" + ((GameKeyDefinition)ChronicleAgentControlGameKeyContext.ToggleControl).ToString();
            var keyName = textManager.FindText("str_key_name", keyTextId)?.ToString();
            var keyDescription = textManager.FindText("str_key_description", keyTextId)?.ToString();
            var loaded = !string.IsNullOrWhiteSpace(category) && !category.Contains(ChronicleAgentControlGameKeyContext.CategoryId) &&
                         !string.IsNullOrWhiteSpace(keyName) && !keyName.Contains(keyTextId) &&
                         !string.IsNullOrWhiteSpace(keyDescription) && !keyDescription.Contains(keyTextId);
            var options = new GameKeyOptionCategoryVM(_ => { }, new[] { GameKeyMainCategories.CampaignMapCategory }, Array.Empty<int>());
            var option = options.GameKeyGroups.SelectMany(group => group.GameKeys).FirstOrDefault(item =>
                item.CurrentGameKey.GroupId == ChronicleAgentControlGameKeyContext.CategoryId &&
                item.CurrentGameKey.Id == ChronicleAgentControlGameKeyContext.ToggleControl);
            var listedInNativeOptions = option != null && option.Name == keyName &&
                                       option.Description == keyDescription && option.CurrentKey != null;
            options.OnFinalize();
            ChronicleDiagnostics.Write("agent-input-key-display-text|loaded=" + loaded + "|categoryPresent=" + !string.IsNullOrWhiteSpace(category) +
                "|namePresent=" + !string.IsNullOrWhiteSpace(keyName) + "|descriptionPresent=" + !string.IsNullOrWhiteSpace(keyDescription) +
                "|optionsVisible=" + listedInNativeOptions + "|optionsKey=" + (option?.OptionValueText ?? "missing"));
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-key-display-text|loaded=False|type=" + exception.GetType().Name);
        }
    }

    private static void TryInstallFocusGuard()
    {
        if (_focusGuardInstalled) return;
        var managerType = AccessTools.TypeByName("SandBox.View.Map.MapViewsContainer");
        var target = managerType == null ? null : AccessTools.Method(managerType, "IsOpeningEscapeMenuOnFocusChangeAllowedForAll", Type.EmptyTypes);
        if (target == null) return;
        try
        {
            var prefix = AccessTools.Method(typeof(ChroniclePlayerInputOwnership), nameof(KeepFocusLossEscapeMenuClosed));
            FocusGuardHarmony.Patch(target, prefix: new HarmonyMethod(prefix));
            _focusGuardInstalled = true;
            ChronicleDiagnostics.Write("agent-input-focus-guard-installed|target=MapViewsContainer.IsOpeningEscapeMenuOnFocusChangeAllowedForAll");
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-focus-guard-install-failed|type=" + exception.GetType().Name);
        }
    }

    private static bool KeepFocusLossEscapeMenuClosed(ref bool __result)
    {
        if (!ChronicleAgentRuntimeController.ShouldOwnPlayerInput) return true;
        __result = false;
        return false;
    }

    private static void TryCaptureNativeFocusPermissionBaseline()
    {
        if (_focusProbeBaselineAttempted || Game.Current?.GameStateManager?.ActiveState is not MapState || MapScreen.Instance == null) return;
        _focusProbeBaselineAttempted = true;
        try
        {
            _focusProbeBaselineAllowed = ReadNativeFocusPermission();
            _focusProbeBaselineCaptured = true;
            ChronicleDiagnostics.Write("agent-input-focus-baseline|allowed=" + _focusProbeBaselineAllowed + "|blockingViews=" + DescribeNativeFocusPermissionBlockers() +
                "|patchOwners=" + DescribeFocusPermissionPatchOwners());
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-focus-baseline-failed|type=" + exception.GetType().Name);
        }
    }

    private static bool ReadNativeFocusPermission()
    {
        var mapScreen = MapScreen.Instance ?? throw new InvalidOperationException("Native MapScreen is unavailable.");
        var containerField = AccessTools.Field(mapScreen.GetType(), "_mapViewsContainer") ??
                             throw new MissingFieldException(mapScreen.GetType().FullName, "_mapViewsContainer");
        var container = containerField.GetValue(mapScreen) ?? throw new InvalidOperationException("MapViewsContainer is unavailable.");
        var permissionMethod = AccessTools.Method(container.GetType(), "IsOpeningEscapeMenuOnFocusChangeAllowedForAll", Type.EmptyTypes) ??
                               throw new MissingMethodException(container.GetType().FullName, "IsOpeningEscapeMenuOnFocusChangeAllowedForAll");
        return (bool)permissionMethod.Invoke(container, null);
    }

    private static string DescribeFocusPermissionPatchOwners()
    {
        var managerType = AccessTools.TypeByName("SandBox.View.Map.MapViewsContainer");
        var target = managerType == null ? null : AccessTools.Method(managerType, "IsOpeningEscapeMenuOnFocusChangeAllowedForAll", Type.EmptyTypes);
        var patches = target == null ? null : Harmony.GetPatchInfo(target);
        return patches == null ? "none" : string.Join(",", patches.Owners.OrderBy(owner => owner, StringComparer.Ordinal));
    }

    private static string DescribeNativeFocusPermissionBlockers()
    {
        try
        {
            var mapScreen = MapScreen.Instance;
            var containerField = mapScreen == null ? null : AccessTools.Field(mapScreen.GetType(), "_mapViewsContainer");
            var container = containerField?.GetValue(mapScreen);
            var getViews = container == null ? null : AccessTools.Method(container.GetType(), "GetMapViewsCopy", Type.EmptyTypes);
            var views = getViews?.Invoke(container, null) as IEnumerable;
            if (views == null) return "unknown";
            var blocked = new System.Collections.Generic.List<string>();
            foreach (var view in views)
            {
                if (view == null || view.GetType().GetProperty("IsFinalized")?.GetValue(view) is true) continue;
                var permission = AccessTools.Method(view.GetType(), "IsOpeningEscapeMenuOnFocusChangeAllowed", Type.EmptyTypes);
                if (permission != null && permission.Invoke(view, null) is bool allowed && !allowed)
                    blocked.Add(view.GetType().FullName ?? view.GetType().Name);
            }
            return blocked.Count == 0 ? "none" : string.Join(",", blocked);
        }
        catch (Exception exception)
        {
            return "capture-failed:" + exception.GetType().Name;
        }
    }

    private static void TryRunFocusLossProbe()
    {
        _focusLossProbeCompleted = true;
        var mapScreen = MapScreen.Instance;
        if (mapScreen == null || Game.Current?.GameStateManager?.ActiveState is not MapState || mapScreen.IsEscapeMenuOpened)
        {
            ChronicleDiagnostics.Write("agent-input-focus-probe|passed=False|reason=map-screen-unavailable-or-escape-already-open");
            return;
        }

        var priorStopOnFocusLoss = BannerlordConfig.StopGameOnFocusLost;
        var escapeBefore = mapScreen.IsEscapeMenuOpened;
        bool? permissionWhileOwned = null;
        var focusGuardPrefixOwnedVerified = false;
        var escapeAfterSimulatedLoss = escapeBefore;
        try
        {
            var orderedLayers = ScreenManager.SortedLayers;
            var layerPresent = _globalLayer != null && orderedLayers.Contains(_globalLayer.ControlLayer);
            var layerTopmost = layerPresent && ReferenceEquals(orderedLayers.LastOrDefault(), _globalLayer.ControlLayer);
            var layerMask = _globalLayer?.ControlLayer.InputRestrictions.InputUsageMask;
            var layerFocused = _globalLayer?.ControlLayer.IsFocusLayer == true &&
                               _globalLayer.ControlLayer.FocusTest() &&
                               ReferenceEquals(ScreenManager.FocusedLayer, _globalLayer.ControlLayer);
            var layerHitTest = _globalLayer?.ControlLayer.HitTest() == true;
            var layerProbePassed = layerPresent && layerTopmost && layerMask == InputUsageMask.All && layerFocused && layerHitTest;
            ChronicleDiagnostics.Write("agent-input-layer-probe|passed=" + layerProbePassed + "|present=" + layerPresent + "|topmost=" + layerTopmost +
                "|mask=" + layerMask + "|focus=" + layerFocused + "|hitTest=" + layerHitTest);
            BannerlordConfig.StopGameOnFocusLost = true;
            permissionWhileOwned = ReadNativeFocusPermission();
            focusGuardPrefixOwnedVerified = TestFocusGuardPrefix(agentExpected: true);
            ScreenManager.OnGameWindowFocusChange(focusGained: false);
            escapeAfterSimulatedLoss = MapScreen.Instance?.IsEscapeMenuOpened ?? false;
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-focus-probe|passed=False|reason=probe-exception|type=" + exception.GetType().Name);
        }
        finally
        {
            try { ScreenManager.OnGameWindowFocusChange(focusGained: true); }
            catch (Exception exception) { ChronicleDiagnostics.Write("agent-input-focus-probe-focus-restore-failed|type=" + exception.GetType().Name); }
            if (MapScreen.Instance?.IsEscapeMenuOpened == true)
            {
                var closeEscapeMenu = AccessTools.Method(typeof(MapScreen), "OnEscapeMenuToggled", new[] { typeof(bool) });
                try { closeEscapeMenu?.Invoke(MapScreen.Instance, new object[] { false }); }
                catch (Exception exception) { ChronicleDiagnostics.Write("agent-input-focus-probe-escape-cleanup-failed|type=" + exception.GetType().Name); }
            }
            BannerlordConfig.StopGameOnFocusLost = priorStopOnFocusLoss;
        }

        var callbackEscapeStayedClosed = !escapeBefore && !escapeAfterSimulatedLoss && MapScreen.Instance?.IsEscapeMenuOpened == false;
        var passed = _focusProbeBaselineCaptured && _focusProbeBaselineAllowed && permissionWhileOwned == false &&
                     focusGuardPrefixOwnedVerified && callbackEscapeStayedClosed;
        ChronicleDiagnostics.Write("agent-input-focus-probe|passed=" + passed + "|focusLossPermission=" + permissionWhileOwned +
            "|guardPrefixOverride=" + focusGuardPrefixOwnedVerified + "|nativeBaselinePermission=" + _focusProbeBaselineAllowed +
            "|callbackEscapeStayedClosed=" + callbackEscapeStayedClosed +
            "|escapeBefore=" + escapeBefore + "|escapeAfterSimulatedLoss=" + escapeAfterSimulatedLoss +
            "|configuredStopOnFocusLoss=" + priorStopOnFocusLoss + "|testTemporarilyForcedNativeSetting=True");
    }

    private static void TryRunFocusRestoreProbe()
    {
        _focusRestoreProbeCompleted = true;
        try
        {
            var nativePermissionAfterRelease = ReadNativeFocusPermission();
            var guardPrefixPassthrough = TestFocusGuardPrefix(agentExpected: false);
            var passed = _focusProbeBaselineCaptured && nativePermissionAfterRelease == _focusProbeBaselineAllowed && guardPrefixPassthrough;
            ChronicleDiagnostics.Write("agent-input-focus-restored-probe|passed=" + passed + "|baselineAllowed=" + _focusProbeBaselineAllowed +
                "|permissionAfterRelease=" + nativePermissionAfterRelease + "|guardPrefixPassthrough=" + guardPrefixPassthrough);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-focus-restored-probe|passed=False|type=" + exception.GetType().Name);
        }
    }

    private static bool TestFocusGuardPrefix(bool agentExpected)
    {
        var prefix = AccessTools.Method(typeof(ChroniclePlayerInputOwnership), nameof(KeepFocusLossEscapeMenuClosed));
        if (prefix == null) return false;
        object[] arguments = { true };
        var runOriginal = (bool)prefix.Invoke(null, arguments);
        var result = (bool)arguments[0];
        return agentExpected ? !runOriginal && !result : runOriginal && result;
    }

    private static void AdvanceSyntheticInputRoutingProbe()
    {
        var controlLayer = _globalLayer?.ControlLayer;
        if (!_locked || controlLayer == null || !ReferenceEquals(ScreenManager.FocusedLayer, controlLayer) || _inputRoutingProbeStage >= 3) return;
        try
        {
            if (_inputRoutingProbeStage == 0)
            {
                _syntheticMouseRoutePassed = TryRunSyntheticMouseRoutingProbe();
                Input.PressKey(InputKey.Escape);
                _inputRoutingProbeStage = 1;
                _inputRoutingProbeWaitTicks = 0;
                ChronicleDiagnostics.Write("agent-input-routing-probe-injected|key=Escape");
                return;
            }

            if (!IsSyntheticKeyActive(InputKey.Escape) && ++_inputRoutingProbeWaitTicks < 3) return;
            _syntheticEscapeRoutePassed = IsSyntheticKeyActive(InputKey.Escape) && IsScreenLayerRoutingKeyboard(controlLayer);
            Input.ClearKeys();
            _inputRoutingProbeStage = 3;
            ChronicleDiagnostics.Write("agent-input-routing-probe|mousePassed=" + _syntheticMouseRoutePassed + "|escapePassed=" + _syntheticEscapeRoutePassed + "|source=NativeScreenManager-synthetic-events");
        }
        catch (Exception exception)
        {
            Input.ClearKeys();
            _inputRoutingProbeStage = 3;
            ChronicleDiagnostics.Write("agent-input-routing-probe|mousePassed=False|escapePassed=False|source=NativeScreenManager-synthetic-events|failure=" + exception.GetType().Name);
        }
    }

    private static bool TryRunSyntheticMouseRoutingProbe()
    {
        var controlLayer = _globalLayer?.ControlLayer;
        if (!_locked || controlLayer == null || !ReferenceEquals(ScreenManager.FocusedLayer, controlLayer) || Input.IsKeyDown(InputKey.LeftMouseButton)) return false;
        var inputManagerType = typeof(Input);
        var target = AccessTools.Method(inputManagerType, nameof(Input.IsKeyDown), new[] { typeof(InputKey) });
        if (target == null) return false;
        var harmonyId = "ChronicleFramework.AgentInputMouseRouteProbe." + Guid.NewGuid().ToString("N");
        var harmony = new Harmony(harmonyId);
        var prefix = AccessTools.Method(typeof(ChroniclePlayerInputOwnership), nameof(ForceMouseDownForRoutingProbe));
        try
        {
            harmony.Patch(target, prefix: new HarmonyMethod(prefix));
            _syntheticMouseProbeActive = true;
            ScreenManager.EarlyUpdate(ScreenManager.UsableArea);
            foreach (var screenLayer in ScreenManager.SortedLayers)
                if (screenLayer != null && screenLayer.IsActive) screenLayer.ProcessEvents();
            return IsScreenLayerRoutingMouse(controlLayer);
        }
        catch (Exception exception)
        {
            ChronicleDiagnostics.Write("agent-input-mouse-routing-probe-failed|type=" + exception.GetType().Name);
            return false;
        }
        finally
        {
            _syntheticMouseProbeActive = false;
            try
            {
                harmony.Unpatch(target, HarmonyPatchType.All, harmonyId);
                ScreenManager.EarlyUpdate(ScreenManager.UsableArea);
                foreach (var screenLayer in ScreenManager.SortedLayers)
                    if (screenLayer != null && screenLayer.IsActive) screenLayer.ProcessEvents();
            }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write("agent-input-mouse-routing-probe-cleanup-failed|type=" + exception.GetType().Name);
            }
        }
    }

    private static bool ForceMouseDownForRoutingProbe(InputKey key, ref bool __result)
    {
        if (!_syntheticMouseProbeActive || key != InputKey.LeftMouseButton) return true;
        __result = true;
        return false;
    }

    private static bool IsSyntheticKeyActive(InputKey key) => Input.IsKeyDown(key) || Input.IsKeyPressed(key);

    private static bool IsScreenLayerRoutingMouse(ChronicleInputOwnershipScreenLayer controlLayer)
    {
        var lowerLayerAllowed = ScreenManager.SortedLayers.Any(screenLayer => screenLayer != null &&
            !ReferenceEquals(screenLayer, controlLayer) && screenLayer.IsActive && screenLayer.Input.IsMouseButtonAllowed);
        return controlLayer.IsHitThisFrame && controlLayer.Input.IsMouseButtonAllowed && !lowerLayerAllowed;
    }

    private static bool IsScreenLayerRoutingKeyboard(ChronicleInputOwnershipScreenLayer controlLayer)
    {
        var lowerLayerAllowed = ScreenManager.SortedLayers.Any(screenLayer => screenLayer != null &&
            !ReferenceEquals(screenLayer, controlLayer) && screenLayer.IsActive && screenLayer.Input.IsKeysAllowed);
        return ReferenceEquals(ScreenManager.FocusedLayer, controlLayer) && controlLayer.Input.IsKeysAllowed && !lowerLayerAllowed;
    }

    private static bool HasUsableToggleBinding()
    {
        var key = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl);
        return key != null &&
               ((key.KeyboardKey != null && key.KeyboardKey.InputKey != InputKey.Invalid) ||
                (key.ControllerKey != null && key.ControllerKey.InputKey != InputKey.Invalid));
    }

    private static bool HasToggleBindingConflict() => FindToggleBindingConflict() != null;

    private static bool TryRepairDefaultToggleBinding(string conflict)
    {
        var gameKey = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl);
        if (gameKey?.KeyboardKey == null || gameKey.DefaultKeyboardKey == null ||
            gameKey.KeyboardKey.InputKey != gameKey.DefaultKeyboardKey.InputKey) return false;

        var candidates = new[]
        {
            InputKey.F9, InputKey.F8, InputKey.F7, InputKey.F6, InputKey.F5, InputKey.F4,
            InputKey.F3, InputKey.F2, InputKey.F1, InputKey.NumpadMultiply, InputKey.Insert,
            InputKey.Delete, InputKey.Home, InputKey.PageUp, InputKey.PageDown,
            InputKey.F13, InputKey.F14, InputKey.F15, InputKey.F16, InputKey.F17, InputKey.F18,
            InputKey.F19, InputKey.F20, InputKey.F21, InputKey.F22, InputKey.F23, InputKey.F24
        };

        foreach (var candidate in candidates)
        {
            gameKey.KeyboardKey.ChangeKey(candidate);
            if (FindToggleBindingConflict() != null) continue;
            HotKeyManager.MarkForSave();
            ChronicleDiagnostics.Write("agent-input-toggle-key-repaired|previous=" + gameKey.DefaultKeyboardKey.InputKey + "|current=" + candidate + "|conflict=" + conflict);
            return true;
        }

        gameKey.KeyboardKey.ChangeKey(gameKey.DefaultKeyboardKey.InputKey);
        ChronicleDiagnostics.Write("agent-input-toggle-key-repair-failed|reason=no-unbound-native-key");
        return false;
    }

    private static string FindToggleBindingConflict()
    {
        var ownKey = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl);
        if (ownKey == null) return "toggle-game-key-missing";
        foreach (var category in HotKeyManager.GetAllCategories())
        {
            foreach (var key in category.RegisteredGameKeys)
            {
                if (key == null || ReferenceEquals(key, ownKey)) continue;
                if (KeysOverlap(ownKey.KeyboardKey, key.KeyboardKey) || KeysOverlap(ownKey.ControllerKey, key.ControllerKey))
                    return category.GameKeyCategoryId + "/" + key.StringId;
            }

            foreach (var hotKey in category.RegisteredHotKeys)
            {
                if (hotKey == null) continue;
                foreach (var boundKey in hotKey.Keys)
                    if (KeysOverlap(ownKey.KeyboardKey, boundKey) || KeysOverlap(ownKey.ControllerKey, boundKey))
                        return category.GameKeyCategoryId + "/" + hotKey.Id;
            }
        }
        return null;
    }

    private static bool KeysOverlap(Key first, Key second) =>
        first != null && second != null && first.InputKey != InputKey.Invalid && first.InputKey == second.InputKey;

    private static void SetLocked(bool locked, bool notifyPlayer = true)
    {
        if (_locked == locked)
        {
            if (locked && _globalLayer != null && !ReferenceEquals(ScreenManager.FocusedLayer, _globalLayer.ControlLayer))
                ScreenManager.TrySetFocus(_globalLayer.ControlLayer);
            return;
        }

        var wasFocused = _globalLayer != null && ReferenceEquals(ScreenManager.FocusedLayer, _globalLayer.ControlLayer);
        _locked = locked;
        if (_globalLayer != null)
        {
            _globalLayer.ControlLayer.SetLocked(locked);
            if (locked) ScreenManager.TrySetFocus(_globalLayer.ControlLayer);
            else if (wasFocused) ScreenManager.TryLoseFocus(_globalLayer.ControlLayer);
        }
        ChronicleDiagnostics.Write("agent-player-input-owner|owner=" + (locked ? "agent" : "player"));
        if (!notifyPlayer) return;
        if (locked)
        {
            var binding = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl)?.ToString();
            if (string.IsNullOrWhiteSpace(binding) || binding == "invalid") binding = "按键设置中的 Chronicle Agent Control 切换键";
            ShowSafetyMessage("AI已接管玩家控制；按“" + binding + "”安全停止AI并交还控制。可在选项→控制→战役地图中更改按键。");
        }
        else
        {
            ShowSafetyMessage("AI已停止，玩家控制已恢复。");
        }
    }

    private static void SyncMissionInput(bool lockInput)
    {
        var mission = MissionState.Current?.CurrentMission;
        if (!lockInput)
        {
            RestoreMissionInput();
            return;
        }

        if (mission == null || mission.InputManager == null) return;
        if (!ReferenceEquals(mission, _missionWithBlockedInput))
        {
            RestoreMissionInput();
            _missionWithBlockedInput = mission;
            _missionOriginalInput = mission.InputManager;
            _missionBlockedInput = new EmptyInputContext();
            mission.InputManager = _missionBlockedInput;
            ChronicleDiagnostics.Write("agent-mission-input-blocked|mission=" + mission.SceneName);
            return;
        }

        if (ReferenceEquals(mission.InputManager, _missionBlockedInput) || mission.InputManager is ChronicleMissionLeaveInputContext) return;

        // Preserve a third-party replacement as the context to restore, while reapplying the input gate.
        _missionOriginalInput = mission.InputManager;
        mission.InputManager = _missionBlockedInput;
        ChronicleDiagnostics.Write("agent-mission-input-reblocked|reason=input-context-replaced");
    }

    private static void RestoreMissionInput()
    {
        if (_missionWithBlockedInput != null)
        {
            try
            {
                if (ReferenceEquals(_missionWithBlockedInput.InputManager, _missionBlockedInput) ||
                    _missionWithBlockedInput.InputManager is ChronicleMissionLeaveInputContext)
                {
                    _missionWithBlockedInput.InputManager = _missionOriginalInput;
                    ChronicleDiagnostics.Write("agent-mission-input-restored");
                }
            }
            catch (Exception exception)
            {
                ChronicleDiagnostics.Write("agent-mission-input-restore-failed|type=" + exception.GetType().Name);
            }
        }
        _missionWithBlockedInput = null;
        _missionOriginalInput = null;
        _missionBlockedInput = null;
    }

    private static bool IsCampaignMapAvailable()
    {
        var activeState = Game.Current?.GameStateManager?.ActiveState;
        return activeState is MapState && MapScreen.Instance?.IsEscapeMenuOpened != true &&
               !ChronicleInquiryAdapter.IsInquiryOpen && Campaign.Current != null;
    }

    private static bool IsToggleKeyDown()
    {
        var gameKey = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl);
        if (gameKey == null) return false;
        return (gameKey.KeyboardKey != null && gameKey.KeyboardKey.InputKey != InputKey.Invalid && Input.IsKeyDown(gameKey.KeyboardKey.InputKey)) ||
               (gameKey.ControllerKey != null && gameKey.ControllerKey.InputKey != InputKey.Invalid && Input.IsKeyDown(gameKey.ControllerKey.InputKey));
    }

    private static void HandleToggle()
    {
        if (ChronicleAgentRuntimeController.ShouldOwnPlayerInput)
        {
            ChronicleDiagnostics.Write("agent-input-toggle|direction=agent-to-player");
            ChronicleAgentRuntimeController.RequestStop();
            return;
        }

        if (!IsCampaignMapAvailable())
        {
            ShowSafetyMessage("请先回到没有弹窗的战役地图，再启动自主Agent。");
            return;
        }

        if (HasToggleBindingConflict())
        {
            ShowSafetyMessage("控制权切换键与其他游戏按键冲突，请先在按键设置中修改。");
            return;
        }

        ChronicleDiagnostics.Write("agent-input-toggle|direction=player-to-agent");
        ChronicleAgentRuntimeController.RequestStart();
    }

    private static void ShowSafetyMessage(string message)
    {
        try { MBInformationManager.AddQuickInformation(new TextObject(message), 6000); }
        catch { ChronicleDiagnostics.Write("agent-input-notice-failed"); }
    }

    private static void PollToggleKey()
    {
        if (!IsToggleKeyDown())
        {
            _toggleKeyWasDown = false;
            return;
        }
        if (_toggleKeyWasDown) return;
        _toggleKeyWasDown = true;
        if (HasToggleBindingConflict())
        {
            if (ChronicleAgentRuntimeController.ShouldOwnPlayerInput)
            {
                ShowSafetyMessage("控制权切换键与其他游戏按键冲突，正在停止AI以避免锁住玩家输入。");
                ChronicleAgentRuntimeController.RequestStop();
            }
            return;
        }
        HandleToggle();
    }

    private static void AdvanceOwnershipToggleHarnessProbe()
    {
        if (_ownershipToggleHarnessProbeStage == 0 && ChronicleAgentRuntimeController.IsHostRunning)
        {
            if (!PressHarnessToggleKey("agent-to-player"))
            {
                ChronicleDiagnostics.Write("agent-input-toggle-harness-probe|passed=False|reason=native-key-unavailable");
                _ownershipToggleHarnessProbeStage = 4;
                return;
            }
            _ownershipToggleHarnessProbeStage = 1;
            return;
        }

        if (_ownershipToggleHarnessProbeStage == 1 && !ChronicleAgentRuntimeController.ShouldOwnPlayerInput && !ChronicleAgentRuntimeController.OwnsHost)
        {
            Input.ClearKeys();
            PollToggleKey();
            if (!PressHarnessToggleKey("player-to-agent"))
            {
                ChronicleDiagnostics.Write("agent-input-toggle-harness-probe|passed=False|reason=native-key-unavailable");
                _ownershipToggleHarnessProbeStage = 4;
                return;
            }
            _ownershipToggleHarnessProbeStage = 2;
            return;
        }

        if (_ownershipToggleHarnessProbeStage == 2 && ChronicleAgentRuntimeController.IsHostRunning)
        {
            Input.ClearKeys();
            PollToggleKey();
            if (!PressHarnessToggleKey("agent-to-player"))
            {
                ChronicleDiagnostics.Write("agent-input-toggle-harness-probe|passed=False|reason=native-key-unavailable");
                _ownershipToggleHarnessProbeStage = 4;
                return;
            }
            _ownershipToggleHarnessProbeStage = 3;
            return;
        }

        if (_ownershipToggleHarnessProbeStage == 3 && !ChronicleAgentRuntimeController.ShouldOwnPlayerInput && !ChronicleAgentRuntimeController.OwnsHost)
        {
            ChronicleDiagnostics.Write("agent-input-toggle-harness-probe|passed=True|cycle=agent-player-agent-player");
            _ownershipToggleHarnessProbeStage = 4;
        }
    }

    private static bool PressHarnessToggleKey(string direction)
    {
        var key = _gameKeyContext?.GetGameKey(ChronicleAgentControlGameKeyContext.ToggleControl)?.KeyboardKey;
        if (key == null || key.InputKey == InputKey.Invalid) return false;
        ChronicleDiagnostics.Write("agent-input-toggle-harness-probe|press=" + direction + "|key=" + key.InputKey + "|source=NativeInput.PressKey");
        Input.PressKey(key.InputKey);
        PollToggleKey();
        return true;
    }

    private sealed class ChronicleInputOwnershipGlobalLayer : GlobalLayer
    {
        internal ChronicleInputOwnershipScreenLayer ControlLayer { get; }

        internal ChronicleInputOwnershipGlobalLayer(ChronicleAgentControlGameKeyContext gameKeyContext)
        {
            ControlLayer = new ChronicleInputOwnershipScreenLayer(gameKeyContext);
            Layer = ControlLayer;
        }

        protected override void OnTick(float dt) => PollToggleKey();
    }

    private sealed class ChronicleInputOwnershipScreenLayer : ScreenLayer
    {
        private bool _locked;

        internal ChronicleInputOwnershipScreenLayer(ChronicleAgentControlGameKeyContext gameKeyContext)
            : base("ChronicleAgentControl", int.MaxValue)
        {
            Input.RegisterHotKeyCategory(gameKeyContext);
            SetLocked(false);
        }

        internal void SetLocked(bool locked)
        {
            _locked = locked;
            IsFocusLayer = locked;
            if (locked) InputRestrictions.SetInputRestrictions(isMouseVisible: true, mask: InputUsageMask.All);
            else InputRestrictions.ResetInputRestrictions();
        }

        public override bool HitTest() => _locked;
        public override bool FocusTest() => _locked;
    }
}

internal sealed class ChronicleAgentControlGameKeyContext : GameKeyContext
{
    internal const string CategoryId = "ChronicleAgentControl";
    internal const int ToggleControl = 0;

    internal ChronicleAgentControlGameKeyContext()
        : base(CategoryId, 1, GameKeyContextType.Default)
    {
        RegisterGameKey(new GameKey(ToggleControl, "ToggleAgentControl", CategoryId, InputKey.F10, InputKey.Invalid,
            GameKeyMainCategories.CampaignMapCategory));
    }
}
