-- Author: Fetty42
-- Version: 1.1.0.0

local dbPrintfOn = false
local dbInfoPrintfOn = false

local function dbInfoPrintf(...)
	if dbInfoPrintfOn then
    	print(string.format(...))
	end
end

local function dbPrintf(...)
	if dbPrintfOn then
    	print(string.format(...))
	end
end

local function dbPrint(...)
	if dbPrintfOn then
    	print(...)
	end
end

local function dbPrintHeader(funcName)
	if dbPrintfOn then
		if g_currentMission ~=nil and g_currentMission.missionDynamicInfo ~=nil then
			print(string.format("Call %s: isDedicatedServer=%s | isServer()=%s | isMasterUser=%s | isMultiplayer=%s | isClient()=%s | farmId=%s", 
							funcName, tostring(g_dedicatedServer~=nil), tostring(g_currentMission:getIsServer()), tostring(g_currentMission.isMasterUser), tostring(g_currentMission.missionDynamicInfo.isMultiplayer), tostring(g_currentMission:getIsClient()), tostring(g_currentMission:getFarmId())))
		else
			print(string.format("Call %s: isDedicatedServer=%s | g_currentMission=%s",
							funcName, tostring(g_dedicatedServer~=nil), tostring(g_currentMission)))
		end
	end
end


FieldOverview = {}; -- Class

-- global variables
FieldOverview.dir = g_currentModDirectory
FieldOverview.modName = g_currentModName

FieldOverview.dlg			= nil

-- =========================================================
-- Harvest multiplier cache (AFI parity)
-- =========================================================

FS25_FarmlandOverview = FS25_FarmlandOverview or {}
FS25_FarmlandOverview.stoneCoveragePctByFarmlandId =
    FS25_FarmlandOverview.stoneCoveragePctByFarmlandId or {}

source(FieldOverview.dir .. "gui/FieldDlgFrame.lua")

function FieldOverview:loadMap(name)
    dbPrintHeader("FieldOverview:loadMap()")
end

function FieldOverview:ShowFieldDlg(actionName, keyStatus, arg3, arg4, arg5)
	dbPrintHeader("FieldOverview:ShowFieldDlg()")

	FieldOverview.dlg = nil
	g_gui:loadProfiles(FieldOverview.dir .. "gui/guiProfiles.xml")

    -- Safety: ensure FieldDlgFrame class is loaded (source can fail silently on some errors)
    if FieldDlgFrame == nil then
        local ok, err = pcall(function()
            source(FieldOverview.dir .. "gui/FieldDlgFrame.lua")
        end)

        if not ok then
            print(string.format(
                "[FS25_FarmlandOverview] ERROR loading gui/FieldDlgFrame.lua: %s",
                tostring(err)
            ))
            return
        end
    end

	local fieldDlgFrame = FieldDlgFrame.new(g_i18n)
	g_gui:loadGui(FieldOverview.dir .. "gui/FieldDlgFrame.xml", "FieldDlgFrame", fieldDlgFrame)
	FieldOverview.dlg = g_gui:showDialog("FieldDlgFrame")
end

function FieldOverview:onLoad(savegame)end;
function FieldOverview:onUpdate(dt)end;
function FieldOverview:deleteMap()end;
function FieldOverview:keyEvent(unicode, sym, modifier, isDown)end;
function FieldOverview:mouseEvent(posX, posY, isDown, isUp, button)end;

addModEventListener(FieldOverview);