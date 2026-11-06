-- The whole addon under the fake client in tests/wow.lua: which lines are hidden for whom, the
-- friends-list and roster timing, the sound mute across reloads, the settings page and the slash
-- commands.

local T = dofile("tests/t.lua")
local wow = dofile("tests/wow.lua")

local SOUND = 567518

local function Slash(text)
    SlashCmdList.GUILDLOGINHUSH(text)
end

-- Each scenario starts from a freshly started client.
local test = T.test
T.test = function(name, fn)
    test(name, function()
        wow.Restart()
        fn()
    end)
end

T.test("defaults hide a guild member's online and offline lines and mute the sound", function()
    local ns = wow.Load()
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false, "online line hidden")
    T.eq(wow.Offline("Zeus"), false, "offline line hidden")
    T.same(ns.db, { hideOnline = true, hideOffline = true, muteSound = true })
    T.same(wow.soundCalls, { "mute " .. SOUND })
    T.eq(wow.MuteCount(SOUND), 1)
    T.eq(wow.rosterRequests, 1, "the roster is requested at login")
    T.eq(wow.friendRequests, 1, "and so is the friends list")
end)

T.test("a friend who is not in the guild keeps both lines", function()
    wow.Load()
    wow.roster.Zeus = true
    wow.friends.Hera = true
    T.eq(wow.Online("Hera"), true)
    T.eq(wow.Offline("Hera"), true)
    T.eq(wow.Online("Zeus"), false, "the guild member is still hidden")
end)

T.test("a friend who is also a guild member is hidden", function()
    wow.Load()
    wow.roster.Zeus = true
    wow.friends.Zeus = true
    T.eq(wow.Online("Zeus"), false)
    T.eq(wow.Offline("Zeus"), false)
end)

T.test("out of a guild nothing is hidden and no roster is requested", function()
    wow.Load({ setup = function() wow.inGuild = false end })
    T.eq(wow.Online("Zeus"), true)
    T.eq(wow.Offline("Zeus"), true)
    T.eq(wow.rosterRequests, 0)
    Slash("status")
    T.ok(wow.Printed("not in a guild"))
end)

T.test("a name the roster does not list is a guild member once the friends list is known", function()
    wow.Load()
    T.eq(wow.Online("Newbie"), false, "not a friend, so a guild member who joined after the roster was read")
    T.eq(wow.Offline("Newbie"), false)
end)

T.test("before the friends list arrives, unknown names stay visible and roster hits are hidden", function()
    wow.Load({ friends = false })
    wow.roster.Zeus = true
    T.eq(wow.Online("Hera"), true, "could be a friend: shown")
    T.eq(wow.Offline("Hera"), true)
    T.eq(wow.Online("Zeus"), false, "in the roster: hidden")
    Slash("status")
    T.ok(wow.Printed("Waiting for the friends list"))
    wow.Fire("FRIENDLIST_UPDATE")
    T.eq(wow.Online("Hera"), false, "now known not to be a friend")
end)

T.test("the wait for the friends list ends on its own", function()
    wow.Load({ friends = false })
    T.eq(wow.Online("Hera"), true)
    wow.Advance(14)
    T.eq(wow.Online("Hera"), true)
    wow.Advance(1)
    T.eq(wow.Online("Hera"), false)
end)

T.test("a client without character friends needs no friends list", function()
    wow.Load({ friends = false, setup = function() wow.legacyFriends = false end })
    T.eq(wow.friendRequests, 0)
    T.eq(wow.Online("Hera"), false, "every line is a guild member's")
end)

T.test("no answer about the friend system is not 'no friends': the list is still requested and waited for", function()
    wow.Load({ friends = false, setup = function() wow.legacyFriends = nil end })
    T.eq(wow.friendRequests, 1)
    wow.friends.Hera = true
    T.eq(wow.Online("Hera"), true, "shown while the list may still be on its way")
    wow.Fire("FRIENDLIST_UPDATE")
    T.eq(wow.Online("Hera"), true, "a friend")
    T.eq(wow.Online("Zeus"), false, "not a friend")
end)

