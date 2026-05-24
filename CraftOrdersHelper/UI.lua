local _, CraftHelper = ...;

CraftHelper.UI = {};
CraftHelper.UI.rows = {};
CraftHelper.UI.isAggregate = true;
CraftHelper.UI.selectedRecipeIndex = 1;

local function SafeGetItemInfo(itemID)
    if C_Item and C_Item.GetItemInfo then
        return C_Item.GetItemInfo(itemID);
    end
    return GetItemInfo(itemID);
end

-- ---------------------------------------------------------------------------
-- Dropdown helper
-- ---------------------------------------------------------------------------
local function CreateDropdown(parent, label, options, onSelect, getCurrent)
    local frame = CreateFrame("Frame", nil, parent);
    frame:SetSize(240, 22);

    local labelText = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    labelText:SetPoint("LEFT", 0, 0);
    labelText:SetText(label);
    labelText:SetTextColor(0.8, 0.8, 0.8, 1);
    frame.labelText = labelText;

    local btn = CreateFrame("Button", nil, frame, "UIMenuButtonStretchTemplate");
    btn:SetSize(140, 22);
    btn:SetPoint("RIGHT", 0, 0);
    btn:SetScript("OnClick", function(self)
        if CraftHelper.UI.activeDropdown and CraftHelper.UI.activeDropdown.anchor == self then
            CraftHelper.UI.activeDropdown:Hide();
        else
            CraftHelper.UI:OpenDropdownMenu(self, options, onSelect);
        end
    end);

    local btnText = btn:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall");
    btnText:SetPoint("CENTER", 0, 0);
    btnText:SetWidth(120);
    btnText:SetJustifyH("CENTER");
    btn.text = btnText;

    frame.button = btn;

    frame.UpdateText = function()
        local current = getCurrent();
        for _, opt in ipairs(options) do
            if opt.key == current then
                btn.text:SetText(opt.name);
                return;
            end
        end
        btn.text:SetText("...");
    end;

    frame:UpdateText();
    return frame;
end

function CraftHelper.UI:OpenDropdownMenu(anchor, options, onSelect)
    if self.activeDropdown then
        self.activeDropdown:Hide();
        self.activeDropdown = nil;
    end

    local menu = CreateFrame("Frame", nil, anchor, "BackdropTemplate");
    menu:SetSize(150, #options * 20 + 4);
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2);
    menu:SetFrameStrata("DIALOG");
    menu.anchor = anchor;
    menu:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    });
    menu:EnableMouse(true);

    for i, opt in ipairs(options) do
        local row = CreateFrame("Button", nil, menu);
        row:SetSize(142, 18);
        row:SetPoint("TOPLEFT", 4, -(i - 1) * 20 - 2);

        local highlight = row:CreateTexture(nil, "HIGHLIGHT");
        highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
        highlight:SetBlendMode("ADD");
        highlight:SetAllPoints();
        highlight:Hide();
        row:SetHighlightTexture(highlight);

        local text = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
        text:SetPoint("LEFT", 4, 0);
        text:SetText(opt.name);
        text:SetJustifyH("LEFT");
        row.text = text;

        row:SetScript("OnClick", function()
            onSelect(opt.key);
            menu:Hide();
            self.activeDropdown = nil;
        end);
    end

    menu:SetScript("OnHide", function()
        self.activeDropdown = nil;
    end);

    self.activeDropdown = menu;
    menu:Show();
end

-- ---------------------------------------------------------------------------
-- Main UI
-- ---------------------------------------------------------------------------
function CraftHelper.UI:Init()
    self:CreateFrame();
    self:DetectAndAttachToAuctionHouse();
end

function CraftHelper.UI:DetectAndAttachToAuctionHouse()
    if AuctionHouseFrame then
        self:AttachToModernAH();
        return;
    end
    if AuctionFrame then
        self:AttachToLegacyAH();
        return;
    end

    local waiter = CreateFrame("Frame");
    waiter:RegisterEvent("ADDON_LOADED");
    waiter:SetScript("OnEvent", function(_, _event, addon)
        if addon == "Blizzard_AuctionHouseUI" then
            CraftHelper.UI:AttachToModernAH();
            waiter:UnregisterAllEvents();
        elseif addon == "Blizzard_AuctionUI" then
            CraftHelper.UI:AttachToLegacyAH();
            waiter:UnregisterAllEvents();
        end
    end);
