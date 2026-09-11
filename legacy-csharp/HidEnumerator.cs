using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;

namespace MacroPad
{
    internal static class HidEnumerator
    {
        public static List<RawDeviceInfo> EnumerateAll()
        {
            var result = new List<RawDeviceInfo>();
            uint count = 0;
            uint listItemSize = (uint)Marshal.SizeOf<NativeMethods.RAWINPUTDEVICELIST>();

            uint ret = NativeMethods.GetRawInputDeviceList(null, ref count, listItemSize);
            if (ret == unchecked((uint)-1) || count == 0) return result;

            var list = new NativeMethods.RAWINPUTDEVICELIST[count];
            ret = NativeMethods.GetRawInputDeviceList(list, ref count, listItemSize);
            if (ret == unchecked((uint)-1)) return result;

            foreach (var item in list)
            {
                var info = new RawDeviceInfo { Handle = item.hDevice, Type = item.dwType };
                info.Path = GetDeviceName(item.hDevice);
                FillDeviceInfo(item.hDevice, info);
                info.ParsePathTags();
                result.Add(info);
            }

            return result;
        }

        private static string GetDeviceName(IntPtr hDevice)
        {
            uint size = 0;
            NativeMethods.GetRawInputDeviceInfo(hDevice, NativeMethods.RIDI_DEVICENAME, IntPtr.Zero, ref size);
            if (size == 0) return "";

            // Size is in "characters" for this command; allocate generously in bytes (UTF-16).
            IntPtr buf = Marshal.AllocHGlobal((int)size * 2 + 2);
            try
            {
                uint r = NativeMethods.GetRawInputDeviceInfo(hDevice, NativeMethods.RIDI_DEVICENAME, buf, ref size);
                if (r == unchecked((uint)-1)) return "";
                return Marshal.PtrToStringUni(buf) ?? "";
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }

        private static void FillDeviceInfo(IntPtr hDevice, RawDeviceInfo info)
        {
            uint size = (uint)Marshal.SizeOf<NativeMethods.RID_DEVICE_INFO>();
            IntPtr buf = Marshal.AllocHGlobal((int)size);
            try
            {
                var seed = new NativeMethods.RID_DEVICE_INFO { cbSize = size };
                Marshal.StructureToPtr(seed, buf, false);

                uint r = NativeMethods.GetRawInputDeviceInfo(hDevice, NativeMethods.RIDI_DEVICEINFO, buf, ref size);
                if (r == unchecked((uint)-1)) return;

                var filled = Marshal.PtrToStructure<NativeMethods.RID_DEVICE_INFO>(buf);
                if (filled.dwType == NativeMethods.RIM_TYPEHID)
                {
                    info.VendorId = filled.hid.dwVendorId;
                    info.ProductId = filled.hid.dwProductId;
                    info.UsagePage = filled.hid.usUsagePage;
                    info.Usage = filled.hid.usUsage;
                }
                // Note: pure keyboard/mouse legacy devices (dwType == RIM_TYPEKEYBOARD/RIM_TYPEMOUSE)
                // don't carry VID/PID in this struct - only the HID variant does. Your macro pad's
                // collections should all report as RIM_TYPEHID since it's a HID-class composite device.
            }
            finally
            {
                Marshal.FreeHGlobal(buf);
            }
        }
    }
}