T.test("names with the player's own realm match the roster and the friends list in either form", function()
    wow.Load()
    wow.roster["Zeus-Forever"] = true
    T.eq(wow.Online("Zeus-Forever", "Zeus"), false, "full name in the roster")
    T.eq(wow.Offline("Zeus-Forever"), false)
    wow.roster = { Ares = true }
    T.eq(wow.Online("Ares-Forever", "Ares"), false, "short name in the roster")
    wow.roster = {}
    wow.friends = { Apollo = true }
    T.eq(wow.Offline("Apollo-Forever"), true, "a friend listed without the realm stays")
end)

T.test("a name from another realm is never shortened: a cross-realm friend who shares a guildmate's name stays", function()
    local ns = wow.Load()
    wow.roster.Zeus = true
    wow.friends["Zeus-Otherrealm"] = true
    T.same(ns.Names("Zeus-Otherrealm"), { "Zeus-Otherrealm" })
    T.same(ns.Names("Zeus-Forever"), { "Zeus-Forever", "Zeus" })
    T.eq(wow.Online("Zeus-Otherrealm", "Zeus"), true)
    T.eq(wow.Offline("Zeus-Otherrealm"), true)
    T.eq(wow.Online("Zeus"), false, "the guildmate of that name is still hidden")
    wow.friends = {}
    wow.roster = { ["Hera-Otherrealm"] = true }
    T.eq(wow.Online("Hera-Otherrealm", "Hera"), false, "a cross-realm guild member is found under the full name")
end)

T.test("the realm name is read once the client knows it", function()
    wow.Load({ setup = function() GetNormalizedRealmName = function() return nil end end })
    wow.roster.Zeus = true
    wow.friends["Zeus-Forever"] = true
    T.eq(wow.Online("Zeus-Forever", "Zeus"), true, "no realm known yet: the full name is a friend, not shortened")
    GetNormalizedRealmName = function() return "Forever" end
    wow.friends = {}
    T.eq(wow.Online("Zeus-Forever", "Zeus"), false)
end)

T.test("each line type has its own switch", function()
    local ns = wow.Load()
    wow.roster.Zeus = true
    ns.SetOption("hideOnline", false)
    T.eq(wow.Online("Zeus"), true)
    T.eq(wow.Offline("Zeus"), false)
    ns.SetOption("hideOnline", true)
    ns.SetOption("hideOffline", false)
    T.eq(wow.Online("Zeus"), false)
    T.eq(wow.Offline("Zeus"), true)
    ns.SetOption("hideOffline", true)
    T.eq(wow.Offline("Zeus"), false)
end)

