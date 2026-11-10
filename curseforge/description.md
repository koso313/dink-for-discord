# Dink For Discord

**Post your World of Warcraft: Forever moments to Discord, with screenshots.** Deaths, level ups, epic loot, boss kills, quests, professions, reputation and more, posted to your guild or friends' channel as they happen.

Inspired by the Dink plugin for RuneLite (Old School RuneScape). Not affiliated with the Dink project or with Blizzard.

## What it posts

| Alert | When |
|---|---|
| Death | You die (Hardcore deaths are marked) |
| Level up | You level up, with "every N levels" and "always at 60" options |
| Loot | Items at or above a quality, or worth at least X gold. Allow and block lists. Items from one kill come as one post. Uses Auctionator prices if installed |
| Quests | You turn in a quest |
| Boss kills | Dungeon and raid bosses, with your kill count and fight time |
| Professions | Skill milestones (every 25 points by default) |
| Reputation | You reach Honored, Revered or Exalted |
| Collections | New mounts, companions, toys (and appearances, if you want) |
| Legacy | Legacy completions (experimental) |
| Gold | Gold milestones (100g, 1000g, ...) |
| PvP | Honorable kills and duel wins (off by default) |
| Trades | Completed trades (off by default) |
| Auction House | Auctions sold or won (off by default) |
| Chat | Chat messages matching your patterns (off by default) |

Every alert can have its own screenshot setting, message template (`%PLAYER% has reached level %LEVEL%!`) and its own webhook.

## Setup (2 minutes)

1. **Install the addon** (this page) and the free **Dink For Discord Helper** for Windows (link below).
2. In Discord: **Server Settings > Integrations > Webhooks > New Webhook**, pick a channel, **Copy Webhook URL**.
3. In game, type **/dink**, paste the URL, click **Save & Reload**.
4. Start the helper (a bell appears in your system tray) and click **Send test alert** in game.

## Why a helper app?

WoW addons can't connect to the internet, so nothing inside the game can post to Discord by itself. The helper is a small Windows app (about 125 KB, no install) that sits in your tray and does the posting.

How the alert gets from the game to the helper: for each alert the addon takes one extra screenshot with a tiny data code in the top-left corner (visible for a split second). The helper reads that screenshot, posts the alert with your normal screenshot attached, and deletes the data screenshot. If the helper isn't running, alerts are also saved and posted the next time you /reload, log out or quit (within 24 hours).

The helper does **not** read game memory, inject anything, send key presses or touch the game in any way. It only reads your Screenshots folder and the addon's saved settings file, and it only posts to discord.com webhooks.

## Commands

- `/dink` open settings
- `/dink test` send a test alert
- `/dink history` recent alerts

## Download the helper

**[Download DinkHelper.exe (GitHub releases)](https://github.com/koso313/dink-for-discord/releases/latest)**

Unzip it anywhere and double-click. Windows may say "Windows protected your PC" because the app isn't signed: click **More info > Run anyway**. Source code: [github.com/koso313/dink-for-discord](https://github.com/koso313/dink-for-discord)
