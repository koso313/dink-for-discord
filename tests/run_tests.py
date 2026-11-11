"""End-to-end tests for Dink For Discord without the game.

1. Runs the real addon Lua (Lua 5.1, like WoW) against tests/wow_stub.lua.
2. Builds the whole window (every tab, every alert page) to catch errors.
3. Fires game events for every alert type and checks the saved alerts.
4. Rebuilds each data code the addon drew into a real screenshot (JPEG, several qualities
   and resolutions) and decodes it with the helper (DinkHelper.exe --decode).
5. Writes a fake WoW folder (SavedVariables + Screenshots), runs the helper once against a
   fake Discord server, and checks posts, screenshots, deletions and duplicates.

Run:  python tests/run_tests.py
"""
import http.server
import json
import os
import shutil
import subprocess
import sys
import tempfile
import threading

from PIL import Image, ImageDraw
import lupa.lua51 as lupa51

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ADDON = os.path.join(ROOT, "DinkForDiscord")
HELPER = os.path.join(ROOT, "Helper", "DinkHelper", "bin", "Release", "net48", "DinkHelper.exe")
BACKGROUND = os.path.join(os.path.dirname(ROOT), "PaladinLevelingGuide", "Screenshots", "4-guide-window.png")

failures = []


def check(cond, label):
    print(("  ok    " if cond else "  FAIL  ") + label)
    if not cond:
        failures.append(label)


# ---------------------------------------------------------------- load the addon
def load_addon():
    lua = lupa51.LuaRuntime(unpack_returned_tuples=True)
    with open(os.path.join(ROOT, "tests", "wow_stub.lua"), encoding="utf-8") as f:
        lua.execute(f.read())
    ns = lua.table()
    toc = open(os.path.join(ADDON, "DinkForDiscord.toc"), encoding="utf-8").read().splitlines()
    files = [l.strip() for l in toc if l.strip() and not l.startswith("#")]
    loader = lua.eval("function(code, name, ns) local fn = assert(loadstring(code, '@' .. name)); fn('DinkForDiscord', ns) end")
    for name in files:
        with open(os.path.join(ADDON, name), encoding="utf-8") as f:
            loader(f.read(), name, ns)
    return lua, ns


def outbox(lua):
    box = lua.globals().DinkForDiscordDB.outbox
    return [json.loads(box[i]) for i in range(1, len(box) + 1)]


# ---------------------------------------------------------------- data code -> image
def render_shot(shot, size, background=None):
    w, h = size
    if background and os.path.exists(background):
        img = Image.open(background).convert("RGB").resize((w, h))
    else:
        img = Image.new("RGB", (w, h), (40, 60, 30))
    d = ImageDraw.Draw(img)
    d.rectangle([0, 0, int(shot["w"]) - 1, int(shot["h"]) - 1], fill=(0, 0, 0))
    for c in shot["cells"]:
        x, y, cw, ch = int(c["x"]), int(c["y"]), int(c["w"]), int(c["h"])
        d.rectangle([x, y, x + cw - 1, y + ch - 1], fill=(int(c["r"] * 255), int(c["g"] * 255), int(c["b"] * 255)))
    return img


def lua_shot_to_py(shot):
    cells = shot.cells
    return {"w": shot.w, "h": shot.h,
            "cells": [dict(x=cells[i].x, y=cells[i].y, w=cells[i].w, h=cells[i].h, r=cells[i].r, g=cells[i].g, b=cells[i].b)
                      for i in range(1, len(cells) + 1)]}


def decode(path):
    r = subprocess.run([HELPER, "--decode", path], capture_output=True, text=True, encoding="utf-8")
    return r.stdout if r.returncode == 0 else None


