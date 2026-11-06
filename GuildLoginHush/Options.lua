-- WoW Forever Guild Login Hush: the settings page (Esc > Options > AddOns > Guild Login Hush, or
-- /glh). Three checkboxes on Blizzard's vertical layout. The page writes straight into the saved
-- settings table; each change is applied through ns.OptionChanged.

local _, ns = ...

local category
local settings = {} -- [key] = the Settings object for that setting

-- Registered once the saved settings have loaded (ADDON_LOADED), since the page writes into them.
function ns.RegisterSettings(db)
    if not (Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterAddOnSetting
        and Settings.CreateCheckbox and Settings.RegisterAddOnCategory) then
        return
    end
    category = Settings.RegisterVerticalLayoutCategory("Guild Login Hush")
    for _, option in ipairs(ns.OPTIONS) do
        local variable = "GUILDLOGINHUSH_" .. option.key:upper()
        local setting = Settings.RegisterAddOnSetting(category, variable, option.key, db, Settings.VarType.Boolean,
            option.label, ns.DEFAULTS[option.key])
        setting:SetValueChangedCallback(function()
            ns.OptionChanged(option.key)
        end)
        Settings.CreateCheckbox(category, setting, option.tooltip)
        settings[option.key] = setting
    end
    Settings.RegisterAddOnCategory(category)
end

-- Sets a value through its Settings object, so an open page shows the change and the value-changed
-- callback applies it. False when the page is not registered.
function ns.SetSettingValue(key, value)
    local setting = settings[key]
    if not setting then
        return false
    end
    setting:SetValue(value)
    return true
end

function ns.OpenOptions()
    if not category then
        SlashCmdList.GUILDLOGINHUSH("status")
        return
    end
    Settings.OpenToCategory(category:GetID())
end
