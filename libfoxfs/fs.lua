local dt = require("libfoxfs.datatypes")
local dev = require("libfoxfs.dev")

local fox = {}
fox.flag_size = 3
fox.inodes_per_512k = 200
fox.date_size = 6
fox.devmaj_size = 1
fox.devmin_size = 1
fox.namelen_size = 1

fox.journal = {
	group_bitmap_allocate = 1,
	group_bitmap_free     = 2,
	inode_set_flags       = 3,
	inode_free            = 4,
	inode_update_pointer  = 5,
	inode_update_size     = 6,
	inode_change_mode     = 7,
	inode_change_times    = 8,
	inode_update          = 9,
}

local fs = {}

fox.superblock = dt.serder(dt.dt.superblock_base, {})

function fox.open(dv)
	local blk = dv.blksize
	local ldev, sb, super
	while blk < 0xFFFF do
		ldev = dev.logi_wrap(dv, blk)
		sb = ldev.read(1)
		super = fox.superblock(sb)
		if super.magic == "foxfs!!!" and super.ver_maj == 1 and super.ver_min == 0 then break end
		blk = blk * 2
	end
	local types = dt.structures(super.sizes)
	super = types.superblock(sb)
	return setmetatable({
		dev = dv,
		types = types,
		super = super,
		group_cache = {},
		dir_cache = setmetatable({}, {__index=function(self, path)
			for i=1, #self do
				if self[i].path == path then
					return self[i].blk
				end
			end
		end})
	}, {__index=fs})
end

local function min_bytes(n)
	local x = 0
	for i=1, 8 do
		x = (x << 8) | 0xFF
		if x >= n then
			return i, x
		end
	end
end

function fox.uuidgen()
	local resv = {
		[7] = 0x40 | math.random(0, 15),
		[9] = 0x80 | math.random(0, 0x3F)
	}
	local uuid = ""
	for i=1, 16 do
		uuid = uuid .. string.char(resv[i] or math.random(0, 255))
	end
	return uuid
end

function fox.human_uuid(uuid)
	local pairs = {4, 2, 2, 2, 6}
	local groups = {}
	local c = 1
	for i=1, #pairs do
		for j=1, pairs[i] do
			groups[i] = (groups[i] or "")..string.format("%.2x", uuid:byte(c))
			c = c + 1
		end
	end
	return table.concat(groups, "-")
end

function fox.optimal_settings(dev, blksize, max_uid, max_gid)
	--print(blksize % dev.blksize, blksize, dev.blksize)
	if blksize and (blksize % dev.blksize ~= 0) then return nil, "logical block size must be multiple of physical block size" end
	blksize = blksize or dev.blksize
	local _logi_blk = blksize/dev.blksize
	local size_512k = (dev.blksize*dev.blocks)/(512*1024)
	local inodes = math.min(size_512k*fox.inodes_per_512k, 0x7FFFFFFFFFFFFFFF)
	local uid_size = min_bytes(max_uid)
	if not uid_size then return nil, "uid too large" end
	local gid_size = min_bytes(max_gid)
	if not gid_size then return nil, "gid too large" end
	local inode_size, max_inode = min_bytes(inodes)
	if not inode_size then return nil, "too large of volume" end
	local logi_blks = dev.blocks/_logi_blk
	local blk_size, max_block = min_bytes(logi_blks)
	if not blk_size then return nil, "volume too large" end
	local loc_size, max_loc = min_bytes(blksize)
	if not loc_size then return nil, "block size is too large" end

	local bg_header_size = #dt.serder(dt.dt.structs.blockgroup, {
		block = blk_size,
		flags = fox.flag_size,
		locsize = loc_size,
		inode = inode_size
	}) 
	local max_blocks_per_group = (blksize-bg_header_size)*8
	local groups = math.ceil(logi_blks/max_blocks_per_group)
	local blocks_per_group = math.ceil(logi_blks/groups)
	local inodes_per_group = math.ceil(inodes/groups)
	local inode_l = #dt.serder(dt.dt.structs.inode, {
		_uid = uid_size,
		gid = gid_size,
		locsize = loc_size,
		block = blk_size,
		date = fox.date_size,
		flags = fox.flag_size
	})
	local inode_header_size = #dt.serder(dt.dt.structs.inodegroup, {
		block = blk_size,
		locsize = loc_size
	})
	local inodes_per_blk = (blksize-inode_header_size)//inode_l
	local inode_blks_per_group = math.max(inodes_per_group/inodes_per_blk)
	local max_inodes = inode_blks_per_group*inodes_per_blk*groups
	
	return {
		sizes = {
			block = blk_size,
			namelen = fox.namelen_size,
			locsize = loc_size,
			date = fox.date_size,
			_uid = uid_size,
			gid = gid_size,
			devmaj = fox.devmaj_size,
			devmin = fox.devmin_size,
			flags = fox.flag_size,
			inode = inode_size
		},
		groups = groups,
		group_size = blocks_per_group,
		group_inodes = inodes_per_group,
		max_inodes = max_inodes,
		blk_inodes = inodes_per_blk,
		blocks = logi_blks,
		blksize = blksize
	}
end

function fs:journal_add(inode, blk, etype, data)

end

function fs:save_group(blk)
	local grp = self.group_cache[blk]
	if not grp then return end
	self.dev.write(self.types.blockgroup(grp)..grp.bitmap)
end

function fs:load_group(blk)
	if not self.group_cache[blk] then
		local _blk = self.dev.read(blk)
		local group = self.types.blockgroup(_blk)
		group.bitmap = _blk:sub(#self.types.blockgroup+1)
		self.group_cache[blk] = group
	end
	return self.group_cache[blk]
end

function fs:first_free_blk(group)
	local grpi = self:load_group(group)
	if grpi.free_blocks == 0 then return end
	local bitmap = grpi.bitmap
	for i=0, #bitmap-1 do
		local b = bitmap:byte(i+1)
		for j=0, 7 do
			if b & (1 << j) == 0 then
				return i*8+j
			end
		end
	end
end

local function check_blk(bitmap, blk)
	local i, j = blk//8, blk % 8
	return (bitmap:byte(i)  >> i) & 1 > 0
end

local function set_bitmap(bitmap, blk, val)
	local i, j = blk//8, blk % 8
	local left = bitmap:sub(1, i-1)
	local right = bitmap:sub(i+1)
	local b = bitmap:byte(i)
	local mask = ~bitmap ~ (1 << j)
	return left .. string.char((b & mask) | val << j) .. right
end

function fs:allocate_blk(group, blk)
	local grpi = self:load_group(group)
	if grpi.free_blocks == 0 then return end
	local bitmap = grpi.bitmap
	if check_blk(bitmap, blk) then
		error("attempt to allocate already allocated block")
	end
	self:journal_add(0, group, fox.journal.group_bitmap_allocate, self.types.sizes("block", blk))
	grpi.bitmap = set_bitmap(bitmap, blk, 1)
end

function fs:free_blk(group, blk)

end

function fs:block_to_group(blk)
	local group_n = (blk//self.super.blocks_per_group)
	local group_loc = group_n * self.super.blocks_per_group
	if group_n == 0 then
		group_loc = self.super.first_group
	end
	local local_blk = blk - group_loc
	return group_loc, blk
end

function fs:allocate_inode(group)

end

return fox