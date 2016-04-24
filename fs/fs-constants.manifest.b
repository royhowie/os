/* ------------------------------------------ */
/* --- format_disc -------------------------- */
/* ------------------------------------------ */

// Address of the super block on disc.
SB_block_addr               = 0

// The super block will be a 128-word vector.
// These constants represent the offset within
// the super block for useful pieces of data.

// SB_FBL = super block free block list

// This represents where the FBL starts.
// Remember, the FBL operates like a stack,
// so the start will be
//      1 + (blocks_on_disc / 128)
// So, e.g., if there are 6k blocks on the
// disc, we will need 46.875 => 47 pages
// to list all of the free blocks.
// Therefore, the start of the FBL
// will be at block #47, whereas the end
// will be at block #1. This leaves 47
// blocks (1, 2, 3, …, 46, 47) for the FBL.
SB_FBL_start                = 0

// This is the block which represents our
// current "window" into the FBL. This will
// start off equal to `SB_FBL_start` and
// will slowly move towards `SB_FBL_end`.
SB_FBL_index                = 1

// The offset index within the window into
// the FBL. Will start off at 127 (last word)
// and move towards 0. Once it hits -1,
// a new block (window) will have to be read
// into memory.
SB_FBL_index_offset         = 2

// Continuing the above example, `SB_FBL_end`
// will almost always be the block at index 1.
SB_FBL_end                  = 3

// Number of blocks being used by the FBL.
SB_FBL_size                 = 4

// Block location of the root directory.
SB_root_dir                 = 5

// Date on which the super block was formatted.
SB_format_date              = 6

// Format_check and format_check_value are
// used to determine whether the disc has been
// formatted already.
//
// This is done by checking whether
// format_date % format_check === format_check_value
//
// SB_format_check is a random value between
// 1 and 2**26. This is because there are
// approximately 2**29 seconds between Jan 1 2000
// and May 2016. Thus, if max value was between
// 1 and 2**32 - 1 then there would be a 7 in 8
// chance that x mod format_check would equal x.
SB_format_check             = 7
SB_format_check_value       = 8
SB_max_random_check_val     = 2 ** 26

// Store the disc number so disc can be properly
// dismounted.
SB_disc_number              = 9

// Disc name. Up to 8 words ( 32 characters)
// including the null terminator.
SB_name                     = 10
SB_max_name_len             = 32
SB_max_name_len_words       = 8

/* ----------------------------------------- */
/* --- directory entry---------------------- */
/* ----------------------------------------- */
SIZEOF_DIR_ENT              = 8

DIR_E_date                  = 0
DIR_E_block                 = 1
DIR_E_file_size             = 2
DIR_E_file_type             = 3
DIR_E_name                  = 4
DIR_E_name_len              = 32

ONE_BLOCK                   = 1

/* ----------------------------------------- */
/* --- mount ------------------------------- */
/* ----------------------------------------- */
max_number_of_discs         = 32
DISCS                       = vec(max_number_of_discs)

// Boolean on whether disc has been altered.
// If true, disc will be written back on dismount.
disc_has_changed            = 0

// Pointer to 128-word vector containing the
// super block.
disc_data                   = 1

// Pointer to 128-word vector containing the
// window (one block) into the free block list.
disc_FBL_window             = 2

// FILE* to the current directory.
disc_current_dir            = 3

// size in words of the disc_info vector
disc_info_size              = 4
BLOCK_LEN                   = 128

/* ----------------------------------------- */
/* --- files ------------------------------- */
/* ----------------------------------------- */
FILE_TABLE_SIZE             = 32
FILE_TABLE                  = vec(FILE_TABLE_SIZE)

FT_ENTRY_SIZE               = 6
FTB_size                    = 512
FTB_size_words              = 128

// Pointer to 128-word vector containing the header
// block of the file.
// FT_header                   = 0,

// Pointer to vector of length 2 * levels
// following the pattern
//  0:  pointer to block containing level 0 (head)
//  1:  offset within block level 0
//  2:  pointer to block indicated by block0[offset0]
//  3:  offset within block level 1
//  ...
//  2n:     block containing level n-1 (leaf)
//  2n+1    offset within leaf block
FT_block_tree               = 0

FT_BT_byte_pos              = 1

// Is the file being read ('R') or written to ('W')?
FT_direction                = 2

// Has the file header been modified?
FT_modified                 = 3

// Pointer to the disc object.
FT_disc_info                = 4

// Number of disc on which file is located.
FT_disc_number              = 5

// Boolean indicating whether file has reached its
// end. 
FT_file_is_EOF              = 6

// FH = File Header
// These constants serve as pointed to data within
// a file header. Compare this to F_ constants,
// which refer to data within a file table entry.

// Files will consist of pointers to blocks of data.
// `F_levels` will be the "levels of recursion."
// For example, if F_levels = 1, then the file header
// will contain pointers to blocks of data. If
// F_levels = 2, then the header will contain pointers
// to pointers to blocks of data.
FH_levels                   = 0

// Is it a file 'F' or directory 'D'?
FH_type                     = 1

// File data information.
FH_date_created             = 2
FH_date_accessed            = 3

// Length of the file in bytes.
FH_length                   = 4

// Block number of directory containing this file.
FH_parent_dir               = 5

// Block number where the file header is located.
FH_current_block            = 6

// Name of file or directory. Can be up to 4 words long.
FH_name                     = 7
FH_name_len                 = 32

FH_first_word               = 11

FT_EOF                      = -1
FT_FILE                     = 'F'
FT_DIRECTORY                = 'D'
FT_READ                     = 'r'
FT_WRITE                    = 'w'
FT_BOTH                     = 'b'