end

function CraftHelper.UI:CreateFrame()
    local f = CreateFrame("Frame", "CraftOrdersHelperFrame", UIParent, "BackdropTemplate");
    f:SetSize(320, 460);
    f:SetPoint("CENTER", 0, 0);
    f:SetFrameStrata("HIGH");
    f:SetMovable(true);
    f:EnableMouse(true);
    f:RegisterForDrag("LeftButton");
    f:SetScript("OnDragStart", f.StartMoving);
    f:SetScript("OnDragStop", f.StopMovingOrSizing);
    f:Hide();

    f:SetBackdrop({
        bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 32,
        edgeSize = 32,
        insets = { left = 11, right = 12, top = 12, bottom = 11 },
    });
    f:SetBackdropColor(0.1, 0.1, 0.1, 1);

    local header = f:CreateTexture(nil, "ARTWORK");
    header:SetTexture("Interface\\DialogFrame\\UI-DialogBox-Header");
    header:SetSize(270, 64);
    header:SetPoint("TOP", 0, 12);

    local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    title:SetPoint("TOP", header, "TOP", 0, -14);
    title:SetText("CraftOrdersHelper");
    title:SetTextColor(1, 0.82, 0, 1);

    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton");
    close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -5, -5);
    close:SetScript("OnClick", function() f:Hide(); end);

    -- Aggregate checkbox
    local cb = CreateFrame("CheckButton", nil, f, "UICheckButtonTemplate");
    cb:SetPoint("TOPLEFT", 20, -40);
    cb.text:SetText("Aggregate all recipes");
    cb.text:SetTextColor(1, 0.82, 0, 1);
    cb:SetChecked(true);
    cb:SetScript("OnClick", function(button)
        CraftHelper.UI.isAggregate = button:GetChecked();
        CraftHelper.UI:Refresh();
    end);
    self.aggregateCheckbox = cb;

    -- Character scope dropdown
    local charOptions = {
        { key = "character", name = "This Character" },
        { key = "account", name = "Account" },
    };
    local charDropdown = CreateDropdown(f, "Show:", charOptions,
        function(key)
            CraftHelper.Data:SetViewCharacter(key);
            CraftHelper.UI:Refresh();
        end,
        function() return CraftHelper.Data:GetViewCharacter(); end
    );
    charDropdown:SetPoint("TOPLEFT", 20, -66);
    self.charDropdown = charDropdown;

    -- Source filter dropdown
    local sourceOptions = {
        { key = "all", name = "All Sources" },
        { key = "craftorders", name = "Craft Orders" },
        { key = "professions", name = "Professions" },
    };
    local sourceDropdown = CreateDropdown(f, "From:", sourceOptions,
        function(key)
            CraftHelper.Data:SetViewSource(key);
            CraftHelper.UI:Refresh();
        end,
        function() return CraftHelper.Data:GetViewSource(); end
    );
    sourceDropdown:SetPoint("TOPLEFT", 20, -90);
    self.sourceDropdown = sourceDropdown;

    -- Recipe selector (prev/next + name)
    local selector = CreateFrame("Frame", nil, f);
    selector:SetSize(270, 24);
    selector:SetPoint("TOPLEFT", 20, -118);

    local prev = CreateFrame("Button", nil, selector, "UIPanelButtonTemplate");
    prev:SetSize(24, 20);
    prev:SetPoint("LEFT", 0, 0);
    prev:SetText("<");
    prev:SetScript("OnClick", function()
        CraftHelper.UI:SelectPrevRecipe();
    end);

    local nextBtn = CreateFrame("Button", nil, selector, "UIPanelButtonTemplate");
    nextBtn:SetSize(24, 20);
    nextBtn:SetPoint("RIGHT", 0, 0);
    nextBtn:SetText(">");
    nextBtn:SetScript("OnClick", function()
        CraftHelper.UI:SelectNextRecipe();
    end);

    local recipeName = selector:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    recipeName:SetPoint("CENTER", 0, 0);
    recipeName:SetWidth(180);
    recipeName:SetJustifyH("CENTER");
    recipeName:SetTextColor(1, 0.82, 0, 1);
    selector.recipeName = recipeName;

    self.recipeSelector = selector;
    selector:Hide();

    local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate");
    scroll:SetPoint("TOPLEFT", 18, -148);
    scroll:SetPoint("BOTTOMRIGHT", -36, 18);

    local content = CreateFrame("Frame");
    content:SetSize(260, 100);
    scroll:SetScrollChild(content);

    self.scrollFrame = scroll;
    self.content = content;

    self.statusText = f:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    self.statusText:SetPoint("CENTER", scroll, "CENTER", 0, 0);
    self.statusText:SetText("No recipes saved.\nFavorite a recipe in Crafting Orders.");
    self.statusText:SetTextColor(0.5, 0.5, 0.5, 1);
    self.statusText:Hide();

    self.frame = f;
