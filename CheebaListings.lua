-----------------------------------------------------------------------------------------------
-- Client Lua Script for CheebaListings
-- Copyright (c) NCsoft. All rights reserved
-----------------------------------------------------------------------------------------------

require "Window"
require "GameLib"
require "Money"
require "MarketplaceLib"
require "CommodityOrder"
require "ItemAuction"

local CheebaListings = {}

local ktTimeRemaining =
{
	[ItemAuction.CodeEnumAuctionRemaining.Expiring]		= Apollo.GetString("MarketplaceAuction_Expiring"),
	[ItemAuction.CodeEnumAuctionRemaining.LessThanHour]	= Apollo.GetString("MarketplaceAuction_LessThanHour"),
	[ItemAuction.CodeEnumAuctionRemaining.Short]		= Apollo.GetString("MarketplaceAuction_Short"),
	[ItemAuction.CodeEnumAuctionRemaining.Long]			= Apollo.GetString("MarketplaceAuction_Long"),
	[ItemAuction.CodeEnumAuctionRemaining.Very_Long]	= Apollo.GetString("MarketplaceAuction_VeryLong")
}

function CheebaListings:new(o)
    o = o or {}
    setmetatable(o, self)
    self.__index = self
    return o
end

function CheebaListings:Init()
    Apollo.RegisterAddon(self)
end

function CheebaListings:OnLoad()
	self.xmlDoc = XmlDoc.CreateFromFile("CheebaListings.xml")
	self.xmlDoc:RegisterCallback("OnDocumentReady", self)
end

function CheebaListings:OnDocumentReady()
	if self.xmlDoc == nil then
		return
	end

	Apollo.RegisterEventHandler("InterfaceMenuListHasLoaded", "OnInterfaceMenuListHasLoaded", self)
	Apollo.RegisterEventHandler("InterfaceMenu_ToggleCheebaListings", 	"OnToggle", self)
	Apollo.RegisterEventHandler("ToggleAuctionList", 						"OnToggle", self)
	
	Apollo.RegisterEventHandler("OwnedItemAuctions", 						"OnOwnedItemAuctions", self)
	Apollo.RegisterEventHandler("OwnedCommodityOrders", 					"OnOwnedCommodityOrders", self)
	Apollo.RegisterEventHandler("CREDDExchangeInfoResults", 				"OnCREDDExchangeInfoResults", self)

	Apollo.RegisterEventHandler("CommodityAuctionRemoved", 					"OnCommodityAuctionRemoved", self)
	Apollo.RegisterEventHandler("CommodityAuctionFilledPartial", 			"OnCommodityAuctionUpdated", self)
	Apollo.RegisterEventHandler("PostCommodityOrderResult", 				"OnPostCommodityOrderResult", self)

	Apollo.RegisterEventHandler("CommodityInfoResults", 					"OnCommodityInfoResults", self)

	Apollo.RegisterEventHandler("ItemAuctionWon", 							"OnItemAuctionRemoved", self)
	Apollo.RegisterEventHandler("ItemAuctionOutbid", 						"OnItemAuctionRemoved", self)
	Apollo.RegisterEventHandler("ItemAuctionExpired", 						"OnItemAuctionRemoved", self)
	Apollo.RegisterEventHandler("ItemCancelResult", 						"OnItemCancelResult", self)
	Apollo.RegisterEventHandler("ItemAuctionBidPosted", 					"OnItemAuctionUpdated", self)
	Apollo.RegisterEventHandler("PostItemAuctionResult", 					"OnItemAuctionResult", self)
	Apollo.RegisterEventHandler("ItemAuctionBidResult", 					"OnItemAuctionResult", self)

	Apollo.CreateTimer("MarketplaceUpdateTimer", 60, true)
	Apollo.StopTimer("MarketplaceUpdateTimer")

	self.tOrders = nil
	self.tAuctions = nil
	self.tCreddList = nil
end

function CheebaListings:OnInterfaceMenuListHasLoaded()
	Event_FireGenericEvent("InterfaceMenuList_NewAddOn", Apollo.GetString("InterfaceMenu_AuctionListings"), {"InterfaceMenu_ToggleCheebaListings", "", "Icon_Windows32_UI_CRB_InterfaceMenu_CheebaListings"})
end

