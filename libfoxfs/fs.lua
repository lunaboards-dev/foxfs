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
	inode_allocate        = 10
}

fox.flags = {
	-- inode flags
	inode_inline     = 0x000001,
	inode_allocated  = 0x000002,
	inode_compressed = 0x000004,
	inode_immutable  = 0x000008,
	inode_sync       = 0x000010,
	inode_append     = 0x000020,
	inode_noatime    = 0x000040,
	inode_journal    = 0x000080,
	inode_nosubdir   = 0x000100,
	inode_ads        = 0x000200,
	inode_nocow      = 0x000400,

	-- group flags
	group_noalloc       = 0x000001,
	group_grandfathered = 0x000002
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
		locsize = loc_size,
		inode = inode_size
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
	self.dev.write(blk, self.types.blockgroup(grp)..grp.bitmap)
	grp.dirty = nil
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
			--print(i*8+j, (b >> j) & 1)
			if (b >> j) & 1 == 0 then
				return i*8+j
			end
		end
	end
end

function fs:nearest_free_blk(group)
	local blk = self:first_free_blk(group)
	if blk then return group, blk end
	local left = self:load_group(group)
	local right = left.next
	left = left.prev
	while true do
		if left ~= 0 then
			blk = self:first_free_blk(left)
			if blk then
				return left, blk
			else
				left = self:load_group(left).prev
			end
		end
		if right ~= 0 then
			blk = self:first_free_blk(right)
			if blk then
				return right, blk
			else
				right = self:load_group(right).next
			end
		end
	end
end

local function check_blk(bitmap, blk)
	local i, j = blk//8, blk % 8
	--print(blk, (bitmap:byte(i+1) >> j) & 1 )
	return (bitmap:byte(i+1) >> j) & 1 > 0
end

local function set_bitmap(bitmap, blk, val)
	local i, j = blk//8, blk % 8
	i = i + 1
	local left = bitmap:sub(1, i-1)
	local right = bitmap:sub(i+1)
	local b = bitmap:byte(i)
	local mask = ~b ~ (1 << j)
	return left .. string.char((b & mask) | val << j) .. right
end

function fs:allocate_blk(group, blk)
	local grpi = self:load_group(group)
	if grpi.free_blocks == 0 or grpi.inode_block_count >= (self.super.inodes_per_group/self.super.inodes_per_blk) then return end
	local bitmap = grpi.bitmap
	if check_blk(bitmap, blk) then
		error("attempt to allocate already allocated block")
	end
	self:journal_add(0, group, fox.journal.group_bitmap_allocate, self.types.sizes("block", blk))
	grpi.bitmap = set_bitmap(bitmap, blk, 1)
	grpi.free_blocks = grpi.free_blocks - 1
	grpi.dirty = true
	return true
end

function fs:free_blk(group, blk)
	local grpi = self:load_group(group)
	local bitmap = grpi.bitmap
	if not check_blk(bitmap, blk) then
		error("attempt to free already freed block")
	end
	self:journal_add(0, group, fox.journal.group_bitmap_free, self.types.sizes("block", blk))
	grpi.bitmap = set_bitmap(bitmap, blk, 0)
	grpi.free_blocks = grpi.free_blocks + 1
	grpi.dirty = true
	return true
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

function fs:inode_to_group(inode)
	local group_n = (inode//self.super.inodes_per_group)
	local grp_blk = self:group_location(group_n+1)
	local local_inode = inode % self.super.inodes_per_group
	local block = local_inode//self.super.inodes_per_blk
	local num = local_inode & self.super.inodes_per_blk
	return grp_blk, block, num
end

function fs:sync_inode_blk(blk, data)
	local meta = self.types.inodegroup(data)
	for i=1, self.super.inodes_per_blk do
		meta = meta .. self.types.inode(data.inodes[i])
	end
	self.dev.write(blk, meta)
end

function fs:read_inode_blk(blk)
	local iblk = self.dev.read(blk)
	local igrp, nextb = self.types.inodegroup(iblk)
	--local nextb = #self.types.inodegroup+1
	local inds = iblk:sub(#self.types.inodegroup+1)
	local inodes = {}
	for i=1, self.super.inodes_per_blk do
		--print(nextb)
		--print(self.types.inode(iblk, nextb))
		inodes[i], nextb = self.types.inode(iblk, nextb)
	end
	igrp.inodes = inodes
	return igrp
end

function fs:first_free_node(group)
	local function first_free_in_blk(blk)
		local iblk = self:read_inode_blk(blk)
		if iblk.free == 0 then
			return
		end
		for i=1, #iblk.inodes do
			if iblk.inodes[i].flags & fox.flags.inode_allocated == 0 then
				return iblk.first_node+i-1, i-1
			end
		end
	end
	local grpi = self:load_group(group)
	if grpi.free_inodes == 0 or grpi.group_flags & fox.flags.group_noalloc > 0 then return end
	if grpi.first_inode == grpi.last_inode then
		local free = first_free_in_blk(grpi.first_inode)
		if not free then return self.super.inodes_per_blk end
		return free
	else
		local left, right = grpi.first_inode, grpi.last_inode
		while left < right do
			local ind = first_free_in_blk(left)
			if ind then return ind end
			left = self:read_inode_blk(right).next
			ind = first_free_in_blk(right)
			if ind then return ind end
			right = self:read_inode_blk(right).prev
		end
	end
end

function fs:get_inode_blk(group, blk)
	--print("blk", blk)
	local grpi = self:load_group(group)
	local half = grpi.inode_block_count//2
	if blk == 0 then return grpi.first_inode end
	if blk <= half then
		local cur = grpi.first_inode
		for i=1, blk do
			cur = self:read_inode_blk(cur).next
		end
		return cur
	elseif blk > half then
		local cur = grpi.last_inode
		for i=grpi.inode_block_count, blk+1, -1 do
			cur = self:read_inode_blk(cur).prev
		end
		return cur
	end
end

function fs:allocate_inode_blk(group)
	local igrp = self:load_group(group)
	local blk = self:first_free_blk(group)
	if not blk then
		igrp.flags = igrp.flags | fox.flags.group_noalloc
		igrp.dirty = true
	end
	self:allocate_blk(group, blk)
	self:journal_add(0, group, fox.journal.inode_allocate,
		self.types.size("block", igrp.last_inode)..
		self.types.size("block", group+blk))
	self.dev.write(group+blk, self.types.inodegroup {
		prev = igrp.last_inode,
		next = 0,
		free = self.super.inodes_per_blk,
		group = group
	})
	local iblk = self:read_inode_blk(igrp.last_inode)
	iblk.next = group+blk
	self:sync_inode_blk(igrp.last_inode, iblk)
	igrp.last_inode = group+blk
	return group+blk
end

function fs:update_inode(node, data)
	local group, blk, num = self:inode_to_group(node)
	--print("info", group, blk, num)
	local ind_data = self.types.inode(data)
	self:journal_add(node, group, fox.journal.inode_update, ind_data)
	local real_blk = self:get_inode_blk(group, blk)
	local iblk = self:read_inode_blk(real_blk)
	iblk.inodes[num] = data
	print("real blk", real_blk)
	self:sync_inode_blk(real_blk, iblk)
end

function fs:group_location(grp_id)
	if grp_id == 1 then
		return self.super.first_group
	end
	return (grp_id-1)*self.super.blocks_per_group
end

function fs:makenode(info)
	local grp, node
	for i=1, self.super.group_count do
		grp = self:group_location(i)
		node = self:first_free_node(grp)
		print(node, grp)
		if node then
			print(node, grp)
			break
		end
	end
	local inode = {
		mode = info.mode or 0,
		uid = info.uid or 0,
		gid = info.gid or 0,
		flags = (info.flags or 0) | fox.flags.inode_allocated,
		nlinks = info.nlinks or 0,
		size_last = info.size_last or 0,
		blocks = info.blocks or 0,
		atime = info.atime or os.time()*1000,
		mtime = info.mtime or os.time()*1000,
		ctime = info.ctime or os.time()*1000,
		dtime = info.dtime or 0,
		sip = 0,
		dip = 0,
		tip = 0,
		ads = info.ads or 0,
		group = grp,
		0, 0, 0, 0, 0,
		0, 0, 0, 0, 0
	}
	if info.prealloc then
		for i=1, info.prealloc do
			local bgrp, blk = self:nearest_free_blk(grp)
			self:allocate_blk(bgrp, blk)
			inode[i] = bgrp+blk
		end
	end
	print("node", node)
	self:update_inode(node, inode)
	self:save_group(grp)
	return node, inode
end

local hand = {}

function fs:raw_open(node, mode)

end

local dir = {}

function fs:opendir(path)

end

function fs:mkdir(path)

end

return fox