end

function CraftHelper.UI:AttachToModernAH()
    if not AuctionHouseFrame then return; end
    self.ahMode = "modern";
    self.frame:ClearAllPoints();
    self.frame:SetPoint("TOPLEFT", AuctionHouseFrame, "TOPRIGHT", 5, 0);
    AuctionHouseFrame:HookScript("OnShow", function()
        CraftHelper.UI:Refresh();
        CraftHelper.UI.frame:Show();
    end);
    AuctionHouseFrame:HookScript("OnHide", function()
        CraftHelper.UI.frame:Hide();
    end);
    if AuctionHouseFrame:IsShown() then
        self:Refresh();
        self.frame:Show();
    end
end

function CraftHelper.UI:AttachToLegacyAH()
    if not AuctionFrame then return; end
    self.ahMode = "legacy";
    self.frame:ClearAllPoints();
    self.frame:SetPoint("TOPLEFT", AuctionFrame, "TOPRIGHT", 5, 0);
    AuctionFrame:HookScript("OnShow", function()
        CraftHelper.UI:Refresh();
        CraftHelper.UI.frame:Show();
    end);
    AuctionFrame:HookScript("OnHide", function()
        CraftHelper.UI.frame:Hide();
    end);
    if AuctionFrame:IsShown() then
        self:Refresh();
        self.frame:Show();
    end
end

function CraftHelper.UI:SearchItem(itemName)
    if not itemName or itemName == "" then return; end
    if self.ahMode == "modern" and AuctionHouseFrame and AuctionHouseFrame.SearchBar then
        AuctionHouseFrame.SearchBar:SetSearchText(itemName);
        AuctionHouseFrame.SearchBar:StartSearch();
    elseif self.ahMode == "legacy" then
        if AuctionFrameBrowse and BrowseName then
            if BrowseResetButton then BrowseResetButton:Click(); end
            if AuctionFrameTab1 then AuctionFrameTab1:Click(); end
            BrowseName:SetText(itemName);
            if AuctionFrameBrowse_Search then
                AuctionFrameBrowse_Search();
            elseif BrowseSearchButton then
                BrowseSearchButton:Click();
            end
        end
    end
end

function CraftHelper.UI.GetRecipeList()
    return CraftHelper.Data:GetRecipeNames();
end

function CraftHelper.UI:SelectPrevRecipe()
    local list = self:GetRecipeList();
    if #list == 0 then return; end
    self.selectedRecipeIndex = self.selectedRecipeIndex - 1;
    if self.selectedRecipeIndex < 1 then self.selectedRecipeIndex = #list; end
    self:Refresh();
end

function CraftHelper.UI:SelectNextRecipe()
    local list = self:GetRecipeList();
    if #list == 0 then return; end
    self.selectedRecipeIndex = self.selectedRecipeIndex + 1;
    if self.selectedRecipeIndex > #list then self.selectedRecipeIndex = 1; end
    self:Refresh();
end

function CraftHelper.UI:EnsureValidRecipeIndex()
    local list = self:GetRecipeList();
    if #list == 0 then self.selectedRecipeIndex = 1; return nil; end
    if self.selectedRecipeIndex > #list then self.selectedRecipeIndex = 1; end
    if self.selectedRecipeIndex < 1 then self.selectedRecipeIndex = 1; end
    return list[self.selectedRecipeIndex];
end

