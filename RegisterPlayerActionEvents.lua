-- Author: Fetty42
-- Date: 08.12.2024
-- Version: 1.0.0.0

local isDbPrintfOn = false

-- Function to print debug messages if debugging is enabled
-- Usage: dbPrintf("Message: %s", message)
local function dbPrintf(...)
    if isDbPrintfOn then
        print(string.format(...))
    end
end


dbPrintf("    FS25_FieldOverview: register global player action events")


--[[
    This function appends a custom action event registration to the global player action events.
    
    Parameters:
    - self: The PlayerInputComponent instance.
    - controlling: The current controlling state, expected to be "VEHICLE" or other states.
--]]
PlayerInputComponent.registerGlobalPlayerActionEvents = Utils.appendedFunction(
    PlayerInputComponent.registerGlobalPlayerActionEvents,
    function(self, controlling)
        if controlling ~= "VEHICLE" or true then
            local triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings = false, true, false, true, nil, true

            local success, actionEventId, otherEvents = g_inputBinding:registerActionEvent(InputAction.SHOW_FIELD_DLG, FieldOverview, FieldOverview.ShowFieldDlg, triggerUp, triggerDown, triggerAlways, startActive, callbackState, disableConflictingBindings);

            if success then
                -- FieldOverview.actionEventId = actionEventId
                g_inputBinding:setActionEventTextPriority(actionEventId, GS_PRIO_VERY_LOW) -- GS_PRIO_VERY_HIGH, GS_PRIO_HIGH, GS_PRIO_LOW, GS_PRIO_VERY_LOW
                g_inputBinding:setActionEventTextVisibility(actionEventId, true) -- INFO: change "false" to "true" to show keybinding in help window
                dbPrintf("FS25_FieldOverview - Register key (controlling=%s, action=%s, actionId=%s)", controlling, InputAction.SHOW_FIELD_DLG, actionEventId)
            else
                -- Sometimes the registration for cotrolling=vehicle goes wrong. But I don't know why. Nevertheless, it is needed!
                dbPrintf("FS25_FieldOverview - Failed to register key (controlling=%s, action=%s, actionId=%s)", controlling, InputAction.SHOW_FIELD_DLG, actionEventId)
            end    

            -- g_inputBinding:setActionEventText(eventId, g_i18n:getText("moh_HIDE"));
            -- g_inputBinding:setActionEventActive(eventId, true)
            -- EnterClosestVehicle.currentEventId = eventId;
        end
end)

