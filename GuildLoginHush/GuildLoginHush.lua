-- WoW Forever Guild Login Hush
-- Hides the "has come online" and "has gone offline" chat lines about guild members and mutes the
-- sound the client plays when someone comes online. Each is its own setting (/glh, or Esc >
-- Options > AddOns > Guild Login Hush).
--
-- Both lines are system messages built from ERR_FRIEND_ONLINE_SS and ERR_FRIEND_OFFLINE_S, the
-- same for friends and guild members, so the name in a line is checked against the guild roster
-- (C_GuildInfo.MemberExistsByName). Only friends and guild members produce these lines, so a name
-- that is not on the friends list is a guild member's even before the roster has arrived.
-- The sound is played by the client itself, not by any UI code, so MuteSoundFile is the only way
-- to stop it. It is one sound for friends and guild members alike (sound kit 3332 "FriendJoinGame",
-- file 567518 on the 1.60.1 client), and a mute lasts until the client is closed.

local ADDON_NAME, ns = ...

local ipairs, pairs, pcall, type = ipairs, pairs, pcall, type
local strmatch, strgsub, strfind = string.match, string.gsub, string.find

local SOUND_FILE = 567518 -- FriendJoinGame (sound kit 3332) on the Forever 1.60.1 client
local FRIENDS_WAIT = 15 -- seconds after login to stop waiting for the friends list
local PREFIX = "|cff66ccff[Guild Login Hush]|r "

ns.DEFAULTS = { hideOnline = true, hideOffline = true, muteSound = true }

-- The settings, in the order the page shows them.
ns.OPTIONS = {
    {
        key = "hideOnline",
        label = "Hide \"has come online\" lines about guild members",
        tooltip = "The chat line printed when a guild member logs in. Lines about friends who are not in your guild stay.",
    },
    {
        key = "hideOffline",
        label = "Hide \"has gone offline\" lines about guild members",
        tooltip = "The chat line printed when a guild member logs out. Lines about friends who are not in your guild stay.",
    },
    {
        key = "muteSound",
        label = "Mute the login sound",
        tooltip = "The sound the game plays when a guild member or character friend comes online. It is one sound for both, so friends' logins go quiet too; logging out plays none. Battle.net friends' toasts have their own sound, which Options > Social > Online Friends / Offline Friends turn off.",
    },
}

local db -- GuildLoginHushDB, once loaded

local function Print(message)
    print(PREFIX .. message)
end
ns.Print = Print

-- 12.x hands addons "secret" values in some chat contexts; comparing one raises an error, so chat
-- text is checked before it is looked at.
local function Readable(value)
    return not canaccessvalue or canaccessvalue(value)
end

-- Patterns ---------------------------------------------------------------------------------------

-- A Lua pattern matching the whole of a global string, each %s (or %1$s) capturing its text.
local function Pattern(format)
    if type(format) ~= "string" or format == "" then
        return nil
    end
    local pattern = strgsub(format, "[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0")
    pattern = strgsub(pattern, "%%%%%d+%%%$s", "(.-)")
    pattern = strgsub(pattern, "%%%%s", "(.-)")
    return "^" .. pattern .. "$"
end
ns.Pattern = Pattern

local onlinePattern, offlinePattern

local function BuildPatterns()
    onlinePattern = Pattern(ERR_FRIEND_ONLINE_SS)
    offlinePattern = Pattern(ERR_FRIEND_OFFLINE_S)
end
ns.BuildPatterns = BuildPatterns

-- A character name, optionally followed by -Realm: letters only in the name (accented letters are
-- bytes above 127, which these classes leave alone) and no whitespace in the realm. Other system
-- lines fit the offline format too ("That arena team has gone offline."), and this keeps them out.
local function LooksLikeName(name)
    local char, realm = strmatch(name, "^([^%-]+)%-(.+)$")
    char = char or name
    if char == "" or strfind(char, "[%s%c%d%p]") then
        return false
    end
    return realm == nil or not strfind(realm, "[%s%c]")
end
ns.LooksLikeName = LooksLikeName

local homeRealm -- GetNormalizedRealmName(), once the client knows it

