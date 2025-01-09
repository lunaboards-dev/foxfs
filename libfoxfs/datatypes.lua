-- Everything in this file is important for generating the actual structure types.
local dt = {
	structs = {}
}

dt.types = {
	"block", -- Block address
	"namelen", -- Name length
	"locsize", -- Smallest datatype that can contain the size of a block.
	"date", -- Date
	"_uid", -- User ID
	"gid", -- Group ID
	"devmaj", -- Dev Major ID
	"devmin", -- Dev Minor ID
	"flags", -- Flags
	"inode" -- Inode number
}

dt.flags = {
	"inline",
	"allocated",
	"compressed",
	"immutable",
	"sync",
	"append",
	"noatime",
	"journal",
	"nosubdir",
	"ads",
	"nocow"
}

dt.superblock_base = {
	{signature="c8"},
	{ver_maj="u16"},
	{ver_min="u16"},
	{blk_size="u16"},
	{os_id="u16"},
	{mount_count="u16"},
	{max_mounts="u16"},
	{fs_state="u8"},
	{uuid="c16"},
	{sizes="c8"}
}--"<c8HHHHHHBc16c8"

dt.structs.superblock = {
	-- Base superblock.
	{signature="c8"},
	{ver_maj="u16"},
	{ver_min="u16"},
	{blk_size="u16"},
	{os_id="u16"},
	{mount_count="u16"},
	{max_mounts="u16"},
	{fs_state="u8"},
	{uuid="c16"},
	{sizes="c8"},

	-- Inode info
	{total_inodes="inode"},
	{free_inodes="inode"},
	{inodes_per_group="inode"},
	{inodes_per_blk="inode"},
	-- Block info
	{total_blocks="block"},
	{free_blocks="block"},
	{blocks_per_group="block"},
	{first_group="block"},

	-- Boot block
	{boot_block="block"},
	{boot_block_size="locsize"},

	-- Reserved space
	{reserved_inodes="inode"},
	{reserved_blocks="block"},
	{reserved_block_uid="_uid"},
	{reserved_block_gid="gid"},
	{root="inode"},
	{journal="inode"},

	-- Allocation parameters
	{prealloc_blocks="block"},
	{inode_reserved="block"},
	{max_inline_size="locsize"},

	-- Times
	{last_mount="date"},
	{last_check="date"},

	-- Misc
	{max_ads_entries="locsize"}
}

dt.structs.blockgroup = {
	--{bitmap="block"},
	{inode_block_count="locsize"},
	{first_inode="block"},
	{last_inode="block"},
	{first_block="block"},
	{last_block="block"},
	{free_blocks="block"},
	{free_inodes="inode"},
	{next_group="block"},
	{prev_group="block"},
	{cow_reserved="block"},
	{group_flags="flags"},
	{group_sizes="c8"}
}

dt.structs.journal_entry = {
	{inode="inode"},
	{block="block"},
	{time="date"},
	{action="u8"},
	{data_len="u8"}
}

dt.structs.inodegroup = {
	{group="block"},
	{prev="block"},
	{next="block"},
	{free="u8"}
}

dt.structs.dirent = {
	{inode="inode"},
	{namelen="namelen"},
}

dt.structs.inode = {
	{mode="u16"},
	{uid="_uid"},
	{gid="gid"},
	{size_last="locsize"},
	{blocks="block"},
	{atime="date"},
	{mtime="date"},
	{ctime="date"},
	{dtime="date"},
	{flags="flags"},
	{nlink="locsize"},
	{[1]="block"},
	{[2]="block"},
	{[3]="block"},
	{[4]="block"},
	{[5]="block"},
	{[6]="block"},
	{[7]="block"},
	{[8]="block"},
	{[9]="block"},
	{[10]="block"},
	{sip="block"},
	{dip="block"},
	{tip="block"},
	{ads="block"},
	{group="block"}
}

local types = {
	flags = {},
	dt = dt,
}

for i=1, #dt.flags do
	types.flags[dt.flags[i]] = (1 << (i-1))
end

local vtypes = {
	s = "i",
	u = "I",
	c = "c"
}

local function serder(struct, sizes)
	local packstr = ""
	local fields = {}
	local strings = {}
	for i=1, #struct do
		local k, v = next(struct[i])
		local vtype = v:sub(1,1)
		local vsize = v:sub(2)
		if vtype ~= "x" then
			table.insert(fields, k)
		else
			if #vsize > 0 then
				packstr = packstr .. string.rep("x", tonumber(vsize, 10))
			else
				packstr = packstr .. "x"
			end
			goto continue
		end
		local ptype = vtypes[vtype]
		if ptype then
			--print(v, vsize)
			vsize = tonumber(vsize, 10)//8
			if ptype == "c" then
				packstr = packstr .. "c" .. v:sub(2)
				strings[k] = true
			else
				packstr = packstr .. ptype .. vsize
			end
		else
			packstr = packstr .. "I" .. sizes[v]
		end
		::continue::
	end
	return setmetatable({
		fields = fields,
	}, {__call = function(_, input, offset)
		if type(input) == "table" then
			local values = {}
			for i=1, #fields do
				local k = fields[i]
				local v = input[k] or (strings[k] and "") or 0
				--print(i, k, v)
				table.insert(values, v)
			end
			return packstr:pack(table.unpack(values))
		elseif type(input) == "string" then
			local values = table.pack(packstr:unpack(input))
			local out = {}
			for i=1, #fields do
				out[fields[i]] = values[i]
			end
			return out, values[values.n]
		end
	end, __len=function(t)
		return packstr:packsize()
	end})
end

types.serder = serder

function types.size_string(sizes)
	local _size = 0
	for i=1, #dt.types do
		local s = sizes[dt.types[i]]-1
		_size = _size | (s << ((i-1)*4))
	end
	return string.pack("<l", _size)
end

function types.structures(sizes)
	local _t = {}
	local sz = {}
	if type(sizes) == "string" then
		local _sizes = string.unpack("<l", sizes)
		for i=0, #dt.types-1 do
			local vsize = (_sizes >> (i*4)) & 0xF
			sz[dt.types[i+1]] = vsize+1
		end
	else
		sz = sizes
	end
	_t.sizes = setmetatable({}, {__index=sz,__call=function (t, type, val)
		if type(val) == "string" then
			return string.unpack("I"..sz[type], val)
		else
			return string.pack("I"..sz[type], val)
		end
	end})
	for k, v in pairs(dt.structs) do
		_t[k] = serder(v, sz)
	end
	return _t
end

return types