function CheebaListings:OnToggle()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:Destroy()
		self.wndMain = nil
	else
		self.wndMain = Apollo.LoadForm(self.xmlDoc, "CheebaListingsForm", nil, self)
		self.wndMain:SetSizingMinimum(400, 300)
		self.wndMain:Show(false, true)
		Event_FireGenericEvent("WindowManagementAdd", {wnd = self.wndMain, strName = Apollo.GetString("InterfaceMenu_AuctionListings")})

		self.wndMain:FindChild("TitleBGText"):SetData(GameLib.GetPlayerUnit())
		self:RequestData()

		Apollo.StartTimer("MarketplaceUpdateTimer")
	end
end

function CheebaListings:OnDestroy()
	if self.wndMain and self.wndMain:IsValid() then
		self.wndMain:Destroy()
		self.wndMain = nil
		Apollo.StopTimer("MarketplaceUpdateTimer")
	end
end

function CheebaListings:RequestData()
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self.wndMain:FindChild("MainScroll"):Show(false)
	self.wndMain:FindChild("WaitScreen"):Show(true)
	self.wndMain:FindChild("MainScroll"):DestroyChildren()

	MarketplaceLib.RequestOwnedCommodityOrders() -- Leads to OwnedCommodityOrders
	MarketplaceLib.RequestOwnedItemAuctions() -- Leads to OwnedItemAuctions
	CREDDExchangeLib.RequestExchangeInfo() -- Leads to OnCREDDExchangeInfoResults
end

function CheebaListings:RedrawData()
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self.wndMain:FindChild("MainScroll"):Show(false)
	self.wndMain:FindChild("WaitScreen"):Show(true)
	self.wndMain:FindChild("MainScroll"):DestroyChildren()

	if self.tOrders ~= nil then
		self:OnOwnedCommodityOrders(self.tOrders)
	end
	if self.tAuctions ~= nil then
		self:OnOwnedItemAuctions(self.tAuctions)
	end
	if self.tCreddList ~= nil then
		self:OnCREDDExchangeInfoResults({}, self.tCreddList)
	end
end

function CheebaListings:OnOwnedItemAuctions(tAuctions)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self.tAuctions = tAuctions

	for nIdx, aucCurrent in pairs(tAuctions) do
		if aucCurrent and ItemAuction.is(aucCurrent) then
			self:BuildAuctionOrder(nIdx, aucCurrent)
		end
	end

	self:SharedDrawMain()
end

function CheebaListings:OnOwnedCommodityOrders(tOrders)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self.tOrders = tOrders
	self.CommodityOrdersHandlers = {}
	self.CommodityTotalValue = 0

	for nIdx, tCurrOrder in pairs(tOrders) do
		if(tCurrOrder:IsBuy()) then
			self:BuildCommodityOrder(nIdx, tCurrOrder)
		end
	end

	for nIdx, tCurrOrder in pairs(tOrders) do
		if(not tCurrOrder:IsBuy()) then
			self:BuildCommodityOrder(nIdx, tCurrOrder)
		end
	end

	for nIdx, tCurrOrder in pairs(tOrders) do
		local tItem = tCurrOrder:GetItem()
		MarketplaceLib.RequestCommodityInfo(tItem:GetItemId())
	end

	self:SharedDrawMain()
end


function CheebaListings:OnCREDDExchangeInfoResults(arMarketStats, arOrders)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	self.tCreddList = arOrders

	for nIdx, tCurrOrder in pairs(self.tCreddList) do
		self:BuildCreddOrder(nIdx, tCurrOrder)
	end

	self:SharedDrawMain()
end

function CheebaListings:SharedDrawMain()
	local strPlayerName = self.wndMain:FindChild("TitleBGText"):GetData()
	local nNumChildren = #self.wndMain:FindChild("MainScroll"):GetChildren()

	self.wndMain:Show(true)
	self.wndMain:FindChild("MainScroll"):Show(true)
	self.wndMain:FindChild("WaitScreen"):Show(false)
	self.wndMain:FindChild("TitleBGText"):SetText(String_GetWeaselString(Apollo.GetString("MarketplaceListings_PlayerPrefixListings"), strPlayerName))
	self.wndMain:FindChild("MainScroll"):SetText(nNumChildren == 0 and Apollo.GetString("MarketplaceListings_NoActiveListings") or "")
	self.wndMain:FindChild("MainScroll"):ArrangeChildrenVert(0, function(a,b) return a:GetName() > b:GetName() end)
end

-----------------------------------------------------------------------------------------------
-- Item Drawing
-----------------------------------------------------------------------------------------------

