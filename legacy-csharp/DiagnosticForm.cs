using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MacroPad
{
    /// <summary>
    /// Invisible window used purely to receive WM_INPUT. We use a real (but
    /// hidden/off-screen) Form rather than a true message-only window (HWND_MESSAGE)
    /// because WM_INPUT delivery to message-only windows is unreliable pre-Win10 1809
    /// for some usage pages; a normal top-level hidden window is the safe, well-documented
    /// choice and costs nothing since it's never shown.
    ///
    /// IMPORTANT (M1 scope): this registers for input but applies NO suppression.
    /// Every event you generate on the macro pad still reaches Windows/your foreground
    /// app normally, exactly as before. Suppression is M4.
    /// </summary>
    internal class DiagnosticForm : Form
    {
        private readonly int _targetVid;
        private readonly int _targetPid;
        private readonly bool _verbose;
        private readonly Dictionary<IntPtr, RawDeviceInfo> _deviceCache = new();

        public DiagnosticForm(int vid, int pid, bool verbose)
        {
            _targetVid = vid;
            _targetPid = pid;
            _verbose = verbose;

            Text = "MacroPad Diagnostic (hidden - see console output)";
            ShowInTaskbar = false;
            FormBorderStyle = FormBorderStyle.FixedToolWindow;
            StartPosition = FormStartPosition.Manual;
            Location = new System.Drawing.Point(-3000, -3000);
            Width = 1;
            Height = 1;
            Opacity = 0;
        }

        protected override void OnHandleCreated(EventArgs e)
        {
            base.OnHandleCreated(e);
            RefreshDeviceCache();
            RegisterForRawInput();
        }

        private void RefreshDeviceCache()
        {
            _deviceCache.Clear();
            foreach (var d in HidEnumerator.EnumerateAll())
                _deviceCache[d.Handle] = d;
        }

        private void RegisterForRawInput()
        {
            // We register three broad usage buckets that commonly cover keypads/encoders:
            //   Generic Desktop / Keyboard   - the 16-key matrix almost certainly lands here
            //   Generic Desktop / Mouse      - in case an encoder reports as a scroll wheel
            //   Consumer / Consumer Control  - Volume Up/Down/Mute strongly suggest this page
            // The static enumeration above will show us if the device also exposes a
            // vendor-defined usage page (0xFF00+) that we're NOT capturing yet - if so,
            // that's exactly the kind of finding M2 needs, and we'll add it explicitly
            // once we see it (RegisterRawInputDevices requires known page/usage pairs,
            // it can't wildcard vendor-defined pages blindly).
            var devices = new[]
            {
                new NativeMethods.RAWINPUTDEVICE
                {
                    usUsagePage = 0x01, usUsage = 0x06,
                    dwFlags = NativeMethods.RIDEV_INPUTSINK,
                    hwndTarget = Handle
                },
                new NativeMethods.RAWINPUTDEVICE
                {
                    usUsagePage = 0x01, usUsage = 0x02,
                    dwFlags = NativeMethods.RIDEV_INPUTSINK,
                    hwndTarget = Handle
                },
                new NativeMethods.RAWINPUTDEVICE
                {
                    usUsagePage = 0x0C, usUsage = 0x01,
                    dwFlags = NativeMethods.RIDEV_INPUTSINK,
                    hwndTarget = Handle
                },
            };

            bool ok = NativeMethods.RegisterRawInputDevices(
                devices, (uint)devices.Length, (uint)Marshal.SizeOf<NativeMethods.RAWINPUTDEVICE>());

            if (!ok)
            {
                Console.WriteLine($"WARNING: RegisterRawInputDevices failed, Win32 error {Marshal.GetLastWin32Error()}");
            }
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_INPUT)
            {
                HandleRawInput(m.LParam);
            }
            base.WndProc(ref m);
        }

        private void HandleRawInput(IntPtr hRawInput)
        {
            uint headerSize = (uint)Marshal.SizeOf<NativeMethods.RAWINPUTHEADER>();
            uint size = 0;
            NativeMethods.GetRawInputData(hRawInput, NativeMethods.RID_INPUT, IntPtr.Zero, ref size, headerSize);
            if (size == 0) return;

            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try
            {
                uint written = NativeMethods.GetRawInputData(hRawInput, NativeMethods.RID_INPUT, buf, ref size, headerSize);
                if (written == unchecked((uint)-1) || written != size) return;

                var header = Marshal.PtrToStructure<NativeMethods.RAWINPUTHEADER>(buf);

                if (!_deviceCache.TryGetValue(header.hDevice, out var dev))
                {
                    // Possibly a hot-plug we haven't cached yet - refresh once and retry.
                    RefreshDeviceCache();
                    _deviceCache.TryGetValue(header.hDevice, out dev);
                }

                bool isTarget = dev != null && dev.IsTargetDevice(_targetVid, _targetPid);
                if (!isTarget && !_verbose) return;

                string tag = dev != null
                    ? $"[{RawDeviceInfo.TypeName(dev.Type)} Interface={dev.InterfaceTag ?? "?"} " +
                      $"Collection={dev.CollectionTag ?? "?"} UsagePage=0x{dev.UsagePage:X2} " +
                      $"Usage=0x{dev.Usage:X2} ({RawDeviceInfo.UsageName(dev.UsagePage, dev.Usage)})]"
                    : "[Unknown device - not in cache]";

                if (!isTarget)
                    tag = "(OTHER DEVICE, verbose mode) " + tag;

                IntPtr dataPtr = IntPtr.Add(buf, (int)headerSize);

                switch (header.dwType)
                {
                    case NativeMethods.RIM_TYPEKEYBOARD:
                        LogKeyboard(tag, dataPtr);
                        break;
                    case NativeMethods.RIM_TYPEMOUSE:
                        LogMouse(tag, dataPtr);
                        break;
                    case NativeMethods.RIM_TYPEHID:
                        LogHid(tag, dataPtr);
                        break;
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        private static void LogKeyboard(string tag, IntPtr dataPtr)
        {
            var kb = Marshal.PtrToStructure<NativeMethods.RAWKEYBOARD>(dataPtr);
            bool isBreak = (kb.Flags & 0x01) != 0; // RI_KEY_BREAK
            string vkName = SafeVkName(kb.VKey);
            Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} KEYBOARD {tag}");
            Console.WriteLine($"    MakeCode=0x{kb.MakeCode:X2}  VKey=0x{kb.VKey:X2} ({vkName})  " +
                               $"Flags=0x{kb.Flags:X2}  State={(isBreak ? "UP" : "DOWN")}");
        }

        private static void LogMouse(string tag, IntPtr dataPtr)
        {
            var mouse = Marshal.PtrToStructure<NativeMethods.RAWMOUSE>(dataPtr);
            Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} MOUSE {tag}");
            Console.WriteLine($"    ButtonFlags=0x{mouse.usButtonFlags:X4}  " +
                               $"ButtonData(wheel delta if applicable)={(short)mouse.usButtonData}  " +
                               $"dX={mouse.lLastX}  dY={mouse.lLastY}");
        }

        private static void LogHid(string tag, IntPtr dataPtr)
        {
            var hid = Marshal.PtrToStructure<NativeMethods.RAWHID>(dataPtr);
            IntPtr reportsPtr = IntPtr.Add(dataPtr, Marshal.SizeOf<NativeMethods.RAWHID>());
            Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} HID {tag}");
            Console.WriteLine($"    {hid.dwCount} report(s), {hid.dwSizeHid} byte(s) each:");
            for (int i = 0; i < hid.dwCount; i++)
            {
                IntPtr reportPtr = IntPtr.Add(reportsPtr, (int)(i * hid.dwSizeHid));
                var bytes = new byte[hid.dwSizeHid];
                Marshal.Copy(reportPtr, bytes, 0, (int)hid.dwSizeHid);
                Console.WriteLine($"    Report[{i}] = {BitConverter.ToString(bytes)}");
            }
        }

        private static string SafeVkName(ushort vkey)
        {
            try { return ((Keys)vkey).ToString(); }
            catch { return "?"; }
        }
    }
}
