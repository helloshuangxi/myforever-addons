local _, NS = ...
local bindingOwner
local handledThisFrame = false

function NS.RunQuickReplyShortcut()
    -- Clearing edit focus can deliver the same physical key to the binding too.
    if handledThisFrame then return end
    handledThisFrame = true
    C_Timer.After(0, function() handledThisFrame = false end)
    NS.QuickReply()
end

function NS.HandleShortcutKey(editBox, key)
    if key ~= "X" or not IsControlKeyDown()
        or (IsShiftKeyDown and IsShiftKeyDown()) or (IsAltKeyDown and IsAltKeyDown())
        or (IsMetaKeyDown and IsMetaKeyDown()) then return end
    -- Only our own fields use this handler. Native chat and other add-ons retain
    -- their normal editing shortcuts. Drop focus before the edit box can cut.
    editBox:ClearFocus()
    NS.RunQuickReplyShortcut()
end

function NS.InstallQuickReplyShortcut()
    if bindingOwner or type(SetOverrideBinding) ~= "function" then return end
    bindingOwner = CreateFrame("Frame")
    local function install()
        if InCombatLockdown and InCombatLockdown() then
            bindingOwner:RegisterEvent("PLAYER_REGEN_ENABLED")
            return
        end
        -- A session-only override leaves the player's saved key bindings intact.
        SetOverrideBinding(bindingOwner, false, "CTRL-X", "MYFOREVERCHAT_QUICKREPLY")
        bindingOwner:UnregisterEvent("PLAYER_REGEN_ENABLED")
    end
    bindingOwner:SetScript("OnEvent", install)
    install()
end