function CheebaListings:BuildAuctionOrder(nIdx, aucCurrent)
	local tItem = aucCurrent:GetItem()
	local wndCurr = self:FactoryProduce(self.wndMain:FindChild("MainScroll"), "AuctionItem", aucCurrent)

	local bIsOwnAuction = aucCurrent:IsOwned()
	local nCount = aucCurrent:GetCount()
	local nBidAmount = aucCurrent:GetCurrentBid():GetAmount()
	local nMinBidAmount = aucCurrent:GetMinBid():GetAmount()
	local nBuyoutAmount = aucCurrent:GetBuyoutPrice():GetAmount()
	local strPrefix = bIsOwnAuction and Apollo.GetString("MarketplaceListings_AuctionPrefix") or Apollo.GetString("MarketplaceListings_BiddingPrefix")
	local eTimeRemaining = MarketplaceLib.kCommodityOrderListTimeDays

	if bIsOwnAuction then
		wndCurr:FindChild("AuctionTimeLeftText"):SetText(self:HelperFormatTimeString(aucCurrent:GetExpirationTime()))
		wndCurr:FindChild("ListExpiresIconRed"):Show(false)
		wndCurr:FindChild("ListExpiresIconGreen"):Show(true)
		wndCurr:FindChild("AuctionTimeLeftText"):SetTextColor(ApolloColor.new("UI_TextHoloTitle"))
	elseif eTimeRemaining == ItemAuction.CodeEnumAuctionRemaining.Very_Long then
		wndCurr:FindChild("AuctionTimeLeftText"):SetTextRaw(String_GetWeaselString(Apollo.GetString("MarketplaceAuction_VeryLong"), kstrAuctionOrderDuration))
		wndCurr:FindChild("AuctionTimeLeftText"):SetTextColor(ApolloColor.new("UI_TextHoloTitle"))
		wndCurr:FindChild("ListExpiresIconRed"):Show(false)
		wndCurr:FindChild("ListExpiresIconGreen"):Show(true)
	else
		wndCurr:FindChild("AuctionTimeLeftText"):SetTextRaw(ktTimeRemaining[eTimeRemaining])
		wndCurr:FindChild("AuctionTimeLeftText"):SetTextColor(ApolloColor.new("xkcdDullRed"))
		wndCurr:FindChild("ListExpiresIconRed"):Show(true)
		wndCurr:FindChild("ListExpiresIconGreen"):Show(false)
	end

	wndCurr:FindChild("AuctionCancelBtn"):SetData(aucCurrent)
	wndCurr:FindChild("AuctionCancelBtn"):Enable(nBidAmount == 0)
	wndCurr:FindChild("AuctionCancelBtn"):Show(bIsOwnAuction)
	wndCurr:FindChild("AuctionCancelBtnTooltipHack"):Show(bIsOwnAuction and nBidAmount ~= 0)
	wndCurr:FindChild("AuctionPrice"):SetAmount(nBidAmount, true) -- 2nd arg is bInstant
	wndCurr:FindChild("MinimumPrice"):SetAmount(nMinBidAmount, true) -- 2nd arg is bInstant
	wndCurr:FindChild("BuyoutPrice"):SetAmount(nBuyoutAmount, true) -- 2nd arg is bInstant
	wndCurr:FindChild("AuctionBigIcon"):SetSprite(tItem:GetIcon())
	wndCurr:FindChild("AuctionIconAmountText"):SetText(nCount == 1 and "" or nCount)
	wndCurr:FindChild("AuctionItemName"):SetText(String_GetWeaselString(strPrefix, tItem:GetName()))
	Tooltip.GetItemTooltipForm(self, wndCurr:FindChild("AuctionBigIcon"), tItem, {bPrimary = true, bSelling = false, itemCompare = tItem:GetEquippedItemForItemType()})
end

