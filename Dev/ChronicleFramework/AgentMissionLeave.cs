using System;
using System.Numerics;
using TaleWorlds.InputSystem;
using TaleWorlds.Library;

namespace ChronicleFramework;

/// <summary>
/// A Mission-scoped virtual hold for the native Leave Area game action.
/// It does not emit an operating-system key event; all unrelated input passes through.
/// </summary>
internal sealed class ChronicleMissionLeaveInputContext : IInputContext
{
    private readonly IInputContext _inner;
    private readonly int _leaveAreaGameKey;

    internal ChronicleMissionLeaveInputContext(IInputContext inner, int leaveAreaGameKey)
    {
        _inner = inner ?? throw new ArgumentNullException(nameof(inner));
        _leaveAreaGameKey = leaveAreaGameKey;
    }

    public int GetPointerX() => _inner.GetPointerX();
    public int GetPointerY() => _inner.GetPointerY();
    public Vector2 GetPointerPosition() => _inner.GetPointerPosition();
    public bool IsGameKeyDown(int gameKey) => gameKey == _leaveAreaGameKey || _inner.IsGameKeyDown(gameKey);
    public bool IsGameKeyDownImmediate(int gameKey) => _inner.IsGameKeyDownImmediate(gameKey);
    public bool IsGameKeyReleased(int gameKey) => _inner.IsGameKeyReleased(gameKey);
    public bool IsGameKeyPressed(int gameKey) => _inner.IsGameKeyPressed(gameKey);
    public float GetGameKeyAxis(string gameKey) => _inner.GetGameKeyAxis(gameKey);
    public bool IsHotKeyDown(string gameKey) => _inner.IsHotKeyDown(gameKey);
    public bool IsHotKeyReleased(string gameKey) => _inner.IsHotKeyReleased(gameKey);
    public bool IsHotKeyPressed(string gameKey) => _inner.IsHotKeyPressed(gameKey);
    public bool IsHotKeyDoublePressed(string gameKey) => _inner.IsHotKeyDoublePressed(gameKey);
    public bool IsKeyDown(InputKey key) => _inner.IsKeyDown(key);
    public bool IsKeyPressed(InputKey key) => _inner.IsKeyPressed(key);
    public bool IsKeyReleased(InputKey key) => _inner.IsKeyReleased(key);
    public Vec2 GetKeyState(InputKey key) => _inner.GetKeyState(key);
    public float GetMouseMoveX() => _inner.GetMouseMoveX();
    public float GetMouseMoveY() => _inner.GetMouseMoveY();
    public Vec2 GetControllerRightStickState() => _inner.GetControllerRightStickState();
    public Vec2 GetControllerLeftStickState() => _inner.GetControllerLeftStickState();
    public float GetDeltaMouseScroll() => _inner.GetDeltaMouseScroll();
    public bool GetIsControllerConnected() => _inner.GetIsControllerConnected();
    public bool GetIsMouseActive() => _inner.GetIsMouseActive();
    public Vec2 GetMousePositionRanged() => _inner.GetMousePositionRanged();
    public Vec2 GetMousePositionPixel() => _inner.GetMousePositionPixel();
    public float GetMouseSensitivity() => _inner.GetMouseSensitivity();
    public bool IsControlDown() => _inner.IsControlDown();
    public bool IsShiftDown() => _inner.IsShiftDown();
    public bool IsAltDown() => _inner.IsAltDown();
    public InputKey[] GetClickKeys() => _inner.GetClickKeys();
}
