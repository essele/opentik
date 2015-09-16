#!./luajit

local function build_route_uniq(path, ci)
	print("BRU called for "..path)
	return string.format("%s|%s|%s|%s", ci["dst-address"],
			ci["routing-mark"], ci["type"], ci["scope"])
end

local function route_dependencies(path, ci)
	return {}
end


register("/ip/route", {
	["fields"] = {
		["dst-address"] = { default = "0.0.0.0/0" },
		["routing-mark"] = { default = "main" },
		["scope"] = { default = 30 },
		["type"] = { default = "unicast" },
		["pref-src"] = { default = "" },
		["gateway"] = { default = "" },
		["disabled"] = { default = false },
		["uniq"] = { uniq = build_route_uniq },
	},
	["dependencies"] = route_dependencies,
})