function CraftHelper.UI:GetOrCreateRow(index)
    if self.rows[index] then
        return self.rows[index];
    end

    local row = CreateFrame("Frame", nil, self.content);
    row:SetSize(260, 36);

    row.highlight = row:CreateTexture(nil, "HIGHLIGHT");
    row.highlight:SetTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight");
    row.highlight:SetBlendMode("ADD");
    row.highlight:SetAllPoints();
    row.highlight:Hide();

    local iconBg = row:CreateTexture(nil, "BACKGROUND");
    iconBg:SetSize(28, 28);
    iconBg:SetPoint("LEFT", 4, 0);
    iconBg:SetTexture("Interface\\Buttons\\UI-EmptySlot-White");
    iconBg:SetTexCoord(0.08, 0.92, 0.08, 0.92);
    row.iconBg = iconBg;

    local icon = row:CreateTexture(nil, "ARTWORK");
    icon:SetSize(22, 22);
    icon:SetPoint("CENTER", iconBg, "CENTER", 0, 0);
    row.icon = icon;

    local iconBtn = CreateFrame("Button", nil, row);
    iconBtn:SetSize(28, 28);
    iconBtn:SetPoint("CENTER", iconBg, "CENTER", 0, 0);
    iconBtn:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD");
    iconBtn:SetScript("OnClick", function()
        local data = row.data;
        if data then CraftHelper.UI:SearchItem(data.name); end
    end);
    iconBtn:SetScript("OnEnter", function(button)
        row.highlight:Show();
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        if row.data and row.data.itemID then
            GameTooltip:SetItemByID(row.data.itemID);
        end
        GameTooltip:Show();
    end);
    iconBtn:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);
    row.iconBtn = iconBtn;

    local nameBtn = CreateFrame("Button", nil, row);
    nameBtn:SetSize(180, 16);
    nameBtn:SetPoint("TOPLEFT", iconBg, "TOPRIGHT", 6, 2);
    nameBtn:SetScript("OnClick", function()
        local data = row.data;
        if data then CraftHelper.UI:SearchItem(data.name); end
    end);
    nameBtn:SetScript("OnEnter", function(button)
        row.highlight:Show();
        GameTooltip:SetOwner(button, "ANCHOR_RIGHT");
        if row.data and row.data.itemID then
            GameTooltip:SetItemByID(row.data.itemID);
        end
        GameTooltip:Show();
    end);
    nameBtn:SetScript("OnLeave", function()
        row.highlight:Hide();
        GameTooltip:Hide();
    end);

    local nameText = nameBtn:CreateFontString(nil, "OVERLAY", "GameFontNormal");
    nameText:SetPoint("LEFT", 0, 0);
    nameText:SetWidth(180);
    nameText:SetJustifyH("LEFT");
    nameBtn.text = nameText;
    row.nameBtn = nameBtn;

    local qtyText = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall");
    qtyText:SetPoint("TOPLEFT", nameBtn, "BOTTOMLEFT", 0, -1);
    qtyText:SetWidth(230);
    qtyText:SetJustifyH("LEFT");
    row.qtyText = qtyText;

    local line = row:CreateTexture(nil, "ARTWORK");
    line:SetHeight(1);
    line:SetColorTexture(0.25, 0.25, 0.25, 0.6);
    line:SetPoint("BOTTOMLEFT", 8, 0);
    line:SetPoint("BOTTOMRIGHT", -8, 0);

    self.rows[index] = row;
    return row;
end

function CraftHelper.UI:ClearRows()
    for _, row in ipairs(self.rows) do
        row:Hide();
    end
end

