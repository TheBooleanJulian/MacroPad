using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MacroPad
{
    /// <summary>
    /// Device-specific suppression WITHOUT a kernel driver.
    ///
    /// Raw Input tells us which device an event came from, but can't stop delivery.
    /// A global WH_KEYBOARD_LL hook CAN stop delivery (return non-zero, skip
    /// CallNextHookEx), but doesn't know which device an event came from.
    ///
    /// We bridge the two with a timing correlation: when Raw Input reports an event
    /// from the TARGET device, we stash (VKey, down/up, timestamp). When the global
    /// hook sees a matching (VKey, down/up) within a short window, we treat it as
    /// "that one" and block it. Anything the hook sees that doesn't match a recent
    /// stashed event (your real keyboard, anything else) passes through untouched.
    ///
    /// HONEST LIMITATION: this is a heuristic, not a guarantee. If you pressed the
    /// exact same key on your real keyboard and the macro pad within ~30ms of each
    /// other, one event could be misattributed. For a dedicated macro pad this is not
    /// a realistic scenario, but it is categorically different from a kernel-level
    /// per-device filter (which the Interception driver would have given us, had it
    /// installed cleanly).
    /// </summary>
    internal class SuppressionEngine
    {
        private const uint CorrelationWindowMs = 30;
        private const uint PruneAfterMs = 150;

        // Consumer Control usage -> the VK Windows conventionally synthesizes for it.
        // This mapping is the thing we're testing empirically by skipping the separate
        // confirmation script - if it's wrong, suppressed-count will stay 0 for the
        // right encoder and system volume will keep changing; that's the answer.
        private static readonly Dictionary<int, int> ConsumerUsageToVKey = new()
        {
            { 0xE9, 0xAF }, // Volume Increment -> VK_VOLUME_UP
            { 0xEA, 0xAE }, // Volume Decrement -> VK_VOLUME_DOWN
            { 0xE2, 0xAD }, // Mute             -> VK_VOLUME_MUTE
        };

        private class PendingEvent
        {
            public int VKey;
            public bool Down;
            public uint TimeMs;
            public string Label = "";
        }

        private readonly List<PendingEvent> _pending = new();
        private NativeMethods.LowLevelKeyboardProc? _hookProc; // field, not local - must not be GC'd while hooked
        private IntPtr _hookHandle = IntPtr.Zero;
        private int _lastConsumerVKey;

        public event Action<string, bool>? Suppressed;    // (label, wasKeyDown)
        public event Action<string, bool>? PassedThrough;  // (vkeyText, wasKeyDown) - unmatched hook events

        public void Start()
        {
            _hookProc = HookCallback;
            _hookHandle = NativeMethods.SetWindowsHookEx(
                NativeMethods.WH_KEYBOARD_LL, _hookProc, NativeMethods.GetModuleHandle(null), 0);
            if (_hookHandle == IntPtr.Zero)
                throw new InvalidOperationException("SetWindowsHookEx failed, Win32 error " + Marshal.GetLastWin32Error());
        }

        public void Stop()
        {
            if (_hookHandle != IntPtr.Zero)
            {
                NativeMethods.UnhookWindowsHookEx(_hookHandle);
                _hookHandle = IntPtr.Zero;
            }
            _hookProc = null;
        }

        /// Call for TARGET-DEVICE keyboard-type Raw Input events only.
        public void NoteKeyboardEvent(int vkey, bool down, string label)
        {
            Prune();
            _pending.Add(new PendingEvent { VKey = vkey, Down = down, TimeMs = (uint)Environment.TickCount, Label = label });
        }

        /// Call for TARGET-DEVICE Consumer Control HID reports only.
        /// usage == 0 means "released" (report returned to no active usage).
        public void NoteConsumerUsage(int usage, string labelForUsage)
        {
            Prune();
            if (usage != 0 && ConsumerUsageToVKey.TryGetValue(usage, out int vk))
            {
                _lastConsumerVKey = vk;
                _pending.Add(new PendingEvent { VKey = vk, Down = true, TimeMs = (uint)Environment.TickCount, Label = labelForUsage });
            }
            else if (usage == 0 && _lastConsumerVKey != 0)
            {
                _pending.Add(new PendingEvent { VKey = _lastConsumerVKey, Down = false, TimeMs = (uint)Environment.TickCount, Label = labelForUsage });
                _lastConsumerVKey = 0;
            }
        }

        private void Prune()
        {
            uint now = (uint)Environment.TickCount;
            _pending.RemoveAll(p => Diff(now, p.TimeMs) > PruneAfterMs);
        }

        private IntPtr HookCallback(int nCode, IntPtr wParam, IntPtr lParam)
        {
            if (nCode >= 0)
            {
                int msg = wParam.ToInt32();
                bool isDown = msg == NativeMethods.WM_KEYDOWN || msg == NativeMethods.WM_SYSKEYDOWN;
                bool isUp = msg == NativeMethods.WM_KEYUP || msg == NativeMethods.WM_SYSKEYUP;

                if (isDown || isUp)
                {
                    var info = Marshal.PtrToStructure<NativeMethods.KBDLLHOOKSTRUCT>(lParam);
                    bool injected = (info.flags & NativeMethods.LLKHF_INJECTED) != 0;

                    if (!injected)
                    {
                        Prune();
                        int match = _pending.FindIndex(p =>
                            p.VKey == (int)info.vkCode &&
                            p.Down == isDown &&
                            Diff(info.time, p.TimeMs) <= CorrelationWindowMs);

                        if (match >= 0)
                        {
                            var evt = _pending[match];
                            _pending.RemoveAt(match);
                            Suppressed?.Invoke(evt.Label, isDown);
                            return (IntPtr)1; // block: skip CallNextHookEx entirely
                        }

                        PassedThrough?.Invoke($"VK=0x{info.vkCode:X2}", isDown);
                    }
                }
            }
            return NativeMethods.CallNextHookEx(_hookHandle, nCode, wParam, lParam);
        }

        private static uint Diff(uint a, uint b) => a > b ? a - b : b - a;
    }
}
