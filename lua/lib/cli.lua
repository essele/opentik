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


--
-- Given the first byte of a size indication tell us how many more
-- bytes we need, what the new first byte should be, and what template
-- to use to unpack the size
--
local function size_decode(char)
	local byte = char:byte()

	-- decode first digit
	if byte & 0x80 == 0 then
		return 0, byte & 0x7f, ">I1"
	elseif byte & 0xC0 == 0x80 then
		return 1, byte & 0x3f, ">I2"
	elseif byte & 0xE0 == 0xC0 then
		return 2, byte & 0x1f, ">I3"
	elseif byte & 0xF0 == 0xE0 then
		return 3, byte & 0x0f, ">I4"
	elseif byte & 0xF8 == 0xF0 then
		return 4, 0, ">I5"
	end
end


--
-- 
--
local function cli_callback(fdt)
	local fd = fdt.fd

	print("Got cli callback " .. fd)

	if fdt.revents.IN then

		if fdt.want > 0 then
			local data = posix.unistd.read(fd, fdt.want)
			if not data then
				print("error reading")
				posix.unistd.close(fd)
				lib.event.remove_fd(fd)
				return
			end
			local size = data:len()
			if size == 0 then
				print("end of stream")
				posix.unistd.close(fd)
				lib.event.remove_fd(fd)
				return
			end
			fdt.want = fdt.want - size
			table.insert(fdt.buf, data)
			if fdt.want > 0 then return end
		end

		--
		-- We have what we want so far...
		--
		data = table.concat(fdt.buf)
		print("Have "..data:len().." bytes")

		--
		-- If it's just the first byte, then decode and work out
		-- how many bytes we need for size
		--
		if not fdt.template then
			local byte
			fdt.want, byte, fdt.template = size_decode(data)
			if fdt.want > 0 then
				-- Put first byte back
				fdt.buf = { string.pack(">I1", byte ) }
				return
			end
		end

		--
		-- We will have the right number of size bytes so we can unpack
		-- to find out how big the actual data will be
		--
		if not fdt.clisize then
			fdt.clisize = string.unpack(fdt.template, data)
			print("Got size: " .. fdt.clisize)
			fdt.buf = {}
			fdt.have = 0
			fdt.want = fdt.clisize
			return
		end

		--
		-- Here we actually have the cli data
		--
		fdt.template = nil
		fdt.clisize = nil
		fdt.buf = {}
		fdt.want = 1
		print("Got data "..data)
	end

	if fdt.revents.OUT then
		--
		-- If we have some data then we can write as much as possible
		--
		-- TODO: use a table
		local n = posix.unistd.write(fd, fdt.out)
		print("written bytes " .. n)
	
		fdt.outbuf = fdt.outbuf:sub(n+1)
		if fdt.outbuf:len() == 0 then
			fdt.outbuf = nil
			fdt.events.OUT = nil
		end
	end
end

--
-- The cli accept function, this creates the new socket and adds to our
-- poll to ensure we can send/receive as needed
--
local function cli_accept(fdt)
	local fd = fdt.fd

	local newfd = posix.sys.socket.accept(fd)
	print("Got new fd="..newfd)

	--
	-- Do i need to make this non blocking or will it inherit?
	--

	lib.event.add_fd(newfd, cli_callback, { want = 1, buf = {} })

--[[
	fds[newfd] = { fd = newfd, 
					events = { IN = true }, revents = {}, 
					buf = {},
					want = 1,
					callback = cli_callback }
]]--
end

--
-- Create a PF_UNIX socket, bind it and add it to the event system so we can listen
-- to incoming requests
--
local function init()
	local rc

	--
	-- Add a socket for cli interaction
	--
	local cli = posix.sys.socket.socket(posix.sys.socket.AF_UNIX, posix.sys.socket.SOCK_STREAM, 0)

	-- 
	-- Make it non blocking
	--
	local flags = posix.fcntl.fcntl(cli, posix.fcntl.F_GETFL)
	flags = flags | posix.fcntl.O_NONBLOCK
	posix.fcntl.fcntl(cli, posix.fcntl.F_SETFL, flags)

	--
	-- Bind and listen
	--
	posix.unistd.unlink("/tmp/opentik.cli")
	rc = posix.sys.socket.bind(cli, { family = posix.sys.socket.AF_UNIX, path = "/tmp/opentik.cli" })
	assert(rc == 0, "unable to bind cli socket")

	rc = posix.sys.socket.listen(cli, 5)
	assert(rc == 0, "unable to listen on cli socket")

	lib.event.add_fd(cli, cli_accept)
end


return {
	init = init,
}




