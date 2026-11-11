-- HideTrackerForever
-- Permanently hides the default Blizzard objective/quest tracker so that
-- guide windows (e.g. RestedXP) sit alone on the right side of the screen.
--
-- Author: jake (jrpbuilds on GitHub)
--
-- Covers both API generations defensively, since either (or both) may exist
-- on this client:
--   * modern-style:      _G.ObjectiveTrackerFrame
--   * classic-era style: _G.WatchFrame
--
-- Why a login-time :Hide() is not enough: auto quest tracking re-shows the
-- tracker a few seconds later. Persistence comes from three layers:
--   1. secure hooks on each tracker's "Show" and "SetParent" that re-hide
--      instantly after anything re-shows or re-parents the frame
--   2. an OnUpdate safety net sweeping at most once per second
--   3. a re-hook pass on every sweep, catching tracker frames that are only
--      created after login (some clients build ObjectiveTrackerFrame late)
-- Neither frame name is guaranteed to exist, so every access is nil-safe and
-- the addon fails silently rather than erroring at login.
--
-- Toggle with /htf (or /hidetrackerforever), or the minimap button.
-- State is saved in HideTrackerForeverDB and restored on login /reload.

local ADDON_NAME = "HideTrackerForever"
local ICON_PATH = "Interface\\AddOns\\HideTrackerForever\\Media\\icon"
-- Sit on the minimap rim like LibDBIcon / other addon buttons (not inset).
local MINIMAP_EDGE_PAD = 5

local TRACKER_NAMES = { "ObjectiveTrackerFrame", "WatchFrame" }

local hooked = {}     -- tracker frames that already have Show/SetParent hooks
local sweepAccum = 0  -- seconds since the last sweep (1s throttle)
local enabled = true  -- master switch: true = tracker hidden, false = shown
local initialized = false
local minimapButton

-- ---------------------------------------------------------------------------
-- SavedVariables
-- ---------------------------------------------------------------------------

local function defaults()
	return {
		enabled = true,
		minimap = {
			angle = 220,
			hide = false,
		},
	}
end

local function initDB()
	local db = HideTrackerForeverDB
	if type(db) ~= "table" then
		db = defaults()
		HideTrackerForeverDB = db
	end

	if db.enabled == nil then
		db.enabled = true
	end
	if type(db.minimap) ~= "table" then
		db.minimap = defaults().minimap
	end
	if type(db.minimap.angle) ~= "number" then
		db.minimap.angle = 220
	end
	if db.minimap.hide == nil then
		db.minimap.hide = false
	end

	enabled = db.enabled and true or false
	return db
end

local function db()
	return HideTrackerForeverDB
end

-- ---------------------------------------------------------------------------
-- Tracker hide / show
-- ---------------------------------------------------------------------------

local function isShown(frame)
	return frame ~= nil and frame:IsShown()
end

