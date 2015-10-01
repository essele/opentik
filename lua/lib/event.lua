--------------------------------------------------------------------------------
--  This file is part of OpenTik
--  Copyright (C) 2014,15 Lee Essen <lee.essen@nowonline.co.uk>
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

local SOCK_NAME = "/tmp/opentik.sock"

--
-- We have a series of things that can create events, these are typically
-- file handle based (libnl or our event stream) or perhaps signals, or a
-- timer system.
--
-- We use poll() to react to incoming events and then call the relevant
-- callback.
--

local function stdin_read(fd)
	local d = posix.unistd.read(fd, 1024)
	print("STDIN: "..d)
end

local fds = {
--	[1] = { events = {IN=true}, callback=stdin_read },

}


--
-- The callback used when we receive an external event, we need to look it
-- up in the config and call the relevant function
--
local function event_recv(fdt)
	local fd = fdt.fd
	local raw = posix.sys.socket.recv(fd, 1024)
	print("RAW="..raw)
	local event = lib.util.unserialise(raw)

	print("Path = "..event.path)
	print("Got packet "..#raw.." event="..event.event)

	local base = CONFIG[event.path]
	if not base then
		print("Got event for non-existent path: "..event.path)
		return
	end
	local func = base.events[event.event]
	if not func then
		print("Got unconfigured event: "..event.path.." "..event.event)
		return
	end
	func(event)
end

--
-- Initialise the key stuff for the event system
--
local function init()

	--
	-- The AF_UNIX socket for receiving external events
	--
	local rc
	local evs = posix.sys.socket.socket(posix.sys.socket.AF_UNIX, posix.sys.socket.SOCK_DGRAM, 0)
	
	posix.unistd.unlink(SOCK_NAME)
	rc = posix.sys.socket.bind(evs, { family = posix.sys.socket.AF_UNIX, path = SOCK_NAME })
	assert(rc == 0, "unable to bind event socket")
	fds[evs] = { fd = evs, events = { IN = true }, callback = event_recv }
end

--
-- Register an additional filehandle to listen on
--
local function add_fd(fd, callback, fields)
	local table = { fd = fd, events = { IN = true }, revents = {}, callback = callback }
	for k,v in pairs(fields or {}) do
		table[k] = v
	end
	fds[fd] = table
end
local function remove_fd(fd)
	fds[fd] = nil
end

--
-- Send an event
--
local function send(ev)
	local evs = posix.sys.socket.socket(posix.sys.socket.AF_UNIX, posix.sys.socket.SOCK_DGRAM, 0)
	posix.sys.socket.sendto(evs, lib.util.serialise(ev), { family = posix.sys.socket.AF_UNIX, path = SOCK_NAME })
	posix.unistd.close(evs)
end


--
-- The main poll
--
local function poll()
	local rc = posix.poll.poll(fds, 5000)

	-- error
	if rc < 0 then print("poll rc="..rc) return end

	-- timeout
	if rc == 0 then return end

	-- now find any handles ready for processing
	for i,fd in pairs(fds) do
		if fd.revents.IN or fd.revents.OUT then
			print("Got read on "..i)
			fd.callback(fd)
		end
	end
end



return {
	init = init,
	poll = poll,
	send = send,
	add_fd = add_fd,
	remove_fd = remove_fd,
}




