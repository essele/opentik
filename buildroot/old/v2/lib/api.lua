--------------------------------------------------------------------------------
--  This file is part of OpenTik.
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
--------------------------------------------------------------------------------


-- ==============================================================================
-- ==============================================================================
--
-- These are the functions that provide api calls for any modules. These
-- calls handle the delta in configs.
--
-- ==============================================================================
-- ==============================================================================

--
-- At the node level we may be entirely added or removed
--
function is_added(config)
	local ac, dc = config.ac, config.dc

	if(dc and not ac) then return true end
	return false
end
function is_deleted(config)
	local ac, dc = config.ac, config.dc

	if(ac and not dc) then return true end
	return false
end

--
-- For each item (fields and containers) we return an iterator covering
-- the ones that were added, remove or changed. (or all)
--
function each_element(config)
	local dc = config.dc or {}
	local last

	return function()
		while(1) do
			last = next(dc, last)
			return last
		end
	end
end
function each_added(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(dc, last)
			if(not last) then return nil end
			if(not ac[last]) then return last, dc[last] end
		end
	end
end
function each_deleted(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(ac, last)
			if(not last) then return nil end
			if(not dc[last]) then return last, ac[last] end
		end
	end
end
function each_changed(config)
	local ac, dc = config.ac or {}, config.dc or {}
	local last

	return function()
		while(1) do
			last = next(dc, last)
			if(not last) then return nil end
			if(ac[last] and ac[last] ~= dc[last]) then return last, ac[last], dc[last] end
		end
	end
end