-- Names of the tracker frames that currently exist (possibly empty).
local function existingTrackers()
	local found = {}
	for _, name in ipairs(TRACKER_NAMES) do
		if _G[name] then
			found[#found + 1] = name
		end
	end
	return found
end

-- Attach secure Show/SetParent hooks once per frame. hooksecurefunc lets the
-- original call go through, then re-hides immediately after it completes --
-- so any addon or the client that re-shows / re-parents the tracker loses.
-- Secure hooks cannot be unhooked for the session, so while the toggle is
-- off the hooks stay attached but see enabled == false and do nothing.
-- Only :Hide() is called inside the callbacks: SetParent/Move are protected
-- in combat lockdown, Hide is not, so the hooks can never hard-error.
local function hookTracker(frame)
	if not frame or hooked[frame] then
		return
	end
	hooked[frame] = true

	hooksecurefunc(frame, "Show", function(f)
		if enabled then
			f:Hide()
		end
	end)
	hooksecurefunc(frame, "SetParent", function(f)
		if enabled then
			f:Hide()
		end
	end)

	if enabled then
		frame:Hide()
	end
end

-- Hook every tracker name that currently exists in _G. Called repeatedly:
-- cheap, and it is what keeps late-created tracker frames covered and what
-- makes toggling back on instant (hooks are already in place in both states).
local function hookAllTrackers()
	for _, name in ipairs(TRACKER_NAMES) do
		hookTracker(_G[name])
	end
end

-- Re-hook late frames and hide any tracker that is visible again
-- (hiding only applies while the master switch is on).
local function enforceHidden()
	if not initialized then
		return
	end
	hookAllTrackers()
	if not enabled then
		return
	end
	for _, name in ipairs(TRACKER_NAMES) do
		local frame = _G[name]
		if isShown(frame) then
			frame:Hide()
		end
	end
end

local function refreshTrackerContent()
	if WatchFrame_Update then
		pcall(WatchFrame_Update)
	end
	if ObjectiveTracker_Update then
		pcall(ObjectiveTracker_Update)
	end
end

local updateMinimapButton -- forward declaration

-- Flip the tracker window's display: on = hidden forever, off = visible
-- again. Showing fires the trackers' own Show hooks, but they see the
-- switch is off and leave the window alone.
local function setEnabled(state)
	enabled = state and true or false

	local saved = db()
	if saved then
		saved.enabled = enabled
	end

	for _, name in ipairs(existingTrackers()) do
		local frame = _G[name]
		if enabled then
			frame:Hide()
		else
			frame:Show()
		end
	end

	-- After re-showing, ask the client to redraw tracker content, or the
	-- window reappears blank until the next game event.
	if not enabled then
		refreshTrackerContent()
	end

	if updateMinimapButton then
		updateMinimapButton()
	end
end

-- ---------------------------------------------------------------------------
-- Minimap button
-- ---------------------------------------------------------------------------

local function minimapAngle()
	local saved = db()
	if saved and saved.minimap and type(saved.minimap.angle) == "number" then
		return saved.minimap.angle
	end
	return 220
end

local function positionMinimapButton()
	if not minimapButton or not Minimap then
		return
	end
	-- Radius from actual minimap size so the button rides the edge.
	-- Fixed 80px inset the button on Forever's larger minimap.
	local angle = math.rad(minimapAngle())
	local radiusX = (Minimap:GetWidth() / 2) + MINIMAP_EDGE_PAD
	local radiusY = (Minimap:GetHeight() / 2) + MINIMAP_EDGE_PAD
	minimapButton:ClearAllPoints()
	minimapButton:SetPoint(
		"CENTER",
		Minimap,
		"CENTER",
		math.cos(angle) * radiusX,
		math.sin(angle) * radiusY
	)
end

updateMinimapButton = function()
	if not minimapButton then
		return
	end

	local saved = db()
	local hideButton = saved and saved.minimap and saved.minimap.hide
	if hideButton then
		minimapButton:Hide()
	else
		minimapButton:Show()
	end

	local icon = minimapButton.icon
	if icon then
		-- Full color while actively hiding; dim when the tracker is allowed
		-- to show so the button state is readable at a glance.
		if enabled then
			icon:SetVertexColor(1, 1, 1, 1)
			if icon.SetDesaturated then
				icon:SetDesaturated(false)
			end
		else
			icon:SetVertexColor(0.55, 0.55, 0.55, 1)
			if icon.SetDesaturated then
				icon:SetDesaturated(true)
			end
		end
	end

	positionMinimapButton()
end

local function createMinimapButton()
	if minimapButton or not Minimap then
		return
	end

	-- Layout matches Blizzard/LibDBIcon minimap buttons so the gold
	-- MiniMap-TrackingBorder rings the art instead of framing a square inside it.
	local btn = CreateFrame("Button", "HideTrackerForeverMinimapButton", Minimap)
	btn:SetSize(31, 31)
	btn:SetFrameStrata("MEDIUM")
	btn:SetFrameLevel(8)
	btn:RegisterForClicks("LeftButtonUp")
	btn:RegisterForDrag("LeftButton")
	btn:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")
	btn:SetMovable(true)
	btn:EnableMouse(true)

	local icon = btn:CreateTexture(nil, "BACKGROUND")
	icon:SetSize(20, 20)
	icon:SetPoint("TOPLEFT", 7, -5)
	icon:SetTexture(ICON_PATH)
	btn.icon = icon

	local border = btn:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	btn:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:ClearLines()
		GameTooltip:AddLine("HideTrackerForever", 1, 0.82, 0)
		if enabled then
			GameTooltip:AddLine("Tracker: |cff00ff00HIDDEN|r", 1, 1, 1)
			GameTooltip:AddLine("Left-click to show the objective tracker.", 0.8, 0.8, 0.8, true)
		else
			GameTooltip:AddLine("Tracker: |cffff6060VISIBLE|r", 1, 1, 1)
			GameTooltip:AddLine("Left-click to hide the objective tracker.", 0.8, 0.8, 0.8, true)
		end
		GameTooltip:AddLine("Drag to move this button.", 0.55, 0.55, 0.55, true)
		GameTooltip:Show()
	end)

	btn:SetScript("OnLeave", function()
		GameTooltip:Hide()
	end)

	btn:SetScript("OnClick", function(self)
		-- Ignore the click that ends a drag so repositioning does not toggle.
		if self._dragged then
			self._dragged = nil
			return
		end
		setEnabled(not enabled)
		if GameTooltip:IsOwned(self) then
			self:GetScript("OnEnter")(self)
		end
	end)

	btn:SetScript("OnDragStart", function(self)
		self._dragged = true
		self:LockHighlight()
		GameTooltip:Hide()
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local scale = Minimap:GetEffectiveScale()
			local cx, cy = GetCursorPosition()
			cx, cy = cx / scale, cy / scale
			local saved = db()
			if saved and saved.minimap then
				saved.minimap.angle = math.deg(math.atan2(cy - my, cx - mx))
			end
			positionMinimapButton()
		end)
	end)

	btn:SetScript("OnDragStop", function(self)
		self:SetScript("OnUpdate", nil)
		self:UnlockHighlight()
	end)

	minimapButton = btn
	updateMinimapButton()
