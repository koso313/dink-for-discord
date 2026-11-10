using System;
using System.Drawing;
using System.Windows.Forms;

namespace DinkHelper
{
    /// <summary>Status window: where WoW is, whether a webhook is set, what was posted.</summary>
    sealed class StatusForm : Form
    {
        static readonly Color Blurple = Color.FromArgb(88, 101, 242);
        readonly TrayApp app;
        readonly Worker worker;
        readonly Label folderValue, hookValue, lastValue, problem;
        readonly ListBox log;

        public StatusForm(TrayApp app, Worker worker, Icon icon)
        {
            this.app = app;
            this.worker = worker;
            Text = "Dink For Discord Helper";
            Icon = icon;
            Font = new Font("Segoe UI", 9.5f);
            ClientSize = new Size(620, 470);
            MinimumSize = new Size(560, 420);
            StartPosition = FormStartPosition.CenterScreen;
            BackColor = Color.White;

            var header = new Panel { Dock = DockStyle.Top, Height = 64, BackColor = Blurple };
            var pic = new PictureBox { Image = icon.ToBitmap(), SizeMode = PictureBoxSizeMode.Zoom, Bounds = new Rectangle(14, 12, 40, 40) };
            var title = new Label { Text = "Dink For Discord", ForeColor = Color.White, Font = new Font("Segoe UI Semibold", 15f), AutoSize = true, Location = new Point(64, 8) };
            var sub = new Label { Text = "Posts your WoW Forever alerts to Discord. Set alerts up in game with /dink.", ForeColor = Color.FromArgb(225, 228, 255), AutoSize = true, Location = new Point(66, 38) };
            header.Controls.AddRange(new Control[] { pic, title, sub });

            var grid = new TableLayoutPanel { Dock = DockStyle.Top, Height = 120, ColumnCount = 3, Padding = new Padding(14, 12, 14, 0) };
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 110));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Percent, 100));
            grid.ColumnStyles.Add(new ColumnStyle(SizeType.Absolute, 96));
            Label Caption(string t) => new Label { Text = t, AutoSize = true, Font = new Font(Font, FontStyle.Bold), Margin = new Padding(0, 6, 0, 0) };
            Label Value() => new Label { AutoSize = true, MaximumSize = new Size(380, 0), Margin = new Padding(0, 6, 0, 0) };
            folderValue = Value(); hookValue = Value(); lastValue = Value();
            var change = new Button { Text = "Change...", Width = 90 };
            change.Click += (s, e) => app.PickFolder(this);
            grid.Controls.Add(Caption("WoW folder"), 0, 0); grid.Controls.Add(folderValue, 1, 0); grid.Controls.Add(change, 2, 0);
            grid.Controls.Add(Caption("Discord"), 0, 1); grid.Controls.Add(hookValue, 1, 1);
            grid.Controls.Add(Caption("Last alert"), 0, 2); grid.Controls.Add(lastValue, 1, 2);

            problem = new Label { Dock = DockStyle.Top, Height = 30, ForeColor = Color.FromArgb(190, 40, 40), Padding = new Padding(16, 6, 16, 0), Visible = false };

            var buttons = new FlowLayoutPanel { Dock = DockStyle.Bottom, Height = 46, Padding = new Padding(10, 8, 10, 6), FlowDirection = FlowDirection.LeftToRight };
            var test = new Button { Text = "Send a test post", AutoSize = true };
            test.Click += (s, e) => app.SendTest();
            var shots = new Button { Text = "Open Screenshots folder", AutoSize = true };
            shots.Click += (s, e) => app.OpenScreenshots();
            var startup = new CheckBox { Text = "Start with Windows", AutoSize = true, Margin = new Padding(16, 7, 0, 0) };
            try { startup.Checked = TrayApp.StartsWithWindows; } catch { }
            startup.CheckedChanged += (s, e) => { try { TrayApp.StartsWithWindows = startup.Checked; } catch { } };
            buttons.Controls.AddRange(new Control[] { test, shots, startup });

            var logLabel = new Label { Text = "Activity", Dock = DockStyle.Top, Height = 24, Padding = new Padding(14, 6, 0, 0), Font = new Font(Font, FontStyle.Bold) };
            log = new ListBox { Dock = DockStyle.Fill, IntegralHeight = false, BorderStyle = BorderStyle.None, Font = new Font("Consolas", 9f) };
            var logPanel = new Panel { Dock = DockStyle.Fill, Padding = new Padding(14, 0, 14, 0) };
            logPanel.Controls.Add(log);

            Controls.Add(logPanel);
            Controls.Add(logLabel);
            Controls.Add(problem);
            Controls.Add(grid);
            Controls.Add(header);
            Controls.Add(buttons);

            // Closing the window keeps the helper running in the tray.
            FormClosing += (s, e) => { if (e.CloseReason == CloseReason.UserClosing) { e.Cancel = true; Hide(); } };
        }

        public void AddLog(string line)
        {
            if (!IsHandleCreated) return;
            BeginInvoke((Action)(() =>
            {
                log.Items.Add(line);
                while (log.Items.Count > 300) log.Items.RemoveAt(0);
                log.TopIndex = Math.Max(0, log.Items.Count - 1);
            }));
        }

        public void RefreshStatus()
        {
            folderValue.Text = worker.Folder ?? "Not found. Click Change... and pick your World of Warcraft folder.";
            var s = worker.Settings;
            if (worker.Folder == null) hookValue.Text = "-";
            else if (s == null) hookValue.Text = "Waiting for the addon. Install Dink For Discord, log in, then type /dink.";
            else if (s.Webhooks.Count == 0) hookValue.Text = "No webhook yet. In game: /dink, paste your webhook, click Save & Reload.";
            else hookValue.Text = $"{s.Webhooks.Count} webhook(s) ready" + (worker.Paused ? " (paused)" : "");
            lastValue.Text = worker.LastAlert ?? "None yet";
            problem.Text = worker.LastError ?? "";
            problem.Visible = worker.LastError != null;
        }
    }
}
