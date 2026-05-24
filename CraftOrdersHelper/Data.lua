local _, CraftHelper = ...;

CraftHelper.Data = {};

local function SafeGetItemCount(itemID)
    if C_Item and C_Item.GetItemCount then
        return C_Item.GetItemCount(itemID) or 0;
    end
    return GetItemCount(itemID) or 0;
end

local function GetCharacterKey()
    return UnitName("player") .. "-" .. GetRealmName();
end

function CraftHelper.Data:Init()
    -- Ensure both DB tables exist
    CraftHelperDB = CraftHelperDB or {};
    CraftHelperDB.characters = CraftHelperDB.characters or {};
    CraftHelperDB.version = CraftHelperDB.version or "1.3.0";

    CraftHelperDB_Char = CraftHelperDB_Char or {};
    CraftHelperDB_Char.recipes = CraftHelperDB_Char.recipes or {};

    self.charKey = GetCharacterKey();

    -- Default: per-character mode, viewing current char, all sources
    self.accountWide = CraftHelperDB.accountWide or false;
    self.viewCharacter = CraftHelperDB_Char.viewCharacter or "character"; -- "character", "account", or charKey
    self.viewSource = CraftHelperDB_Char.viewSource or "all"; -- "all", "craftorders", "professions"

    if self.accountWide then
        -- Ensure current char exists in account DB
        if not CraftHelperDB.characters[self.charKey] then
            CraftHelperDB.characters[self.charKey] = { recipes = {} };
        end
        self.db = CraftHelperDB.characters[self.charKey];
    else
        self.db = CraftHelperDB_Char;
    end

    self.bagCache = {};
    self:ScanBags();
end

function CraftHelper.Data:SetAccountWide(enabled)
    self.accountWide = enabled;
    CraftHelperDB.accountWide = enabled;

    if enabled then
        if not CraftHelperDB.characters[self.charKey] then
            CraftHelperDB.characters[self.charKey] = { recipes = {} };
        end
        self.db = CraftHelperDB.characters[self.charKey];
    else
        self.db = CraftHelperDB_Char;
    end

    self:ScanBags();
end

function CraftHelper.Data:IsAccountWide()
    return self.accountWide;
end

function CraftHelper.Data:SetViewCharacter(viewChar)
    self.viewCharacter = viewChar;
    CraftHelperDB_Char.viewCharacter = viewChar;
end

function CraftHelper.Data:GetViewCharacter()
    return self.viewCharacter;
end

function CraftHelper.Data:SetViewSource(source)
    self.viewSource = source;
    CraftHelperDB_Char.viewSource = source;
end

function CraftHelper.Data:GetViewSource()
    return self.viewSource;
end

function CraftHelper.Data:GetCharacterList()
    local list = {};
    -- Always show current character and account
    table.insert(list, { key = "character", name = "This Character" });
    table.insert(list, { key = "account", name = "Account" });

    -- Add other characters from account DB
    for charKey, _ in pairs(CraftHelperDB.characters or {}) do
        if charKey ~= self.charKey then
            table.insert(list, { key = charKey, name = charKey });
        end
    end

    return list;
end

function CraftHelper.Data:ScanBags()
    self.bagCache = {};
end

function CraftHelper.Data:GetItemCount(itemID)
    if not itemID then return 0; end
    if self.bagCache[itemID] ~= nil then
        return self.bagCache[itemID];
    end
    local count = SafeGetItemCount(itemID);
    self.bagCache[itemID] = count;
    return self.bagCache[itemID];
end

local function CopyRecipeSources(recipe)
    local sources = {};
    if recipe and type(recipe.sources) == "table" then
        for source, enabled in pairs(recipe.sources) do
            if enabled then
                sources[source] = true;
            end
        end
    end
    if recipe and recipe.source then
        sources[recipe.source] = true;
    end
    return sources;
end

function CraftHelper.Data.RecipeHasSource(recipe, source)
    if source == "all" then
        return true;
    end
    if recipe.sources and recipe.sources[source] then
        return true;
    end
    return recipe.source == source;
end

