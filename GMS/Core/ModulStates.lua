	-- ============================================================================
	--	GMS/Core/ModulStates.lua
	--	GMS.STATES - minimal state registry (can load BEFORE GMS.lua)
	--
	--	PUBLIC API (ONLY):
	--		- GMS.STATES:UPDATE(name, state, reason, meta)
	--		- GMS.STATES:CHECK(name) -> UPPERCASE snapshot
	--		- GMS.STATES:ONUPDATE(fn)
	--
	--	STATES (recommended):
	--		LOADED, INITIALIZED, ENABLED, DISABLED, READY, FAILED
	--
	--	RULES:
	--		- UPDATE(name,"READY")     => ready=true (lifecycle unchanged)
	--		- UPDATE(name,"DISABLED")  => disabled=true, ready=false
	--		- UPDATE(name,"ENABLED")   => disabled=false (ready unchanged)
	--		- UPDATE(name,"FAILED")    => ready=false (disabled unchanged)
	-- ============================================================================

	local _G = _G

	-- Minimaler Namespace-Bootstrap (damit diese Datei vor GMS.lua laden kann)
	_G.GMS = _G.GMS or {}
	_G.GMS.STATES = _G.GMS.STATES or {}

	local STATES = _G.GMS.STATES

	-- Persistente interne Daten (auf dem Singleton)
	STATES._data = STATES._data or {}
	STATES._listeners = STATES._listeners or {}
	STATES._sequence = STATES._sequence or 0

	local DATA = STATES._data
	local LISTENERS = STATES._listeners

	-- ---------------------------------------------------------------------------
	--	Private Helpers (nicht exportiert)
	-- ---------------------------------------------------------------------------

	local function INTERNAL_Now()
		if type(_G.GetTime) == "function" then return _G.GetTime() end
		if type(_G.time) == "function" then return _G.time() end
		return 0
	end

	local function INTERNAL_NormName(name)
		return type(name) == "string" and name or tostring(name)
	end

	local function INTERNAL_Ensure(name)
		local e = DATA[name]
		if not e then
			e = {
				name = name,
				state = "MISSING",
				ready = false,
				disabled = false,
				reason = nil,
				meta = nil,
				sequence = 0,
				timestamp = 0,
			}
			DATA[name] = e
		end
		return e
	end

	local function INTERNAL_Stamp(e)
		STATES._sequence = (STATES._sequence or 0) + 1
		e.sequence = STATES._sequence
		e.timestamp = INTERNAL_Now()
	end

	local function INTERNAL_SnapshotFromEntry(e)
		return {
			NAME      = e.name,
			STATE     = e.state,
			READY     = e.ready,
			DISABLED  = e.disabled,
			REASON    = e.reason,
			META      = e.meta,
			SEQUENCE  = e.sequence,
			TIMESTAMP = e.timestamp,
		}
	end

	local function INTERNAL_SnapshotMissing(name)
		return {
			NAME      = name,
			STATE     = "MISSING",
			READY     = false,
			DISABLED  = false,
			REASON    = nil,
			META      = nil,
			SEQUENCE  = 0,
			TIMESTAMP = 0,
		}
	end

	local function INTERNAL_Notify(name, snap)
		for i = 1, #LISTENERS do
			local fn = LISTENERS[i]
			if type(fn) == "function" then
				pcall(fn, name, snap)
			end
		end
	end

	-- ---------------------------------------------------------------------------
	--	PUBLIC: ONUPDATE
	-- ---------------------------------------------------------------------------

	function STATES:ONUPDATE(fn)
		if type(fn) ~= "function" then
			return false
		end

		LISTENERS[#LISTENERS + 1] = fn
		return true
	end

	-- ---------------------------------------------------------------------------
	--	PUBLIC: CHECK
	-- ---------------------------------------------------------------------------

	function STATES:CHECK(name)
		name = INTERNAL_NormName(name)

		local e = DATA[name]
		if not e then
			return INTERNAL_SnapshotMissing(name)
		end

		return INTERNAL_SnapshotFromEntry(e)
	end

	-- ---------------------------------------------------------------------------
	--	PUBLIC: UPDATE
	-- ---------------------------------------------------------------------------

	function STATES:UPDATE(name, state, reason, meta)
		name = INTERNAL_NormName(name)
		state = tostring(state or "MISSING")

		local e = INTERNAL_Ensure(name)

		-- READY Marker: nur ready=true, state bleibt unverändert
		if state == "READY" then
			e.ready = true
			if reason ~= nil then e.reason = reason end
			if meta ~= nil then e.meta = meta end

			INTERNAL_Stamp(e)

			local snap = INTERNAL_SnapshotFromEntry(e)
			INTERNAL_Notify(name, snap)
			return snap
		end

		-- Normaler Lifecycle-State
		e.state = state

		if state == "DISABLED" then
			e.disabled = true
			e.ready = false
		elseif state == "ENABLED" then
			e.disabled = false
			-- ready bleibt unverändert
		elseif state == "FAILED" then
			e.ready = false
			-- disabled bleibt unverändert
		end

		if reason ~= nil then e.reason = reason end
		if meta ~= nil then e.meta = meta end

		INTERNAL_Stamp(e)

		local snap = INTERNAL_SnapshotFromEntry(e)
		INTERNAL_Notify(name, snap)
		return snap
	end

	-- Subsystem selbst markieren
	STATES:UPDATE("STATES", "ENABLED")
	STATES:UPDATE("STATES", "READY")
