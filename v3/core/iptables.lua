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

function iptables(changes)
    print("Hello From IPTABLES")

	local tables = node_list("iptables/*", changes)
	for _,table in ipairs(tables) do
		print("TABLE: " .. table)
		process_table(table, changes)
	end
end

--
-- 
--
function process_table(table, changes)
    local state = process_changes(changes, string.format("iptables/*%s/", table))

    for _,v in ipairs(state.added) do print("Added: "..v) end
    for _,v in ipairs(state.removed) do print("Removed: "..v) end
    for _,v in ipairs(state.changed) do print("Changed: "..v) end
	
end




VALIDATOR["iptables_table"] = function(v, kp)
	local valid = { ["filter"] = 1, ["mangle"] = 1, ["nat"] = 1, ["raw"] = 1 }

	if valid[v] then return OK end
	--
	-- Now check for partial...
	--
	for k,_ in pairs(valid) do
		if k:sub(1, #v) == v then return PARTIAL, "invalid table name" end
	end
	return FAIL, "invalid table name"
end

VALIDATOR["iptables_chain"] = function(v, kp)
	print("Validating chain ("..v..") for keypath ("..kp..")")
	return OK
end

VALIDATOR["iptables_rule"] = function(v, kp)
	print("Validating rule ("..v..") for keypath ("..kp..")")
	return OK
end

VALIDATOR["OK"] = function(v)
	return OK
end

--
-- Master Structure for iptables
--
master["iptables"] = { ["function"] = iptables }
master["iptables/*"] = { ["style"] = "iptables_table" }
master["iptables/*/*"] = { ["style"] = "iptables_chain" }
master["iptables/*/*/policy"] = { ["type"] = "iptables_policy" }
master["iptables/*/*/rule"] = {     ["with_children"] = 1 }
master["iptables/*/*/rule/*"] = {   ["style"] = "OK",
                                    ["type"] = "iptables_rule",
                                    ["quoted"] = 1 }


