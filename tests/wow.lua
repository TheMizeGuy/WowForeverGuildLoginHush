-- A small fake of the WoW client API, enough to load the addon under LuaJIT and drive it with
-- system chat lines, the guild roster, the friends list, sound muting and the Settings page.
-- Usage: local wow = dofile("tests/wow.lua"); local ns = wow.Load()

local wow = {}

local ADDON_DIR = (os.getenv("ADDON_DIR") or "GuildLoginMute") .. "/"

-- enUS global strings the addon reads, as the Forever 1.60.1 client's string table has them.
local STRINGS = {
    ERR_FRIEND_ONLINE_SS = "|Hplayer:%s|h[%s]|h has come online.",
    ERR_FRIEND_OFFLINE_S = "%s has gone offline.",
}

-- A value the fake canaccessvalue refuses, standing in for a 12.x secret value.
wow.SECRET = setmetatable({}, { __tostring = function() return "<secret>" end })

local function NoOp() end

-- Frames record scripts and events; any other method is a no-op.
local frameMethods = {}
frameMethods.__index = function(_, key)
    return rawget(frameMethods, key) or NoOp
end
function frameMethods.SetScript(frame, name, fn) frame.scripts[name] = fn end
function frameMethods.GetScript(frame, name) return frame.scripts[name] end
function frameMethods.RegisterEvent(frame, event)
    if wow.unknownEvents[event] then
        error("unknown event " .. event)
    end
    if not next(frame.events) then
        wow.eventFrames[#wow.eventFrames + 1] = frame
    end
    frame.events[event] = true
end
function frameMethods.UnregisterEvent(frame, event) frame.events[event] = nil end
function frameMethods.IsEventRegistered(frame, event) return frame.events[event] == true end

function wow.NewFrame()
    return setmetatable({ scripts = {}, events = {} }, frameMethods)
end

-- A Settings object the way Blizzard's AddOnSettingMixin behaves for addons: it default-initialises
-- the saved table, SetValue writes the table and notifies the value-changed callback.
local function NewSetting(category, variable, key, tbl, varType, name, default)
    if tbl[key] == nil then
        tbl[key] = default
    end
    local setting = { category = category, variable = variable, key = key, tbl = tbl, varType = varType, name = name, default = default }
    function setting:SetValueChangedCallback(callback) self.callback = callback end
    function setting:GetValue() return self.tbl[self.key] end
    function setting:SetValue(value)
        if type(value) ~= self.varType then
            error(("setting %s: expected a %s, got %s"):format(self.name, self.varType, type(value)))
        end
        self.tbl[self.key] = value
        if self.callback then
            self.callback(self, value)
        end
    end
    function setting:SetValueToDefault() self:SetValue(self.default) end
    return setting
end

function wow.Reset()
    wow.now = 1000
    wow.timers = {}
    wow.eventFrames = {}
    wow.unknownEvents = {}
    wow.filters = {}
    wow.printed = {}
    wow.inGuild = true
    wow.roster = {} -- [name] = true for guild members the client's roster knows
    wow.friends = {} -- [name] = true for character friends
    wow.rosterRequests = 0
    wow.friendRequests = 0
    wow.legacyFriends = true
    wow.muted = {} -- [fileDataID] = true while muted
    wow.soundCalls = {} -- "mute 567518", "unmute 567518" in order
    wow.hasMuteApi = true
    wow.settings = {} -- Settings objects in registration order
    wow.checkboxes = {}
    wow.chat = { wow.NewFrame(), wow.NewFrame() }

    local G = _G
    for key, value in pairs(STRINGS) do
        G[key] = value
    end
    G.GuildLoginMuteDB = nil
    G.SlashCmdList = {}
    G.print = function(...)
        local parts = {}
        for i = 1, select("#", ...) do
            parts[#parts + 1] = tostring((select(i, ...)))
        end
        wow.printed[#wow.printed + 1] = table.concat(parts, " ")
    end
    G.CreateFrame = function()
        return wow.NewFrame()
    end
    G.GetTime = function() return wow.now end
    G.canaccessvalue = function(...)
        for i = 1, select("#", ...) do
            if select(i, ...) == wow.SECRET then
                return false
            end
        end
        return true
    end
    G.C_Timer = {
        After = function(delay, fn)
            wow.timers[#wow.timers + 1] = { at = wow.now + delay, fn = fn }
        end,
    }
    G.IsInGuild = function() return wow.inGuild end
    G.C_GuildInfo = {
        MemberExistsByName = function(name) return wow.roster[name] == true end,
        GuildRoster = function() wow.rosterRequests = wow.rosterRequests + 1 end,
    }
    G.C_FriendList = {
        GetFriendInfo = function(name)
            if wow.friends[name] then
                return { name = name, connected = true }
            end
        end,
        ShowFriends = function() wow.friendRequests = wow.friendRequests + 1 end,
        IsLegacyFriendSystemEnabled = function() return wow.legacyFriends end,
    }
    G.ChatFrameUtil = {
        AddMessageEventFilter = function(event, fn)
            wow.filters[event] = wow.filters[event] or {}
            table.insert(wow.filters[event], fn)
        end,
        RemoveMessageEventFilter = function(event, fn)
            for index, filter in ipairs(wow.filters[event] or {}) do
                if filter == fn then
                    table.remove(wow.filters[event], index)
                    break
                end
            end
        end,
    }
    G.MuteSoundFile = function(id)
        wow.muted[id] = true
        wow.soundCalls[#wow.soundCalls + 1] = "mute " .. tostring(id)
    end
    G.UnmuteSoundFile = function(id)
        wow.muted[id] = nil
        wow.soundCalls[#wow.soundCalls + 1] = "unmute " .. tostring(id)
    end
    G.Settings = {
        VarType = { Boolean = "boolean", String = "string", Number = "number" },
        Default = { True = true, False = false },
        RegisterVerticalLayoutCategory = function(name)
            wow.category = { name = name, GetID = function() return 77 end }
            return wow.category, { name = name }
        end,
        RegisterAddOnSetting = function(category, variable, key, tbl, varType, name, default)
            local setting = NewSetting(category, variable, key, tbl, varType, name, default)
            wow.settings[#wow.settings + 1] = setting
            return setting
        end,
        CreateCheckbox = function(category, setting, tooltip)
            wow.checkboxes[#wow.checkboxes + 1] = { category = category, setting = setting, tooltip = tooltip }
        end,
        RegisterAddOnCategory = function(category) wow.registeredCategory = category end,
        OpenToCategory = function(id) wow.openedCategory = id end,
    }
end

-- Loads the addon's files in TOC order with a fresh namespace, then logs in and, unless told
-- otherwise, delivers the friends list.
function wow.Load(options)
    options = options or {}
    wow.Reset()
    if options.setup then
        options.setup()
    end
    if not wow.hasMuteApi then
        _G.MuteSoundFile, _G.UnmuteSoundFile = nil, nil
    end
    local ns = {}
    wow.ns = ns
    local toc = assert(io.open(ADDON_DIR .. "GuildLoginMute.toc")):read("*a")
    for file in toc:gmatch("\n([%w_]+%.lua)") do
        assert(loadfile(ADDON_DIR .. file))("GuildLoginMute", ns)
    end
    wow.Fire("ADDON_LOADED", "GuildLoginMute")
    if options.login ~= false then
        wow.Fire("PLAYER_LOGIN")
        if options.friends ~= false then
            wow.Fire("FRIENDLIST_UPDATE")
        end
    end
    return ns
end

function wow.Fire(event, ...)
    for _, frame in ipairs(wow.eventFrames) do
        if frame.events[event] and frame.scripts.OnEvent then
            frame.scripts.OnEvent(frame, event, ...)
        end
    end
end

-- Runs timers that are due, including ones they schedule.
function wow.Advance(seconds)
    wow.now = wow.now + (seconds or 0)
    local ran = true
    while ran do
        ran = false
        for index, timer in ipairs(wow.timers) do
            if timer.at <= wow.now then
                table.remove(wow.timers, index)
                timer.fn()
                ran = true
                break
            end
        end
    end
end

-- Delivers a system line through the CHAT_MSG_SYSTEM filters of every chat window, the way
-- ChatFrameUtil.ProcessMessageEventFilters does; returns true if it stays visible.
function wow.System(text)
    wow.now = wow.now + 0.01
    local shown = false
    for _, frame in ipairs(wow.chat) do
        local discard = false
        for _, filter in ipairs(wow.filters.CHAT_MSG_SYSTEM or {}) do
            if filter(frame, "CHAT_MSG_SYSTEM", text) then
                discard = true
                break
            end
        end
        shown = shown or not discard
    end
    return shown
end

function wow.Online(link, shown)
    return wow.System(STRINGS.ERR_FRIEND_ONLINE_SS:format(link, shown or link:match("^([^%-]+)") or link))
end

function wow.Offline(name)
    return wow.System(STRINGS.ERR_FRIEND_OFFLINE_S:format(name))
end

function wow.Printed(needle)
    for _, line in ipairs(wow.printed) do
        if line:find(needle, 1, true) then
            return true
        end
    end
    return false
end

return wow
