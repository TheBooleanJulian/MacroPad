using System.Collections.Generic;

namespace MacroPad
{
    /// <summary>
    /// Maps the raw identifiers we confirmed via the M1 diagnostic to human-readable
    /// control labels. Purely for logging right now - this becomes the basis for the
    /// actual Lightroom action table once suppression itself is confirmed working.
    /// </summary>
    internal static class MappingTable
    {
        // VKey -> label, for the 16 matrix keys + 3 left-encoder actions (all arrive
        // as ordinary keyboard-type Raw Input events on the MI_01 collection).
        public static readonly Dictionary<int, string> KeyboardVKeyLabels = new()
        {
            { 0x67, "7" },
            { 0x68, "8" },
            { 0x69, "9" },
            { 0x6D, "-" },
            { 0x64, "4" },
            { 0x65, "5" },
            { 0x66, "6" },
            { 0x6B, "+" },
            { 0x61, "1" },
            { 0x62, "2" },
            { 0x63, "3" },
            { 0x6F, "/" },
            { 0x60, "0" },
            { 0x6A, "*" },
            { 0x6E, "." },
            { 0x0D, "Enter" },
            { 0x08, "LeftEncoder-CW (Backspace)" },
            { 0x20, "LeftEncoder-CCW (Space)" },
            { 0x90, "LeftEncoder-Press (NumLock)" },
        };

        // Consumer Control usage -> label, for the 3 right-encoder actions (arrive as
        // HID reports on MI_00/Col03, usage page 0x0C).
        public static readonly Dictionary<int, string> ConsumerUsageLabels = new()
        {
            { 0xE9, "RightEncoder-CCW (VolumeUp)" },
            { 0xEA, "RightEncoder-CW (VolumeDown)" },
            { 0xE2, "RightEncoder-Press (Mute)" },
        };
    }
}
