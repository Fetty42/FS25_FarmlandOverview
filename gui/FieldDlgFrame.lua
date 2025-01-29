-- Author: Fetty42
-- Date: 2024-12-09
-- Version: 1.0.0.0


local isDbPrintfOn = false

local function dbPrintf(...)
	if isDbPrintfOn then
    	print(string.format(...))
	end
end


FieldDlgFrame = {}
local DlgFrame_mt = Class(FieldDlgFrame, MessageDialog)

FieldDlgFrame.mixDlg	= nil


function FieldDlgFrame.new(target, custom_mt)
	dbPrintf("FieldDlgFrame:new()")
	local self = MessageDialog.new(target, custom_mt or DlgFrame_mt)
    self.fields = {}
	return self
end

function FieldDlgFrame:onGuiSetupFinished()
	dbPrintf("FieldDlgFrame:onGuiSetupFinished()")
	FieldDlgFrame:superClass().onGuiSetupFinished(self)
	self.overviewTable:setDataSource(self)
	self.overviewTable:setDelegate(self)
end

function FieldDlgFrame:onCreate()
	dbPrintf("FieldDlgFrame:onCreate()")
	FieldDlgFrame:superClass().onCreate(self)
end


function FieldDlgFrame:onOpen()
	dbPrintf("FieldDlgFrame:onOpen()")
	FieldDlgFrame:superClass().onOpen(self)

	-- Fill data structure
	self.farmlands = {}
	for _, farmland in pairs(g_farmlandManager.farmlands) do
		if farmland.showOnFarmlandsScreen then
            local farmName, farmColor, sectionName, sectionOrder = FieldDlgFrame:getFarmNameAndColor(farmland)
			table.insert(self.farmlands, {farmName = farmName, farmColor = farmColor, farmland = farmland, sectionName = sectionName, sectionOrder = sectionOrder})
        end
	end

    table.sort(self.farmlands, function(a, b)
        if a.sectionOrder == b.sectionOrder then
            return tonumber(a.farmland.name) < tonumber(b.farmland.name)
        else
            return a.sectionOrder < b.sectionOrder
        end
    end)

    -- finalize dialog
	self.overviewTable:reloadData()

	self:setSoundSuppressed(true)
    FocusManager:setFocus(self.overviewTable)
    self:setSoundSuppressed(false)
end


function FieldDlgFrame:getNumberOfItemsInSection(list, section)
    if list == self.overviewTable then
        return #self.farmlands
    else
        return 0
    end
end


function FieldDlgFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.overviewTable then
        local thisFarmland      = self.farmlands[index].farmland

        -- Set attributes for the farmland output
        cell:getAttribute("farmlandName"):setText(thisFarmland.name)
        cell:getAttribute("farmlandAreaHa"):setText(string.format("%1.2f ", thisFarmland.areaInHa) .. g_i18n:getAreaUnit())

        local farmName, farmColor = FieldDlgFrame:getFarmNameAndColor(thisFarmland)
        cell:getAttribute("farmlandOwner"):setText(farmName)
        cell:getAttribute("farmlandOwner").textColor = farmColor

        -- Set attributes for the field output
        if (thisFarmland.field ~= nil) then
            local field             = thisFarmland.field
            local fruitNamePos         = "--"
            local fruitStatePos         = "--"

            -- get infos via field position
            local x, z = field:getCenterOfFieldWorldPosition()
            local fruitTypeIndexPos, growthState = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
            if fruitTypeIndexPos ~= nil then
                local fruitTypePos = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndexPos)
                fruitNamePos = fruitTypePos.fillType.title
                cell:getAttribute("ftIcon"):setImageFilename(fruitTypePos.fillType.hudOverlayFilename)
                cell:getAttribute("ftIcon"):setVisible(true)


                -- determines the growth state of a fruit type and assigns a corresponding text label
                local minHarvest  = fruitTypePos.minHarvestingGrowthState
                local maxHarvest  = fruitTypePos.maxHarvestingGrowthState
                local maxGrowing  = fruitTypePos.minHarvestingGrowthState - 1
                local withered    = fruitTypePos.maxHarvestingGrowthState + 1
                local maxGrowthState = growthState

                if fruitTypePos.minPreparingGrowthState >= 0 then
                    maxGrowing = math.min(maxGrowing, fruitTypePos.minPreparingGrowthState - 1 )
                end

                if fruitTypePos.maxPreparingGrowthState >= 0 then
                    withered = fruitTypePos.maxPreparingGrowthState + 1
                end

                if maxGrowthState == fruitTypePos.cutState then
                    fruitStatePos = g_i18n:getText("ui_growthMapCut")
                elseif maxGrowthState == withered then
                    fruitStatePos = g_i18n:getText("ui_growthMapWithered")
                elseif maxGrowthState > 0 and maxGrowthState <= maxGrowing then
                    fruitStatePos = g_i18n:getText("ui_growthMapGrowing") .. " (" .. tostring(maxGrowthState) .. " / " .. tostring(maxHarvest) .. ")"
                elseif fruitTypePos.minPreparingGrowthState >= 0 and fruitTypePos.minPreparingGrowthState <= maxGrowthState and maxGrowthState <= fruitTypePos.maxPreparingGrowthState then
                    fruitStatePos = g_i18n:getText("ui_growthMapReadyToPrepareForHarvest")
                elseif minHarvest <= maxGrowthState and maxGrowthState <= maxHarvest then
                    fruitStatePos = g_i18n:getText("ui_growthMapReadyToHarvest")
                end
            else
                cell:getAttribute("ftIcon"):setVisible(false)
            end
            -- end
            cell:getAttribute("fieldAreaHa"):setText(string.format("%1.2f ", field.areaHa) .. g_i18n:getAreaUnit())
            cell:getAttribute("fieldCrop"):setText(fruitNamePos)
            cell:getAttribute("fieldCropState"):setText(fruitStatePos)
        else
            cell:getAttribute("fieldAreaHa"):setText("--")
            cell:getAttribute("fieldCrop"):setText("--")
            cell:getAttribute("fieldCropState"):setText("--")
            cell:getAttribute("ftIcon"):setVisible(false)

        end
    end
