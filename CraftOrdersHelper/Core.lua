local addonName, CraftHelper = ...;
_G.CraftHelper = CraftHelper;

local CRAFT_ORDER_SOURCE = "craftorders";
local PROFESSION_FAVORITE_SOURCE = "profession_favorites";
local PROFESSION_TRACKED_SOURCE = "profession_tracked";
local PROFESSION_RECIPE_SCAN_MODES = { false, true };

local function SafeGetItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID);
    end
    return GetItemInfo(itemID);
end

local function SafeRegisterEvent(frame, event)
    pcall(frame.RegisterEvent, frame, event);
end

local function GetRecipeSchematic(recipeID, isRecraft)
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipeSchematic then
        return nil;
    end

    local ok, recipeSchematic = pcall(C_TradeSkillUI.GetRecipeSchematic, recipeID, isRecraft or false);
    if ok then
        return recipeSchematic;
    end
    return nil;
end

local function BuildReagentsFromSchematic(recipeSchematic)
    local reagents = {};
    if not recipeSchematic or not recipeSchematic.reagentSlotSchematics then
        return reagents;
    end

    for _, slot in ipairs(recipeSchematic.reagentSlotSchematics) do
        if slot.reagentType ~= Enum.CraftingReagentType.Finishing then
            local isRequired = slot.required;
            local isBasic = slot.reagentType == Enum.CraftingReagentType.Basic;

            if isRequired or isBasic then
                local reagentList = slot.reagents or {};
                local isQualitySlot = #reagentList > 1;

                if isQualitySlot then
                    local qualityItemIDs = {};
                    local qualityNames = {};
                    local qualityIcons = {};
                    for _, reagent in ipairs(reagentList) do
                        if reagent and reagent.itemID then
                            local itemName, _, _, _, _, _, _, _, _, itemIcon = SafeGetItemInfo(reagent.itemID);
                            if not itemName then
                                itemName = "Item " .. reagent.itemID;
                                itemIcon = 134400;
                            end
                            table.insert(qualityItemIDs, reagent.itemID);
                            table.insert(qualityNames, itemName);
                            table.insert(qualityIcons, itemIcon);
                        end
                    end

                    table.insert(reagents, {
                        isQualitySlot = true,
                        qualityItemIDs = qualityItemIDs,
                        qualityNames = qualityNames,
                        qualityIcons = qualityIcons,
                        name = qualityNames[1] or "Unknown",
                        icon = qualityIcons[1] or 134400,
                        quantityRequired = slot.quantityRequired or 1,
                    });
                elseif #reagentList >= 1 then
                    local reagent = reagentList[1];
                    if reagent and reagent.itemID then
                        local itemName, _, _, _, _, _, _, _, _, itemIcon = SafeGetItemInfo(reagent.itemID);
                        if not itemName then
                            itemName = "Item " .. reagent.itemID;
                            itemIcon = 134400;
                        end

                        table.insert(reagents, {
                            isQualitySlot = false,
                            itemID = reagent.itemID,
                            name = itemName,
                            icon = itemIcon,
                            quantityRequired = slot.quantityRequired or 1,
                        });
                    end
                end
            end
        end
    end

    return reagents;
end

CraftHelper.events = CreateFrame("Frame");
CraftHelper.events:SetScript("OnEvent", function(_, event, ...)
    if CraftHelper[event] then
        CraftHelper[event](CraftHelper, ...);
    end
end);

function CraftHelper:OnLoad()
    self.pendingProfessionRecipes = {};
    self.professionRecipeScanModes = PROFESSION_RECIPE_SCAN_MODES;
    SafeRegisterEvent(self.events, "ADDON_LOADED");
    SafeRegisterEvent(self.events, "BAG_UPDATE");
    SafeRegisterEvent(self.events, "PLAYER_LOGIN");
    SafeRegisterEvent(self.events, "PLAYER_ENTERING_WORLD");
    SafeRegisterEvent(self.events, "CRAFTINGORDERS_CUSTOMER_FAVORITES_CHANGED");
    SafeRegisterEvent(self.events, "TRACKED_RECIPE_UPDATE");
    SafeRegisterEvent(self.events, "TRADE_SKILL_FAVORITES_CHANGED");
    SafeRegisterEvent(self.events, "TRADE_SKILL_DATA_SOURCE_CHANGED");
    SafeRegisterEvent(self.events, "TRADE_SKILL_DETAILS_UPDATE");
    SafeRegisterEvent(self.events, "TRADE_SKILL_LIST_UPDATE");
    SafeRegisterEvent(self.events, "TRADE_SKILL_SHOW");
