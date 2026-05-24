local addonName, CraftHelper = ...;
_G.CraftHelper = CraftHelper;

local function SafeGetItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID);
    end
    return GetItemInfo(itemID);
end

CraftHelper.events = CreateFrame("Frame");
CraftHelper.events:SetScript("OnEvent", function(self, event, ...)
    if CraftHelper[event] then
        CraftHelper[event](CraftHelper, ...);
    end
end);

function CraftHelper:OnLoad()
    self.events:RegisterEvent("ADDON_LOADED");
    self.events:RegisterEvent("BAG_UPDATE");
    self.events:RegisterEvent("PLAYER_LOGIN");
    self.events:RegisterEvent("PLAYER_ENTERING_WORLD");
    self.events:RegisterEvent("CRAFTINGORDERS_CUSTOMER_FAVORITES_CHANGED");
    self.events:RegisterEvent("TRACKED_RECIPE_UPDATE");
end

function CraftHelper:ADDON_LOADED(addon)
    if addon == addonName then
        self.Data:Init();
        self.UI:Init();
        C_Timer.After(2, function()
            self:ScanExistingFavorites();
            self:ScanTrackedRecipes();
        end);
    elseif addon == "Blizzard_ProfessionsCustomerOrders" then
        self:TryHookCraftingForm();
    end
end

function CraftHelper:PLAYER_LOGIN()
    self:TryHookCraftingForm();
    self.Data:ScanBags();
    self.UI:Refresh();
end

function CraftHelper:PLAYER_ENTERING_WORLD()
    if not self.UI.ahMode then
        self.UI:DetectAndAttachToAuctionHouse();
    end
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
        local success = self:CaptureRecipeFromSpellID(recipeID, nil, false, "professions");
        if success then
            self.UI:Refresh();
        end
    else
        self.Data:RemoveRecipe(recipeID);
        self.UI:Refresh();
    end
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
            if not self.Data.db.recipes[option.spellID] then
                self:CaptureRecipeFromSpellID(option.spellID, option.itemName, false, "craftorders");
            end
        end
    end
    self.UI:Refresh();
end

-- ---------------------------------------------------------------------------
-- Scan currently tracked profession recipes
-- ---------------------------------------------------------------------------
function CraftHelper:ScanTrackedRecipes()
    if not C_TradeSkillUI or not C_TradeSkillUI.GetRecipesTracked then
        return;
    end

    local ok, tracked = pcall(C_TradeSkillUI.GetRecipesTracked);
    if not ok or not tracked then
        return;
    end

    for _, recipeID in ipairs(tracked) do
        if not self.Data.db.recipes[recipeID] then
            self:CaptureRecipeFromSpellID(recipeID, nil, false, "professions");
        end
    end
    self.UI:Refresh();
end

-- ---------------------------------------------------------------------------
-- Capture reagents (quality slots capture ALL variants)
-- ---------------------------------------------------------------------------
function CraftHelper:CaptureRecipeFromSpellID(spellID, fallbackName, isRecraft, source)
    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(spellID, isRecraft or false);
    if not recipeSchematic then
        return false;
    end

    local reagents = {};
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
function CraftHelper:TryHookCraftingForm()
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

    local recipeSchematic = C_TradeSkillUI.GetRecipeSchematic(order.spellID, order.isRecraft or false);
    if not recipeSchematic then
        return;
    end

    local reagents = {};
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
        "craftorders"
    );

    self.UI:Refresh();
end

function CraftHelper:OnRecipeUnfavorited(form)
    if not form.CraftHelperSpellID then
        return;
    end

    self.Data:RemoveRecipe(form.CraftHelperSpellID);
    self.UI:Refresh();
end

-- ---------------------------------------------------------------------------
-- Utilities
-- ---------------------------------------------------------------------------
function CraftHelper:Print(msg)
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