T.test("with both line switches off the filter is gone, and it comes back exactly once", function()
    local ns = wow.Load()
    T.eq(#wow.filters.CHAT_MSG_SYSTEM, 1)
    ns.SetOption("hideOnline", false)
    T.eq(#wow.filters.CHAT_MSG_SYSTEM, 1, "offline still hidden")
    ns.SetOption("hideOffline", false)
    T.eq(#wow.filters.CHAT_MSG_SYSTEM, 0)
    ns.SetOption("hideOnline", true)
    ns.SetOption("hideOffline", true)
    T.eq(#wow.filters.CHAT_MSG_SYSTEM, 1)
end)

T.test("the sound follows its switch and is only unmuted when this addon muted it", function()
    local ns = wow.Load({ setup = function() GuildLoginHushDB = { muteSound = false } end })
    T.same(wow.soundCalls, {}, "nothing muted or unmuted at load when the switch is off")
    ns.SetOption("muteSound", true)
    T.same(wow.soundCalls, { "mute " .. SOUND })
    T.eq(wow.MuteCount(SOUND), 1)
    ns.SetOption("muteSound", false)
    T.same(wow.soundCalls, { "mute " .. SOUND, "unmute " .. SOUND })
    T.eq(wow.MuteCount(SOUND), 0)
    ns.SetOption("muteSound", false)
    T.eq(#wow.soundCalls, 2, "turning it off twice unmutes once")
end)

T.test("turning the sound on while it is on mutes once, so off still unmutes", function()
    local ns = wow.Load()
    ns.SetOption("muteSound", true)
    wow.settings[3]:SetValueToDefault() -- the Defaults button notifies again with the same value
    T.same(wow.soundCalls, { "mute " .. SOUND })
    ns.SetOption("muteSound", false)
    T.eq(wow.MuteCount(SOUND), 0)
end)

T.test("a /reload re-applies the mute without stacking it, and off after a reload unmutes", function()
    wow.Load()
    T.eq(wow.MuteCount(SOUND), 1)
    wow.Reload()
    T.eq(wow.MuteCount(SOUND), 1, "the logout unmute and the load mute balance")
    T.same(wow.soundCalls, { "mute " .. SOUND }, "one mute per load")
    wow.Reload()
    Slash("sound off")
    T.eq(wow.MuteCount(SOUND), 0)
    wow.Reload()
    T.eq(wow.MuteCount(SOUND), 0, "the switch is remembered: nothing muted")
    T.same(wow.soundCalls, {})
end)

T.test("logging out, or disabling the addon and reloading, gives the sound back", function()
    wow.Load()
    T.eq(wow.MuteCount(SOUND), 1)
    wow.Logout()
    T.eq(wow.MuteCount(SOUND), 0, "the addon's mute is undone when the UI unloads")
    wow.Logout()
    T.eq(wow.MuteCount(SOUND), 0, "and only once")
end)

T.test("a fresh client start mutes again from the saved setting", function()
    wow.Load()
    wow.Logout()
    wow.Restart()
    wow.Load({ keepDB = true })
    T.eq(wow.MuteCount(SOUND), 1)
end)

T.test("a saved mute is applied again at every load", function()
    wow.Load({ setup = function() GuildLoginHushDB = { muteSound = true, hideOnline = false, hideOffline = false } end })
    T.same(wow.soundCalls, { "mute " .. SOUND })
    T.eq(wow.filters.CHAT_MSG_SYSTEM, nil, "no filter while both line switches are off")
end)

T.test("a client without MuteSoundFile loads, hides lines and says why the sound stays", function()
    wow.Load({ setup = function() wow.hasMuteApi = false end })
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false)
    Slash("status")
    T.ok(wow.Printed("no MuteSoundFile"))
    wow.Logout()
end)

T.test("saved settings of the wrong type fall back to the defaults", function()
    local ns = wow.Load({ setup = function() GuildLoginHushDB = { hideOnline = "yes", hideOffline = false, muteSound = 1, extra = 5 } end })
    T.eq(ns.db.hideOnline, true)
    T.eq(ns.db.hideOffline, false)
    T.eq(ns.db.muteSound, true)
    T.eq(GuildLoginHushDB, ns.db, "the saved table is the live one")
    T.eq(ns.db.extra, 5, "unknown keys are left alone")
end)

T.test("other system lines are never touched", function()
    wow.Load()
    wow.roster.Zeus = true
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h has invited you to join a group."), true)
    T.eq(wow.System("Zeus has gone offline. Really."), true, "anchored at the end")
    T.eq(wow.System("Guild: Zeus has gone offline."), true, "not a character name in front")
    T.eq(wow.System("That arena team has gone offline."), true, "ERR_ARENA_TEAM_NOT_FOUND fits the format but names nobody")
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h has come online"), true, "the period is part of the line")
    T.eq(wow.System("You are not in a guild."), true)
end)

T.test("only character names count, accented letters and realms included", function()
    local ns = wow.Load()
    T.eq(ns.LooksLikeName("Zeus"), true)
    T.eq(ns.LooksLikeName("Zeus-Forever"), true)
    T.eq(ns.LooksLikeName("Zeus-Area-52"), true)
    T.eq(ns.LooksLikeName("Zeus-Mal'Ganis"), true)
    T.eq(ns.LooksLikeName("Åsgård"), true)
    T.eq(ns.LooksLikeName("That arena team"), false)
    T.eq(ns.LooksLikeName("Zeus2"), false)
    T.eq(ns.LooksLikeName("Guild: Zeus"), false)
    T.eq(ns.LooksLikeName(""), false)
    T.eq(ns.LooksLikeName("-Forever"), false)
    T.eq(ns.LooksLikeName("Zeus-Argent Dawn"), false)
    T.same(ns.Names("Zeus"), { "Zeus" })
    T.eq(ns.Names("Guild: Zeus"), nil)
    T.eq(wow.System("Åsgård has gone offline."), false, "an accented guild member is hidden")
end)

T.test("secret or non-string text is left alone without errors", function()
    wow.Load()
    T.eq(wow.System(wow.SECRET), true)
    T.eq(wow.System(nil), true)
    T.eq(wow.System(42), true)
end)

T.test("a localized format string works the same way", function()
    wow.Load({
        setup = function()
            ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h ist jetzt online."
            ERR_FRIEND_OFFLINE_S = "%s ist jetzt offline."
        end,
    })
    wow.roster.Zeus = true
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h ist jetzt online."), false)
    T.eq(wow.System("Zeus ist jetzt offline."), false)
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h has come online."), true, "the English line is not this client's")
end)

T.test("positional format specifiers and pattern characters in a format are handled", function()
    local ns = wow.Load({
        setup = function()
            ERR_FRIEND_ONLINE_SS = "|Hplayer:%1$s|h[%2$s]|h (online) +1."
        end,
    })
    wow.roster.Zeus = true
    T.eq(ns.Pattern("%s has (left) [%s]?"), "^(.-) has %(left%) %[(.-)%]%?$")
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h (online) +1."), false)
    T.eq(wow.System("|Hplayer:Zeus|h[Zeus]|h xonlinex +1."), true)
end)

T.test("a missing format string disables that line type only", function()
    wow.Load({ setup = function() ERR_FRIEND_OFFLINE_S = nil end })
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false)
    T.eq(wow.System("Zeus has gone offline."), true)
end)

T.test("the settings page registers three checkboxes that write the saved table", function()
    local ns = wow.Load()
    T.eq(#wow.settings, 3)
    T.eq(#wow.checkboxes, 3)
    T.eq(wow.registeredCategory, wow.category)
    T.eq(wow.category.name, "Guild Login Hush")
    T.same({ wow.settings[1].key, wow.settings[2].key, wow.settings[3].key }, { "hideOnline", "hideOffline", "muteSound" })
    T.eq(wow.settings[1].tbl, ns.db, "the page writes into the live saved table")
    T.eq(wow.settings[3].variable, "GUILDLOGINHUSH_MUTESOUND")
    wow.roster.Zeus = true
    wow.settings[1]:SetValue(false) -- a click on the page
    T.eq(ns.db.hideOnline, false)
    T.eq(wow.Online("Zeus"), true)
    wow.settings[3]:SetValue(false)
    T.same(wow.soundCalls, { "mute " .. SOUND, "unmute " .. SOUND })
    wow.settings[1]:SetValueToDefault() -- the Defaults button
    T.eq(wow.Online("Zeus"), false)
end)

T.test("slash commands toggle, set and report; /glh opens the page", function()
    local ns = wow.Load()
    Slash("")
    T.eq(wow.openedCategory, 77)
    Slash("online off")
    T.eq(ns.db.hideOnline, false)
    T.eq(wow.settings[1].setValueCalls, 1, "changed through the page's setting, so an open page shows it")
    T.ok(wow.Printed("Hide \"has come online\": off"))
    Slash("ONLINE")
    T.eq(ns.db.hideOnline, true, "no argument toggles")
    T.eq(wow.settings[1].setValueCalls, 2)
    Slash("offline off")
    T.eq(ns.db.hideOffline, false)
    Slash("sound off")
    T.eq(ns.db.muteSound, false)
    T.same(wow.soundCalls, { "mute " .. SOUND, "unmute " .. SOUND })
    Slash("sound on")
    T.eq(wow.soundCalls[3], "mute " .. SOUND)
    Slash("sound maybe")
    T.ok(wow.Printed("/glh sound [on|off]"), "bad argument prints the help")
    Slash("help")
    T.ok(wow.Printed("/glh status"))
    GuildLoginHush_OnAddonCompartmentClick()
    T.eq(wow.openedCategory, 77)
end)

T.test("without the Settings API the slash commands still work and /glh prints the status", function()
    local ns = wow.Load({ setup = function() Settings = nil end })
    Slash("")
    T.ok(wow.Printed("Hide \"has come online\": on"))
    Slash("online off")
    T.eq(ns.db.hideOnline, false)
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), true)
    T.eq(wow.Offline("Zeus"), false)
end)

T.test("joining a guild requests the roster and starts hiding", function()
    local ns = wow.Load({ setup = function() wow.inGuild = false end })
    T.eq(wow.Online("Zeus"), true)
    wow.inGuild = true
    wow.Fire("PLAYER_GUILD_UPDATE", "player")
    T.eq(wow.rosterRequests, 1)
    T.eq(wow.Online("Zeus"), false)
    T.eq(ns.IsGuildMember({ "Zeus" }), true)
end)

T.test("the filter answers every chat window alike with one lookup", function()
    wow.Load()
    wow.roster.Zeus = true
    local calls = 0
    local exists = C_GuildInfo.MemberExistsByName
    C_GuildInfo.MemberExistsByName = function(name)
        calls = calls + 1
        return exists(name)
    end
    T.eq(wow.Online("Zeus"), false)
    T.eq(calls, 1, "one roster lookup for two chat windows")
end)

T.test("the memo never outlives its frame: a later line is judged afresh", function()
    wow.Load()
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false)
    wow.roster = {}
    wow.friends.Zeus = true -- no event fires for that
    T.eq(wow.Online("Zeus"), true, "the next frame's line sees the new state")
    T.eq(wow.Online("Zeus", nil, true), true, "the same text again in that frame is answered from the memo")
end)

T.test("a change within a frame drops the memo: settings, the friends list and the guild", function()
    local ns = wow.Load({ friends = false })
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false)
    ns.SetOption("hideOnline", false)
    T.eq(wow.Online("Zeus", nil, true), true, "a setting changed in the same frame")
    ns.SetOption("hideOnline", true)
    T.eq(wow.Online("Hera"), true, "unknown while the friends list is out")
    wow.Fire("FRIENDLIST_UPDATE")
    T.eq(wow.Online("Hera", nil, true), false, "the friends list arrived in the same frame")
    wow.inGuild = false
    wow.Fire("PLAYER_GUILD_UPDATE", "player")
    T.eq(wow.Online("Hera", nil, true), true, "left the guild in the same frame")
end)

T.test("the fallback is only used while in a guild, and the roster wins over the friends list", function()
    local ns = wow.Load()
    wow.friends.Zeus = true
    T.eq(ns.IsGuildMember({ "Zeus" }), false)
    wow.roster.Zeus = true
    T.eq(ns.IsGuildMember({ "Zeus" }), true)
    wow.inGuild = false
    T.eq(ns.IsGuildMember({ "Zeus" }), false)
end)

T.test("an event this client lacks does not stop the addon from loading", function()
    wow.Load({ setup = function() wow.unknownEvents.PLAYER_GUILD_UPDATE = true end })
    wow.roster.Zeus = true
    T.eq(wow.Online("Zeus"), false)
end)

T.done()
