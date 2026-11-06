Quiets guild logins in World of Warcraft: Forever. Three settings, each on its own switch:

- **Hide "has come online"** chat lines about guild members.
- **Hide "has gone offline"** chat lines about guild members.
- **Mute the login sound**, the chime the game plays when someone comes online.

All three are on by default. `/glh`, the addons button by the minimap, or Esc > Options > AddOns > Guild Login Hush opens the settings page. Settings are saved per account.

## Commands

- `/glh` opens the settings.
- `/glh online on|off` hides or shows "has come online" lines about guild members.
- `/glh offline on|off` hides or shows "has gone offline" lines about guild members.
- `/glh sound on|off` mutes or unmutes the login sound.
- `/glh status` shows the current settings.

Without `on` or `off`, a command flips its setting.

## What it touches, and what it leaves alone

- Lines about friends who are not in your guild stay. A friend who is also a guildmate counts as a guildmate.
- Nothing is hidden while you are not in a guild.
- The login chime is one sound for guild members and character friends, so muting it silences friends' logins too. Logging out plays no sound. Battle.net friends' toasts have their own sound and their own switches under Options > Social.
- The game's own Guild Member Alert setting (Options > Social) turns both lines off together; this addon is for choosing one line, the other, or just the sound.
- With text to speech on for system messages, the game reads these lines aloud before any addon sees them.

## Install

Copy the `GuildLoginHush` folder into `World of Warcraft\_forever_\Interface\AddOns`. A new addon is picked up at the character selection screen, not by `/reload`.

Source and issues: https://github.com/TheMizeGuy/WowForeverGuildLoginHush
