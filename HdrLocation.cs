using System;
using System.Device.Location;
using System.Diagnostics;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("HDR Control")]
[assembly: AssemblyProduct("HDR Control")]

namespace LocalHdrMenu {
    internal static class HdrLocation {
        static int Main(string[] args) {
            try {
                if (args.Length == 1 && args[0] == "--startup") {
                    string launcher = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Toggle-HdrSdr.vbs");
                    var start = new ProcessStartInfo(Path.Combine(Environment.SystemDirectory, "wscript.exe"),
                        "//NoLogo \"" + launcher + "\" Watch") { UseShellExecute = false, CreateNoWindow = true };
                    using (Process.Start(start)) { return 0; }
                }
                if (args.Length != 1 || args[0] != "--read-location" || !Console.IsOutputRedirected) return 1;
                using (var watcher = new GeoCoordinateWatcher()) {
                    if (!watcher.TryStart(true, TimeSpan.FromSeconds(12))) return 1;
                    var position = watcher.Position;
                    if (position.Location.IsUnknown) return 1;
                    using (var output = new BinaryWriter(Console.OpenStandardOutput())) {
                        output.Write(position.Location.Latitude);
                        output.Write(position.Location.Longitude);
                        output.Write(position.Timestamp.UtcDateTime.Ticks);
                    }
                    return 0;
                }
            } catch (Exception) {
                return 1;
            }
        }
    }
}
