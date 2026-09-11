using System;
using System.Runtime.InteropServices;

namespace MacroPad
{
    /// <summary>
    /// Raw Input API P/Invoke surface. This is the whole diagnostic engine:
    /// GetRawInputDeviceList + GetRawInputDeviceInfo(RIDI_DEVICEINFO) give us
    /// VID/PID/UsagePage/Usage per *top-level HID collection* (not just per
    /// composite-device interface), and WM_INPUT + GetRawInputData gives us
    /// live events tagged with the originating device handle.
    /// </summary>
    internal static class NativeMethods
    {
        public const int WM_INPUT = 0x00FF;

        public const uint RIDEV_REMOVE = 0x00000001;
        public const uint RIDEV_PAGEONLY = 0x00000020;
        public const uint RIDEV_INPUTSINK = 0x00000100;
        public const uint RIDEV_NOLEGACY = 0x00000030; // NOT used in M1 - see README limitations

        public const uint RIM_TYPEMOUSE = 0;
        public const uint RIM_TYPEKEYBOARD = 1;
        public const uint RIM_TYPEHID = 2;

        public const uint RIDI_PREPARSEDDATA = 0x20000005;
        public const uint RIDI_DEVICENAME = 0x20000007;
        public const uint RIDI_DEVICEINFO = 0x2000000b;

        public const uint RID_HEADER = 0x10000005;
        public const uint RID_INPUT = 0x10000003;

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTDEVICE
        {
            public ushort usUsagePage;
            public ushort usUsage;
            public uint dwFlags;
            public IntPtr hwndTarget;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTDEVICELIST
        {
            public IntPtr hDevice;
            public uint dwType;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWINPUTHEADER
        {
            public uint dwType;
            public uint dwSize;
            public IntPtr hDevice;
            public IntPtr wParam;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWKEYBOARD
        {
            public ushort MakeCode;
            public ushort Flags; // bit0 = RI_KEY_BREAK (key up), bit1 = RI_KEY_E0, bit2 = RI_KEY_E1
            public ushort Reserved;
            public ushort VKey;
            public uint Message;
            public uint ExtraInformation;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWMOUSE
        {
            public ushort usFlags;
            public ushort usButtonFlags; // RI_MOUSE_WHEEL = 0x0400 etc.
            public ushort usButtonData;  // wheel delta (signed) when usButtonFlags has WHEEL bit
            public uint ulRawButtons;
            public int lLastX;
            public int lLastY;
            public uint ulExtraInformation;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RAWHID
        {
            public uint dwSizeHid; // size of ONE report, in bytes
            public uint dwCount;   // number of reports in this WM_INPUT
            // bRawData[] follows immediately in memory - read manually with Marshal.Copy
        }

        // RID_DEVICE_INFO is a C union on dwType. We lay the three variants
        // at the same offset and only read the one matching dwType.
        [StructLayout(LayoutKind.Explicit)]
        public struct RID_DEVICE_INFO
        {
            [FieldOffset(0)] public uint cbSize;
            [FieldOffset(4)] public uint dwType;
            [FieldOffset(8)] public RID_DEVICE_INFO_HID hid;
            [FieldOffset(8)] public RID_DEVICE_INFO_KEYBOARD keyboard;
            [FieldOffset(8)] public RID_DEVICE_INFO_MOUSE mouse;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RID_DEVICE_INFO_HID
        {
            public uint dwVendorId;
            public uint dwProductId;
            public uint dwVersionNumber;
            public ushort usUsagePage;
            public ushort usUsage;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RID_DEVICE_INFO_KEYBOARD
        {
            public uint dwType;
            public uint dwSubType;
            public uint dwKeyboardMode;
            public uint dwNumberOfFunctionKeys;
            public uint dwNumberOfIndicators;
            public uint dwNumberOfKeysTotal;
        }

        [StructLayout(LayoutKind.Sequential)]
        public struct RID_DEVICE_INFO_MOUSE
        {
            public uint dwId;
            public uint dwNumberOfButtons;
            public uint dwSampleRate;
            public int fHasHorizontalWheel;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetRawInputDeviceList(
            [In, Out] RAWINPUTDEVICELIST[]? pRawInputDeviceList,
            ref uint puiNumDevices,
            uint cbSize);

        [DllImport("user32.dll", SetLastError = true, CharSet = CharSet.Auto)]
        public static extern uint GetRawInputDeviceInfo(
            IntPtr hDevice,
            uint uiCommand,
            IntPtr pData,
            ref uint pcbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool RegisterRawInputDevices(
            RAWINPUTDEVICE[] pRawInputDevices,
            uint uiNumDevices,
            uint cbSize);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern uint GetRawInputData(
            IntPtr hRawInput,
            uint uiCommand,
            IntPtr pData,
            ref uint pcbSize,
            uint cbSizeHeader);

        [DllImport("kernel32.dll")]
        public static extern bool AllocConsole();

        // ---------------- Low-level keyboard hook (for suppression) ----------------
        // WH_KEYBOARD_LL fires for every keyboard event system-wide and CAN block
        // delivery (return non-zero, don't call CallNextHookEx) - but it does not
        // tell you which physical device an event came from. We correlate it
        // against Raw Input (which DOES know the source device) in SuppressionEngine.

        public const int WH_KEYBOARD_LL = 13;
        public const int WM_KEYDOWN = 0x0100;
        public const int WM_KEYUP = 0x0101;
        public const int WM_SYSKEYDOWN = 0x0104;
        public const int WM_SYSKEYUP = 0x0105;
        public const uint LLKHF_EXTENDED = 0x01;
        public const uint LLKHF_INJECTED = 0x10; // ignore keys injected by software (e.g. our own future SendInput)

        public delegate IntPtr LowLevelKeyboardProc(int nCode, IntPtr wParam, IntPtr lParam);

        [StructLayout(LayoutKind.Sequential)]
        public struct KBDLLHOOKSTRUCT
        {
            public uint vkCode;
            public uint scanCode;
            public uint flags;
            public uint time; // ms since system start - comparable to Environment.TickCount
            public IntPtr dwExtraInfo;
        }

        [DllImport("user32.dll", SetLastError = true)]
        public static extern IntPtr SetWindowsHookEx(int idHook, LowLevelKeyboardProc lpfn, IntPtr hMod, uint dwThreadId);

        [DllImport("user32.dll", SetLastError = true)]
        public static extern bool UnhookWindowsHookEx(IntPtr hhk);

        [DllImport("user32.dll")]
        public static extern IntPtr CallNextHookEx(IntPtr hhk, int nCode, IntPtr wParam, IntPtr lParam);

        [DllImport("kernel32.dll", CharSet = CharSet.Auto)]
        public static extern IntPtr GetModuleHandle(string? lpModuleName);
    }
}
