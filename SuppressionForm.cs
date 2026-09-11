using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Windows.Forms;

namespace MacroPad
{
    /// <summary>
    /// M3/M4 (partial): device-specific capture + suppression, no kernel driver.
    /// Confirmed events (matrix + left encoder as Keyboard-type, right encoder as
    /// Consumer Control) are fed into SuppressionEngine. Suppressed events are
    /// logged with their friendly label; nothing is sent to Lightroom yet - that's
    /// the next step once suppression itself is confirmed reliable.
    /// </summary>
    internal class SuppressionForm : Form
    {
        private readonly int _targetVid;
        private readonly int _targetPid;
        private readonly Dictionary<IntPtr, RawDeviceInfo> _deviceCache = new();
        private readonly SuppressionEngine _engine = new();

        private int _suppressedCount = 0;
        private int _passedThroughCount = 0;

        public SuppressionForm(int vid, int pid)
        {
            _targetVid = vid;
            _targetPid = pid;

            Text = "MacroPad Suppression (hidden - see console)";
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

            _engine.Suppressed += (label, down) =>
            {
                _suppressedCount++;
                Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} SUPPRESSED  {label,-32} {(down ? "DOWN" : "UP  ")}   (total suppressed: {_suppressedCount})");
            };
            _engine.PassedThrough += (text, down) =>
            {
                _passedThroughCount++;
                // Very chatty (fires for every keystroke from your real keyboard too) -
                // left in so you can visually confirm normal typing still works.
                Console.WriteLine($"{DateTime.Now:HH:mm:ss.fff} passthrough {text,-32} {(down ? "DOWN" : "UP  ")}   (total passthrough: {_passedThroughCount})");
            };
            _engine.Start();

            Console.WriteLine("Low-level hook installed. Suppression is now ACTIVE for the matched device.");
            Console.WriteLine("Type normally on your real keyboard - it should be completely unaffected.");
            Console.WriteLine("Press keys / turn encoders on the macro pad - each should log as SUPPRESSED");
            Console.WriteLine("and NOT reach any other application (test in Notepad, and check that system");
            Console.WriteLine("volume does not change when you turn the right encoder).\n");
        }

        private void RefreshDeviceCache()
        {
            _deviceCache.Clear();
            foreach (var d in HidEnumerator.EnumerateAll())
                _deviceCache[d.Handle] = d;
        }

        private void RegisterForRawInput()
        {
            var devices = new[]
            {
                new NativeMethods.RAWINPUTDEVICE
                {
                    usUsagePage = 0x01, usUsage = 0x06, // Keyboard
                    dwFlags = NativeMethods.RIDEV_INPUTSINK,
                    hwndTarget = Handle
                },
                new NativeMethods.RAWINPUTDEVICE
                {
                    usUsagePage = 0x0C, usUsage = 0x01, // Consumer Control
                    dwFlags = NativeMethods.RIDEV_INPUTSINK,
                    hwndTarget = Handle
                },
            };

            bool ok = NativeMethods.RegisterRawInputDevices(
                devices, (uint)devices.Length, (uint)Marshal.SizeOf<NativeMethods.RAWINPUTDEVICE>());
            if (!ok)
                Console.WriteLine($"WARNING: RegisterRawInputDevices failed, Win32 error {Marshal.GetLastWin32Error()}");
        }

        protected override void WndProc(ref Message m)
        {
            if (m.Msg == NativeMethods.WM_INPUT)
                HandleRawInput(m.LParam);
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
                    RefreshDeviceCache();
                    _deviceCache.TryGetValue(header.hDevice, out dev);
                }

                bool isTarget = dev != null && dev.IsTargetDevice(_targetVid, _targetPid);
                if (!isTarget) return;

                IntPtr dataPtr = IntPtr.Add(buf, (int)headerSize);

                if (header.dwType == NativeMethods.RIM_TYPEKEYBOARD)
                {
                    var kb = Marshal.PtrToStructure<NativeMethods.RAWKEYBOARD>(dataPtr);
                    bool isBreak = (kb.Flags & 0x01) != 0;
                    string label = MappingTable.KeyboardVKeyLabels.TryGetValue(kb.VKey, out var l) ? l : $"VKey=0x{kb.VKey:X2} (unmapped)";
                    _engine.NoteKeyboardEvent(kb.VKey, !isBreak, label);
                }
                else if (header.dwType == NativeMethods.RIM_TYPEHID && dev!.UsagePage == 0x0C && dev.Usage == 0x01)
                {
                    var hid = Marshal.PtrToStructure<NativeMethods.RAWHID>(dataPtr);
                    IntPtr reportsPtr = IntPtr.Add(dataPtr, Marshal.SizeOf<NativeMethods.RAWHID>());
                    if (hid.dwCount > 0 && hid.dwSizeHid >= 3)
                    {
                        var bytes = new byte[hid.dwSizeHid];
                        Marshal.Copy(reportsPtr, bytes, 0, (int)hid.dwSizeHid);
                        int usage = bytes[1] | (bytes[2] << 8); // confirmed layout: [reportId][usageLo][usageHi]
                        string label = usage != 0 && MappingTable.ConsumerUsageLabels.TryGetValue(usage, out var l)
                            ? l
                            : (usage == 0 ? "(release)" : $"Consumer usage=0x{usage:X2} (unmapped)");
                        _engine.NoteConsumerUsage(usage, label);
                    }
                }
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        protected override void OnFormClosed(FormClosedEventArgs e)
        {
            _engine.Stop();
            base.OnFormClosed(e);
        }
    }
}
