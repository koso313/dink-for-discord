using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Threading;

namespace DinkHelper
{
    /// <summary>Settings the addon saved (read from SavedVariables/DinkForDiscord.lua).</summary>
    public sealed class AddonSettings
    {
        public List<string> Webhooks = new List<string>();
        public Dictionary<string, List<string>> Overrides = new Dictionary<string, List<string>>();
        public bool KeepShots = true;
        public List<string> Outbox = new List<string>();
        public string Source;
        public DateTime SavedAt;

        public List<string> HooksFor(string type)
        {
            if (type != null && Overrides.TryGetValue(type, out var list) && list.Count > 0) return list;
            return Webhooks;
        }

        static List<string> Split(string text) =>
            (text ?? "").Split(new[] { ' ', '\n', '\r', '\t', ',' }, StringSplitOptions.RemoveEmptyEntries)
                .Where(Discord.IsWebhook).ToList();

        public static AddonSettings Read(string path)
        {
            var vars = LuaSv.Parse(File.ReadAllBytes(path));
            var s = new AddonSettings { Source = path, SavedAt = File.GetLastWriteTime(path) };
            if (!(vars.TryGetValue("DinkForDiscordDB", out var dbObj) && dbObj is LuaTable db)) return s;
            var hooks = db.Table("webhooks");
            if (hooks != null)
                foreach (var h in hooks.Array.Concat(hooks.Hash.Values))
                    s.Webhooks.AddRange(Split(h as string));
            s.Webhooks = s.Webhooks.Distinct().ToList();
            var notifiers = db.Table("notifiers");
            if (notifiers != null)
                foreach (var kv in notifiers.Hash)
                    if (kv.Value is LuaTable n)
                    {
                        var list = Split(n.Str("webhook"));
                        if (list.Count > 0) s.Overrides[kv.Key] = list;
                    }
            s.KeepShots = db.Table("general")?.Bool("keepShots", true) ?? true;
            var outbox = db.Table("outbox");
            if (outbox != null) s.Outbox = outbox.Array.OfType<string>().ToList();
            return s;
        }
    }

    public sealed class Worker
    {
        public event Action<string> Log;
        public event Action Changed;

        public readonly State State;
        public string Folder { get; private set; }
        public AddonSettings Settings { get; private set; }
        public string LastAlert { get; private set; }
        public string LastError { get; private set; }
        public bool Paused;

        readonly CancellationTokenSource cancel = new CancellationTokenSource();
        readonly Dictionary<string, DateTime> seenShots = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string, DateTime> svTimes = new Dictionary<string, DateTime>(StringComparer.OrdinalIgnoreCase);
        readonly HashSet<string> failedShots = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        readonly Dictionary<string, AddonSettings> pendingOutbox = new Dictionary<string, AddonSettings>(StringComparer.OrdinalIgnoreCase);
        readonly object gate = new object();
        Thread thread;
        volatile string pendingFolder;
        volatile bool hasPendingFolder;
        DateTime nextRetry = DateTime.MinValue;

        public Worker(State state) { State = state; }

        public string ScreenshotFolder => Folder == null ? null : Path.Combine(Folder, "Screenshots");

        void Say(string msg)
        {
            string line = $"{DateTime.Now:HH:mm:ss}  {msg}";
            try { File.AppendAllText(State.LogPath, DateTime.Now.ToString("yyyy-MM-dd ") + line + Environment.NewLine); } catch { }
            Log?.Invoke(line);
        }

        /// <summary>Switches folders. Safe to call from the window; the worker picks it up on its next pass.</summary>
        public void SetFolder(string folder)
        {
            pendingFolder = folder;
            hasPendingFolder = true;
        }

        void ApplyFolder()
        {
            if (!hasPendingFolder) return;
            hasPendingFolder = false;
            Folder = WowLocator.Normalize(pendingFolder);
            State.WowFolder = Folder;
            State.Save();
            seenShots.Clear(); svTimes.Clear(); pendingOutbox.Clear(); failedShots.Clear();
            Settings = null;
            Say(Folder != null ? "Watching " + Folder : "WoW Forever folder not found. Pick it from the menu.");
            Changed?.Invoke();
        }

        public void Start()
        {
            SetFolder(WowLocator.Normalize(State.WowFolder) ?? WowLocator.Find());
            thread = new Thread(Loop) { IsBackground = true, Name = "DinkWorker" };
            thread.Start();
        }

        public void Stop() { cancel.Cancel(); }

