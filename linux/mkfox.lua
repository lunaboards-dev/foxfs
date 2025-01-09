local dev = require("libfoxfs.dev")
local dt = require("libfoxfs.datatypes")
local fox = require("libfoxfs.fs")

print("mkfox v1.0")
print("")
local media = dev.wrap_file(arg[1], 512)
local settings = assert(fox.optimal_settings(media, 1024, 0xFFFF, 0xFFFF))
local types = dt.structures(settings.sizes)
local size_str = dt.size_string(settings.sizes)

local uuid = fox.uuidgen()

print("UUID: "..fox.human_uuid(uuid))
print(string.format("Block size: %d bytes", settings.blksize))
print(string.format("Volume size: %d blocks (%d bytes)", settings.blocks, settings.blocks*settings.blksize))
print(string.format("Groups: %d groups", settings.groups))
print(string.format("Blocks per group: %d blocks", settings.group_size))
print(string.format("Inodes per group: %d inodes", settings.group_inodes))
print(string.format("Total inodes: %d inodes", settings.max_inodes))
print(string.format("Inodes per block: %d inodes", settings.blk_inodes))

--[[for k, v in pairs(settings) do
	print(k, v)
end
print("===========================")
for i=1, #dt.dt.types do
	local t = dt.dt.types[i]
	print(t, settings.sizes[t])
end]]

local meta_blks = settings.groups+3

local function blkpad(data)
	local pad_amt = settings.blksize - #data
	return data..string.rep("\0", pad_amt)
end

local superblock = blkpad(types.superblock {
	signature = "foxfs!!!",
	ver_maj = 1,
	ver_min = 0,
	blk_size = settings.blksize,
	os_id = 0, -- linux
	mount_count = 0,
	max_mounts = 10,
	fs_state = 0,
	uuid=uuid,--"TODO: ADD UUIDS!",
	sizes = size_str,

	total_inodes = settings.max_inodes,
	free_inodes = settings.max_inodes,
	inodes_per_group = settings.group_inodes,
	inodes_per_blk = settings.blk_inodes,

	total_blocks = settings.blocks,
	free_blocks = settings.blocks-meta_blks,
	blocks_per_group = settings.group_size,
	first_group = 4,

	boot_block = 0,
	boot_block_size = 0,

	reserved_inodes = 0,
	reserved_blocks = 0,
	reserved_block_uid = 0,
	reserved_block_gid = 0,
	root = 1,
	journal = 0,

	prealloc_blocks = 0,
	inode_reserved = 1,
	max_inline_size = settings.sizes.block*13,

	last_mount = os.time()*1000,
	last_check = os.time()*1000,

	max_ads_entries = settings.blksize//#types.dirent
})

media.write(1, superblock)

local start_sec = 3
local prev_group = 0
for i=1, settings.groups do
	io.stdout:write(string.format("\rWriting group %d of %d (Block 0x%x)", i, settings.groups, start_sec))
	local last_group = i == settings.group
	local next_start = (settings.group_size*i+1)
	media.write(start_sec, blkpad(types.blockgroup {
		first_inode = start_sec+1,
		last_inode = start_sec+1,
		first_block = start_sec,
		last_block = settings.group_size,
		free_blocks = settings.group_size - (i == 1 and 5 or 2),
		free_inodes = settings.blk_inodes,
		next_group = last_group and 0 or next_start,
		prev_group = prev_group,
		group_flags = 0,
		group_sizes = size_str
	}.."\x03"))
	media.write(start_sec+1, blkpad(types.inodegroup {
		group = start_sec,
		prev = 0,
		next = 0,
		free = settings.blk_inodes
	}))
	start_sec = next_start
end
print("\n")
media.close()
print("Write complete.")