function CheebaListings:OnCommodityInfoResults(nItemId, tStats, tOrders)
	if not self.wndMain or not self.wndMain:IsValid() then
		return
	end

	-- Average Small
	local nSmall = 0
	for idx, tRow in ipairs(tStats.arBuyOrderPrices) do
		local nCurrPrice = tRow.monPrice:GetAmount()
		if nCurrPrice and nCurrPrice > 0 then
			if nSmall == 0 then
				nSmall = nCurrPrice
			end
		end
	end

	-- Average Big
	local nBig = 0
	for idx, tRow in ipairs(tStats.arSellOrderPrices) do
		local nCurrPrice = tRow.monPrice:GetAmount()
		if nCurrPrice and nCurrPrice > 0 then
			if nBig == 0 then
				nBig = nCurrPrice
			end
		end
	end

	for nIdx, tCurrOrder in pairs(self.tOrders) do
		local tItem = tCurrOrder:GetItem()
		local iItemId = tItem:GetItemId()

		if(nItemId == iItemId) then

		self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityProfit"):SetAmount(nBig-nSmall, true) -- 2nd arg is bInstant
		self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityProfitPercent"):SetText(tonumber(string.format("%." .. 0 .. "f", nBig/nSmall*100)) .. "%", 0)

			iMyPrice = tCurrOrder:GetPricePerUnit():GetAmount()
			if(tCurrOrder:IsBuy()) then
				-- Print(tItem:GetName() .. ": " .. nSmall .. ">" .. iMyPrice)
				if(nSmall > iMyPrice) then 
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityDifference"):Show(true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityDifference"):SetAmount(nSmall-iMyPrice, true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityLost"):Show(true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityBuyBG"):Show(false)
				end
			else
				if(nBig < iMyPrice) then 
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityDifference"):Show(true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityDifference"):SetAmount(iMyPrice-nBig, true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommodityLost"):Show(true)
					self.CommodityOrdersHandlers[nIdx]:FindChild("CommoditySellBG"):Show(false)
				end
			end

		end

	end

end

function CheebaListings:BuildCommodityOrder(nIdx, aucCurrent)

	local tItem = aucCurrent:GetItem()
	local wndCurr = self:FactoryProduce(self.wndMain:FindChild("MainScroll"), "CommodityItem", aucCurrent)

	local nCount = aucCurrent:GetCount()
	local strPrefix = aucCurrent:IsBuy() and Apollo.GetString("CRB_Buy") or Apollo.GetString("CRB_Sell")

	self.CommodityOrdersHandlers[nIdx] = wndCurr

	self.CommodityTotalValue = self.CommodityTotalValue + (nCount*aucCurrent:GetPricePerUnit():GetAmount())

	self.wndMain:FindChild("CommodityTotalValue"):SetAmount(self.CommodityTotalValue, true)

	-- Tint a different color if Buy
	wndCurr:FindChild("CommodityCancelBtn"):SetData(aucCurrent)
	wndCurr:FindChild("CommodityBuyBG"):Show(aucCurrent:IsBuy())
	wndCurr:FindChild("CommoditySellBG"):Show(not aucCurrent:IsBuy())
	wndCurr:FindChild("CommodityBigIcon"):SetSprite(tItem:GetIcon())
	wndCurr:FindChild("CommodityIconAmountText"):SetText(nCount == 1 and "" or nCount)
	wndCurr:FindChild("CommodityItemName"):SetText(String_GetWeaselString(Apollo.GetString("MarketplaceListings_AuctionLabel"), strPrefix, tItem:GetName()))
	wndCurr:FindChild("CommodityPrice"):SetAmount(aucCurrent:GetPricePerUnit():GetAmount(), true) -- 2nd arg is bInstant
	wndCurr:FindChild("CommodityTimeLeftText"):SetText(self:HelperFormatTimeString(aucCurrent:GetExpirationTime()))
	Tooltip.GetItemTooltipForm(self, wndCurr:FindChild("CommodityBigIcon"), tItem, {bPrimary = true, bSelling = false, itemCompare = tItem:GetEquippedItemForItemType()})
end

function CheebaListings:BuildCreddOrder(nIdx, aucCurrent)
	local wndCurr = self:FactoryProduce(self.wndMain:FindChild("MainScroll"), "CreddItem", aucCurrent)
	wndCurr:FindChild("CreddCancelBtn"):SetData(aucCurrent)
	wndCurr:FindChild("CreddLabel"):SetText(aucCurrent:IsBuy() and Apollo.GetString("MarketplaceCredd_BuyLabel") or Apollo.GetString("MarketplaceCredd_SellLabel"))
	wndCurr:FindChild("CreddPrice"):SetAmount(aucCurrent:GetPrice(), true) -- 2nd arg is bInstant
	wndCurr:FindChild("CreddTimeLeftText"):SetText(self:HelperFormatTimeString(aucCurrent:GetExpirationTime()))
end

-----------------------------------------------------------------------------------------------
-- UI Interaction (mostly to cancel order)
-----------------------------------------------------------------------------------------------

function CheebaListings:OnCancelBtn(wndHandler, wndControl)
	local aucCurrent = wndHandler:GetData()
	if self.wndConfirmDelete == nil or not self.wndConfirmDelete:IsValid() then
		self.wndConfirmDelete = Apollo.LoadForm(self.xmlDoc, "ConfirmDelete", self.wndMain:FindChild("ConfirmBlocker"), self)
	end
	self.wndMain:FindChild("ConfirmBlocker"):Show(true)
	self.wndConfirmDelete:Invoke()
	
	self.wndConfirmDelete:FindChild("CancelCommodityConfirmBtn"):Show(wndHandler:GetName() == "CommodityCancelBtn")
	self.wndConfirmDelete:FindChild("CancelAuctionConfirmBtn"):Show(wndHandler:GetName() == "AuctionCancelBtn")
	self.wndConfirmDelete:FindChild("CancelCREDDListingBtn"):Show(wndHandler:GetName() == "CreddCancelBtn")
	
	if wndHandler:GetName() == "CommodityCancelBtn" then
		self.wndConfirmDelete:FindChild("CancelCommodityConfirmBtn"):SetData(aucCurrent)
		self.wndConfirmDelete:FindChild("Title"):SetText(Apollo.GetString("MarketplaceListings_CancelCommodityConfirm"))
		
	elseif wndHandler:GetName() == "AuctionCancelBtn" then
		self.wndConfirmDelete:FindChild("CancelAuctionConfirmBtn"):SetData(aucCurrent)
		self.wndConfirmDelete:FindChild("Title"):SetText(Apollo.GetString("MarketplaceListings_CancelAuctionConfirm"))

	else
		self.wndConfirmDelete:FindChild("CancelCREDDListingBtn"):SetData(aucCurrent)
		self.wndConfirmDelete:FindChild("Title"):SetText(Apollo.GetString("MarketplaceListings_CancelCREDDConfirm"))
	end
end

function CheebaListings:OnAuctionCancelConfirmBtn(wndHandler, wndControl)
	local aucCurrent = wndHandler:GetData()
	if not aucCurrent then
		return
	end
	aucCurrent:Cancel()
	self.wndMain:FindChild("MainScroll"):Show(false)
	self.wndConfirmDelete:Destroy()
	self.wndMain:FindChild("RefreshBlocker"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthLargeTemp")
	self.wndMain:FindChild("ConfirmBlocker"):Show(false)
end

function CheebaListings:OnCommodityCancelConfirmBtn(wndHandler, wndControl)
	local aucCurrent = wndHandler:GetData()
	if not aucCurrent or not aucCurrent:IsPosted() then
		return
	end
	aucCurrent:Cancel()
	self.wndMain:FindChild("MainScroll"):Show(false)
	self.wndConfirmDelete:Destroy()
	self.wndMain:FindChild("RefreshBlocker"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthLargeTemp")
	self.wndMain:FindChild("ConfirmBlocker"):Show(false)
end

function CheebaListings:OnCreddCancelConfirmBtn(wndHandler, wndControl)
	local aucCurrent = wndHandler:GetData()
	if not aucCurrent or not aucCurrent:IsPosted() then
		return
	end
	CREDDExchangeLib.CancelOrder(aucCurrent)
	self:RequestData()
	self.wndConfirmDelete:Destroy()
	self.wndMain:FindChild("RefreshBlocker"):SetSprite("CRB_WindowAnimationSprites:sprWinAnim_BirthLargeTemp")
	self.wndMain:FindChild("ConfirmBlocker"):Show(false)
end

function CheebaListings:OnCommodityItemSmallMouseEnter(wndHandler, wndControl)
	if wndHandler == wndControl and wndHandler:FindChild("CommodityCancelBtn") then
		wndHandler:FindChild("CommodityCancelBtn"):Show(true)
	end
end

function CheebaListings:OnCommodityItemSmallMouseExit(wndHandler, wndControl)
	if wndHandler == wndControl and wndHandler:FindChild("CommodityCancelBtn") then
		wndHandler:FindChild("CommodityCancelBtn"):Show(false)
	end
end

-----------------------------------------------------------------------------------------------
-- Auction/Commodity update events
-----------------------------------------------------------------------------------------------

function CheebaListings:OnCommodityAuctionRemoved(eAuctionEventType, oRemoved)
	-- TODO
	--if eAuctionEventType == MarketplaceLib.AuctionEventType.Fill then
	--elseif eAuctionEventType == MarketplaceLib.AuctionEventType.Expire then
	--elseif eAuctionEventType == MarketplaceLib.AuctionEventType.Cancel then
	--end

	if self.tOrders ~= nil then
		for nIdx, tCurrOrder in ipairs(self.tOrders) do
			if tCurrOrder == oRemoved then
				table.remove(self.tOrders, nIdx)
				break
			end
		end
		self:RedrawData()
	else
		self:RequestData()
	end
end

function CheebaListings:OnCommodityAuctionUpdated(oUpdated)
	if self.tOrders ~= nil then
		local bFound = false
		for nIdx, tCurrOrder in ipairs(self.tOrders) do
			if tCurrOrder == oUpdated then
				self.tOrders[nIdx] = oUpdated
				bFound = true
			end
		end
		if not bFound then
			table.insert(self.tOrders, oUpdated)
		end

		self:RedrawData()
	else
		self:RequestData()
	end
end

function CheebaListings:OnPostCommodityOrderResult(eAuctionResult, oAdded)
	if eAuctionResult ~= MarketplaceLib.AuctionPostResult.Ok or not oAdded:IsPosted() then
		return
	end

	if self.tOrders == nil then
		self.tOrders = {}
	end

	self:OnCommodityAuctionUpdated(oAdded)
end

function CheebaListings:OnItemAuctionRemoved(aucRemoved)
	if self.tAuctions ~= nil then
		for nIdx, aucCurrent in ipairs(self.tAuctions) do
			if aucCurrent == aucRemoved then
				table.remove(self.tAuctions, nIdx)
				break
			end
		end
		self:RedrawData()
	else
		self:RequestData()
	end
end

function CheebaListings:OnItemCancelResult(eAuctionResult, aucRemoved)
	if eAuctionResult == MarketplaceLib.AuctionPostResult.AlreadyHasBid then
		Event_FireGenericEvent("GenericEvent_LootChannelMessage", Apollo.GetString("MarketplaceListings_CantCancelHasBid"))
	end

	if eAuctionResult ~= MarketplaceLib.AuctionPostResult.Ok then
		return
	end

	self:OnItemAuctionRemoved(aucRemoved)
end

function CheebaListings:OnItemAuctionUpdated(aucUpdated)
	if self.tAuctions ~= nil then
		local bFound = false
		for nIdx, aucCurrent in ipairs(self.tAuctions) do
			if aucCurrent == aucUpdated then
				self.tAuctions[nIdx] = aucUpdated
				bFound = true
			end
		end
		if not bFound then
			table.insert(self.tAuctions, aucUpdated)
		end

		self:RedrawData()
	else
		self:RequestData()
	end
end

function CheebaListings:OnItemAuctionResult(eAuctionResult, aucAdded)
	if eAuctionResult ~= MarketplaceLib.AuctionPostResult.Ok then
		return
	end

	if self.tAuctions == nil then
		self.tAuctions = {}
	end

	self:OnItemAuctionUpdated(aucAdded)
end

function CheebaListings:OnItemListingClose(wndHandler, wndControl)
	
	if self.wndConfirmDelete and self.wndConfirmDelete:IsValid() then
		self.wndConfirmDelete:Destroy()
	end
	
	self.wndMain:FindChild("ConfirmBlocker"):Show(false)

end



-----------------------------------------------------------------------------------------------
-- Helpers
-----------------------------------------------------------------------------------------------

function CheebaListings:HelperFormatTimeString(oExpirationTime)
	local strResult = ""
	local nInSeconds = math.floor(math.abs(Time.SecondsElapsed(oExpirationTime))) -- CLuaTime object
	local nHours = math.floor(nInSeconds / 3600)
	local nMins = math.floor(nInSeconds / 60 - (nHours * 60))

	if nHours > 0 then
		strResult = String_GetWeaselString(Apollo.GetString("MarketplaceListings_Hours"), nHours)
	elseif nMins > 0 then
		strResult = String_GetWeaselString(Apollo.GetString("MarketplaceListings_Minutes"), nMins)
	else
		strResult = Apollo.GetString("MarketplaceListings_LessThan1m")
	end
	return strResult
end

function CheebaListings:FactoryProduce(wndParent, strFormName, tObject) -- Using AuctionObjects
	local wnd = wndParent:FindChildByUserData(tObject)
	if not wnd then
		wnd = Apollo.LoadForm(self.xmlDoc, strFormName, wndParent, self)
		wnd:SetData(tObject)
	end
	return wnd
end

local CheebaListingsInst = CheebaListings:new()
CheebaListingsInst:Init()
