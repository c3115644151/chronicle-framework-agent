#Requires -Version 7.0
# Keeps an automation launch from holding the user desktop: while the game loads it re-hands the
# foreground to the window the user was using before the run started.
if (-not ("ChronicleWindowGuard" -as [type])) {
Add-Type -Namespace "" -Name ChronicleWindowGuard -MemberDefinition @'
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr handle);
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr handle, out uint processId);
    public static System.Threading.Thread StartRestoring(System.IntPtr prior, int gameProcessId, int seconds) {
        var thread = new System.Threading.Thread(() => {
            for (var step = 0; step < seconds; step++) {
                try {
                    var current = GetForegroundWindow();
                    uint owner;
                    GetWindowThreadProcessId(current, out owner);
                    if (current != prior && (int)owner == gameProcessId) SetForegroundWindow(prior);
                } catch { }
                System.Threading.Thread.Sleep(1000);
            }
        });
        thread.IsBackground = true;
        thread.Start();
        return thread;
    }
'@
}