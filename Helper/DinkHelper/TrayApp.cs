using System;
using System.Diagnostics;
using System.Drawing;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using System.Windows.Forms;
using Microsoft.Win32;

namespace DinkHelper
{
    /// <summary>System tray icon plus a small status window. All real setup happens in game (/dink).</summary>
    sealed class TrayApp : ApplicationContext
    {
        const string RunKey = @"Software\Microsoft\Windows\CurrentVersion\Run";
        const string RunName = "DinkForDiscordHelper";

        readonly NotifyIcon tray;
        readonly Worker worker;
        readonly Icon icon;
        StatusForm form;
        string lastBalloonError;

        public TrayApp(string[] args)
        {
            icon = LoadIcon();
            worker = new Worker(State.Load());
            tray = new NotifyIcon { Icon = icon, Text = "Dink For Discord", Visible = true };
            var menu = new ContextMenuStrip();
            menu.Items.Add("Open Dink helper", null, (s, e) => ShowForm());
            menu.Items.Add("Send a test post", null, (s, e) => SendTest());
            menu.Items.Add("Open Screenshots folder", null, (s, e) => OpenScreenshots());
            var pause = new ToolStripMenuItem("Pause posting") { CheckOnClick = true };
            pause.CheckedChanged += (s, e) => { worker.Paused = pause.Checked; UpdateTray(); };
            menu.Items.Add(pause);
            menu.Items.Add(new ToolStripSeparator());
            menu.Items.Add("Exit", null, (s, e) => ExitThread());
            tray.ContextMenuStrip = menu;
            tray.DoubleClick += (s, e) => ShowForm();

            worker.Log += line => form?.AddLog(line);
            worker.Changed += () => UI(() => { UpdateTray(); form?.RefreshStatus(); });
            worker.Start();

            bool firstRun = !File.Exists(State.LogPath);
            if (firstRun || args.Contains("--show")) ShowForm();
            else tray.ShowBalloonTip(3000, "Dink For Discord", "Running in the tray. Alerts from WoW Forever will post to Discord.", ToolTipIcon.Info);
        }

        static Icon LoadIcon()
        {
            try
            {
                using (var s = typeof(TrayApp).Assembly.GetManifestResourceStream("DinkHelper.icon.ico"))
                    if (s != null) return new Icon(s);
            }
            catch { }
            return SystemIcons.Application;
        }

        void UI(Action a)
        {
            var target = form != null && form.IsHandleCreated ? (Control)form : null;
            if (target != null && target.InvokeRequired) target.BeginInvoke(a);
            else if (target == null) syncContext.Post(_ => a(), null);
            else a();
        }
        readonly System.Threading.SynchronizationContext syncContext =
            System.Threading.SynchronizationContext.Current ?? new WindowsFormsSynchronizationContext();

        void UpdateTray()
        {
            string status = worker.Paused ? "paused"
                : worker.Folder == null ? "WoW folder not found"
                : worker.LastError != null ? "problem - open for details"
                : "running";
            string text = "Dink For Discord - " + status;
            tray.Text = text.Length > 63 ? text.Substring(0, 63) : text;
            if (worker.LastError != null && worker.LastError != lastBalloonError)
            {
                lastBalloonError = worker.LastError;
                tray.ShowBalloonTip(5000, "Dink For Discord", worker.LastError, ToolTipIcon.Warning);
            }
            if (worker.LastError == null) lastBalloonError = null;
        }

        void ShowForm()
        {
            if (form == null || form.IsDisposed)
            {
                form = new StatusForm(this, worker, icon);
            }
            form.Show();
            form.WindowState = FormWindowState.Normal;
            form.Activate();
            form.RefreshStatus();
        }

        public void SendTest()
        {
            Task.Run(() =>
            {
                string err = worker.SendHelperTest();
                UI(() => MessageBox.Show(err == null ? "Test post sent. Check your Discord channel." : "Couldn't post: " + err,
                    "Dink For Discord", MessageBoxButtons.OK, err == null ? MessageBoxIcon.Information : MessageBoxIcon.Warning));
            });
        }

        public void OpenScreenshots()
        {
            string dir = worker.ScreenshotFolder;
            if (dir != null && Directory.Exists(dir)) Process.Start("explorer.exe", "\"" + dir + "\"");
            else MessageBox.Show("No Screenshots folder yet. Take one screenshot in game (Print Screen) and try again.", "Dink For Discord");
        }

        public void PickFolder(IWin32Window owner)
        {
            using (var dlg = new FolderBrowserDialog { Description = "Select your World of Warcraft folder (the one that contains _forever_)." })
            {
                if (dlg.ShowDialog(owner) != DialogResult.OK) return;
                if (WowLocator.Normalize(dlg.SelectedPath) == null)
                {
                    MessageBox.Show("That folder doesn't contain WoW Forever (_forever_).", "Dink For Discord", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                    return;
                }
                worker.SetFolder(dlg.SelectedPath);
            }
        }

        public static bool StartsWithWindows
        {
            get
            {
                using (var k = Registry.CurrentUser.OpenSubKey(RunKey))
                    return k?.GetValue(RunName) != null;
            }
            set
            {
                using (var k = Registry.CurrentUser.CreateSubKey(RunKey))
                {
                    if (value) k.SetValue(RunName, "\"" + Application.ExecutablePath + "\"");
                    else k.DeleteValue(RunName, false);
                }
            }
        }

        protected override void ExitThreadCore()
        {
            worker.Stop();
            tray.Visible = false;
            tray.Dispose();
            base.ExitThreadCore();
        }
    }
}
