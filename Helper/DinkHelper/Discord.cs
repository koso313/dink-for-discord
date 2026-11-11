using System;
using System.Collections.Generic;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.IO;
using System.Linq;
using System.Net;
using System.Net.Http;
using System.Text.RegularExpressions;
using System.Threading;
using System.Web.Script.Serialization;

namespace DinkHelper
{
    /// <summary>An alert as sent by the addon (JSON inside the data code or the saved outbox).</summary>
    public sealed class Alert
    {
        public string Id, Type, Title, Message, Player, Class, Zone, Ruleset, Url, AddonVersion;
        public int Level, Color;
        public long Timestamp;
        public bool HasImage, Compact;
        public List<string[]> Fields = new List<string[]>();
        public List<bool> FieldInline = new List<bool>();

        static readonly JavaScriptSerializer Json = new JavaScriptSerializer();

        public static Alert Parse(string json)
        {
            if (!(Json.DeserializeObject(json) is Dictionary<string, object> d)) return null;
            string S(string k) => d.TryGetValue(k, out var v) && v != null ? Convert.ToString(v) : null;
            long N(string k) => d.TryGetValue(k, out var v) && v != null && !(v is string) ? Convert.ToInt64(v) : 0;
            var a = new Alert
            {
                Id = S("id"), Type = S("t") ?? "TEST", Title = S("title"), Message = S("msg") ?? "",
                Player = S("p") ?? "Someone", Class = S("cls"), Zone = S("zone"), Ruleset = S("rs"),
                Url = S("url"), AddonVersion = S("ver"),
                Level = (int)N("lvl"), Color = (int)N("col"), Timestamp = N("ts"), HasImage = N("img") == 1,
                Compact = S("sty") == "c",
            };
            if (d.TryGetValue("fields", out var f) && f is object[] list)
                foreach (var item in list)
                    if (item is object[] pair && pair.Length >= 2)
                    {
                        a.Fields.Add(new[] { Convert.ToString(pair[0]), Convert.ToString(pair[1]) });
                        a.FieldInline.Add(pair.Length > 2 && pair[2] is bool b && b);
                    }
            return string.IsNullOrEmpty(a.Id) ? null : a;
        }
    }

    public static class Discord
    {
        static readonly HttpClient Http = new HttpClient { Timeout = TimeSpan.FromSeconds(60) };
        static readonly JavaScriptSerializer Json = new JavaScriptSerializer { MaxJsonLength = int.MaxValue };
        const long MaxUpload = 8L * 1024 * 1024;

        static Discord()
        {
            ServicePointManager.SecurityProtocol |= SecurityProtocolType.Tls12;
            Http.DefaultRequestHeaders.UserAgent.ParseAdd("DinkForDiscordHelper/1.1");
        }

        static readonly Regex WebhookPattern = new Regex(
            @"^https://(ptb\.|canary\.)?discord(app)?\.com/api/webhooks/\d+/[\w-]+(\?.*)?$", RegexOptions.IgnoreCase);

        /// <summary>Only real Discord webhooks are accepted, so the helper can't be used to send screenshots elsewhere.</summary>
        public static bool IsWebhook(string url)
        {
            if (string.IsNullOrWhiteSpace(url)) return false;
            if (Environment.GetEnvironmentVariable("DINK_TEST_ALLOW_LOCALHOST") == "1" && url.StartsWith("http://127.0.0.1:")) return true;
            return WebhookPattern.IsMatch(url.Trim());
        }

        static readonly Dictionary<string, string> ClassNames = new Dictionary<string, string>
        {
            ["WARRIOR"] = "Warrior", ["PALADIN"] = "Paladin", ["HUNTER"] = "Hunter", ["ROGUE"] = "Rogue",
            ["PRIEST"] = "Priest", ["SHAMAN"] = "Shaman", ["MAGE"] = "Mage", ["WARLOCK"] = "Warlock", ["DRUID"] = "Druid",
        };

        static string Cut(string s, int max) => s == null ? null : s.Length <= max ? s : s.Substring(0, max - 1) + "…";