        void Loop()
        {
            int tick = 0;
            while (!cancel.IsCancellationRequested)
            {
                try
                {
                    lock (gate)
                    {
                        ApplyFolder();
                        if (Folder != null && !Paused) Pass(tick == 0, tick % 3 == 0);
                    }
                }
                catch (Exception ex) { Say("Error: " + ex.Message); }
                tick++;
                cancel.Token.WaitHandle.WaitOne(700);
            }
        }

        public void RunOnce()
        {
            lock (gate)
            {
                ApplyFolder();
                if (Folder != null) Pass(true, true);
            }
        }

        // Live screenshots go first so an alert never gets posted from saved data without its picture.
        void Pass(bool startup, bool readSettings)
        {
            if (readSettings) CheckSavedVariables();
            CheckScreenshots(startup);
            foreach (var s in pendingOutbox.Values.ToList()) PostOutbox(s);
            pendingOutbox.Clear();
        }

        // ---------------------------------------------------------- saved settings + outbox
        IEnumerable<string> SavedVariableFiles()
        {
            string account = Path.Combine(Folder, "WTF", "Account");
            if (!Directory.Exists(account)) yield break;
            foreach (var dir in Directory.GetDirectories(account))
            {
                string f = Path.Combine(dir, "SavedVariables", "DinkForDiscord.lua");
                if (File.Exists(f)) yield return f;
            }
        }

        void CheckSavedVariables()
        {
            var files = SavedVariableFiles().ToList();
            if (files.Count == 0) return;
            bool changed = false;
            var newest = files.OrderByDescending(File.GetLastWriteTime).First();
            foreach (var f in files)
            {
                var t = File.GetLastWriteTime(f);
                if (svTimes.TryGetValue(f, out var old) && old == t && Settings != null) continue;
                AddonSettings s;
                try { s = AddonSettings.Read(f); }
                catch (Exception ex) { Say("Couldn't read addon settings yet: " + ex.Message); continue; }
                svTimes[f] = t;
                changed = true;
                if (f == newest)
                {
                    bool first = Settings == null;
                    Settings = s;
                    Say(s.Webhooks.Count > 0
                        ? $"Loaded addon settings: {s.Webhooks.Count} webhook(s){(s.Overrides.Count > 0 ? $", {s.Overrides.Count} alert-specific" : "")}."
                        : "Addon settings found, but no webhook yet. In game: /dink, paste it, Save & Reload.");
                    if (first) Changed?.Invoke();
                }
                pendingOutbox[f] = s;
            }
            if (changed) { nextRetry = DateTime.MinValue; Changed?.Invoke(); }
        }

        void PostOutbox(AddonSettings s)
        {
            long cutoff = DateTimeOffset.UtcNow.AddHours(-24).ToUnixTimeSeconds();
            foreach (var json in s.Outbox)
            {
                Alert a;
                try { a = Alert.Parse(json); } catch { continue; }
                if (a == null || State.WasPosted(a.Id) || a.Timestamp < cutoff) continue;
                Deliver(a, null, "saved data");
            }
        }

        // ---------------------------------------------------------- screenshots
        void CheckScreenshots(bool startup)
        {
            string dir = ScreenshotFolder;
            if (!Directory.Exists(dir)) return;
            var files = new DirectoryInfo(dir).GetFiles()
                .Where(f => IsImage(f.Name))
                .OrderBy(f => f.LastWriteTime).ThenBy(f => f.Name).ToList();
            var fresh = new List<FileInfo>();
            bool retry = failedShots.Count > 0 && DateTime.Now >= nextRetry;
            if (retry) nextRetry = DateTime.Now.AddSeconds(20);
            foreach (var f in files)
            {
                bool known = seenShots.TryGetValue(f.FullName, out var t) && t == f.LastWriteTime;
                if (known && !(retry && failedShots.Contains(f.FullName))) continue;
                seenShots[f.FullName] = f.LastWriteTime;
                // At startup only look at the last two days, so a big folder isn't scanned every time.
                if (startup && f.LastWriteTime < DateTime.Now.AddDays(-2)) continue;
                fresh.Add(f);
            }
            foreach (var f in fresh)
            {
                if (cancel.IsCancellationRequested) return;
                if (!WaitUntilWritten(f.FullName)) { seenShots.Remove(f.FullName); continue; }
                string json = StripDecoder.DecodeFile(f.FullName);
                if (json == null) continue; // a normal screenshot
                Alert a;
                try { a = Alert.Parse(json); } catch { a = null; }
                if (a == null) continue;
                if (State.WasPosted(a.Id)) { TryDelete(f.FullName); failedShots.Remove(f.FullName); continue; }

                string clean = a.HasImage ? FindCleanShot(files, f) : null;
                if (Deliver(a, clean, "live"))
                {
                    failedShots.Remove(f.FullName);
                    TryDelete(f.FullName);
                    if (clean != null && Settings != null && !Settings.KeepShots) TryDelete(clean);
                }
                else
                {
                    if (failedShots.Add(f.FullName)) nextRetry = DateTime.Now.AddSeconds(20);
                }
            }
        }

