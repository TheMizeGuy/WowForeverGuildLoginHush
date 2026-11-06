# WoW Forever Guild Login Mute

Quiets guild logins in the World of Warcraft: Forever client (build 1.60.x, interface 16001).
Three settings, each on its own:

- hide the "`[Name] has come online.`" chat line about guild members;
- hide the "`Name has gone offline.`" chat line about guild members;
- mute the sound the game plays when someone comes online.

All three are on by default. `/glm`, the addons button by the minimap, and Esc > Options >
AddOns > Guild Login Mute open the settings page. Settings are saved per account.

## Commands

| Command | Effect |
|---|---|
| `/glm` | Open the settings |
| `/glm online [on\|off]` | Hide (or show) "has come online" lines about guild members |
| `/glm offline [on\|off]` | Hide (or show) "has gone offline" lines about guild members |
| `/glm sound [on\|off]` | Mute (or unmute) the login sound |
| `/glm status` | Show the current settings |

Without `on` or `off`, the command flips the setting.

## How it works

The client prints both lines as system messages built from the same two format strings for
friends and guild members (`ERR_FRIEND_ONLINE_SS`, `ERR_FRIEND_OFFLINE_S`), so the addon reads
the name out of the line, using the client's own format strings so other languages work, and
asks the guild roster whether it belongs to a guild member (`C_GuildInfo.MemberExistsByName`).
Only friends and guild members produce these lines, so a name the roster does not list is still a
guild member's when it is not on the friends list; that covers someone who joined the guild after
the roster was read. Until the friends list has arrived after login, a name the roster does not
know is left visible rather than hidden. Lines about friends who are not in your guild are never
touched, and nothing is hidden while you are not in a guild.

The login sound is played by the game client itself, not by any interface code, so the addon
mutes its sound file (`MuteSoundFile`): sound kit 3332 "FriendJoinGame", file 567518 on the
1.60.1 client. It is one sound for friends and guild members alike, so with the mute on, friends'
logins are silent too. Logging out plays no sound. A mute lasts until the client is closed, so
the addon applies it again at every login, and it only unmutes a sound it muted itself.

## Limits

- The friend and guild lines are the same text, so a friend who is also in your guild is treated
  as a guild member and hidden.
- Muting the sound mutes it for friends' logins too; there is no separate guild sound.
- When the client is in its chat security lockdown, system lines do not reach addon filters at
  all, so lines in that window cannot be hidden.

## Install

Copy the `GuildLoginMute` folder into the Forever client's AddOns directory:

```
C:\Program Files (x86)\World of Warcraft\_forever_\Interface\AddOns\GuildLoginMute
```

A brand-new addon is picked up at the character selection screen, not by `/reload`: log out to
character select and back in. After editing the `.toc` file, restart the client.

`scripts/deploy.sh [ssh-host] [addons-dir]` streams the folder to a Windows machine over ssh and
checks the file count. `addons-dir` defaults to the path above and `ssh-host` to the author's
machine, so pass both when deploying to your own.

## Checks

`bash tests/run.sh` checks Lua syntax (`luajit -bl`), that the TOC lists every Lua file, that
every global, `C_` function, event and frame method the addon uses exists in the Forever 1.60.1
(70790) client (`tests/audit_globals.py`, against the client's UI source, API documentation and
global strings; `python3 tests/audit_globals.py --fetch` downloads those into `.cache/` once),
then runs `tests/test_addon.lua`, which loads the addon under a fake client (`tests/wow.lua`) and
drives system lines, the roster, the friends list, the sound mute, the settings page and the
slash commands. The script must end with `ALL PASSED`. Only the game itself can confirm that the
sound file is the one the live client plays and that the settings page lays out as expected.

## Release

Bump `## Version` in the `.toc`, then build the zip with the addon folder at its root:

```
zip -r -X dist/GuildLoginMute-<version>.zip GuildLoginMute -x '*.DS_Store' -x '*/._*'
```
