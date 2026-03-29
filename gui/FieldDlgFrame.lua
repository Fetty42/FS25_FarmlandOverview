-- Author: Fetty42
-- Version: 1.1.0.0


local isDbPrintfOn = false

local function dbPrintf(...)
	if isDbPrintfOn then
    	print(string.format(...))
	end
end

local function getStoneCoveragePctForFarmland(thisFarmland)
    if thisFarmland == nil or thisFarmland.id == nil or thisFarmland.field == nil then
        return nil
    end

    local farmlandId = thisFarmland.id
    local cached = FS25_FarmlandOverview.stoneCoveragePctByFarmlandId[farmlandId]
    if cached ~= nil then
        return cached
    end

    if g_currentMission == nil or g_currentMission.stoneSystem == nil then
        return nil
    end

    local mapId, firstChannel, numChannels = g_currentMission.stoneSystem:getDensityMapData()
    if mapId == nil then
        return nil
    end

    local modifier = DensityMapModifier.new(mapId, firstChannel, numChannels, g_terrainNode)
    local densityMapPolygon = thisFarmland.field:getDensityMapPolygon()
    densityMapPolygon:applyToModifier(modifier)

    -- Remaining stones metric:
    -- Based on observed values during testing:
    --   1 = none, 2 = small, 3 = medium, 4 = large, values > 4 represent cleared/picked state.
    -- We compute remaining stones as the area where value equals 2/3/4.
    local filterEq2 = DensityMapFilter.new(modifier)
    filterEq2:setValueCompareParams(DensityValueCompareType.EQUAL, 2)
    local _, area2, totalArea = modifier:executeGet(filterEq2)
    if totalArea == nil or totalArea == 0 then
        return nil
    end

    local filterEq3 = DensityMapFilter.new(modifier)
    filterEq3:setValueCompareParams(DensityValueCompareType.EQUAL, 3)
    local _, area3, _ = modifier:executeGet(filterEq3)

    local filterEq4 = DensityMapFilter.new(modifier)
    filterEq4:setValueCompareParams(DensityValueCompareType.EQUAL, 4)
    local _, area4, _ = modifier:executeGet(filterEq4)

    local remainingArea = (area2 or 0) + (area3 or 0) + (area4 or 0)
    local pct = (remainingArea / totalArea) * 100
    FS25_FarmlandOverview.stoneCoveragePctByFarmlandId[farmlandId] = pct

    return pct
end

-- =========================================================
-- Density map sampling for all-field evaluation (mulch/plow/roll/fert/lime/weeds)
-- =========================================================

local function buildSoilLayerCache()
    local mission = g_currentMission
    if mission == nil or mission.fieldGroundSystem == nil or FieldDensityMap == nil then
        return nil
    end

    local cache = {}

    local function addFgsLayer(key, layerId)
        local mapId, firstChannel, numChannels = mission.fieldGroundSystem:getDensityMapData(layerId)
        if mapId ~= nil and firstChannel ~= nil and numChannels ~= nil then
            cache[key] = {mapId = mapId, firstChannel = firstChannel, numChannels = numChannels, layerId = layerId}
        end
    end

    addFgsLayer("mulch", FieldDensityMap.STUBBLE_SHRED_LEVEL)
    addFgsLayer("plow",  FieldDensityMap.PLOW_LEVEL)
    addFgsLayer("roll",  FieldDensityMap.ROLLER_LEVEL)
    addFgsLayer("spray", FieldDensityMap.SPRAY_LEVEL)
    addFgsLayer("lime",  FieldDensityMap.LIME_LEVEL)

    if mission.fieldGroundSystem.getMaxValue ~= nil then
        if cache.spray ~= nil then
            cache.spray.maxValue = mission.fieldGroundSystem:getMaxValue(FieldDensityMap.SPRAY_LEVEL)
        end
        if cache.lime ~= nil then
            cache.lime.maxValue = mission.fieldGroundSystem:getMaxValue(FieldDensityMap.LIME_LEVEL)
        end
    end

    if mission.weedSystem ~= nil and mission.weedSystem.getMapHasWeed ~= nil
        and mission.weedSystem.getDensityMapData ~= nil
        and mission.weedSystem:getMapHasWeed() then
        local mapId, firstChannel, numChannels = mission.weedSystem:getDensityMapData()
        if mapId ~= nil and firstChannel ~= nil and numChannels ~= nil then
            cache.weed = {mapId = mapId, firstChannel = firstChannel, numChannels = numChannels, maxValue = 9}
        end
    end

    return cache