        static bool IsImage(string name)
        {
            string ext = Path.GetExtension(name).ToLowerInvariant();
            return ext == ".jpg" || ext == ".jpeg" || ext == ".png" || ext == ".tga";
        }

        // The normal screenshot is the one taken just before the data screenshot.
        string FindCleanShot(List<FileInfo> files, FileInfo dataShot)
        {
            var candidates = files
                .Where(f => f.FullName != dataShot.FullName && f.LastWriteTime <= dataShot.LastWriteTime.AddSeconds(1)
                            && f.LastWriteTime >= dataShot.LastWriteTime.AddSeconds(-20))
                .OrderByDescending(f => f.LastWriteTime).ThenByDescending(f => f.Name);
            foreach (var c in candidates)
            {
                if (!File.Exists(c.FullName)) continue;
                if (StripDecoder.DecodeFile(c.FullName) != null) continue; // another data shot
                return c.FullName;
            }
            return null;
        }

        static bool WaitUntilWritten(string path)
        {
            long last = -1;
            for (int i = 0; i < 20; i++)
            {
                try
                {
                    long len = new FileInfo(path).Length;
                    if (len > 0 && len == last)
                    {
                        using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read)) { }
                        return true;
                    }
                    last = len;
                }
                catch (IOException) { }
                catch (UnauthorizedAccessException) { }
                Thread.Sleep(150);
            }
            return false;
        }

        void TryDelete(string path)
        {
            try { File.Delete(path); seenShots.Remove(path); } catch { }
        }

        // ---------------------------------------------------------- posting
        bool Deliver(Alert a, string imagePath, string how)
        {
            var hooks = Settings?.HooksFor(a.Type) ?? new List<string>();
            if (hooks.Count == 0)
            {
                LastError = "No webhook yet. In game: /dink, paste your webhook, then Save & Reload.";
                if (!warnedNoHook) { Say("Got an alert but no webhook is set. In game: /dink, paste it, then Save & Reload."); warnedNoHook = true; }
                Changed?.Invoke();
                return false;
            }
            warnedNoHook = false;
            byte[] image = null;
            if (imagePath != null)
            {
                try { image = Discord.PrepareImage(imagePath); }
                catch (Exception ex) { Say("Couldn't read the screenshot: " + ex.Message); }
            }
            bool allOk = true;
            foreach (var hook in hooks)
            {
                string err = Discord.Post(hook, a, image, cancel.Token);
                if (err != null) { allOk = false; LastError = err; Say($"Couldn't post \"{a.Title}\": {err}"); }
            }
            if (allOk)
            {
                State.MarkPosted(a.Id);
                LastError = null;
                LastAlert = $"{a.Title} at {DateTime.Now:HH:mm}";
                Say($"Posted \"{a.Title}\" ({how}{(image != null ? ", with screenshot" : "")}).");
            }
            Changed?.Invoke();
            return allOk;
        }
        bool warnedNoHook;

        /// <summary>Posts a test straight from the helper (no game needed) to check the webhook.</summary>
        public string SendHelperTest()
        {
            var hooks = Settings?.Webhooks ?? new List<string>();
            if (hooks.Count == 0) return "No webhook found yet. In game: /dink, paste your webhook, then Save & Reload.";
            var a = new Alert
            {
                Id = "helper-test-" + DateTime.Now.Ticks, Type = "TEST", Title = "Dink helper is connected",
                Message = "The helper can post to this channel. Alerts from the game will show up here.",
                Player = "Dink For Discord", Color = 0x7289da, Timestamp = DateTimeOffset.UtcNow.ToUnixTimeSeconds(),
            };
            foreach (var h in hooks)
            {
                string err = Discord.Post(h, a, null, cancel.Token);
                if (err != null) return err;
            }
            return null;
        }
    }
}