end


-- Retrieves the farm name and color associated with a given farmland.
function FieldDlgFrame:getFarmNameAndColor(thisFarmland)
    local ownerFarmId       = thisFarmland.farmId
    local farmColor         = { 1, 1, 1, 1 }
    local farmName = ""
    local sectionName = ""
    local sectionOrder = "9"

    if ownerFarmId == g_currentMission:getFarmId() and ownerFarmId ~= FarmManager.SPECTATOR_FARM_ID then
        -- the farmland is owned by the current player's farm
        farmName = g_i18n:getText("ownerYou")
        if g_currentMission.missionDynamicInfo.isMultiplayer then
            local farm = g_farmManager:getFarmById(ownerFarmId)
            if farm ~= nil then
                farmName  = farm.name .. string.format(" (%s)", g_i18n:getText("ownerYou"))
                farmColor = Farm.COLORS[farm.color]
            end
        end
        sectionName = farmName
        sectionOrder = "1"
    elseif ownerFarmId == AccessHandler.EVERYONE or ownerFarmId == AccessHandler.NOBODY then
        -- the farmland is owned by everyone or nobody
        farmColor = { 0.5, 0.5, 0.5, 1 }
        local npc = thisFarmland:getNPC()
        if npc ~= nil then
            farmName = "NPC-" .. npc.title
            sectionName = "NPC"
            sectionOrder = "7"
        else
            farmName = g_i18n:getText("ownerUnknown")
            sectionName = farmName
            sectionOrder = "8"
        end
    else
        local farm = g_farmManager:getFarmById(ownerFarmId)
        if farm ~= nil then
            -- the farmland is owned by another farm
            farmName  = farm.name
            farmColor = Farm.COLORS[farm.color]
            sectionName = farmName
            sectionOrder = "2-" .. sectionName
        else
            farmName = g_i18n:getText("ownerUnknown")
            farmColor = { 0.5, 0.5, 0.5, 1 }
            sectionName = farmName
            sectionOrder = "9"
        end
    end
    return farmName, farmColor, sectionName, sectionOrder
end



--- Get the field polygon vertices from the map. These determine the field boundary in the game's
--- initial state. These do not reflect changes made by terrain modification or plowing, to get a
--- field polygon with those changes, use the FieldScanner
---@return table [{x, y, z}] field polygon vertices
function FieldDlgFrame:getFieldPolygon(field)
    local unpackedVertices = field:getDensityMapPolygon():getVerticesList()
    local vertices = {}
    for i = 1, #unpackedVertices, 2 do
        local x, z = unpackedVertices[i], unpackedVertices[i + 1]
        table.insert(vertices, { x = x, y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 1, z), z = z })
    end
    return vertices
end



