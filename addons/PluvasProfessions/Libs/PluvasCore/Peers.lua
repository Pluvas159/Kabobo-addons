-- PluvasCore: Pluvas addons that work together.
--
-- Every addon still ships and runs on its own. A feature that needs another Pluvas addon asks for
-- it with ns:Peer(name) each time it runs, and shows nothing when that addon is not loaded. Load
-- order between addons is not guaranteed, so never cache a peer at load time.
--
-- APIs live in one shared global table, PluvasAddons[addon folder name]: the only global
-- PluvasCore creates on its own. An exposed API is a contract: add functions, but do not change
-- what existing ones take or return.
local _, ns = ...

-- Publishes this addon's API (a table of functions) for other Pluvas addons.
function ns:Expose(api)
	local registry = _G.PluvasAddons
	if type(registry) ~= "table" then
		registry = {}
		_G.PluvasAddons = registry
	end
	registry[ns.name] = api
	return api
end

-- Another Pluvas addon's API, or nil when that addon is not loaded (missing or disabled).
function ns:Peer(name)
	local registry = _G.PluvasAddons
	if type(registry) ~= "table" then return nil end
	return registry[name]
end
