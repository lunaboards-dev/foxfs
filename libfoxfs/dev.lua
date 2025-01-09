local dev = {}

function dev.wrap_comp(addr)
	local c = component or require("component")
	local comp = component.proxy(addr)
	local blksize = comp.getSectorSize()
	local blks = comp.getCapacity()//blksize
	return {
		read = function(sector)
			return comp.readSector(sector)
		end,
		write = function(sector, data)
			return comp.writeSector(sector, data)
		end,
		blksize = comp.getSectorSize(),
		blocks = blks
	}
end

function dev.wrap_file(file, blkoverride)
	local ok, lfs = pcall(require, "lfs")
	local blksize = blkoverride or 512
	if not blkoverride and ok then
		blksize = lfs.attributes(file, "blksize")
	end
	local h = io.open(file, "r+b")
	local size = h:seek("end", 0)
	return {
		blksize = blksize,
		blocks = size//blksize,
		read = function(sector)
			h:seek("set", sector*blksize)
			return h:read(blksize)
		end,
		write = function(sector, data)
			h:seek("set", sector*blksize)
			h:write(data:sub(1, blksize))
			h:flush()
		end,
		close = function() h:close() end
	}
end

function dev.logi_wrap(d, logiblk)
	local phy_per_logi = logiblk//d.blksize
	if phy_per_logi == 1 then return d end
	local logiblkcount = d.blocks//phy_per_logi
	return {
		blksize = logiblk,
		blocks = logiblkcount,
		read = function(blk)
			local buf = {}
			for i=1, phy_per_logi do
				buf[i] = d.read(blk+i-1)
			end
			return table.concat(buf)
		end,
		write = function(blk, data)
			for i=1, phy_per_logi do
				local st = ((i-1)*d.blksize)+1
				local en = st+d.blksize-1
				d.write(blk+i-1, data:sub(st, en))
			end
		end
	}
end

return dev