using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Web.Script.Serialization;
using Microsoft.Win32;

namespace DinkHelper
{
    /// <summary>The helper's own small state file: WoW folder and which alerts were already posted.</summary>
    public sealed class State
    {
        public string WowFolder;
        public List<string> Posted = new List<string>();
        public long FirstRun;

        static string Dir => Environment.GetEnvironmentVariable("DINK_STATE_DIR")
            ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "DinkForDiscord");
        static string FilePath => Path.Combine(Dir, "state.json");
        public static string LogPath => Path.Combine(Dir, "helper.log");

        HashSet<string> postedSet;

        public static State Load()
        {
            State s = null;
            try
            {
                if (File.Exists(FilePath))
                    s = new JavaScriptSerializer().Deserialize<State>(File.ReadAllText(FilePath));
            }
            catch { }
            s = s ?? new State();
            if (s.Posted == null) s.Posted = new List<string>();
            if (s.FirstRun == 0) s.FirstRun = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            s.postedSet = new HashSet<string>(s.Posted);
            return s;
        }

        public void Save()
        {
            try
            {
                Directory.CreateDirectory(Dir);
                if (Posted.Count > 3000) { Posted = Posted.Skip(Posted.Count - 2000).ToList(); postedSet = new HashSet<string>(Posted); }
                string tmp = FilePath + ".tmp";
                File.WriteAllText(tmp, new JavaScriptSerializer().Serialize(new { WowFolder, Posted, FirstRun }));
                if (File.Exists(FilePath)) File.Delete(FilePath);
                File.Move(tmp, FilePath);
            }
            catch { }
        }

        public bool WasPosted(string id) => postedSet.Contains(id);
        public void MarkPosted(string id) { if (postedSet.Add(id)) Posted.Add(id); Save(); }
    }

    public static class WowLocator
    {
        /// <summary>Finds the WoW Forever folder (the one with Wow.exe inside "_forever_").</summary>
        public static string Find()
        {
            var roots = new List<string>();
            foreach (var key in new[] { @"SOFTWARE\WOW6432Node\Blizzard Entertainment\World of Warcraft", @"SOFTWARE\Blizzard Entertainment\World of Warcraft" })
            {
                try
                {
                    using (var k = Registry.LocalMachine.OpenSubKey(key))
                    {
                        var p = k?.GetValue("InstallPath") as string;
                        if (!string.IsNullOrEmpty(p)) { roots.Add(p); roots.Add(Path.GetDirectoryName(p.TrimEnd('\\'))); }
                    }
                }
                catch { }
            }
            foreach (var drive in DriveInfo.GetDrives().Where(d => d.DriveType == DriveType.Fixed && d.IsReady))
            {
                string r = drive.RootDirectory.FullName;
                roots.Add(Path.Combine(r, "Program Files (x86)", "World of Warcraft"));
                roots.Add(Path.Combine(r, "Program Files", "World of Warcraft"));
                roots.Add(Path.Combine(r, "World of Warcraft"));
                roots.Add(Path.Combine(r, "Games", "World of Warcraft"));
                roots.Add(Path.Combine(r, "Battle.net", "World of Warcraft"));
            }
            foreach (var root in roots.Where(r => !string.IsNullOrEmpty(r)).Distinct(StringComparer.OrdinalIgnoreCase))
            {
                string f = Normalize(root);
                if (f != null) return f;
            }
            return null;
        }

        /// <summary>Accepts the WoW root or the _forever_ folder itself; returns the _forever_ folder or null.</summary>
        public static string Normalize(string path)
        {
            if (string.IsNullOrEmpty(path)) return null;
            try
            {
                if (Path.GetFileName(path.TrimEnd('\\', '/')).Equals("_forever_", StringComparison.OrdinalIgnoreCase) && Directory.Exists(path))
                    return path.TrimEnd('\\', '/');
                string sub = Path.Combine(path, "_forever_");
                if (Directory.Exists(sub)) return sub;
            }
            catch { }
            return null;
        }
    }
}