# ---------------------------------------------------------------- SavedVariables writer (WoW style)
SV_WRITER = r"""
function(name, value)
  local out = {}
  local function esc(s) return '"' .. s:gsub('\\', '\\\\'):gsub('"', '\\"'):gsub('\n', '\\n'):gsub('\r', '\\r') .. '"' end
  local function val(v, indent)
    local t = type(v)
    if t == "string" then return esc(v) elseif t == "number" or t == "boolean" then return tostring(v) end
    local lines = { "{" }
    local n = #v
    for i = 1, n do lines[#lines + 1] = indent .. "\t" .. val(v[i], indent .. "\t") .. ", -- [" .. i .. "]" end
    local keys = {}
    for k in pairs(v) do if not (type(k) == "number" and k >= 1 and k <= n) then keys[#keys + 1] = k end end
    table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
    for _, k in ipairs(keys) do
      local key = type(k) == "number" and ("[" .. k .. "]") or ("[" .. esc(k) .. "]")
      lines[#lines + 1] = indent .. "\t" .. key .. " = " .. val(v[k], indent .. "\t") .. ","
    end
    lines[#lines + 1] = indent .. "}"
    return table.concat(lines, "\n")
  end
  return "\n" .. name .. " = " .. val(value, "") .. "\n"
end
"""


# ---------------------------------------------------------------- fake Discord
class FakeDiscord(http.server.BaseHTTPRequestHandler):
    posts = []

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        ctype = self.headers.get("Content-Type", "")
        entry = {"path": self.path, "ctype": ctype, "image": None}
        if ctype.startswith("multipart/form-data"):
            boundary = ctype.split("boundary=")[1].strip('"').encode()
            for part in body.split(b"--" + boundary):
                if b"name=payload_json" in part or b'name="payload_json"' in part:
                    entry["payload"] = json.loads(part.split(b"\r\n\r\n", 1)[1].rsplit(b"\r\n", 1)[0])
                elif b"files[0]" in part:
                    entry["image"] = part.split(b"\r\n\r\n", 1)[1].rsplit(b"\r\n", 1)[0]
        else:
            entry["payload"] = json.loads(body)
        FakeDiscord.posts.append(entry)
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(b'{"id":"1"}')

    def log_message(self, *args):
        pass