-- The forms a name can take in the roster and the friends list: as written and, when it carries
-- the player's own realm, without it ("Zeus-Forever" and "Zeus"). A name from another realm keeps
-- its realm, since character names are unique only per realm. nil when the text is not a
-- character name at all.
local function Names(name)
    if not LooksLikeName(name) then
        return nil
    end
    local names = { name }
    local short, realm = strmatch(name, "^([^%-]+)%-(.+)$")
    if short then
        if not homeRealm and GetNormalizedRealmName then
            homeRealm = GetNormalizedRealmName()
        end
        if homeRealm and realm == homeRealm then
            names[#names + 1] = short
        end
    end
    return names
end
ns.Names = Names

-- Who the line is about ----------------------------------------------------------------------------

local friendsLoaded = false -- FRIENDLIST_UPDATE has fired, or the wait for it ran out

local function InRoster(names)
    local exists = C_GuildInfo and C_GuildInfo.MemberExistsByName
    if not exists then
        return false
    end
    for _, name in ipairs(names) do
        local ok, found = pcall(exists, name)
        if ok and found then
            return true
        end
    end
    return false
end

local function IsFriend(names)
    local get = C_FriendList and C_FriendList.GetFriendInfo
    if not get then
        return false
    end
    for _, name in ipairs(names) do
        local ok, info = pcall(get, name)
        if ok and info then
            return true
        end
    end
    return false
end

-- Whether a line about a player with these names is about a guild member. While the friends list
-- has not arrived, a name the roster does not know is left visible.
local function IsGuildMember(names)
    if not IsInGuild() then
        return false
    end
    if InRoster(names) then
        return true
    end
    if not friendsLoaded or IsFriend(names) then
        return false
    end
    return true -- only friends and guild members produce these lines
end
ns.IsGuildMember = IsGuildMember

-- The chat filter ---------------------------------------------------------------------------------

-- A filter runs once per chat window that shows the event; the memo keeps them in step.
local memoText, memoTime, memoHide

local function SystemFilter(_, _, text)
    if not db or not Readable(text) or type(text) ~= "string" then
        return false
    end
    local now = GetTime()
    if text == memoText and now == memoTime then
        return memoHide
    end
    local hide = false
    -- The online line carries the name twice (link target and display); the first is enough.
    local link = onlinePattern and strmatch(text, onlinePattern)
    if link then
        local names = db.hideOnline == true and Names(link)
        hide = names ~= nil and names ~= false and IsGuildMember(names)
    else
        local name = offlinePattern and strmatch(text, offlinePattern)
        if name then
            local names = db.hideOffline == true and Names(name)
            hide = names ~= nil and names ~= false and IsGuildMember(names)
        end
    end
    memoText, memoTime, memoHide = text, now, hide
    return hide
end
ns.SystemFilter = SystemFilter

-- Blizzard wraps every registered filter call in a secure call and packs its arguments, so the
-- filter is only registered while a line type is being hidden.
local filtered = false

local function UpdateFilter()
    local want = db ~= nil and (db.hideOnline or db.hideOffline) and (onlinePattern ~= nil or offlinePattern ~= nil)
    local add = ChatFrameUtil and ChatFrameUtil.AddMessageEventFilter or ChatFrame_AddMessageEventFilter
    local remove = ChatFrameUtil and ChatFrameUtil.RemoveMessageEventFilter or ChatFrame_RemoveMessageEventFilter
    if want and not filtered and add then
        add("CHAT_MSG_SYSTEM", SystemFilter)
        filtered = true
    elseif not want and filtered and remove then
        remove("CHAT_MSG_SYSTEM", SystemFilter)
        filtered = false
    end
end

-- The sound ----------------------------------------------------------------------------------------

local function CanMute()
    return type(MuteSoundFile) == "function" and type(UnmuteSoundFile) == "function"
end

-- A mute outlives /reload and relogging but not the client, and the engine may count mutes rather
-- than keep one flag, so every load mutes at most once and PLAYER_LOGOUT (which /reload fires
-- too) unmutes it again: the addon's mutes and unmutes always balance, and disabling the addon
-- brings the sound back. The sound is only ever unmuted when this addon muted it.
local muted = false

local function ApplySound()
    if not CanMute() then
        return
    end
    if db.muteSound then
        if not muted then
            MuteSoundFile(SOUND_FILE)
            muted = true
        end
    elseif muted then
        UnmuteSoundFile(SOUND_FILE)
        muted = false
    end
end

local function ReleaseSound()
    if muted and CanMute() then
        UnmuteSoundFile(SOUND_FILE)
        muted = false
    end
end

-- Settings -----------------------------------------------------------------------------------------

local function LoadSettings()
    local saved = type(GuildLoginHushDB) == "table" and GuildLoginHushDB or {}
    GuildLoginHushDB = saved
    for key, default in pairs(ns.DEFAULTS) do
        if type(saved[key]) ~= "boolean" then
            saved[key] = default
        end
    end
    db = saved
    ns.db = db
end

-- Called after a setting changed, from the settings page or a slash command.
function ns.OptionChanged(key)
    memoText = nil
    if key == "muteSound" then
        ApplySound()
    else
        UpdateFilter()
    end
end

-- Changes a setting through its Settings object when the page is registered, so an open page shows
-- the change, else directly.
function ns.SetOption(key, value)
    if ns.SetSettingValue and ns.SetSettingValue(key, value) then
        return
    end
    db[key] = value
    ns.OptionChanged(key)
end

-- Events ------------------------------------------------------------------------------------------

local events = CreateFrame("Frame")
local handlers = {}

local function RequestRoster()
    if IsInGuild() and C_GuildInfo and C_GuildInfo.GuildRoster then
        C_GuildInfo.GuildRoster()
    end
end

local function FriendsReady()
    friendsLoaded = true
    memoText = nil
    events:UnregisterEvent("FRIENDLIST_UPDATE")
end

function handlers.ADDON_LOADED(name)
    if name ~= ADDON_NAME then
        return
    end
    events:UnregisterEvent("ADDON_LOADED")
    LoadSettings()
    BuildPatterns()
    if ns.RegisterSettings then
        ns.RegisterSettings(db)
    end
    ApplySound()
    UpdateFilter()
end

function handlers.PLAYER_LOGIN()
    RequestRoster()
    if C_FriendList and C_FriendList.IsLegacyFriendSystemEnabled then
        -- A definite false means this client has no character friends, so every line is a guild
        -- member's. The call may return nothing before the friends list exists; that is not false.
        local ok, enabled = pcall(C_FriendList.IsLegacyFriendSystemEnabled)
        if ok and enabled == false then
            friendsLoaded = true
            memoText = nil
            return
        end
    end
    if C_FriendList and C_FriendList.ShowFriends then
        pcall(C_FriendList.ShowFriends)
    end
    -- The list normally arrives within a second. Without it every line would stay visible all
    -- session, so the wait ends after a while.
    C_Timer.After(FRIENDS_WAIT, function()
        if not friendsLoaded then
            FriendsReady()
        end
    end)
end

handlers.FRIENDLIST_UPDATE = FriendsReady
handlers.PLAYER_LOGOUT = ReleaseSound

function handlers.PLAYER_GUILD_UPDATE(unit)
    if unit == nil or unit == "player" then
        memoText = nil
        RequestRoster()
    end
end

events:SetScript("OnEvent", function(_, event, ...)
    handlers[event](...)
end)
for event in pairs(handlers) do
    -- Tolerate an event this client build does not have.
    pcall(events.RegisterEvent, events, event)
end

-- Slash commands ----------------------------------------------------------------------------------

local KEYS = { online = "hideOnline", offline = "hideOffline", sound = "muteSound" }

local function State(on)
    return on and "on" or "off"
end

local function PrintStatus()
    Print(("Hide \"has come online\": %s. Hide \"has gone offline\": %s. Mute the login sound: %s.")
        :format(State(db.hideOnline), State(db.hideOffline), State(db.muteSound)))
    if not IsInGuild() then
        Print("You are not in a guild, so no line is hidden.")
    elseif not friendsLoaded and (db.hideOnline or db.hideOffline) then
        Print("Waiting for the friends list. Until it arrives, lines about players the roster does not list stay visible.")
    end
    if db.muteSound and not CanMute() then
        Print("This client has no MuteSoundFile, so the sound cannot be muted.")
    end
end

local function PrintHelp()
    Print("commands:")
    print("  /glh                   open the settings")
    print("  /glh online [on|off]   hide \"has come online\" lines about guild members")
    print("  /glh offline [on|off]  hide \"has gone offline\" lines about guild members")
    print("  /glh sound [on|off]    mute the login sound")
    print("  /glh status            show the current settings")
end

SLASH_GUILDLOGINHUSH1 = "/glh"
SLASH_GUILDLOGINHUSH2 = "/guildhush"
SlashCmdList.GUILDLOGINHUSH = function(message)
    local command, rest = strmatch(message or "", "^%s*(%S*)%s*(%S*)")
    command, rest = command:lower(), rest:lower()
    local key = KEYS[command]
    if command == "" then
        if ns.OpenOptions then
            ns.OpenOptions()
        else
            PrintStatus()
        end
    elseif key then
        local value
        if rest == "on" then
            value = true
        elseif rest == "off" then
            value = false
        elseif rest == "" then
            value = not db[key]
        else
            PrintHelp()
            return
        end
        ns.SetOption(key, value)
        PrintStatus()
    elseif command == "status" then
        PrintStatus()
    else
        PrintHelp()
    end
end

-- Addon compartment (the addons button by the minimap).
function GuildLoginHush_OnAddonCompartmentClick()
    SlashCmdList.GUILDLOGINHUSH("")
end