-- ---------------------------------------------------------------------------
-- Main refresh
-- ---------------------------------------------------------------------------
function CraftHelper.UI:Refresh()
    if not self.frame then return; end

    -- Update dropdown texts
    self.charDropdown:UpdateText();
    self.sourceDropdown:UpdateText();

    self:ClearRows();

    if not CraftHelper.Data:HasRecipes() then
        self.statusText:SetText("No recipes saved.\nFavorite or track a recipe.");
        self.statusText:Show();
        self.recipeSelector:Hide();
        self.content:SetHeight(100);
        return;
    end

    self.statusText:Hide();

    local reagents = {};

    if self.isAggregate then
        self.recipeSelector:Hide();
        reagents = CraftHelper.Data:GetAggregateReagents();
    else
        self.recipeSelector:Show();
        local selected = self:EnsureValidRecipeIndex();
        if selected then
            self.recipeSelector.recipeName:SetText(selected.name);
            reagents = CraftHelper.Data:GetRecipeReagents(selected.id);
        else
            self.recipeSelector.recipeName:SetText("No recipes");
        end
    end

    if #reagents == 0 then
        local statusMessage = self.isAggregate and "All reagents in bags!"
            or "All reagents for this recipe in bags!";
        self.statusText:SetText(statusMessage);
        self.statusText:Show();
        self.content:SetHeight(100);
        return;
    end

    local totalHeight = 0;
    for i, reagent in ipairs(reagents) do
        -- Refresh name/icon from cache
        if reagent.isQualitySlot then
            for idx, qid in ipairs(reagent.qualityItemIDs or {}) do
                local refreshedName, _, _, _, _, _, _, _, _, refreshedIcon = SafeGetItemInfo(qid);
                if refreshedName and refreshedName ~= "" then
                    reagent.qualityNames[idx] = refreshedName;
                    reagent.qualityIcons[idx] = refreshedIcon;
                    if idx == 1 then
                        reagent.name = refreshedName;
                        reagent.icon = refreshedIcon;
                    end
                end
            end
            CraftHelper.Data:UpdateReagentName(
                reagent.qualityItemIDs[1],
                reagent.qualityNames[1],
                reagent.qualityIcons[1]
            );
        else
            local refreshedName, _, _, _, _, _, _, _, _, refreshedIcon = SafeGetItemInfo(reagent.itemID);
            if refreshedName and refreshedName ~= "" then
                reagent.name = refreshedName;
                reagent.icon = refreshedIcon;
                CraftHelper.Data:UpdateReagentName(reagent.itemID, refreshedName, refreshedIcon);
            end
        end

        local row = self:GetOrCreateRow(i);
        row.data = reagent;
        row.icon:SetTexture(reagent.icon);
        row.nameBtn.text:SetText(reagent.name);
        row.nameBtn.text:SetTextColor(1, 0.82, 0, 1);

        local qtyStr;
        if reagent.isQualitySlot then
            -- Query actual quality atlas names from game API at runtime
            local lowIcon = "|cFFAAAAAAL|r";
            local highIcon = "|cFFFFD700H|r";
            if C_TradeSkillUI and C_TradeSkillUI.GetItemReagentQualityInfo then
                local qid1 = reagent.qualityItemIDs[1];
                if qid1 then
                    local ok1, qInfo1 = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, qid1);
                    if ok1 and qInfo1 and qInfo1.iconChat then
                        local okm1, markup1 = pcall(CreateAtlasMarkup, qInfo1.iconChat, 14, 14);
                        if okm1 then lowIcon = markup1; end
                    end
                end
                local qid2 = reagent.qualityItemIDs[2];
                if qid2 then
                    local ok2, qInfo2 = pcall(C_TradeSkillUI.GetItemReagentQualityInfo, qid2);
                    if ok2 and qInfo2 and qInfo2.iconChat then
                        local okm2, markup2 = pcall(CreateAtlasMarkup, qInfo2.iconChat, 14, 14);
                        if okm2 then highIcon = markup2; end
                    end
                end
            end
            qtyStr = string.format(
                "Need: |cFFFFFFFF%d|r  %s |cFFFFFFFF%d|r  %s |cFFFFFFFF%d|r  Buy: |cFFFF0000%d|r",
                reagent.quantityRequired,
                lowIcon,
                reagent.lowCount or 0,
                highIcon,
                reagent.highCount or 0,
                reagent.missing
            );
        else
            qtyStr = string.format(
                "Need: |cFFFFFFFF%d|r  Have: |cFF00FF00%d|r  Buy: |cFFFF0000%d|r",
                reagent.quantityRequired,
                reagent.owned or 0,
                reagent.missing
            );
        end
        row.qtyText:SetText(qtyStr);

        row:SetPoint("TOPLEFT", self.content, "TOPLEFT", 0, -(i - 1) * 36);
        row:Show();
        totalHeight = i * 36;
    end

    self.content:SetHeight(math.max(totalHeight, 100));
end