end

function CraftHelper:ADDON_LOADED(addon)
    if addon == addonName then
        self.Data:Init();
        self.UI:Init();
        C_Timer.After(2, function()
            self:ScanExistingFavorites();
            self:ScheduleProfessionRecipeScan();
        end);
    elseif addon == "Blizzard_ProfessionsCustomerOrders" then
        self:TryHookCraftingForm();
    elseif addon == "Blizzard_Professions" then
        self:ScheduleProfessionRecipeScan();
    end
end

function CraftHelper:PLAYER_LOGIN()
    self:TryHookCraftingForm();
    self.Data:ScanBags();
    self:ScheduleProfessionRecipeScan();
    self.UI:Refresh();
end

function CraftHelper:PLAYER_ENTERING_WORLD()
    if not self.UI.ahMode then
        self.UI:DetectAndAttachToAuctionHouse();
    end
    self:ScheduleProfessionRecipeScan();
end

function CraftHelper:BAG_UPDATE()
    self.Data:ScanBags();
    if self.UI.frame and self.UI.frame:IsShown() then
        self.UI:Refresh();
    end
end

function CraftHelper:CRAFTINGORDERS_CUSTOMER_FAVORITES_CHANGED()
    self:ScanExistingFavorites();
end

function CraftHelper:TRACKED_RECIPE_UPDATE(recipeID, tracked)
    if tracked then
        self:QueueProfessionRecipe(recipeID, false, PROFESSION_TRACKED_SOURCE);
        self:QueueProfessionRecipe(recipeID, true, PROFESSION_TRACKED_SOURCE);
    else
        if self:IsProfessionRecipeTracked(recipeID) then
            self:QueueProfessionRecipe(recipeID, false, PROFESSION_TRACKED_SOURCE);
            self:QueueProfessionRecipe(recipeID, true, PROFESSION_TRACKED_SOURCE);
        else
            self.Data:RemoveRecipe(recipeID, PROFESSION_TRACKED_SOURCE);
            self.UI:Refresh();
        end
    end
end

function CraftHelper:TRADE_SKILL_FAVORITES_CHANGED(isFavorite, recipeID)
    if not recipeID then
        self:ScheduleProfessionRecipeScan();
        return;
    end

    if isFavorite then
        self:QueueProfessionRecipe(recipeID, false, PROFESSION_FAVORITE_SOURCE);
    else
        self.Data:RemoveRecipe(recipeID, PROFESSION_FAVORITE_SOURCE);
        self.UI:Refresh();
    end
end

CraftHelper["TRADE_SKILL_DATA_SOURCE_CHANGED"] = function(self)
    self:ScheduleProfessionRecipeScan();
end

CraftHelper["TRADE_SKILL_DETAILS_UPDATE"] = function(self)
    self:ScheduleProfessionRecipeScan();
end

CraftHelper["TRADE_SKILL_LIST_UPDATE"] = function(self)
    self:ScheduleProfessionRecipeScan();
end

CraftHelper["TRADE_SKILL_SHOW"] = function(self)
    self:ScheduleProfessionRecipeScan();
end

-- ---------------------------------------------------------------------------
-- Scan existing favorites via API
-- ---------------------------------------------------------------------------
function CraftHelper:ScanExistingFavorites()
    if not C_CraftingOrders or not C_CraftingOrders.GetCustomerOptions then
        return;
    end

    local ok, results = pcall(function()
        return C_CraftingOrders.GetCustomerOptions({
            categoryFilters = {},
            searchText = nil,
            minLevel = 0,
            maxLevel = 0,
            uncollectedOnly = false,
            usableOnly = false,
            upgradesOnly = false,
            currentExpansionOnly = false,
            includePoor = true,
            includeCommon = true,
            includeUncommon = true,
            includeRare = true,
            includeEpic = true,
            includeLegendary = true,
            includeArtifact = true,
            isFavoritesSearch = true,
        });
    end);

    if not ok or not results or not results.options then
        return;
    end

    for _, option in ipairs(results.options) do
        if option.spellID then
            self:CaptureRecipeFromSpellID(option.spellID, option.itemName, false, CRAFT_ORDER_SOURCE);
        end
    end
    self.UI:Refresh();
end

