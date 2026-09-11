using System;
using System.Windows.Forms;

namespace MacroPad
{
    internal static class Program
    {
        // Your hardware, from the spec. Override with --vid/--pid (hex, no 0x prefix)
        // if you ever need to point this at a different device.
        private const int DefaultVid = 0x0818;
        private const int DefaultPid = 0xD18A;

        [STAThread]
        private static void Main(string[] args)
        {
            bool diagnostic = HasFlag(args, "--diagnostic");
            bool listOnly = HasFlag(args, "--list");
            bool verbose = HasFlag(args, "--verbose");
            bool suppress = HasFlag(args, "--suppress");

            if (!diagnostic && !listOnly && !suppress)
            {
                NativeMethods.AllocConsole();
                PrintUsage();
                return;
            }

            NativeMethods.AllocConsole();

            int vid = ArgHex(args, "--vid", DefaultVid);
            int pid = ArgHex(args, "--pid", DefaultPid);

            if (suppress)
            {
                RunSuppress(vid, pid);
                return;
            }

            Console.WriteLine("=== MacroPad Diagnostic Tool (M1) ===");
            Console.WriteLine($"Target device: VID=0x{vid:X4} PID=0x{pid:X4}");
            Console.WriteLine("No suppression is active. Your normal keyboard/mouse are completely untouched.\n");

            Console.WriteLine("--- Static enumeration (GetRawInputDeviceList) ---");
            Console.WriteLine("Every currently attached raw-input device / top-level HID collection:\n");

            var devices = HidEnumerator.EnumerateAll();
            int matchCount = 0;
            foreach (var d in devices)
            {
                bool isTarget = d.IsTargetDevice(vid, pid);
                if (isTarget) matchCount++;
                if (isTarget) Console.ForegroundColor = ConsoleColor.Green;
                Console.WriteLine((isTarget ? ">>> MATCH  " : "           ") + d);
                Console.WriteLine();
                Console.ResetColor();
            }

            Console.WriteLine($"Found {matchCount} matching top-level collection(s) for VID_0818&PID_D18A.");
            if (matchCount == 0)
            {
                Console.WriteLine("No match found. Is the keypad plugged in? Double-check VID/PID with --vid/--pid.");
            }
            Console.WriteLine();

            if (listOnly)
            {
                Console.WriteLine("(--list specified: exiting without live capture.)");
                return;
            }

            Console.WriteLine("--- Live capture ---");
            Console.WriteLine("Press every key on the 4x4 matrix, rotate both encoders both directions,");
            Console.WriteLine("and press both encoder buttons. Watch which Interface/Collection/UsagePage");
            Console.WriteLine("fires for each physical control - that's the mapping M2 needs.");
            if (!verbose)
                Console.WriteLine("(Only matching-device events are shown. Pass --verbose to see everything.)");
            Console.WriteLine("Close this console window to stop.\n");

            Application.EnableVisualStyles();
            var form = new DiagnosticForm(vid, pid, verbose);
            Application.Run(form);
        }

        private static void RunSuppress(int vid, int pid)
        {
            Console.WriteLine("=== MacroPad Suppression (M3/M4, no kernel driver) ===");
            Console.WriteLine($"Target device: VID=0x{vid:X4} PID=0x{pid:X4}\n");

            var devices = HidEnumerator.EnumerateAll();
            int matchCount = 0;
            foreach (var d in devices)
                if (d.IsTargetDevice(vid, pid)) matchCount++;

            if (matchCount == 0)
            {
                Console.WriteLine("No matching device found - is the keypad plugged in?");
                return;
            }
            Console.WriteLine($"Found {matchCount} matching top-level collection(s). Starting suppression...\n");

            Application.EnableVisualStyles();
            var form = new SuppressionForm(vid, pid);
            Application.Run(form);
        }

        private static bool HasFlag(string[] args, string flag)
        {
            foreach (var a in args)
                if (string.Equals(a, flag, StringComparison.OrdinalIgnoreCase)) return true;
            return false;
        }

        private static int ArgHex(string[] args, string name, int fallback)
        {
            for (int i = 0; i < args.Length - 1; i++)
            {
                if (string.Equals(args[i], name, StringComparison.OrdinalIgnoreCase))
                {
                    if (int.TryParse(args[i + 1], System.Globalization.NumberStyles.HexNumber, null, out int v))
                        return v;
                }
            }
            return fallback;
        }

        private static void PrintUsage()
        {
            Console.WriteLine("MacroPad.exe --diagnostic [--verbose] [--vid HHHH] [--pid HHHH]");
            Console.WriteLine("    Enumerate matching HID devices, then log live input events until closed.");
            Console.WriteLine();
            Console.WriteLine("MacroPad.exe --list [--vid HHHH] [--pid HHHH]");
            Console.WriteLine("    Print the static device enumeration only, then exit (no live capture).");
            Console.WriteLine();
            Console.WriteLine("MacroPad.exe --suppress [--vid HHHH] [--pid HHHH]");
            Console.WriteLine("    Actively block the matched device's input system-wide (no kernel driver)");
            Console.WriteLine("    while logging what got suppressed. Your real keyboard is unaffected.");
        }
    }
}