        static readonly Dictionary<string, string> Emoji = new Dictionary<string, string>
        {
            ["DEATH"] = "\U0001F480", ["LEVEL"] = "\U0001F389", ["LOOT"] = "\U0001F4B0", ["QUEST"] = "\U0001F4DC",
            ["BOSS"] = "⚔️", ["SKILL"] = "\U0001F6E0️", ["REP"] = "\U0001F91D", ["COLLECTION"] = "\U0001F984",
            ["LEGACY"] = "\U0001F3C6", ["PVP"] = "\U0001F5E1️", ["GOLD"] = "\U0001FA99", ["TRADE"] = "\U0001F501",
            ["AUCTION"] = "\U0001F528", ["CHAT"] = "\U0001F4AC", ["TEST"] = "\U0001F514",
        };

        /// <summary>Short card: emoji + message as the title, one detail line, screenshot as a small thumbnail.</summary>
        static Dictionary<string, object> BuildCompact(Alert a, string className, bool withImage)
        {
            string text = string.IsNullOrWhiteSpace(a.Message) ? a.Title ?? "Dink" : a.Message.Replace("\r", "").Replace("\n", " ");
            string title = (Emoji.TryGetValue(a.Type ?? "", out var e) ? e + " " : "") + text;
            var details = new List<string>();
            if (a.Level > 0) details.Add($"Level {a.Level}" + (className != null ? " " + className : ""));
            if (!string.IsNullOrEmpty(a.Zone)) details.Add(a.Zone);
            if (!string.IsNullOrEmpty(a.Ruleset) && a.Ruleset != "Normal") details.Add(a.Ruleset);
            string desc = string.Join(" · ", details);
            if (a.Fields.Count > 0)
            {
                string extra = string.Join(" · ", a.Fields.Take(6).Select(f => string.IsNullOrEmpty(f[1]) ? f[0] : $"{f[0]}: {f[1]}"));
                desc = desc.Length > 0 ? desc + "\n" + Cut(extra, 300) : Cut(extra, 300);
            }
            var embed = new Dictionary<string, object> { ["title"] = Cut(title, 256), ["color"] = a.Color & 0xFFFFFF };
            if (desc.Length > 0) embed["description"] = desc;
            if (!string.IsNullOrEmpty(a.Url) && Uri.TryCreate(a.Url, UriKind.Absolute, out var u) && u.Scheme == "https") embed["url"] = a.Url;
            if (withImage) embed["thumbnail"] = new Dictionary<string, object> { ["url"] = "attachment://screenshot.jpg" };
            return new Dictionary<string, object> { ["embeds"] = new[] { embed } };
        }

        public static Dictionary<string, object> BuildPayload(Alert a, bool withImage)
        {
            string className = a.Class != null && ClassNames.TryGetValue(a.Class, out var cn) ? cn : null;
            if (a.Compact) return BuildCompact(a, className, withImage);
            string author = a.Player;
            if (a.Level > 0) author += $" • Level {a.Level}" + (className != null ? " " + className : "");
            var embed = new Dictionary<string, object>
            {
                ["title"] = Cut(a.Title ?? "Dink", 256),
                ["description"] = Cut(a.Message, 4000),
                ["color"] = a.Color & 0xFFFFFF,
                ["author"] = a.Class != null && className != null
                    ? new Dictionary<string, object> { ["name"] = Cut(author, 256), ["icon_url"] = $"https://wow.zamimg.com/images/wow/icons/large/classicon_{a.Class.ToLowerInvariant()}.jpg" }
                    : new Dictionary<string, object> { ["name"] = Cut(author, 256) },
            };
            if (!string.IsNullOrEmpty(a.Url) && Uri.TryCreate(a.Url, UriKind.Absolute, out var u) && u.Scheme == "https") embed["url"] = a.Url;
            if (a.Fields.Count > 0)
                embed["fields"] = a.Fields.Take(25).Select((f, i) => new Dictionary<string, object>
                {
                    ["name"] = Cut(f[0], 256), ["value"] = Cut(string.IsNullOrEmpty(f[1]) ? "-" : f[1], 1024), ["inline"] = a.FieldInline[i],
                }).ToArray();
            string footer = "Dink For Discord • WoW Forever";
            if (!string.IsNullOrEmpty(a.Ruleset) && a.Ruleset != "Normal") footer += " • " + a.Ruleset;
            if (!string.IsNullOrEmpty(a.Zone)) footer += " • " + a.Zone;
            embed["footer"] = new Dictionary<string, object> { ["text"] = Cut(footer, 2048) };
            if (a.Timestamp > 0) embed["timestamp"] = DateTimeOffset.FromUnixTimeSeconds(a.Timestamp).ToString("yyyy-MM-ddTHH:mm:ssZ");
            if (withImage) embed["image"] = new Dictionary<string, object> { ["url"] = "attachment://screenshot.jpg" };
            return new Dictionary<string, object> { ["embeds"] = new[] { embed } };
        }

