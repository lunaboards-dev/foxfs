fn vint_val(auto v) {
    return v.v;
};

fn blk_ptr_base(auto v) {
    return (v * 512)-v;
};

struct foxfs_vint<auto size>{
    match(size) {
        (0): u8 v;
        (1): u16 v;
        (2): u24 v;
        (3): u32 v;
        (4): u8 v[5];
        (5): u48 v;
        (6): u8 v[7];
        (7): u64 v;
    }
} [[sealed, format("vint_val")]];

struct foxfs_vptr<T, auto size>{
    match(size) {
        (0): T *v : u8 [[pointer_base("blk_ptr_base")]];
        (1): T *v : u16 [[pointer_base("blk_ptr_base")]];
        (2): T *v : u24 [[pointer_base("blk_ptr_base")]];
        (3): T *v : u32 [[pointer_base("blk_ptr_base")]];
        //(4): u8 v[5];
        (5): T *v : u48 [[pointer_base("blk_ptr_base")]];
        //(6): u8 v[7];
        (7): T *v : u64 [[pointer_base("blk_ptr_base")]];
    }
};// [[sealed, format("vint_val")]];

bitfield foxfs_inode_flags<auto size> {
    inline : 1;
    allocated : 1;
    comrpessed : 1;
    immutable : 1;
    sync : 1;
    append : 1;
    noatime : 1;
    journal : 1;
    nosubdir : 1;
    ads : 1;
    nocow : 1;
    padding : ((size+1)*8-10);
};

bitfield foxfs_sizes {
    block : 4;
    namelen : 4;
    locsize : 4;
    date : 4;
    uid : 4;
    gid : 4;
    devmaj : 4;
    devmin : 4;
    flags : 4;
    inode : 4;
    padding : 24;
};

struct foxfs_inode<auto sizes> {
    u16 mode;
    foxfs_vint<sizes.uid> uid;
    foxfs_vint<sizes.gid> gid;
    foxfs_vint<sizes.locsize> size_last;
    foxfs_vint<sizes.block> blocks;
    foxfs_vint<sizes.date> atime;
    foxfs_vint<sizes.date> mtime;
    foxfs_vint<sizes.date> ctime;
    foxfs_vint<sizes.date> dtime;
    foxfs_inode_flags<sizes.flags> flags;
    foxfs_vint<sizes.locsize> nlink;
    foxfs_vint<sizes.block> block_ptrs[10];
    foxfs_vint<sizes.block> sip;
    foxfs_vint<sizes.block> dip;
    foxfs_vint<sizes.block> tip;
    foxfs_vint<sizes.block> ads;
    foxfs_vint<sizes.block> group;
};

struct foxfs_inodegroup<auto sizes> {
    char magic[5];
    padding[1];
    foxfs_vint<sizes.block> group;
    foxfs_vint<sizes.block> prev;
    foxfs_vint<sizes.block> next;
    foxfs_vint<sizes.inode> first_node;
    u8 free;
    foxfs_inode<sizes> indodes[7];
};

struct foxfs_blockgroup<auto sizes> {
    char magic[5];
    padding[1];
    foxfs_vint<sizes.locsize> inode_block_count;
    //foxfs_vint<sizes.block> first_inode;
    foxfs_vptr<foxfs_inodegroup<sizes>, sizes.block> first_inode;
    foxfs_vint<sizes.block> last_inode;
    foxfs_vint<sizes.block> first_block;
    foxfs_vint<sizes.block> last_block;
    foxfs_vint<sizes.block> free_blocks;
    foxfs_vint<sizes.block> free_inodes;
    foxfs_vint<sizes.block> next_group;
    foxfs_vint<sizes.block> prev_group;
    foxfs_vint<sizes.block> cow_reserved;
    foxfs_vint<sizes.flags> flags;
    foxfs_sizes sizes;
};

struct foxfs_super_data<auto sizes> {
    foxfs_vint<sizes.inode> total_inodes;
    foxfs_vint<sizes.inode> free_inodes;
    foxfs_vint<sizes.inode> inodes_per_group;
    foxfs_vint<sizes.inode> inodes_per_blk;
    
    foxfs_vint<sizes.block> total_blocks;
    foxfs_vint<sizes.block> free_blocks;
    foxfs_vint<sizes.block> blocks_per_group;
    //foxfs_vint<sizes.block> first_group;
    foxfs_vptr<foxfs_blockgroup<sizes>, sizes.block> first_group;
    foxfs_vint<sizes.block> group_count;
    
    foxfs_vint<sizes.block> boot_block;
    foxfs_vint<sizes.locsize> boot_block_size;
    
    foxfs_vint<sizes.inode> reserved_inodes;
    foxfs_vint<sizes.block> reserved_blocks;
    foxfs_vint<sizes.uid> reserved_uid;
    foxfs_vint<sizes.gid> reserved_gid;
    foxfs_vint<sizes.inode> root;
    foxfs_vint<sizes.inode> journal;
    
    
    foxfs_vint<sizes.block> prealloc_blocks;
    foxfs_vint<sizes.block> inode_reserved_blocks;
    foxfs_vint<sizes.locsize> max_inline_size;
    
    
    foxfs_vint<sizes.date> last_mount;
    foxfs_vint<sizes.date> last_check;
    
    foxfs_vint<sizes.locsize> max_ads_entries;
};

struct foxfs_super {
    char sig[8];
    u16 vmaj;
    u16 vmin;
    u16 blksize;
    u16 osid;
    u16 mount_count;
    u16 max_mounts;
    u8 fs_state;
    u8 uuid[16];
    foxfs_sizes sizes;
    
    foxfs_super_data<sizes> data [[inline]];
};

foxfs_super super @ 512;

//foxfs_blockgroup<super.sizes> group @ (super.data.first_group.v * 512);