function FieldDlgFrame:onButtonWarpToField()
    dbPrintf("FieldDlgFrame:onButtonWarpField()")

    local warpX, warpY, warpZ = 0, 0, 0
    local dropHeight       = 1.2
    local thisFarmland     = self.farmlands[self.overviewTable.selectedIndex].farmland

    if thisFarmland.field ~= nil then
        warpX, warpZ = thisFarmland.field:getCenterOfFieldWorldPosition()   -- user better x, z values
        warpY =  getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, warpX, 0, warpZ);

    else
        warpX, warpZ = thisFarmland.xWorldPos, thisFarmland.zWorldPos -- todo: find a better way to get the height (y)
        warpY =  getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, warpX, 0, warpZ);
    end

    dbPrintf("Warping to: %f, %f, %f", warpX, warpY, warpZ)

    g_gui:showGui("")

    if g_localPlayer ~= nil and g_localPlayer:getCurrentVehicle() ~= nil then
        local curVehicle = g_localPlayer:getCurrentVehicle()
        curVehicle:doLeaveVehicle()
    end
    g_localPlayer:teleportTo(warpX, warpY + dropHeight, warpZ)


    -- Test, to get mor Infos
    -- if true then
    --     local x, z = thisFarmland.field:getCenterOfFieldWorldPosition()
    --     local y = getTerrainHeightAtWorldPos(g_currentMission.terrainRootNode, x, 0, z)
    --     dbPrintf("Field Center: x=%s, y=%s, z=%s", x, y, z)

    --     local isOnField, densityBits, groundType = FSDensityMapUtil.getFieldDataAtWorldPosition(x,y,z)
    --     local fruitTypeIndex, growthState = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
    --     local fruitTypeName = "--"
    --     if fruitTypeIndex ~= nil then
    --         local fruitType = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndex)
    --         print("fruitTypeName=" .. fruitType.name)
    --         fruitTypeName = fruitType.fillType.title
    --     end
    --     --local fieldType = FSDensityMapUtil.getFieldTypeAtWorldPos(x, z)
    --     dbPrintf("isOnField=%s, densityBits=%s, groundType=%s, fruitTypeIndex=%s, fruitTypeName=%s, growthState=%s", tostring(isOnField), tostring(densityBits), tostring(groundType), fruitTypeIndex, fruitTypeName, tostring(growthState))

    --     dbPrintf("Field Polygon")
    --     local vertices = FieldDlgFrame:getFieldPolygon(thisFarmland.field)
    --     for i, point in ipairs(vertices) do
    --         dbPrintf("  %s -->  x=%s y=%s z=%s ", i, point.x, point.y, point.z)
    --     end
    --     dbPrintf("")

    --     local width = 2
    --     local length = 2
    --     dbPrintf("Field Area: c1=(%s, %s), c2=(%s, %s), c3=(%s, %s))", x - width / 2, z - length / 2, x + width / 2, z - length / 2, x - width / 2, z + length / 2)
    --     for _, fruitType in pairs(g_fruitTypeManager:getFruitTypes()) do
    --         if not (fruitType == g_fruitTypeManager:getFruitTypeByName("MEADOW")) then
    --             local fruitTypeIndex = fruitType.index
    --             -- local fruitValue, _, _, _    = FSDensityMapUtil.getFruitArea(spec.fruitTypeIndex, x, z, x1, z1, x2, z2, nil, spec.allowsForageGrowthState)
    --             -- local fruitValue, numPixels, totalNumPixels, c = FSDensityMapUtil.getFruitArea(fruitType.index, x - width / 2, z - length / 2, x + width / 2, z, x, z + length / 2, true, true)
    --             local fruitValue, numPixels, totalNumPixels, c = FSDensityMapUtil.getFruitArea(fruitType.index, x - width / 2, z - length / 2, x + width / 2, z - length / 2, x - width / 2, z + length / 2, true, true)
    --             if fruitValue > 0 or numPixels > 0 then
    --                 dbPrintf("getFruitArea (allowsForageGrowthState = true):  fruitTypeindex=%2s, fruitTypeName=%15s, fruitValue=%s, numPixels=%s, totalNumPixels=%s, c=%s", fruitType.index, fruitType.name, fruitValue, numPixels, totalNumPixels, c)
    --             end

    --             -- fruitValue, numPixels, totalNumPixels, c = FSDensityMapUtil.getFruitArea(fruitType.index, x - width / 2, z - length / 2, x + width / 2, z - length / 2, x - width / 2, z + length / 2, true, false)
    --             -- if fruitValue > 0 or numPixels > 0 then
    --             --     dbPrintf("getFruitArea (allowsForageGrowthState = false): fruitTypeindex=%2s, fruitTypeName=%15s, fruitValue=%s, numPixels=%s, totalNumPixels=%s, c=%s", fruitType.index, fruitType.name, fruitValue, numPixels, totalNumPixels, c)
    --             -- end

    --             fruitValue, numPixels, totalNumPixels, growthState = FSDensityMapUtil.getFruitArea(fruitType.index, x, z, x, z, x, z, true, true)
    --             if fruitValue > 0 or numPixels > 0 then
    --                 dbPrintf("getFruitArea Point (allowsForageGrowthState = true):  fruitTypeindex=%2s, fruitTypeName=%15s, fruitValue=%s, numPixels=%s, totalNumPixels=%s, growthState=%s", fruitType.index, fruitType.name, fruitValue, numPixels, totalNumPixels, growthState)
    --             end
    --         end
    --     end
    -- end
    -- Test end
end


function FieldDlgFrame:onClose()
	dbPrintf("FieldDlgFrame:onClose()")
	self.farmlands = {}
	FieldDlgFrame:superClass().onClose(self)
end


function FieldDlgFrame:onClickBack(sender)
	dbPrintf("FieldDlgFrame:onClickBack()")
	self:close()
end

