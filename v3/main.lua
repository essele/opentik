#!./luajit
--------------------------------------------------------------------------------
--  This file is part of OpenTik
--  Copyright (C) 2014 Lee Essen <lee.essen@nowonline.co.uk>
--
--  This program is free software: you can redistribute it and/or modify
--  it under the terms of the GNU General Public License as published by
--  the Free Software Foundation, either version 3 of the License, or
--  (at your option) any later version.
--
--  This program is distributed in the hope that it will be useful,
--  but WITHOUT ANY WARRANTY; without even the implied warranty of
--  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
--  GNU General Public License for more details.
--
--  You should have received a copy of the GNU General Public License
--  along with this program.  If not, see <http://www.gnu.org/licenses/>.
------------------------------------------------------------------------------

package.path = "./lib/?.lua"
package.cpath = "./lib/?.so"

-- global level packages
require("lfs")
require("utils")
require("config")
--require("api")

-- different namespace packages
local base64 = require("base64")

--
-- global configuration spaces
--
master={}
current={}
new={}

--
-- import all of the core modules
--
dofile("core/interface.lua")
dofile("core/iptables.lua")
dofile("core/dnsmasq.lua")


function other() 
	print("other: dummy function called")
end


master["test"] = { ["function"] = other }
master["test/lee"] = { ["type"] = "name" }



current["interface/ethernet/*0/ip"] = "192.168.95.1/24"
current["interface/ethernet/*1/ip"] = "192.168.95.2/24"
current["interface/ethernet/*2/ip"] = "192.168.95.33"
current["interface/ethernet/*2/mtu"] = 1500
current["interface/ethernet/*0/mtu"] = 1500
current["interface/ethernet/fred"] = "yep"

current["dns/forwarder/server"] = { "one", "two", "three" }
current["dns/file"] = "afgljksdhfglkjsdhf glsjdfgsdfg\nsdfgkjsdfkljg\nsdfgsdg\nsdfgsdfg\n"





new = copy_table(current)
new["interface/ethernet/*1/ip"] = "192.168.95.4/24"
--new["interface/ethernet/*2/ip"] = "192.168.95.33"
new["interface/ethernet/*0/mtu"] = nil
current["interface/ethernet/bill"] = "nope"

new["iptables/*filter/*FORWARD/policy"] = "ACCEPT"
new["iptables/*filter/*FORWARD/rule/*10"] = "-s 12.3.4 -j ACCEPT"
new["iptables/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"
--new["iptables2/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"

new["dns/forwarding/server"] = { "one", "three", "four" }
new["dns/forwarding/cache-size"] =150
new["dns/forwarding/listen-on"] = { "eth0" }
--new["dns/forwarding/options"] = { "no-resolv", "other-stuff" }

new["dns/domain-match/*xbox/domain"] = { "XBOXLIVE.COM", "xboxlive.com", "live.com" }
new["dns/domain-match/*xbox/group"] = "vpn-dst"
new["dns/domain-match/*iplayer/domain"] = { "bbc.co.uk", "bbci.co.uk" }
new["dns/domain-match/*iplayer/group"] = "vpn-dst"

new["dhcp/flag"] = "hello"


CF_new = new
CF_current = current



rc, err = set(new, "interface/ethernet/0/mtu", "1234")
if not rc then print("ERROR: " .. err) end
rc, err = set(new, "iptables/filter/INPUT/rule/0030", "-a -b -c")
if not rc then print("ERROR: " .. err) end

rc, err = set(new, "iptables/nat/PREROUTING/rule/0010", "-a -b -c")
rc, err = set(new, "iptables/mangle/PREROUTING/rule/0010", "-a -b -c")
rc, err = set(new, "iptables/nat/POSTROUTING/rule/0020", "-a -b -c")


--delete(new, "iptables")
delete(new, "interface/ethernet/2")
--delete(new, "dns")
--delete(new, "dhcp")

show(current, new)
--dump(new)
----local xx = import("sample")
--
----show(xx, xx)
--
----
---- Build the work list
----
work_list = build_work_list(current, new)

--print("\n\n")
--
-- Now run through and check the dependencies
--
for key, fields in pairs(work_list) do
	print("Work: " .. key)
	for i,v in ipairs(fields) do
		print("\t" .. v)
	end
	local depends = master[key]["depends"] or {}
	for _,d in ipairs(depends) do
		print("\tDEPEND: " .. d)
		if work_list[d] then
			print("\tSKIP THIS ONE DUE TO DEPENDS")
			goto continue
		end
	end
	print("DOING WORK for ["..key.."]\n")
	local func = master[key]["function"]
	local work_hash = values_to_keys(work_list[key])

	local ok, rc, err = pcall(func, work_hash)
	print("ok="..tostring(ok).." rc="..tostring(rc).." err="..tostring(err))

	work_list[key] = nil
::continue::
end