end

-- ---------------------------------------------------------------------------
-- Safety net + login
-- ---------------------------------------------------------------------------

-- Sweep at most once per second and re-hide any tracker that reappeared.
local sweep = CreateFrame("Frame", "HideTrackerForeverSweep", UIParent)
sweep:SetScript("OnUpdate", function(_, delta)
	if not initialized then
		return
	end
	sweepAccum = sweepAccum + (delta or 0)
	if sweepAccum < 1 then
		return
	end
	sweepAccum = 0
	enforceHidden()
end)

local bootstrap = CreateFrame("Frame")
bootstrap:RegisterEvent("ADDON_LOADED")
bootstrap:RegisterEvent("PLAYER_ENTERING_WORLD")
bootstrap:SetScript("OnEvent", function(self, event, arg1)
	if event == "ADDON_LOADED" then
		if arg1 ~= ADDON_NAME then
			return
		end
		initDB()
		initialized = true
		createMinimapButton()
		setEnabled(enabled)
		self:UnregisterEvent("ADDON_LOADED")
	elseif event == "PLAYER_ENTERING_WORLD" then
		enforceHidden()
		-- Minimap may not exist until the world UI is up on some clients.
		if not minimapButton then
			createMinimapButton()
		else
			updateMinimapButton()
		end
	end
end)

-- ---------------------------------------------------------------------------
-- Slash commands
-- ---------------------------------------------------------------------------

SLASH_HIDETRACKERFOREVER1 = "/htf"
SLASH_HIDETRACKERFOREVER2 = "/hidetrackerforever"
SlashCmdList.HIDETRACKERFOREVER = function(msg)
	msg = string.gsub(string.lower(msg or ""), "^%s*(.-)%s*$", "%1")
	if msg == "on" then
		setEnabled(true)
	elseif msg == "off" then
		setEnabled(false)
	elseif msg == "minimap" or msg == "button" then
		local saved = db()
		if not saved then
			return
		end
		if type(saved.minimap) ~= "table" then
			saved.minimap = defaults().minimap
		end
		saved.minimap.hide = not saved.minimap.hide
		if not minimapButton then
			createMinimapButton()
		end
		updateMinimapButton()
	else
		setEnabled(not enabled)
	end
end
