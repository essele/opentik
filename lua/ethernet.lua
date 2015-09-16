#!./luajit

--
-- When we print we will need to be selective about default-name.
-- If it matches name then we don't show it
--


--
-- Maintain the lookup for system interface in the /interface (_if_lookup) section
-- so that we can map from interface events back to the correct item in the cf.
--
local function ether_ci_postprocess(path, ci, going)
	local uniq = ci._uniq
	local base = CONFIG["/interface"]
	local map = (not going and { ["path"] = path, ["uniq"] = uniq }) or nil

	base._if_lookup = base._if_lookup or {}
	base._if_lookup[ci._system_name] = map
end


--
--
--
lib.cf.register("/interface/ethernet", {
	["fields"] = {
		["name"] = { 
			uniq = true, 
			default=""
		},
		["default-name"] = { 	
			readonly = true, 
			default = function(_, ci) return ci._orig_name end,
			prep = function(_, ci)
							if ci.name == ci._orig_name then return nil end
							return ci._orig_name
						end
		 },
		["disabled"] = { 
			default = false,
			prep = false,
		},
		["mtu"] = { 
			restart = true, 
			default = 87654,
		},
		["type"] = { 
			readonly = true, 
			default = "ether",
			prep = false,
		},
	},
	
	["flags"] = {
		{ name = "disabled", field = "disabled", flag = "X", pos = 1 },
		{ name = "running", field = "_running", flag = "R", pos = 1 },
		{ name = "slave", field = "_slave", flag = "S", pos = 2 },
	},

	["options"] = {
		["duplicate"] = "/interface",
		["ci-post-process"] = ether_ci_postprocess,
		["can-delete"] = false,			-- can't delete ether interfaces
		["can-disable"] = true,			-- can disable them though
		["field-order"] = { "name", "default-name", "disabled", "mtu", "type" }
	},
})

--
-- Pre-init the ethernet interfaces
--
lib.cf.set("/interface/ethernet", nil, { ["name"] = "ether1", _system_name = "eth0", _orig_name = "ether1" })
lib.cf.set("/interface/ethernet", nil, { ["name"] = "ether2", _system_name = "eth1", _orig_name = "ether2" })
lib.cf.set("/interface/ethernet", nil, { ["name"] = "ether3", _system_name = "eth2", _orig_name = "ether3" })

