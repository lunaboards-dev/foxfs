#ifndef __FOXFS_STRUCTS
#define __FOXFS_STRUCTS

#include <stdint.h>

#define FFSS_TYPEMASK 0x7F00
#define FFSS_VALMASK 0xFF
#define FFSS_STRM 0x8000

#define FFSS_INT 0x0000
#define FFSS_STR 0x0100
#define FFSS_VAR 0x0200
#define FFSS_VARS 0x0300

#define FFSS_UINT8 (FFSS_INT | 0)
#define FFSS_UINT16 (FFSS_INT | 1)
#define FFSS_UINT24 (FFSS_INT | 2)
#define FFSS_UINT32 (FFSS_INT | 3)
#define FFSS_UINT48 (FFSS_INT | 4)
#define FFSS_UINT64 (FFSS_INT | 5)

#define FFSS_V_BLOCK (FFSS_VAR | 0)
#define FFSS_V_NAMELEN (FFSS_VAR | 1)
#define FFSS_V_NLINK (FFSS_VAR | 2)
#define FFSS_V_LOCSIZE (FFSS_VAR | 3)
#define FFSS_V_DATE (FFSS_VAR | 4)
#define FFSS_V_UID (FFSS_VAR | 5)
#define FFSS_V_GID (FFSS_VAR | 6)
#define FFSS_V_DEVMIN (FFSS_VAR | 7)
#define FFSS_V_DEVMAJ (FFSS_VAR | 8)
#define FFSS_V_FLAGS (FFSS_VAR | 9)
#define FFSS_V_INODE (FFSS_VAR | 10)

struct foxfs_sizes {
	uint8_t block : 4;
	uint8_t namelen : 4;
	uint8_t nlink : 4;
	uint8_t locsize : 4;
	uint8_t date : 4;
	uint8_t uid : 4;
	uint8_t gid : 4;
	uint8_t devmin : 4;
	uint8_t devmaj : 4;
	uint8_t flags : 4;
	uint8_t inode : 4;
} __attribute((packed));

struct foxfs_superblock {
	char sig[8]; // foxfs!!!
	uint16_t ver_maj;
	uint16_t ver_min;
	uint16_t blk_size;
	uint16_t os_id;
	uint16_t mount_count;
	uint16_t max_mounts;
	uint8_t fs_state;

	struct foxfs_sizes sizes;
} __attribute((packed));

int struct_partmetadata[] = {};
int struct_blockgroup[] = {
	FFSS_V_BLOCK, // Block usage bitmap
	FFSS_V_BLOCK, // Inode allocation table
	FFSS_V_LOCSIZE, // Number of unallocated blocks
	FFSS_V_LOCSIZE, // Number of unallocated inodes
	FFSS_UINT8, // Flags
	FFSS_STR | sizeof(struct foxfs_sizes)
};
int struct_inode[] = {
	FFSS_UINT16, // mode
	FFSS_V_UID, // UID
	FFSS_V_GID, // GID
	FFSS_V_LOCSIZE, // Local Size
	FFSS_V_BLOCK, // Number of blocks
	FFSS_V_DATE, // access time
	FFSS_V_DATE, // creation time
	FFSS_V_DATE, // modification time
	FFSS_V_DATE, // deletion time
	FFSS_UINT16, // Number of hard links
	FFSS_V_FLAGS, // Flags.
	FFSS_V_BLOCK, // Direct block pointer 0
	FFSS_V_BLOCK, // Direct block pointer 1
	FFSS_V_BLOCK, // Direct block pointer 2
	FFSS_V_BLOCK, // Direct block pointer 3
	FFSS_V_BLOCK, // Direct block pointer 4
	FFSS_V_BLOCK, // Direct block pointer 5
	FFSS_V_BLOCK, // Direct block pointer 6
	FFSS_V_BLOCK, // Direct block pointer 7
	FFSS_V_BLOCK, // Direct block pointer 8
	FFSS_V_BLOCK, // Direct block pointer 9
	FFSS_V_BLOCK, // single indirect pointer
	FFSS_V_BLOCK, // double ip
	FFSS_V_BLOCK, // triple ip
	FFSS_V_BLOCK, // ADS Directory location
	
};
int struct_dirent[] = {
	FFSS_V_NAMELEN | FFSS_STRM,
	FFSS_V_INODE
};

#endif