function CraftHelper.Data:SaveRecipe(recipeID, recipeName, reagents, isRecraft, source)
    local existing = self.db.recipes[recipeID];
    local sources = CopyRecipeSources(existing);
    sources[source or "unknown"] = true;

    self.db.recipes[recipeID] = {
        name = recipeName or ("Recipe " .. recipeID),
        reagents = reagents,
        isRecraft = isRecraft,
        timestamp = time(),
        source = source or "unknown",
        sources = sources,
    };
end

function CraftHelper.Data:RemoveRecipe(recipeID, source)
    if source then
        local recipe = self.db.recipes[recipeID];
        if not recipe then
            return;
        end

        local sources = CopyRecipeSources(recipe);
        sources[source] = nil;

        if next(sources) then
            recipe.sources = sources;
            recipe.source = next(sources);
            return;
        end
    end

    self.db.recipes[recipeID] = nil;
end

-- Get active DB based on viewCharacter setting
function CraftHelper.Data:GetActiveDB()
    local view = self.viewCharacter;
    if view == "character" then
        if self.accountWide then
            return CraftHelperDB.characters[self.charKey] or { recipes = {} };
        else
            return CraftHelperDB_Char;
        end
    elseif view == "account" then
        -- Aggregate all characters' recipes
        local merged = { recipes = {} };
        for _, charData in pairs(CraftHelperDB.characters or {}) do
            for recipeID, recipe in pairs(charData.recipes or {}) do
                if not merged.recipes[recipeID] then
                    merged.recipes[recipeID] = recipe;
                end
            end
        end
        -- Also include current char if not in account DB (char mode)
        if not self.accountWide then
            for recipeID, recipe in pairs(CraftHelperDB_Char.recipes or {}) do
                if not merged.recipes[recipeID] then
                    merged.recipes[recipeID] = recipe;
                end
            end
        end
        return merged;
    else
        -- Specific character key
        return CraftHelperDB.characters[view] or { recipes = {} };
    end
end

function CraftHelper.Data:GetAllRecipes()
    local activeDB = self:GetActiveDB();
    local result = {};

    for recipeID, recipe in pairs(activeDB.recipes) do
        local sourceFilter = self.viewSource;
        if CraftHelper.Data.RecipeHasSource(recipe, sourceFilter) then
            result[recipeID] = recipe;
        end
    end

    return result;
end

function CraftHelper.Data:HasRecipes()
    return next(self:GetAllRecipes()) ~= nil;
end

-- ---------------------------------------------------------------------------
-- Aggregate reagents across ALL saved recipes (filtered by view)
-- ---------------------------------------------------------------------------
function CraftHelper.Data:GetAggregateReagents()
    local recipes = self:GetAllRecipes();
    local aggregated = {};

    for recipeID, recipe in pairs(recipes) do
        for _, reagent in ipairs(recipe.reagents) do
            if reagent.isQualitySlot then
                local key = (reagent.qualityItemIDs[1] or 0) .. "_quality";
                local existing = aggregated[key];
                if not existing then
                    existing = {
                        isQualitySlot = true,
                        qualityItemIDs = reagent.qualityItemIDs,
                        qualityNames = reagent.qualityNames,
                        qualityIcons = reagent.qualityIcons,
                        name = reagent.name,
                        icon = reagent.icon,
                        quantityRequired = 0,
                        recipes = {},
                    };
                    aggregated[key] = existing;
                end
                existing.quantityRequired = existing.quantityRequired + reagent.quantityRequired;
                table.insert(existing.recipes, {
                    recipeID = recipeID,
                    recipeName = recipe.name,
                    qty = reagent.quantityRequired,
                });
            elseif reagent.itemID then
                local existing = aggregated[reagent.itemID];
                if not existing then
                    existing = {
                        isQualitySlot = false,
                        itemID = reagent.itemID,
                        name = reagent.name,
                        icon = reagent.icon,
                        quantityRequired = 0,
                        recipes = {},
                    };
                    aggregated[reagent.itemID] = existing;
                end
                existing.quantityRequired = existing.quantityRequired + reagent.quantityRequired;
                table.insert(existing.recipes, {
                    recipeID = recipeID,
                    recipeName = recipe.name,
                    qty = reagent.quantityRequired,
                });
            end
        end
    end

    local result = {};
    for _, data in pairs(aggregated) do
        if data.isQualitySlot then
            local lowCount = self:GetItemCount(data.qualityItemIDs[1] or 0);
            local highCount = 0;
            if data.qualityItemIDs[2] then
                highCount = self:GetItemCount(data.qualityItemIDs[2]);
            end
            data.lowCount = lowCount;
            data.highCount = highCount;
            data.totalOwned = lowCount + highCount;
            data.missing = math.max(0, data.quantityRequired - data.totalOwned);
        else
            data.owned = self:GetItemCount(data.itemID);
            data.missing = math.max(0, data.quantityRequired - data.owned);
        end

        if data.missing > 0 then
            table.insert(result, data);
        end
    end

    table.sort(result, function(a, b) return a.name < b.name end);
    return result;
