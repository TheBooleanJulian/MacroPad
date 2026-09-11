using System;
using System.Text.RegularExpressions;

namespace MacroPad
{
    /// <summary>
    /// One row of GetRawInputDeviceList() - i.e. one top-level HID collection.
    /// A single composite device (like your VID_0818/PID_D18A keypad) will show
    /// up as SEVERAL of these: one per interface, and potentially more than one
    /// per interface if that interface exposes multiple top-level collections
    /// (e.g. a keyboard collection AND a consumer-control collection under the
    /// same MI_xx). That's exactly the ambiguity M1 exists to resolve.
    /// </summary>
    internal class RawDeviceInfo
    {
        public IntPtr Handle;
        public uint Type; // RIM_TYPEMOUSE / RIM_TYPEKEYBOARD / RIM_TYPEHID
        public string Path = "";
        public uint VendorId;
        public uint ProductId;
        public ushort UsagePage;
        public ushort Usage;
        public string? InterfaceTag; // e.g. "MI_00"
        public string? CollectionTag; // e.g. "Col01"

        public bool IsTargetDevice(int vid, int pid) => VendorId == vid && ProductId == pid;

        public void ParsePathTags()
        {
            var mi = Regex.Match(Path, @"MI_([0-9A-Fa-f]{2})");
            if (mi.Success) InterfaceTag = "MI_" + mi.Groups[1].Value;

            var col = Regex.Match(Path, @"Col0*([0-9A-Fa-f]+)", RegexOptions.IgnoreCase);
            if (col.Success) CollectionTag = "Col" + col.Groups[1].Value.PadLeft(2, '0');

            // RID_DEVICE_INFO only carries VID/PID for RIM_TYPEHID collections - keyboard-
            // and mouse-type collections (RIM_TYPEKEYBOARD/RIM_TYPEMOUSE, e.g. a standard
            // HID boot-keyboard matrix or a mouse-wheel encoder) leave VendorId/ProductId
            // at 0 even though the device path always encodes them. Fill in from the path
            // whenever the API didn't give us a value, so matching works for every type.
            if (VendorId == 0 && ProductId == 0)
            {
                var vidPid = Regex.Match(Path, @"VID_([0-9A-Fa-f]{4})&PID_([0-9A-Fa-f]{4})", RegexOptions.IgnoreCase);
                if (vidPid.Success)
                {
                    VendorId = Convert.ToUInt32(vidPid.Groups[1].Value, 16);
                    ProductId = Convert.ToUInt32(vidPid.Groups[2].Value, 16);
                }
            }
        }

        public override string ToString()
        {
            return $"VID=0x{VendorId:X4} PID=0x{ProductId:X4}  Type={TypeName(Type)}  " +
                   $"Interface={InterfaceTag ?? "?"}  Collection={CollectionTag ?? "?"}  " +
                   $"UsagePage=0x{UsagePage:X2}  Usage=0x{Usage:X2} ({UsageName(UsagePage, Usage)})\n" +
                   $"    PATH={Path}";
        }

        public static string TypeName(uint t) => t switch
        {
            NativeMethods.RIM_TYPEMOUSE => "Mouse",
            NativeMethods.RIM_TYPEKEYBOARD => "Keyboard",
            NativeMethods.RIM_TYPEHID => "HID",
            _ => "Unknown"
        };

        public static string UsageName(ushort page, ushort usage)
        {
            if (page == 0x01)
            {
                return usage switch
                {
                    0x02 => "GenericDesktop:Mouse",
                    0x06 => "GenericDesktop:Keyboard",
                    0x00 => "GenericDesktop:Undefined",
                    _ => $"GenericDesktop:0x{usage:X2}"
                };
            }
            if (page == 0x0C) return usage == 0x01 ? "Consumer:ConsumerControl" : $"Consumer:0x{usage:X2}";
            if (page >= 0xFF00) return $"VendorDefined(page 0x{page:X4}):0x{usage:X2}";
            return $"Page 0x{page:X2}:Usage 0x{usage:X2}";
        }
    }
}
