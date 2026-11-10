using System;
using System.IO;
using System.Threading;
using System.Windows.Forms;

namespace DinkHelper
{
    static class Program
    {
        [STAThread]
        static int Main(string[] args)
        {
            // Command-line modes, used by the automated tests:
            //   DinkHelper.exe --decode <image>      prints the alert JSON hidden in a screenshot
            //   DinkHelper.exe --once <wow folder>   processes screenshots and saved alerts once, then exits
            if (args.Length >= 2 && args[0] == "--decode")
            {
                string json = StripDecoder.DecodeFile(args[1]);
                Console.Out.Write(json ?? "");
                return json == null ? 1 : 0;
            }
            if (args.Length >= 1 && args[0] == "--selftest")
            {
                // Builds the status window without showing it, to catch layout errors.
                var worker = new Worker(State.Load());
                using (var form = new StatusForm(null, worker, System.Drawing.SystemIcons.Application))
                {
                    var handle = form.Handle;
                    form.RefreshStatus();
                    form.AddLog("selftest");
                }
                Console.Out.Write("selftest ok");
                return 0;
            }
            if (args.Length >= 2 && args[0] == "--once")
            {
                var worker = new Worker(State.Load());
                worker.Log += line => Console.Out.WriteLine(line);
                worker.SetFolder(args[1]);
                worker.RunOnce();
                return 0;
            }

            using (var mutex = new Mutex(true, @"Local\DinkForDiscordHelper", out bool first))
            {
                if (!first)
                {
                    MessageBox.Show("Dink For Discord Helper is already running. Look for the bell icon in your system tray.",
                        "Dink For Discord", MessageBoxButtons.OK, MessageBoxIcon.Information);
                    return 0;
                }
                Application.EnableVisualStyles();
                Application.SetCompatibleTextRenderingDefault(false);
                Application.Run(new TrayApp(args));
            }
            return 0;
        }
    }
}