end

-- ---------------------------------------------------------------------------
-- Reagents for a SINGLE recipe
-- ---------------------------------------------------------------------------
function CraftHelper.Data:GetRecipeReagents(recipeID)
    local recipes = self:GetAllRecipes();
    local recipe = recipes[recipeID];
    if not recipe then return {}; end

    local result = {};
    for _, reagent in ipairs(recipe.reagents) do
        if reagent.isQualitySlot then
            local lowCount = self:GetItemCount(reagent.qualityItemIDs[1] or 0);
            local highCount = 0;
            if reagent.qualityItemIDs[2] then
                highCount = self:GetItemCount(reagent.qualityItemIDs[2]);
            end
            local totalOwned = lowCount + highCount;
            local missing = math.max(0, reagent.quantityRequired - totalOwned);
            if missing > 0 then
                table.insert(result, {
                    isQualitySlot = true,
                    qualityItemIDs = reagent.qualityItemIDs,
                    qualityNames = reagent.qualityNames,
                    qualityIcons = reagent.qualityIcons,
                    name = reagent.name,
                    icon = reagent.icon,
                    quantityRequired = reagent.quantityRequired,
                    lowCount = lowCount,
                    highCount = highCount,
                    missing = missing,
                });
            end
        elseif reagent.itemID then
            local owned = self:GetItemCount(reagent.itemID);
            local missing = math.max(0, reagent.quantityRequired - owned);
            if missing > 0 then
                table.insert(result, {
                    isQualitySlot = false,
                    itemID = reagent.itemID,
                    name = reagent.name,
                    icon = reagent.icon,
                    quantityRequired = reagent.quantityRequired,
                    owned = owned,
                    missing = missing,
                });
            end
        end
    end

    table.sort(result, function(a, b) return a.name < b.name end);
    return result;
end

function CraftHelper.Data:GetRecipeNames()
    local recipes = self:GetAllRecipes();
    local names = {};
    for recipeID, recipe in pairs(recipes) do
        table.insert(names, {id = recipeID, name = recipe.name});
    end
    table.sort(names, function(a, b) return a.name < b.name end);
    return names;
end

function CraftHelper.Data:GetRecipeCount()
    local count = 0;
    for _ in pairs(self:GetAllRecipes()) do count = count + 1; end
    return count;
end

function CraftHelper.Data:UpdateReagentName(itemID, newName, newIcon)
    if not itemID or not newName then return; end
    for _, recipe in pairs(self:GetAllRecipes()) do
        for _, reagent in ipairs(recipe.reagents) do
            if reagent.isQualitySlot then
                for i, qid in ipairs(reagent.qualityItemIDs) do
                    if qid == itemID then
                        reagent.qualityNames[i] = newName;
                        reagent.qualityIcons[i] = newIcon;
                        if i == 1 then
                            reagent.name = newName;
                            reagent.icon = newIcon;
                        end
                    end
                end
            elseif reagent.itemID == itemID then
                reagent.name = newName;
                reagent.icon = newIcon;
            end
        end
    end
end
