	
	-- ============================================================================
	--	GMS/Core/UI/AceEmbedding.lua
	--	AceGUI embedding into the WoW content frame
	-- ============================================================================
	
	local LibStub = LibStub
	if not LibStub then return end
	
	local AceAddon = LibStub("AceAddon-3.0", true)
	if not AceAddon then return end
	
	local GMS = AceAddon:GetAddon("GMS", true)
	if not GMS then return end
	
	local UI = GMS:GetModule("UI", true)
	if not UI then return end
	
	local AceGUI = LibStub("AceGUI-3.0", true)
	if not AceGUI then return end
	
	-- ---------------------------------------------------------------------------
	--	Releases the AceGUI root widget (if any)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:ACE_ReleaseAceRootIfPresent()
	if self._root and AceGUI then
		AceGUI:Release(self._root)
	end
	self._root = nil
	end
	
	-- ---------------------------------------------------------------------------
	--	Ensures a fresh AceGUI root (SimpleGroup Fill) exists in the content frame
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:ACE_EnsureAceRootExists()
	if not self._content then return end
	self:ACE_ReleaseAceRootIfPresent()
	
	local root = AceGUI:Create("SimpleGroup")
	root:SetLayout("Fill")
	root.frame:SetParent(self._content)
	root.frame:ClearAllPoints()
	root.frame:SetAllPoints(self._content)
	root.frame:Show()
	
	self._root = root
	end
	
	-- ---------------------------------------------------------------------------
	--	Releases all children from the root (safe)
	--
	--	@return nil
	-- ---------------------------------------------------------------------------
	function UI:ACE_ReleaseChildrenFromRoot()
	if not self._root then return end
	self._root:ReleaseChildren()
	end
