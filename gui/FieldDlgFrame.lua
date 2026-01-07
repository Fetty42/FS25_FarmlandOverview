-- Author: Fetty42
-- Date: 30.03.2025
-- Version: 1.0.1.0


local isDbPrintfOn = false

local function dbPrintf(...)
	if isDbPrintfOn then
    	print(string.format(...))
	end
end


FieldDlgFrame = {}
local DlgFrame_mt = Class(FieldDlgFrame, MessageDialog)

FieldDlgFrame.mixDlg	= nil
FieldDlgFrame.lastSelectedIndex = nil   -- Restore the previous position in the list


function FieldDlgFrame.new(target, custom_mt)
	dbPrintf("FieldDlgFrame:new()")
	local self = MessageDialog.new(target, custom_mt or DlgFrame_mt)
    self.fields = {}
    self.sortColumn = "number" -- default sort by number (Nr.)
    self.sortAscending = true
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
    -- Build list and precompute sortable values
    self.farmlands = {}
    for _, farmland in pairs(g_farmlandManager.farmlands) do
        if farmland.showOnFarmlandsScreen then
            local farmName, farmColor, sectionName, sectionOrder = FieldDlgFrame:getFarmNameAndColor(farmland)
            local entry = {farmName = farmName, farmColor = farmColor, farmland = farmland, sectionName = sectionName, sectionOrder = sectionOrder}
            entry.farmlandArea = farmland.areaInHa
            if farmland.field ~= nil then
                entry.fieldArea = farmland.field.areaHa
                local x, z = farmland.field:getCenterOfFieldWorldPosition()
                local fruitTypeIndexPos, _ = FSDensityMapUtil.getFruitTypeIndexAtWorldPos(x, z)
                if fruitTypeIndexPos ~= nil then
                    local fruitTypePos = g_fruitTypeManager:getFruitTypeByIndex(fruitTypeIndexPos)
                    entry.cropName = fruitTypePos.fillType.title
                else
                    entry.cropName = "--"
                end
            else
                entry.fieldArea = nil
                entry.cropName = "--"
            end
            table.insert(self.farmlands, entry)
        end
    end

    -- Apply sort: primary by owner (sectionOrder), secondary according to selected column
    self:applySorting()

    -- finalize dialog
	self.overviewTable:reloadData()

        --  Restore the previous position
    if FieldDlgFrame.lastSelectedIndex ~= nil then
        self.overviewTable:setSelectedItem(1, FieldDlgFrame.lastSelectedIndex)
    end

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


-- Apply sorting while keeping owner (sectionOrder) as primary key
function FieldDlgFrame:applySorting()
    table.sort(self.farmlands, function(a, b)
        if a.sectionOrder ~= b.sectionOrder then
            return a.sectionOrder < b.sectionOrder
        end

        -- same owner/section -> apply chosen secondary sort
        local asc = self.sortAscending and 1 or -1

        local function cmpString(x, y)
            if x == y then return 0 end
            if x == nil then return 1 end
            if y == nil then return -1 end
            return (x < y) and -1 or 1
        end

        if self.sortColumn == "number" then
            local an = tonumber(a.farmland.name)
            local bn = tonumber(b.farmland.name)
            if an and bn then
                if an == bn then return false end
                return (an < bn) == self.sortAscending
            else
                return (a.farmland.name < b.farmland.name) == self.sortAscending
            end
        elseif self.sortColumn == "farmlandArea" then
            if a.farmlandArea == b.farmlandArea then
                return (a.farmland.name < b.farmland.name) == self.sortAscending
            end
            return (a.farmlandArea < b.farmlandArea) == self.sortAscending
        elseif self.sortColumn == "fieldArea" then
            local va = a.fieldArea or -1
            local vb = b.fieldArea or -1
            if va == vb then
                return (a.farmland.name < b.farmland.name) == self.sortAscending
            end
            return (va < vb) == self.sortAscending
        elseif self.sortColumn == "crop" then
            local c = cmpString(a.cropName, b.cropName)
            if c == 0 then
                return (a.farmland.name < b.farmland.name) == self.sortAscending
            end
            return (c < 0) == self.sortAscending
        else
            -- default: keep original behaviour (numeric name else text)
            local an = tonumber(a.farmland.name)
            local bn = tonumber(b.farmland.name)
            if an and bn then
                return an < bn
            else
                return a.farmland.name < b.farmland.name
            end
        end
    end)
end


-- Header click handlers: toggle sort column / direction and refresh
function FieldDlgFrame:onClickSortByNumber()
    if self.sortColumn == "number" then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = "number"
        self.sortAscending = true
    end
    self:applySorting()
    self.overviewTable:reloadData()
end

function FieldDlgFrame:onClickSortByFarmlandArea()
    if self.sortColumn == "farmlandArea" then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = "farmlandArea"
        self.sortAscending = false
    end
    self:applySorting()
    self.overviewTable:reloadData()
end

function FieldDlgFrame:onClickSortByFieldArea()
    if self.sortColumn == "fieldArea" then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = "fieldArea"
        self.sortAscending = false
    end
    self:applySorting()
    self.overviewTable:reloadData()
end

function FieldDlgFrame:onClickSortByCrop()
    if self.sortColumn == "crop" then
        self.sortAscending = not self.sortAscending
    else
        self.sortColumn = "crop"
        self.sortAscending = true
    end
    self:applySorting()
    self.overviewTable:reloadData()
end


function FieldDlgFrame:populateCellForItemInSection(list, section, index, cell)
    if list == self.overviewTable then
        local entry = self.farmlands[index]
        local thisFarmland      = entry.farmland

        -- Set attributes for the farmland output
        local isSale = FS25_MyCollection_DH ~=nil and FS25_MyCollection_DH.LimitedFieldSellAndBuy ~= nil and FS25_MyCollection_DH.LimitedFieldSellAndBuy.farmlandsOnOffer ~= nil and FS25_MyCollection_DH.LimitedFieldSellAndBuy.farmlandsOnOffer[thisFarmland.name] ~= nil and FS25_MyCollection_DH.LimitedFieldSellAndBuy.farmlandsOnOffer[thisFarmland.name] == true
        if isSale then
            cell:getAttribute("farmlandName"):setTextColor(1, 0, 0, 1)  -- red
        else
            cell:getAttribute("farmlandName").textColor = cell:getAttribute("farmlandAreaHa").textColor  -- default
        end
        cell:getAttribute("farmlandName"):setText(thisFarmland.name)
        cell:getAttribute("farmlandAreaHa"):setText(string.format("%1.2f ", g_i18n:getArea(entry.farmlandArea)) .. g_i18n:getAreaUnit())

        cell:getAttribute("farmlandOwner"):setText(entry.farmName)
        cell:getAttribute("farmlandOwner").textColor = entry.farmColor

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
            if entry.fieldArea ~= nil then
                cell:getAttribute("fieldAreaHa"):setText(string.format("%1.2f ", g_i18n:getArea(entry.fieldArea)) .. g_i18n:getAreaUnit())
            else
                cell:getAttribute("fieldAreaHa"):setText("--")
            end
            cell:getAttribute("fieldCrop"):setText(entry.cropName)
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


function FieldDlgFrame:onButtonWarpToField()
    dbPrintf("FieldDlgFrame:onButtonWarpField()")

    FieldDlgFrame.lastSelectedIndex = self.overviewTable.selectedIndex
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
        g_localPlayer:leaveVehicle()
    end
    g_localPlayer:teleportTo(warpX, warpY + dropHeight, warpZ, false, false)
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

