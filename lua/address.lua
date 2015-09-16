#!./luajit


register("/ip/address", {
	["fields"] = {
		["disabled"] = { },
		["address"] = { },
		["interface"] = { },
		["network"] = { },
	},
	["cf"] = {
		{ ["address"] = "5.133.182.9/24", ["interface"] = "eth0" },
		{ ["address"] = "192.168.95.1/24" },
		{ ["address"] = "10.7.0.1/8" },
	},
})

--
-- Unique matching sequence used to match live data with config data
--
local function address_build_uniq(rt)
	return string.format("%s|%s", rt["address"], rt["interface"] or "")
end

--
-- Read the address list and populate a live structure
--
local function address_get_live(base)
	local rc = {}
	local fh = io.popen("ip -4 addr show", "r")
	local iface = nil
	for entry in fh:lines() do
		local addr = {}
		local testiface = entry:match("^%d+:%s+([^:]+):")

		if testiface then
			iface = testiface
			goto continue
		end

		if iface == "lo" then goto continue end

		local ip = entry:match("inet%s+([^%s]+)%s")
		if ip then
			print("GOT iface="..iface.." ip="..ip)
			local o1, o2, o3, o4, nm = ip:match("(%d+)%.(%d+)%.(%d+)%.(%d+)/(%d+)")
			local quad = bit.lshift(o1, 24) + bit.lshift(o2, 16) + bit.lshift(o3, 8) + o4
			local mask = bit.lshift((2^nm)-1, 32-nm)
			local res = bit.band(quad, mask)

			local nm = string.format("%d.%d.%d.%d", 
						bit.rshift(bit.band(res, 0xff000000), 24),
						bit.rshift(bit.band(res, 0x00ff0000), 16),
						bit.rshift(bit.band(res, 0x0000ff00), 8),
						bit.band(res, 0x000000ff))
			
			print(string.format("Quad is %x ... mask is %x == %x", quad, mask, res))
			print("NET="..nm)

			local live = {
				["address"] = ip,
				["network"] = nm,
				["interface"] = iface
			}
			local uniq = base._build_uniq(live)
			live["_uniq"] = uniq
			rc[uniq] = live
		end
::continue::
	end
	return rc
end

--
-- Setup the function to get live data
--
CONFIG["/ip/address"]._get_live = address_get_live
CONFIG["/ip/address"]._build_uniq = address_build_uniq