-- ---------------------------------------------------------------------------
-- Scan current profession favorites and tracked profession recipes
-- ---------------------------------------------------------------------------
function CraftHelper:ScanProfessionRecipes()
    local shouldRefresh = false;

    if self:ScanProfessionFavorites() then
        shouldRefresh = true;
    end
    if self:ScanTrackedRecipes() then
        shouldRefresh = true;
    end

    if shouldRefresh then
        self.UI:Refresh();
    end
end

function CraftHelper:ScanProfessionFavorites()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetAllRecipeIDs or not C_TradeSkillUI.IsRecipeFavorite then
        return false;
    end

    local ok, recipeIDs = pcall(C_TradeSkillUI.GetAllRecipeIDs);
    if not ok or type(recipeIDs) ~= "table" then
        return false;
    end

    local foundCurrentProfession = false;
    for _, recipeID in ipairs(recipeIDs) do
        foundCurrentProfession = true;
        local favoriteOk, isFavorite = pcall(C_TradeSkillUI.IsRecipeFavorite, recipeID);
        if favoriteOk then
            if isFavorite then
                self:QueueProfessionRecipe(recipeID, false, PROFESSION_FAVORITE_SOURCE);
            else
                self.Data:RemoveRecipe(recipeID, PROFESSION_FAVORITE_SOURCE);
            end
        end
    end

    return foundCurrentProfession;
end

function CraftHelper:ScanTrackedRecipes()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then
        return false;
    end

    local foundTracked = false;
    for _, isRecraft in ipairs(self.professionRecipeScanModes or { false, true }) do
        local ok, tracked = pcall(C_TradeSkillUI.GetRecipesTracked, isRecraft);
        if ok and tracked then
            foundTracked = true;
            for _, recipeID in ipairs(tracked) do
                self:QueueProfessionRecipe(recipeID, isRecraft, PROFESSION_TRACKED_SOURCE);
            end
        end
    end

    return foundTracked;
end

function CraftHelper:ScheduleProfessionRecipeScan()
    if self.professionRecipeScanScheduled then
        return;
    end

    self.professionRecipeScanScheduled = true;
    C_Timer.After(0.5, function()
        CraftHelper.professionRecipeScanScheduled = false;
        CraftHelper:ScanProfessionRecipes();
    end);
end

function CraftHelper:ScheduleTrackedRecipeScan()
    self:ScheduleProfessionRecipeScan();
end

function CraftHelper:IsProfessionRecipeTracked(recipeID)
    if not C_TradeSkillUI or not C_TradeSkillUI.IsRecipeTracked then
        return false;
    end

    for _, isRecraft in ipairs(self.professionRecipeScanModes or { false, true }) do
        local ok, isTracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, isRecraft);
        if ok and isTracked then
            return true;
        end
    end

    return false;
end

function CraftHelper:QueueProfessionRecipe(recipeID, isRecraft, source)
    if not recipeID then
        return;
    end

    local normalizedSource = source or PROFESSION_TRACKED_SOURCE;
    if normalizedSource == PROFESSION_TRACKED_SOURCE and C_TradeSkillUI and C_TradeSkillUI.IsRecipeTracked then
        local ok, isTracked = pcall(C_TradeSkillUI.IsRecipeTracked, recipeID, isRecraft or false);
        if ok and not isTracked then
            return;
        end
    end

    local key = tostring(recipeID) .. ":" .. tostring(isRecraft or false) .. ":" .. normalizedSource;
    if not self.pendingProfessionRecipes[key] then
        self.pendingProfessionRecipes[key] = {
            recipeID = recipeID,
            isRecraft = isRecraft or false,
            source = normalizedSource,
            attempts = 0,
        };
    end

    self:SchedulePendingProfessionRecipes();
end

function CraftHelper:SchedulePendingProfessionRecipes()
    if self.pendingProfessionRecipesScheduled then
        return;
    end

    self.pendingProfessionRecipesScheduled = true;
    C_Timer.After(0.5, function()
        CraftHelper.pendingProfessionRecipesScheduled = false;
        CraftHelper:ProcessPendingProfessionRecipes();
    end);
end

function CraftHelper:ProcessPendingProfessionRecipes()
    local hasPending = false;
    local changed = false;

    for key, entry in pairs(self.pendingProfessionRecipes) do
        entry.attempts = entry.attempts + 1;

        if self:CaptureRecipeFromSpellID(entry.recipeID, nil, entry.isRecraft, entry.source) then
            self.pendingProfessionRecipes[key] = nil;
            changed = true;
        elseif entry.attempts >= 20 then
            self.pendingProfessionRecipes[key] = nil;
        else
            hasPending = true;
        end
    end

    if changed then
        self.UI:Refresh();
    end
    if hasPending then
        self:SchedulePendingProfessionRecipes();
    end
