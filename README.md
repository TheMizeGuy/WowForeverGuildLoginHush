# WoW Forever Guild Login Hush

Quiets guild logins in the World of Warcraft: Forever client (build 1.60.x, interface 16001).
Three settings, each on its own:

- hide the "`[Name] has come online.`" chat line about guild members;
- hide the "`Name has gone offline.`" chat line about guild members;
- mute the sound the game plays when someone comes online.

All three are on by default. `/glh`, the addons button by the minimap, and Esc > Options >
AddOns > Guild Login Hush open the settings page. Settings are saved per account.

The game's own Guild Member Alert setting (Esc > Options > Social) turns both lines off together;
this addon is for choosing one line, the other, or the sound separately.

## Commands

| Command | Effect |
|---|---|
| `/glh` | Open the settings |
| `/glh online [on\|off]` | Hide (or show) "has come online" lines about guild members |
| `/glh offline [on\|off]` | Hide (or show) "has gone offline" lines about guild members |
| `/glh sound [on\|off]` | Mute (or unmute) the login sound |
| `/glh status` | Show the current settings |

Without `on` or `off`, the command flips the setting.

## How it works

The client prints both lines as system messages built from the same two format strings for
character friends and guild members (`ERR_FRIEND_ONLINE_SS`, `ERR_FRIEND_OFFLINE_S`), so the
addon reads the name out of the line, using the client's own format strings so other languages
work, and asks the guild roster whether it belongs to a guild member
(`C_GuildInfo.MemberExistsByName`). Only friends and guild members produce these lines, so a name
the roster does not list is still a guild member's when it is not on the friends list; that
covers someone who joined the guild after the roster was read. After login, a name the roster
does not know is left visible until the friends list has arrived, or for 15 seconds at most;
the list normally arrives within a second. Lines about friends who are not in your guild are left
alone, and nothing is hidden while you are not in a guild.

The login sound is played by the game client itself, not by any interface code, so the addon
mutes its sound file (`MuteSoundFile`): sound kit 3332 "FriendJoinGame", file 567518 on the
1.60.1 client. It is one sound for guild members and character friends coming online, so with
the mute on, friends' logins are silent too; logging out plays none. Battle.net friends' online
and offline toasts play their own sound, which this addon leaves alone (Esc > Options > Social >
Online Friends and Offline Friends turn those toasts off). A mute lasts until the client is
closed, so the addon mutes once at every login, unmutes when the interface unloads (logout,
relog and `/reload`) and only ever unmutes a sound it muted itself, so disabling the addon brings
the sound back.

## Limits

- The friend and guild lines are the same text, so a friend who is also in your guild is treated
  as a guild member and hidden.
- Muting the sound mutes it for character friends' logins too; there is no separate guild sound.
- With text to speech on for system messages, the game reads these lines aloud before any addon
  sees them, so hidden lines are still spoken unless System messages are turned off in the
  text-to-speech options.
- When the client is in its chat security lockdown, system lines do not reach addon filters at
  all, so lines in that window cannot be hidden.

## Install

Get the zip from the [GitHub releases](https://github.com/TheMizeGuy/WowForeverGuildLoginHush/releases)
or from CurseForge, and copy the `GuildLoginHush` folder into the Forever client's AddOns directory:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GuildLoginHush
```

A brand-new addon is picked up at the character selection screen, not by `/reload`: log out to
character select and back in. After editing the `.toc` file, restart the client.

`scripts/deploy.sh [ssh-host] [addons-dir]` streams the folder to a Windows machine over ssh and
checks the file count. `addons-dir` is the AddOns directory itself and defaults to
`C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns`; `ssh-host` defaults to the
author's machine, so pass both when deploying to your own.

## Checks

`bash tests/run.sh` checks Lua syntax (`luajit -bl`, plus a grep for `goto` and labels, which
LuaJIT accepts and the client's Lua 5.1 does not), that the TOC lists every Lua file, that every
global, `C_` function, `Settings` and `ChatFrameUtil` field, event and frame method the addon
uses exists in the Forever 1.60.1 (70790) client (`tests/audit_globals.py`, against the client's
UI source, API documentation and global strings; `python3 tests/audit_globals.py --fetch`
downloads those into `.cache/` once, and until then the script ends with
`ALL PASSED (API audit skipped)`), then runs `tests/test_addon.lua`, which loads the addon under
a fake client (`tests/wow.lua`) and drives system lines, the roster, the friends list, the sound
mute across reloads and logouts, the settings page and the slash commands. The script must end
with `ALL PASSED`. Only the game itself can confirm that the sound file is the one the live
client plays and that the settings page lays out as expected.

## Release

Bump `## Version` in the `.toc`, then build the zip with the addon folder at its root:

```
mkdir -p dist && zip -r -X dist/GuildLoginHush-<version>.zip GuildLoginHush -x '*.DS_Store' -x '*/._*'
```
