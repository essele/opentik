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

master["test"] = { ["function"] = other }
master["test/lee"] = { ["type"] = "name" }

master["iptables"] = { ["function"] = iptables }
master["iptables/*"] = { ["style"] = "iptables_table" }
master["iptables/*/*"] = { ["style"] = "iptables_chain" }
master["iptables/*/*/policy"] = { ["type"] = "iptables_policy" }
master["iptables/*/*/rule"] = {     ["with_children"] = 1 }
master["iptables/*/*/rule/*"] = {   ["style"] = "OK",
                                    ["type"] = "iptables_rule",
                                    ["quoted"] = 1 }

master["dns"] = { ["function"] = "xxx" }

master["dns/forwarder"] = {}
master["dns/forwarder/server"] = { ["type"] = "OK", ["list"] = 1 }
master["dns/file"] = { ["type"] = "file/text" }

master["dhcp"] = {  ["delegate"] = "dns" }
master["dhcp/flag"] = { ["type"] = "string" }




current["interface/ethernet/*0/ip"] = "192.168.95.1/24"
current["interface/ethernet/*1/ip"] = "192.168.95.2/24"
current["interface/ethernet/*0/mtu"] = 1500

current["dns/forwarder/server"] = { "one", "two", "three" }
current["dns/file"] = "afgljksdhfglkjsdhf glsjdfgsdfg\nsdfgkjsdfkljg\nsdfgsdg\nsdfgsdfg\n"





new = copy_table(current)
new["interface/ethernet/*1/ip"] = "192.168.95.4/24"
new["interface/ethernet/*2/ip"] = "192.168.95.33"
new["interface/ethernet/*0/mtu"] = nil

new["iptables/*filter/*FORWARD/policy"] = "ACCEPT"
new["iptables/*filter/*FORWARD/rule/*10"] = "-s 12.3.4 -j ACCEPT"
new["iptables/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"
--new["iptables2/*filter/*FORWARD/rule/*20"] = "-d 2.3.4.5 -j DROP"

new["dns/forwarder/server"] = { "one", "three", "four" }
new["dhcp/flag"] = "hello"


rc, err = set(new, "interface/ethernet/0/mtu", "1234")
if not rc then print("ERROR: " .. err) end
rc, err = set(new, "iptables/filter/INPUT/rule/0030", "-a -b -c")
if not rc then print("ERROR: " .. err) end
rc, err = set(new, "dns/forwarder/server", "a new one")
if not rc then print("ERROR: " .. err) end

delete(new, "iptables")

show(current, new)
--dump(new)
----local xx = import("sample")
--
----show(xx, xx)
--
----
---- Build the work list
----
work_list = build_work_list()

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
	print("DOING WOEK\n")
	work_list[key] = nil
::continue::
end