        /// <summary>Makes the screenshot small enough for Discord (re-encodes as JPEG when needed).</summary>
        public static byte[] PrepareImage(string path)
        {
            byte[] raw = File.ReadAllBytes(path);
            bool isJpeg = raw.Length > 3 && raw[0] == 0xFF && raw[1] == 0xD8;
            using (var ms = new MemoryStream(raw))
            using (var img = Image.FromStream(ms))
            {
                if (isJpeg && raw.Length <= MaxUpload && img.Width <= 2560) return raw;
                double scale = Math.Min(1.0, 1920.0 / img.Width);
                int w = (int)(img.Width * scale), h = (int)(img.Height * scale);
                using (var bmp = new Bitmap(w, h))
                {
                    using (var g = Graphics.FromImage(bmp))
                    {
                        g.InterpolationMode = InterpolationMode.HighQualityBicubic;
                        g.DrawImage(img, 0, 0, w, h);
                    }
                    var codec = ImageCodecInfo.GetImageEncoders().First(c => c.FormatID == ImageFormat.Jpeg.Guid);
                    for (long q = 90; q >= 50; q -= 10)
                    {
                        var p = new EncoderParameters(1);
                        p.Param[0] = new EncoderParameter(System.Drawing.Imaging.Encoder.Quality, q);
                        using (var outMs = new MemoryStream())
                        {
                            bmp.Save(outMs, codec, p);
                            if (outMs.Length <= MaxUpload || q == 50) return outMs.ToArray();
                        }
                    }
                }
            }
            return raw;
        }

        static string WithWait(string url)
        {
            if (url.Contains("wait=")) return url;
            return url + (url.Contains("?") ? "&" : "?") + "wait=true";
        }

        /// <summary>Posts one alert to one webhook. Retries on rate limits and network errors. Returns null on success, else an error.</summary>
        public static string Post(string webhook, Alert alert, byte[] image, CancellationToken cancel)
        {
            if (!IsWebhook(webhook)) return "not a Discord webhook URL";
            string body = Json.Serialize(BuildPayload(alert, image != null));
            string lastError = null;
            for (int attempt = 0; attempt < 6 && !cancel.IsCancellationRequested; attempt++)
            {
                HttpContent content;
                if (image != null)
                {
                    var multi = new MultipartFormDataContent();
                    multi.Add(new StringContent(body, System.Text.Encoding.UTF8, "application/json"), "payload_json");
                    var file = new ByteArrayContent(image);
                    file.Headers.ContentType = new System.Net.Http.Headers.MediaTypeHeaderValue("image/jpeg");
                    multi.Add(file, "files[0]", "screenshot.jpg");
                    content = multi;
                }
                else content = new StringContent(body, System.Text.Encoding.UTF8, "application/json");

                try
                {
                    using (var resp = Http.PostAsync(WithWait(webhook.Trim()), content, cancel).GetAwaiter().GetResult())
                    {
                        if (resp.IsSuccessStatusCode) return null;
                        string text = resp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                        int code = (int)resp.StatusCode;
                        if (code == 429)
                        {
                            double wait = 2;
                            var m = Regex.Match(text, "\"retry_after\"\\s*:\\s*([\\d.]+)");
                            if (m.Success) wait = double.Parse(m.Groups[1].Value, System.Globalization.CultureInfo.InvariantCulture);
                            lastError = "rate limited";
                            cancel.WaitHandle.WaitOne(TimeSpan.FromSeconds(Math.Min(60, wait + 0.25)));
                            continue;
                        }
                        if (code >= 500) lastError = $"Discord error {code}";
                        else if (code == 401 || code == 404) return "webhook not found (deleted or mistyped?)";
                        else return $"Discord refused the post ({code}): {Cut(text, 200)}";
                    }
                }
                catch (Exception ex) when (!cancel.IsCancellationRequested)
                {
                    lastError = ex.InnerException?.Message ?? ex.Message;
                }
                finally { content.Dispose(); }
                cancel.WaitHandle.WaitOne(TimeSpan.FromSeconds(Math.Pow(2, attempt + 1)));
            }
            return lastError ?? "cancelled";
        }
    }
}