end

-- ---------------------------------------------------------------------------
-- Capture reagents (quality slots capture ALL variants)
-- ---------------------------------------------------------------------------
function CraftHelper:CaptureRecipeFromSpellID(spellID, fallbackName, isRecraft, source)
    local recipeSchematic = GetRecipeSchematic(spellID, isRecraft or false);
    if not recipeSchematic then
        return false;
    end

    local reagents = BuildReagentsFromSchematic(recipeSchematic);

    self.Data:SaveRecipe(
        spellID,
        recipeSchematic.name or fallbackName or ("Recipe " .. spellID),
        reagents,
        isRecraft or false,
        source or "unknown"
    );

    return true;
end

-- ---------------------------------------------------------------------------
-- Hook into Crafting Order form
-- ---------------------------------------------------------------------------
function CraftHelper.TryHookCraftingForm()
    if not ProfessionsCustomerOrderFormMixin then
        return false;
    end
    if ProfessionsCustomerOrderFormMixin.CraftHelperHooked then
        return true;
    end

    local originalInit = ProfessionsCustomerOrderFormMixin.Init;
    ProfessionsCustomerOrderFormMixin.Init = function(form, order, ...)
        local result = {originalInit(form, order, ...)};
        CraftHelper:OnCraftingFormInit(form, order);
        return unpack(result);
    end

    ProfessionsCustomerOrderFormMixin.CraftHelperHooked = true;
    return true;
end

function CraftHelper:OnCraftingFormInit(form, order)
    if not order or not order.spellID then
        return;
    end

    local recipeSchematic = GetRecipeSchematic(order.spellID, order.isRecraft or false);
    if not recipeSchematic then
        return;
    end

    local reagents = BuildReagentsFromSchematic(recipeSchematic);

    form.CraftHelperReagents = reagents;
    form.CraftHelperRecipeName = recipeSchematic.name;
    form.CraftHelperSpellID = order.spellID;
    form.CraftHelperIsRecraft = order.isRecraft or false;

    if form.FavoriteButton then
        if form.FavoriteButton:GetChecked() and not self.Data.db.recipes[order.spellID] then
            self:OnRecipeFavorited(form);
        end

        if not form.FavoriteButton.CraftHelperHooked then
            local originalOnClick = form.FavoriteButton:GetScript("OnClick");
            form.FavoriteButton:SetScript("OnClick", function(button, ...)
                if originalOnClick then
                    originalOnClick(button, ...);
                end

                if button:GetChecked() then
                    CraftHelper:OnRecipeFavorited(form);
                else
                    CraftHelper:OnRecipeUnfavorited(form);
                end
            end);
            form.FavoriteButton.CraftHelperHooked = true;
        end
    end
end

function CraftHelper:OnRecipeFavorited(form)
    if not form.CraftHelperSpellID or not form.CraftHelperReagents then
        return;
    end

    self.Data:SaveRecipe(
        form.CraftHelperSpellID,
        form.CraftHelperRecipeName,
        form.CraftHelperReagents,
        form.CraftHelperIsRecraft,
        CRAFT_ORDER_SOURCE
    );

    self.UI:Refresh();
end

function CraftHelper:OnRecipeUnfavorited(form)
    if not form.CraftHelperSpellID then
        return;
    end

    self.Data:RemoveRecipe(form.CraftHelperSpellID, CRAFT_ORDER_SOURCE);
    self.UI:Refresh();
end

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
function CraftHelper.Print(_, msg)
    print("|cFF00FF00CraftOrdersHelper|r: " .. tostring(msg));
end

SLASH_CRAFTHELPER1 = "/crafthelper";
SLASH_CRAFTHELPER2 = "/ch";
SlashCmdList["CRAFTHELPER"] = function(msg)
    if msg == "debug" then
        CraftHelper:PrintDebugInfo();
        return;
    end
    if CraftHelper.UI.frame then
        if CraftHelper.UI.frame:IsShown() then
            CraftHelper.UI.frame:Hide();
        else
            CraftHelper.UI.frame:Show();
            CraftHelper.UI:Refresh();
        end
    end
end

function CraftHelper:PrintDebugInfo()
    local count = self.Data:GetRecipeCount();
    self:Print("Saved recipes: " .. count);
    self:Print("View: " .. self.Data:GetViewCharacter() .. " | Source: " .. self.Data:GetViewSource());
end

-- Start up
CraftHelper:OnLoad();