end

local function buildSoilSamplers(layerCache)
    if layerCache == nil then
        return nil
    end

    local samplers = {}

    local function addSampler(key, layer)
        if layer == nil then
            return
        end
        local modifier = DensityMapModifier.new(layer.mapId, layer.firstChannel, layer.numChannels, g_terrainNode)
        local filter = DensityMapFilter.new(modifier)
        samplers[key] = {modifier = modifier, filter = filter, maxValue = layer.maxValue}
    end

    addSampler("mulch", layerCache.mulch)
    addSampler("plow",  layerCache.plow)
    addSampler("roll",  layerCache.roll)
    addSampler("spray", layerCache.spray)
    addSampler("lime",  layerCache.lime)
    addSampler("weed",  layerCache.weed)

    return samplers
end

local function applyFieldPolygonToModifier(field, modifier)
    if field == nil then
        return nil
    end
    local poly = field:getDensityMapPolygon()
    if poly == nil then
        return nil
    end
    poly:applyToModifier(modifier)
    return poly
end

local function executeAreaForValue(modifier, filter, value)
    filter:setValueCompareParams(DensityValueCompareType.EQUAL, value)
    local _, area, totalArea = modifier:executeGet(filter)
    return area or 0, totalArea or 0
end

local function computePct(area, totalArea)
    if totalArea == nil or totalArea <= 0 then
        return 0
    end
    return (area / totalArea) * 100
end

