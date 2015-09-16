--
-- vi:filetype=lua
--

--
-- Standard ipv4 addresses (eg. 1.2.3.4)
--
VALIDATOR["Xipv4"] = function(v)
	local a,b,c,d = string.match(v, "^(%d+)%.(%d+)%.(%d+).(%d+)$")

	if(not a) then return false, "invalid ipv4 address" end
	a, b, c, d = tonumber(a), tonumber(b), tonumber(c), tonumber(d)

	if(a>255 or b>255 or c>255 or d>255 ) then return false, "invalid ipv4 address" end
	return true
end


--
-- primary function for handling dnsmasq configuration. We don't really deal
-- with adds and removes here, we just create the needed config and (re)start the
-- process.
--
local function cf_dnsmasq(path, key, config)
	print("This is the cf_dnsmasq function")

	print("PATH="..tostring(path))
	print("KEY="..tostring(key))
	dump(config)

	local cf = config.dc

	-- get our resolvers...
	local resolvers = cf.dns and cf.dns.resolvers;
	if(resolvers) then
		for i,v in ipairs(resolvers) do
			print("RESOLVER: ["..i.."] -- "..v)
		end
	end

	-- host entries
	local hosts = cf.dns and cf.dns.host;
	if(hosts) then
		for k,v in pairs(hosts) do
			print("HOST: " .. k .. " IP="..v.ipv4)
		end
	end

	return true
end

--
-- our dnsmasq (dns/dhcp) definition
--
CONFIG.master["dnsmasq"] = {
	_hidden = 1,
	_function = cf_dnsmasq,
	["dns"] = {
		["resolvers"] = {
			_type = "list/ipv4"
		},
		["host"] = {
			_keep_with_children = 1,
			["*"] = {
				["ipv4"] = { _type = "ipv4" },
				["aliases"] = { _type = "list/hostname" },
			}
		},
	},
	["dhcp"] = {
		["blag"] = {
			_type = "string"
		}
	}
}

CONFIG.master["dns"] = { _alias = "/dnsmasq/dns" }
CONFIG.master["dhcp"] = { _alias = "/dnsmasq/dhcp" }