# ---------------------------------------------------------------- tests
def main():
    if not os.path.exists(HELPER):
        print("Build the helper first: dotnet build -c Release Helper/DinkHelper")
        sys.exit(2)

    print("Loading addon")
    lua, ns = load_addon()
    T = lua.globals().TEST
    fire = T.Fire
    fire("ADDON_LOADED", "DinkForDiscord")
    fire("PLAYER_LOGIN")
    fire("PLAYER_ENTERING_WORLD")
    T.Run(4)
    db = lua.globals().DinkForDiscordDB
    check(db is not None and db.general.live, "settings created with defaults")
    db.general.debug = True  # event errors get printed to chat; checked at the end
    check(any("Not connected" in str(m) for m in T.chat.values()), "first login says it isn't connected yet")

    print("Window")
    ui = ns.UI
    errors = []
    for tab in ["discord", "alerts", "delivery", "history"]:
        try:
            ui.Show(ui, tab)
        except Exception as e:
            errors.append(f"{tab}: {e}")
    for n in ns.NOTIFIERS.values():
        try:
            ui.SelectNotifier(ui, n.key)
        except Exception as e:
            errors.append(f"{n.key}: {e}")
    check(not errors, "every tab and alert page builds" + (": " + "; ".join(errors) if errors else ""))

    # Configure like a player would.
    db.webhooks[1] = "https://discord.com/api/webhooks/123456/abcDEF-xyz"
    check(ns.HasWebhook(), "pasted webhook is recognised")
    db.webhooks[1] = "https://example.com/not-a-webhook"
    check(not ns.HasWebhook(), "non-Discord URL is rejected")
    db.webhooks[1] = "https://discord.com/api/webhooks/123456/abcDEF-xyz"

    print("Alerts")
    T["items"][19019] = lua.eval('{ name = "Thunderfury, Blessed Blade of the Windseeker", quality = 5, sell = 255000, '
                              'link = "|cffff8000|Hitem:19019::::::::60:::::|h[Thunderfury, Blessed Blade of the Windseeker]|h|r" }')
    T["items"][2589] = lua.eval('{ name = "Linen Cloth", quality = 1, sell = 13, link = "|cffffffff|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r" }')
    T["items"][12345] = lua.eval('{ name = "Shiny Epic Helm", quality = 4, sell = 50000, link = "|cffa335ee|Hitem:12345::::::::60:::::|h[Shiny Epic Helm]|h|r" }')

    def last():
        box = outbox(lua)
        return box[-1] if box else None

    start = len(outbox(lua))
    fire("PLAYER_LEVEL_UP", 43)
    check(last() and last()["t"] == "LEVEL" and "level 43" in last()["msg"], "level up")
    check(last()["lvl"] == 43, "level-up post shows the new level")

    T.targetName, T.targetDead = "Baron Geddon", True
    fire("LOOT_OPENED")
    fire("CHAT_MSG_LOOT", "You receive loot: " + T["items"][19019].link + ".")
    fire("CHAT_MSG_LOOT", "You receive loot: " + T["items"][2589].link + "x4.")
    T.Run(2)
    a = last()
    check(a and a["t"] == "LOOT" and "Thunderfury" in a["msg"] and "Baron Geddon" in a["msg"] and "Linen" not in a["msg"],
          "loot: legendary sent, common filtered, source named")
    check(a and a.get("url", "") == "https://www.wowhead.com/forever/item=19019", "loot links to the item on Wowhead Forever")

    # Two good items in one loot window become one alert.
    n_before = len(outbox(lua))
    fire("CHAT_MSG_LOOT", "You receive loot: " + T["items"][12345].link + ".")
    fire("CHAT_MSG_LOOT", "You receive loot: " + T["items"][19019].link + ".")
    T.Run(2)
    check(len(outbox(lua)) == n_before + 1 and "Shiny Epic Helm" in last()["msg"] and "Thunderfury" in last()["msg"],
          "items looted together are grouped into one alert")

    # Hidden (secret) loot message falls back to bag comparison.
    T.bags[1] = lua.eval('{ link = "|cff9d9d9d|Hitem:2589::::::::60:::::|h[Linen Cloth]|h|r", count = 2 }')
    fire("BAG_UPDATE_DELAYED")
    secret_msg = "secret loot message"
    T.secret[secret_msg] = True
    n_before = len(outbox(lua))
    fire("CHAT_MSG_LOOT", secret_msg)
    T.bags[2] = lua.eval('{ link = "|cffa335ee|Hitem:12345::::::::60:::::|h[Shiny Epic Helm]|h|r", count = 1 }')
    fire("BAG_UPDATE_DELAYED")
    T.Run(2)
    check(len(outbox(lua)) == n_before + 1 and "Shiny Epic Helm" in last()["msg"], "hidden loot message: found via bags")

    fire("QUEST_TURNED_IN", 169, 2400, 1500)
    check(last()["t"] == "QUEST" and "Gath'Ilzogg" in last()["msg"], "quest turn-in")
    check(last().get("url") == "https://www.wowhead.com/forever/quest=169", "quest links to Wowhead Forever")

    fire("ENCOUNTER_START", 1001, "Edwin VanCleef", 1, 5)
    T.Run(30)
    fire("ENCOUNTER_END", 1001, "Edwin VanCleef", 1, 5, 1)
    b = last()
    check(b["t"] == "BOSS" and "kill count of 1" in b["msg"], "boss kill with kill count")
    check(b["title"] == "Boss kills", "boss kill is titled as a kill, not a wipe")
    check(any(f[0] == "Fight time" and f[1].startswith("0:3") for f in b.get("fields", [])), "boss fight time")
    n_before = len(outbox(lua))
    fire("ENCOUNTER_END", 1001, "Edwin VanCleef", 1, 5, 0)
    check(len(outbox(lua)) == n_before, "wipes are off by default")

    fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 150.")
    check(last()["t"] == "SKILL" and "150 Mining" in last()["msg"], "profession milestone")
    n_before = len(outbox(lua))
    fire("CHAT_MSG_SKILL", "Your skill in Mining has increased to 151.")
    check(len(outbox(lua)) == n_before, "non-milestone skill-up ignored")

    T.factions = lua.eval('{ { name = "Stormwind", standing = 5, id = 72 } }')
    fire("PLAYER_ENTERING_WORLD")
    T.Run(4)
    T.factions[1].standing = 6
    fire("UPDATE_FACTION")
    check(last()["t"] == "REP" and "Honored with Stormwind" in last()["msg"], "reputation standing")

    T.money = 1200000  # 120g
    fire("PLAYER_MONEY")
    check(last()["t"] == "GOLD" and "100 gold" in last()["msg"], "gold milestone")

    fire("PLAYER_DEAD")
    check(last()["t"] == "DEATH" and "Stranglethorn" in last()["msg"], "death")

    db.notifiers.AUCTION.enabled = True
    fire("CHAT_MSG_SYSTEM", "A buyer has been found for your auction of Black Lotus.")
    check(last()["t"] == "AUCTION" and "Black Lotus" in last()["msg"], "auction sold")

    db.notifiers.CHAT.enabled = True
    db.notifiers.CHAT.patterns = "*grats*\nhello there"
    fire("CHAT_MSG_GUILD", "big grats on 60!", "Jaina-Forever")
    check(last()["t"] == "CHAT" and "Jaina: big grats" in last()["msg"], "chat pattern match")

    db.notifiers.PVP.enabled = True
    fire("CHAT_MSG_SYSTEM", "Thrall has defeated Garrosh in a duel")
    check(last()["t"] == "PVP" and "Garrosh" in last()["msg"], "duel win")

    db.notifiers.LEVEL.template = "DING %PLAYER% -> %LEVEL% in %ZONE%"
    fire("PLAYER_LEVEL_UP", 44)
    check(last()["msg"] == "DING Thrall Stormrider -> 44 in Stranglethorn Vale", "custom message template")
    db.notifiers.LEVEL.enabled = False
    n_before = len(outbox(lua))
    fire("PLAYER_LEVEL_UP", 45)
    check(len(outbox(lua)) == n_before, "disabled alert is not sent")

    sent = outbox(lua)[start:]
    check(all(isinstance(x["id"], str) and x["p"] == "Thrall Stormrider" for x in sent), "every alert has an id and the full Forever name")
    check(len({x["id"] for x in outbox(lua)}) == len(outbox(lua)), "alert ids are unique")

    print("Screenshots and data codes")
    T.Run(90)  # let the capture queue drain (each alert needs about 2 seconds)
    shots = [T.shots[i] for i in range(1, len(T.shots) + 1)]
    data_shots = [s for s in shots if s.cells]
    clean_shots = [s for s in shots if not s.cells]
    check(len(data_shots) >= len(sent), f"one data screenshot per alert ({len(data_shots)} for {len(sent)})")
    check(len(clean_shots) > 0, "normal screenshots taken for alerts that want one")
    check(all(s.quality == "10" for s in data_shots), "data screenshots use best quality")
    secs = [s.sec for s in shots]
    check(len(secs) == len(set(secs)), "every screenshot is taken in a different second (no overwriting)")
    check(sum(1 for i in range(len(shots) - 1) if not shots[i].cells and shots[i + 1].cells) == len(clean_shots),
          "each normal screenshot is followed by its data screenshot")
    check(T.cvars.screenshotQuality == "3", "screenshot quality put back afterwards")

    # Test button pressed with the window open: the window must not be in the picture.
    ui.Show(ui, "discord")
    first = len(T.shots)
    ns.SendTest()
    T.Run(6)
    new = [T.shots[i] for i in range(first + 1, len(T.shots) + 1)]
    clean_new = [s for s in new if not s.cells]
    check(clean_new and all(s.windowAlpha == 0 for s in clean_new), "Dink window hidden in the screenshot")
    check(lua.globals().DinkForDiscordFrame._alpha == 1 and lua.globals().DinkForDiscordFrame._shown, "Dink window comes back afterwards")

    tmp = tempfile.mkdtemp(prefix="dinktest_")
    try:
        py_shots = [lua_shot_to_py(s) for s in data_shots]
        # Decode under several JPEG qualities / resolutions.
        ok_counts = {}
        for label, size, quality in [("1080p png", (1920, 1080), None), ("1080p jpeg 95", (1920, 1080), 95),
                                     ("1080p jpeg 75", (1920, 1080), 75), ("1080p jpeg 50", (1920, 1080), 50)]:
            good = 0
            for i, s in enumerate(py_shots):
                img = render_shot(s, size, BACKGROUND)
                path = os.path.join(tmp, f"q_{i}.{'png' if quality is None else 'jpg'}")
                if quality is None:
                    img.save(path)
                else:
                    img.save(path, quality=quality, subsampling=2)
                out = decode(path)
                if out and json.loads(out)["id"] == json.loads(out)["id"]:
                    good += 1
            ok_counts[label] = good
            check(good == len(py_shots), f"decode {label}: {good}/{len(py_shots)}")

        # Higher resolutions: re-run the addon's drawing at 1440p and 4K.
        for (w, h) in [(2560, 1440), (3840, 2160)]:
            T.screenW, T.screenH = w, h
            ns.SendTest()
            T.Run(6)
            s = lua_shot_to_py([x for x in [T.shots[i] for i in range(1, len(T.shots) + 1)] if x.cells][-1])
            path = os.path.join(tmp, f"res_{h}.jpg")
            render_shot(s, (w, h), BACKGROUND).save(path, quality=75, subsampling=2)
            out = decode(path)
            check(out is not None and json.loads(out)["t"] == "TEST", f"decode at {w}x{h}")
        T.screenW, T.screenH = 1920, 1080

        # A normal screenshot must not decode.
        plain = os.path.join(tmp, "plain.jpg")
        Image.open(BACKGROUND).convert("RGB").resize((1920, 1080)).save(plain, quality=90)
        check(decode(plain) is None, "normal screenshot is ignored")

        # Compact style: the setting tags each alert so the helper builds the short card.
        db.general.compact = True
        ns.SendTest()
        T.Run(6)
        db.general.compact = False
        last = outbox(lua)[-1]
        check(last.get("sty") == "c", "compact setting tags the alert")
        ns.SendTest()
        T.Run(6)
        check("sty" not in outbox(lua)[-1], "normal style leaves alerts untagged")

        print("Helper end to end")
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), FakeDiscord)
        port = server.server_address[1]
        threading.Thread(target=server.serve_forever, daemon=True).start()
        hook = f"http://127.0.0.1:{port}/api/webhooks/1/abc"
        hook_loot = f"http://127.0.0.1:{port}/api/webhooks/2/loot"
        db.webhooks[1] = hook
        db.webhooks[2] = "https://example.com/evil"
        db.notifiers.LOOT.webhook = hook_loot

        wow = os.path.join(tmp, "World of Warcraft", "_forever_")
        sv_dir = os.path.join(wow, "WTF", "Account", "TESTACCOUNT", "SavedVariables")
        ss_dir = os.path.join(wow, "Screenshots")
        os.makedirs(sv_dir)
        os.makedirs(ss_dir)

        # Live screenshots for the first 3 alerts (clean + data each); the rest only in saved data.
        box = outbox(lua)
        live = box[-3:]
        import time as _time
        t0 = int(_time.time()) - 600
        for i, alert in enumerate(live):
            alert = dict(alert, img=1)
            if i == 2:
                alert["sty"] = "c"   # one live alert in compact style
            # Re-encode this exact alert with the addon's own encoder.
            T.payloadJson = json.dumps(alert, separators=(",", ":"))
            ns.Strip.Show(T.payloadJson)
            T.cvars.screenshotQuality = "10"
            lua.globals().Screenshot()
            T.pendingShot = False
            s = lua_shot_to_py([x for x in [T.shots[j] for j in range(1, len(T.shots) + 1)] if x.cells][-1])
            ns.Strip.Hide()
            clean = os.path.join(ss_dir, f"WoWScrnShot_111026_1200{i}0.jpg")
            data = os.path.join(ss_dir, f"WoWScrnShot_111026_1200{i}1.jpg")
            Image.open(BACKGROUND).convert("RGB").resize((1920, 1080)).save(clean, quality=85)
            render_shot(s, (1920, 1080), BACKGROUND).save(data, quality=75, subsampling=2)
            os.utime(clean, (t0 + i * 10, t0 + i * 10))
            os.utime(data, (t0 + i * 10 + 0.3, t0 + i * 10 + 0.3))
        user_shot = os.path.join(ss_dir, "WoWScrnShot_111026_110000.jpg")
        Image.open(BACKGROUND).convert("RGB").save(user_shot, quality=85)
        os.utime(user_shot, (t0 - 3600, t0 - 3600))

        # Fix the timestamps so the saved alerts count as recent.
        now = int(_time.time())
        for i in range(1, len(db.outbox) + 1):
            a = json.loads(db.outbox[i])
            a["ts"] = now - 60
            db.outbox[i] = json.dumps(a, separators=(",", ":"))
        # Live alerts carry the same ids, so keep them in sync.
        writer = lua.eval(SV_WRITER)
        with open(os.path.join(sv_dir, "DinkForDiscord.lua"), "w", encoding="utf-8", newline="\n") as f:
            f.write(writer("DinkForDiscordDB", db))

        env = dict(os.environ, DINK_TEST_ALLOW_LOCALHOST="1", DINK_STATE_DIR=os.path.join(tmp, "state"))
        r = subprocess.run([HELPER, "--once", os.path.dirname(wow)], capture_output=True, text=True, env=env, timeout=120)
        print("    helper said:\n      " + "\n      ".join(r.stdout.strip().splitlines()))
        posts = FakeDiscord.posts
        total = len(outbox(lua))
        check(len(posts) == total, f"every saved alert posted once ({len(posts)} posts for {total} alerts)")
        with_img = [p for p in posts if p["image"]]
        check(len(with_img) == 3, f"live alerts posted with their screenshot ({len(with_img)})")
        check(all(p["image"][:2] == b"\xff\xd8" for p in with_img), "screenshot uploaded as JPEG")
        def shown(p):
            e = p["payload"]["embeds"][0]
            return (e.get("image") or e.get("thumbnail") or {}).get("url")
        check(all(shown(p) == "attachment://screenshot.jpg" for p in with_img), "embed shows the attached screenshot")
        compact = [p["payload"]["embeds"][0] for p in posts if "footer" not in p["payload"]["embeds"][0]]
        check(len(compact) == 2, f"compact alerts posted as short cards ({len(compact)})")
        thumb = [c for c in compact if "thumbnail" in c]
        check(len(thumb) == 2 and not any("image" in c or "author" in c for c in thumb), "compact card uses a small thumbnail")
        check(any(c["title"].startswith("🔔 Thrall Stormrider is ready") for c in compact),
              "compact title is the emoji and message")
        check(all("Level " in c.get("description", "") and "Paladin" in c.get("description", "") for c in compact),
              "compact line shows level and class")
        loot_posts = [p for p in posts if p["payload"]["embeds"][0]["title"] in ("Loot", "Shiny Epic Helm", "Thunderfury, Blessed Blade of the Windseeker")]
        check(loot_posts and all(p["path"].startswith("/api/webhooks/2/loot") for p in loot_posts), "loot uses its own webhook override")
        check(not any("example.com" in p["path"] for p in posts), "non-Discord webhook never used")
        e = posts[0]["payload"]["embeds"][0]
        check(e["author"]["name"].startswith("Thrall Stormrider") and "Paladin" in e["author"]["name"], "embed author shows full name, level and class")
        check("WoW Forever" in e["footer"]["text"], "embed footer")
        left = sorted(os.listdir(ss_dir))
        check(len(left) == 4, f"data screenshots deleted, normal ones kept ({len(left)} files left)")
        check(os.path.exists(user_shot), "player's own screenshot untouched")

        FakeDiscord.posts = []
        subprocess.run([HELPER, "--once", os.path.dirname(wow)], capture_output=True, text=True, env=env, timeout=120)
        check(len(FakeDiscord.posts) == 0, "second run posts nothing again (no duplicates)")
        server.shutdown()
    finally:
        shutil.rmtree(tmp, ignore_errors=True)

    errs = [str(m) for m in T.chat.values() if "error in" in str(m)]
    check(not errs, "no errors inside event handlers" + (": " + " | ".join(errs[:3]) if errs else ""))

    print()
    if failures:
        print(f"{len(failures)} FAILED:")
        for f in failures:
            print("  - " + f)
        sys.exit(1)
    print("All tests passed.")


if __name__ == "__main__":
    main()
