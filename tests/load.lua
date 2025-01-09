local dt = require("libfoxfs.datatypes")
local fox = require("libfoxfs.fs")
local dev = require("libfoxfs.dev")

local image = arg[1]
local media = dev.wrap_file(image, 512)
local blk = media.read(1)
local sig, vmaj, vmin, blksize, os_id, mcount, mmax, state, uuid, sizes = dt.dt.superblock_base:unpack(blk)
local types = dt.structures(sizes)

print("============ Sizes ============")
for i=1, #dt.dt.types do
	local t = dt.dt.types[i]
	print(i, t, types.sizes[t])
end