local function computeDensitySoilStatusForFarmland(thisFarmland, hasCrop, samplers)
    if thisFarmland == nil or thisFarmland.id == nil or thisFarmland.field == nil or samplers == nil then
        return nil
    end

    local field = thisFarmland.field
    local result = {}

    -- Mulch (0/1): use v=1 coverage
    if samplers.mulch ~= nil then
        local modifier = samplers.mulch.modifier
        local filter = samplers.mulch.filter
        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local area1, totalArea = executeAreaForValue(modifier, filter, 1)
            result.mulchPct = computePct(area1, totalArea)
        end
    end

    -- Plow (0/1): use v=1 coverage
    if samplers.plow ~= nil then
        local modifier = samplers.plow.modifier
        local filter = samplers.plow.filter
        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local area1, totalArea = executeAreaForValue(modifier, filter, 1)
            result.plowPct = computePct(area1, totalArea)
        end
    end

    -- Roll (0/1): only applicable if crop exists
    if hasCrop and samplers.roll ~= nil then
        local modifier = samplers.roll.modifier
        local filter = samplers.roll.filter
        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local area1, totalArea = executeAreaForValue(modifier, filter, 1)
            result.rolledPct = computePct(area1, totalArea)
        end
    end

    -- Fertilizer (0/1/2): gating based on "highest present level < 90%"
    if samplers.spray ~= nil then
        local modifier = samplers.spray.modifier
        local filter = samplers.spray.filter
        local maxValue = samplers.spray.maxValue or 2
        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local area2, totalArea = executeAreaForValue(modifier, filter, math.min(2, maxValue))
            local area1, _ = executeAreaForValue(modifier, filter, math.min(1, maxValue))

            local pct2 = computePct(area2, totalArea)
            local pct1 = computePct(area1, totalArea)

            result.fertPct = 0

            if maxValue >= 2 and pct2 >= 90 then
                result.fertPct = 100
            elseif maxValue >= 2 and pct2 > 0 then
                -- second pass in progress; show dominant lower state (0 or 50)
                local area0 = math.max(0, totalArea - area1 - area2)
                if area1 >= area0 then
                    result.fertPct = 50
                else
                    result.fertPct = 0
                end
            else
                -- no v=2 anywhere; first-pass gating on v=1
                if pct1 >= 90 then
                    result.fertPct = 50
                else
                    -- first pass in progress or none; hold at 0 until v=1 completes
                    result.fertPct = 0
                end
            end
        end
    end

    -- Lime (0/1/2/3): if v=3 < 90 and present, ignore v=3 and show dominant among v=0/1/2
    if samplers.lime ~= nil then
        local modifier = samplers.lime.modifier
        local filter = samplers.lime.filter
        local maxValue = samplers.lime.maxValue or 3

        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local area3, totalArea = executeAreaForValue(modifier, filter, math.min(3, maxValue))
            local area2, _ = executeAreaForValue(modifier, filter, math.min(2, maxValue))
            local area1, _ = executeAreaForValue(modifier, filter, math.min(1, maxValue))

            local pct3 = computePct(area3, totalArea)

            result.limePct = 0

            if maxValue >= 3 and pct3 >= 90 then
                result.limePct = 100
            else
                local area0 = math.max(0, totalArea - area1 - area2 - area3)

                if maxValue >= 3 and pct3 > 0 then
                    -- liming in progress; ignore v=3 for "likely previous state"
                    if area2 >= area1 and area2 >= area0 then
                        result.limePct = 66.7
                    elseif area1 >= area0 then
                        result.limePct = 33.3
                    else
                        result.limePct = 0
                    end
                else
                    -- no v=3: show dominant among v=0/1/2
                    if area2 >= area1 and area2 >= area0 then
                        result.limePct = 66.7
                    elseif area1 >= area0 then
                        result.limePct = 33.3
                    else
                        result.limePct = 0
                    end
                end
            end
        end
    end

    -- Weeds: Yes if penalizing coverage (v=3/4/5) is >= 10%
    if samplers.weed ~= nil then
        local modifier = samplers.weed.modifier
        local filter = samplers.weed.filter
        if applyFieldPolygonToModifier(field, modifier) ~= nil then
            local filter = DensityMapFilter.new(modifier)
            local area3, totalArea = executeAreaForValue(modifier, filter, 3)
            local area4, _ = executeAreaForValue(modifier, filter, 4)
            local area5, _ = executeAreaForValue(modifier, filter, 5)

            local penalizingArea = area3 + area4 + area5
            local penalizingPct = computePct(penalizingArea, totalArea)
            result.weedsPenalizingPct = penalizingPct

            -- Yield-factor mapping (based on your verified AFI/HUD observations):
            --   Small      => 0.5
            --   SmallDense => 0.75
            --   Large      => 1.0
            -- Anything below 10% penalizing coverage counts as 0.
            result.weedYieldFactor = 0
            if penalizingPct >= 10 then
                if area5 >= area4 and area5 >= area3 then
                    result.weedYieldFactor = 1.0
                elseif area4 >= area3 then
                    result.weedYieldFactor = 0.75
                else
                    result.weedYieldFactor = 0.5
                end
            end
        end
    end

    return result
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

    -- Density-map approach: clear derived caches each open so values reflect current world state.
    if FS25_FarmlandOverview ~= nil and FS25_FarmlandOverview.stoneCoveragePctByFarmlandId ~= nil then
        FS25_FarmlandOverview.stoneCoveragePctByFarmlandId = {}
    end

	-- Fill data structure
    -- Build list and precompute sortable values
    self.farmlands = {}

    -- Density layer cache is built once per dialog open to minimize engine calls.
    local soilLayerCache = buildSoilLayerCache()
    self._soilSamplers = buildSoilSamplers(soilLayerCache)
    self._soilQueueIndex = 1
    self._soilReloadTimer = 0
    self._soilDirty = false
    self._soilBatchSize = (FS25_FarmlandOverview ~= nil and FS25_FarmlandOverview.soilLazyBatchSize) or 3

    -- Game settings (can be changed mid-save). Re-read each time the dialog opens.
    self._yieldSettings = {
        plowingRequiredEnabled = true,
        limeRequired = true,
        weedsEnabled = true
    }

    local mi = (g_currentMission ~= nil) and g_currentMission.missionInfo or nil
    if mi ~= nil then
        if mi.plowingRequiredEnabled ~= nil then
            self._yieldSettings.plowingRequiredEnabled = mi.plowingRequiredEnabled
        end
        if mi.limeRequired ~= nil then
            self._yieldSettings.limeRequired = mi.limeRequired
        end
        if mi.weedsEnabled ~= nil then
            self._yieldSettings.weedsEnabled = mi.weedsEnabled
        end
    end

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
					entry.fruitTypeIndex = fruitTypeIndexPos
                else
                    entry.cropName = "--"
					entry.fruitTypeIndex = nil
                end
            else
                entry.fieldArea = nil
                entry.cropName = "--"
				entry.fruitTypeIndex = nil
            end

            table.insert(self.farmlands, entry)
        end
    end

    -- Apply sort: primary by owner (sectionOrder), secondary according to selected column
    self:applySorting()

    -- Lazy-load soil status to avoid long dialog open hitches on large maps.
    -- We compute the first screen worth immediately, then process the rest in update().
    if self._soilSamplers ~= nil then
        local total = #self.farmlands
        local initialCount = math.min(total, 20)

        for i = 1, initialCount do
            local e = self.farmlands[i]
            e.hasCrop = (e.cropName ~= "--")
            e.soilStatus = computeDensitySoilStatusForFarmland(e.farmland, e.hasCrop, self._soilSamplers)
        end

        self._soilQueueIndex = initialCount + 1
        self._soilDirty = true
    end

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

        -- Localized Yes/No for status columns
        local textYes = g_i18n:getText("ui_fieldDlg_valYes")
        if textYes == nil or textYes == "ui_fieldDlg_valYes" then
            textYes = "Yes"
        end
        local textNo = g_i18n:getText("ui_fieldDlg_valNo")
        if textNo == nil or textNo == "ui_fieldDlg_valNo" then
            textNo = "No"
        end

        -- Localized "Ready" prefix for crop state
        local readyLabel = g_i18n:getText("ui_fieldDlg_stateReady")
        if readyLabel == nil or readyLabel == "ui_fieldDlg_stateReady" then
            readyLabel = "Ready"
        end

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
            cell:getAttribute("fieldCropState").textColor = cell:getAttribute("fieldCrop").textColor

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
                    cell:getAttribute("fieldCropState"):setTextColor(1, 0, 0, 1)
                elseif maxGrowthState == withered then
                    fruitStatePos = g_i18n:getText("ui_growthMapWithered")
                elseif maxGrowthState > 0 and maxGrowthState <= maxGrowing then
                    fruitStatePos = g_i18n:getText("ui_growthMapGrowing") .. " (" .. tostring(maxGrowthState) .. " / " .. tostring(maxHarvest) .. ")"
                elseif fruitTypePos.minPreparingGrowthState >= 0
                    and fruitTypePos.minPreparingGrowthState <= maxGrowthState
                    and maxGrowthState <= fruitTypePos.maxPreparingGrowthState then
                    -- preparing for harvest is NOT harvestable yet
                    fruitStatePos = g_i18n:getText("ui_growthMapGrowing")
                        .. " (" .. tostring(maxGrowthState) .. " / " .. tostring(maxHarvest) .. ")"
                elseif minHarvest <= maxGrowthState and maxGrowthState <= maxHarvest then
                    fruitStatePos = readyLabel .. " (" .. tostring(maxGrowthState) .. " / " .. tostring(maxHarvest) .. ")"
                    if maxGrowthState < maxHarvest then
                        cell:getAttribute("fieldCropState"):setTextColor(1, 1, 0, 1) -- yellow: harvestable, not max
                    else
                        cell:getAttribute("fieldCropState"):setTextColor(0, 1, 0, 1) -- green: max growth
                    end
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
            -- YIELD (engine-calculated harvest multiplier via HUD cache)
            local yieldAttr = cell:getAttribute("fieldYield")
            if yieldAttr ~= nil then
                local yieldText = "--"
                yieldAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                local multiplier = nil

                -- Engine-based multiplier (7 args, verified by probe):
                --   (fruitTypeIndex, fertF, plowF, limeF, weedBonusF, bonusA, bonusB)
                -- bonusA/bonusB are two independent +2.5% flags (order doesn't matter for the total).
                if g_currentMission ~= nil
                    and g_currentMission.getHarvestScaleMultiplier ~= nil
                    and entry ~= nil
                    and entry.fruitTypeIndex ~= nil
                    and entry.soilStatus ~= nil then

                    local ss = entry.soilStatus

                    -- Fertilizer: 0/50/100 already determined by your density gating logic
                    local sprayF = (ss.fertPct or 0) / 100

                    -- Plow: use your density-map yes/no (>=90 => 1 else 0)
                    local plowF = ((ss.plowPct or 0) >= 90) and 1 or 0

                    -- Lime: 0 / 33.3 / 66.7 / 100 -> normalize to 0..1
                    local limeF = (ss.limePct or 0) / 100

                    -- Weeds: density-derived *penalty* factor mapping (0 / 0.5 / 0.75 / 1)
                    local weedPenaltyF = ss.weedYieldFactor or 0
                    -- Engine expects a WEED-BONUS factor (1.0 = full +20%, 0.0 = no weeds bonus)
                    local weedBonusF = math.max(0, math.min(1, 1 - weedPenaltyF))

                    -- Honor game settings (can be toggled mid-save)
                    local ys = self._yieldSettings
                    if ys ~= nil then
                        if ys.plowingRequiredEnabled == false then
                            plowF = 1
                        end
                        if ys.limeRequired == false then
                            limeF = 1
                        end
                        if ys.weedsEnabled == false then
                            weedBonusF = 1
                        end
                    end

                    -- Engine expects a WEED-BONUS factor (1.0 = no penalty / full +20%, 0.0 = full penalty)
                    local weedBonusF = math.max(0, math.min(1, 1 - weedPenaltyF))

                    -- Two independent +2.5% bonuses:
                    -- Mulch bonus applies if mulch coverage >= 90%
                    local mulchFlag = ((ss.mulchPct or 0) >= 90) and 1 or 0

                    -- Roll bonus applies only when crop state is Ready or Growing; otherwise "--" in table,
                    -- but for yield we simply treat it as not applicable (0).
                    local growingLabel = g_i18n:getText("ui_growthMapGrowing")
                    local isGrowing = (fruitStatePos ~= nil)
                        and string.sub(fruitStatePos, 1, string.len(growingLabel)) == growingLabel
                    local isReady = (fruitStatePos ~= nil)
                        and string.sub(fruitStatePos, 1, string.len(readyLabel)) == readyLabel
                    local rollApplicable = entry.hasCrop and (isGrowing or isReady)
                    -- Note: roll density layer stores "needs rolling" coverage (rolledPct). Bonus applies when needsRollingPct is low.
                    local rollFlag = (rollApplicable and (ss.rolledPct or 0) <= 10) and 1 or 0

                    local ok, res = pcall(g_currentMission.getHarvestScaleMultiplier, g_currentMission,
                        entry.fruitTypeIndex, sprayF, plowF, limeF, weedBonusF, mulchFlag, rollFlag)
                    if ok and type(res) == "number" then
                        multiplier = res
                    end
                end

                if multiplier ~= nil then
                    local bonus = (multiplier - 1.0) * 100.0

                    if bonus >= 0 then
                        yieldText = string.format("+%.1f%%", bonus)
                    else
                        yieldText = string.format("%.1f%%", bonus)
                    end

                    if bonus > 0 then
                        yieldAttr:setTextColor(0.1, 0.8, 0.1, 1.0)
                    elseif bonus < 0 then
                        yieldAttr:setTextColor(0.9, 0.2, 0.2, 1.0)
                    end
                end

                yieldAttr:setText(yieldText)
            end

            -- Mulched (density map)
            local mulchedAttr = cell:getAttribute("fieldMulched")
            if mulchedAttr ~= nil then
                local t = "--"
                mulchedAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                if entry.soilStatus ~= nil and entry.soilStatus.mulchPct ~= nil then
                    if entry.soilStatus.mulchPct >= 90 then
                        t = textYes
                        mulchedAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    else
                        t = textNo
                        mulchedAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    end
                end

                mulchedAttr:setText(t)
            end

            -- Plowed (density map)
            local plowedAttr = cell:getAttribute("fieldPlowed")
            if plowedAttr ~= nil then
			    local ys = self._yieldSettings
                local t = "--"
                plowedAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                -- If periodic plowing is disabled in game settings, show "--"
                if ys ~= nil and ys.plowingRequiredEnabled == false then
                    -- keep default "--" + default color
                elseif entry.soilStatus ~= nil and entry.soilStatus.plowPct ~= nil then
                    if entry.soilStatus.plowPct >= 90 then
                        t = textYes
                        plowedAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    else
                        t = textNo
                        plowedAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    end
                end

                plowedAttr:setText(t)
            end

            -- Rolled (density map; only applicable for Growing(X/Y) or Ready(X/Y))
            local rolledAttr = cell:getAttribute("fieldRolled")
            if rolledAttr ~= nil then
                local t = "--"
                rolledAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                local growingLabel = g_i18n:getText("ui_growthMapGrowing")
                local isGrowing = (fruitStatePos ~= nil)
                    and string.sub(fruitStatePos, 1, string.len(growingLabel)) == growingLabel
                local isReady = (fruitStatePos ~= nil)
                    and string.sub(fruitStatePos, 1, string.len(readyLabel)) == readyLabel

                if (isGrowing or isReady) then
                    if entry.hasCrop then
                        if entry.soilStatus ~= nil and entry.soilStatus.rolledPct ~= nil then
                            if entry.soilStatus.rolledPct >= 90 then
                                    t = textNo
                                    rolledAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                            else
                                t = textYes
                                rolledAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                            end
                        end
					end
                end

                rolledAttr:setText(t)
            end

            -- Fertilized (density map; 0/50/100 with 90% gating)
            local fertAttr = cell:getAttribute("fieldFert")
            if fertAttr ~= nil then
                local t = "--"
                fertAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                if entry.soilStatus ~= nil and entry.soilStatus.fertPct ~= nil then
                    local pct = entry.soilStatus.fertPct
                    if pct == 0 then
                        t = "0%"
                        fertAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    elseif pct == 50 then
                        t = "50%"
                        fertAttr:setTextColor(1.0, 1.0, 0.0, 1.0)
                    elseif pct == 100 then
                        t = "100%"
                        fertAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    end
                end

                fertAttr:setText(t)
            end

            -- Stones
            local stonesAttr = cell:getAttribute("fieldStones")
            if stonesAttr ~= nil then
                local t = "--"
                stonesAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                local pct = nil
                if thisFarmland ~= nil and thisFarmland.id ~= nil then
                    pct = FS25_FarmlandOverview.stoneCoveragePctByFarmlandId[thisFarmland.id]
                end
                if pct == nil then
                    pct = getStoneCoveragePctForFarmland(thisFarmland)
                end

                if pct ~= nil then
                    if pct < 0.1 then
                        t = textNo
                        stonesAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    else
                        t = textYes
                        stonesAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    end
                end

                stonesAttr:setText(t)
            end

            -- Weeds (density map; Yes if penalizing coverage >= 10%)
            local weedsAttr = cell:getAttribute("fieldWeeds")
            if weedsAttr ~= nil then
			    local ys = self._yieldSettings
                local t = "--"
                weedsAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                -- If weeds are disabled in game settings, show "--"
                if ys ~= nil and ys.weedsEnabled == false then
                    -- keep default "--" + default color
                elseif entry.soilStatus ~= nil and entry.soilStatus.weedsPenalizingPct ~= nil then
                    if entry.soilStatus.weedsPenalizingPct >= 10 then
                        t = textYes
                        weedsAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    else
                        t = textNo
                        weedsAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    end
                end

                weedsAttr:setText(t)
            end

            -- Lime (density map; 0.0 / 33.3 / 66.7 / 100 with dominant lower-state during application)
            local limeAttr = cell:getAttribute("fieldLime")
            if limeAttr ~= nil then
			    local ys = self._yieldSettings
                local t = "--"
                limeAttr:setTextColor(1.0, 1.0, 1.0, 1.0)

                -- If lime is disabled in game settings, show "--"
                if ys ~= nil and ys.limeRequired == false then
                    -- keep default "--" + default color
                elseif entry.soilStatus ~= nil and entry.soilStatus.limePct ~= nil then
                    local pct = entry.soilStatus.limePct
                    if pct == 0 then
                        t = "0.0%"
                        limeAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    elseif pct == 33.3 then
                        t = "33.3%"
                        limeAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    elseif pct == 66.7 then
                        t = "66.7%"
                        limeAttr:setTextColor(1.0, 0.0, 0.0, 1.0)
                    elseif pct == 100 then
                        t = "100%"
                        limeAttr:setTextColor(0.0, 1.0, 0.0, 1.0)
                    end
                end

                limeAttr:setText(t)
            end
        else
            cell:getAttribute("fieldAreaHa"):setText("--")
            cell:getAttribute("fieldCrop"):setText("--")
            cell:getAttribute("fieldCropState"):setText("--")
            cell:getAttribute("fieldCropState").textColor = cell:getAttribute("fieldCrop").textColor
            cell:getAttribute("ftIcon"):setVisible(false)

            local yieldAttr = cell:getAttribute("fieldYield")
            if yieldAttr ~= nil then
                yieldAttr:setText("--")
                yieldAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local mulchedAttr = cell:getAttribute("fieldMulched")
            if mulchedAttr ~= nil then
                mulchedAttr:setText("--")
                mulchedAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local plowedAttr = cell:getAttribute("fieldPlowed")
            if plowedAttr ~= nil then
                plowedAttr:setText("--")
                plowedAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local rolledAttr = cell:getAttribute("fieldRolled")
            if rolledAttr ~= nil then
                rolledAttr:setText("--")
                rolledAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local fertAttr = cell:getAttribute("fieldFert")
            if fertAttr ~= nil then
                fertAttr:setText("--")
                fertAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local stonesAttr = cell:getAttribute("fieldStones")
            if stonesAttr ~= nil then
                stonesAttr:setText("--")
                stonesAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local weedsAttr = cell:getAttribute("fieldWeeds")
            if weedsAttr ~= nil then
                weedsAttr:setText("--")
                weedsAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end

            local limeAttr = cell:getAttribute("fieldLime")
            if limeAttr ~= nil then
                limeAttr:setText("--")
                limeAttr:setTextColor(1.0, 1.0, 1.0, 1.0)
            end
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
    self._soilSamplers = nil
    self._soilQueueIndex = nil
    self._soilReloadTimer = nil
    self._soilDirty = nil
	FieldDlgFrame:superClass().onClose(self)
end

function FieldDlgFrame:update(dt)
    FieldDlgFrame:superClass().update(self, dt)

    if self._soilSamplers == nil or self._soilQueueIndex == nil then
        return
    end

    local total = #self.farmlands
    if self._soilQueueIndex > total then
        return
    end

    local processed = 0
    local batchSize = self._soilBatchSize or 3

    while self._soilQueueIndex <= total and processed < batchSize do
        local e = self.farmlands[self._soilQueueIndex]
        if e ~= nil and e.soilStatus == nil then
            e.hasCrop = (e.cropName ~= "--")
            e.soilStatus = computeDensitySoilStatusForFarmland(e.farmland, e.hasCrop, self._soilSamplers)
            self._soilDirty = true
        end

        self._soilQueueIndex = self._soilQueueIndex + 1
        processed = processed + 1
    end

    if self._soilDirty then
        self._soilReloadTimer = (self._soilReloadTimer or 0) + dt
        if self._soilReloadTimer >= 200 then
            self._soilReloadTimer = 0
            self._soilDirty = false
            self.overviewTable:reloadData()
        end
    end
end

function FieldDlgFrame:onClickBack(sender)
	dbPrintf("FieldDlgFrame:onClickBack()")
	self:close()
end

