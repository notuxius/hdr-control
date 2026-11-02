using System;
using System.Device.Location;
using System.IO;
using System.Reflection;

[assembly: AssemblyTitle("HDR Control")]
[assembly: AssemblyProduct("HDR Control")]

namespace LocalHdrMenu {
    internal static class HdrLocation {
        // Only the tray starts this one-shot reader, with an anonymous stdout pipe.
        static int Main(string[] args) {
            if (args.Length != 1 || args[0] != "--read-location" || !Console.IsOutputRedirected) return 1;
            try {
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
