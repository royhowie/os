import "io"
import "strings"

export { format_disc, mount, dismount }

manifest {
    /* ------------------------------------------ */
    /* --- format_disc -------------------------- */
    /* ------------------------------------------ */

    // Address of the super block on disc.
    SB_block_addr               = 0,

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
    SB_FBL_start                = 0,

    // This is the block which represents our
    // current "window" into the FBL. This will
    // start off equal to `SB_FBL_start` and
    // will slowly move towards `SB_FBL_end`.
    SB_FBL_index                = 1,

    // The offset index within the window into
    // the FBL. Will start off at 127 (last word)
    // and move towards 0. Once it hits -1,
    // a new block (window) will have to be read
    // into memory.
    SB_FBL_index_offset         = 2,

    // Continuing the above example, `SB_FBL_end`
    // will almost always be the block at index 1.
    SB_FBL_end                  = 3,

    // Number of blocks being used by the FBL.
    SB_FBL_size                 = 4,

    // Block location of the root directory.
    SB_root_dir                 = 5,

    // Date on which the super block was formatted.
    SB_format_date              = 6,

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
    SB_format_check             = 7,
    SB_format_check_value       = 8,
    SB_max_random_check_val     = 2 ** 26,

    // Store the disc number so disc can be properly
    // dismounted.
    SB_disc_number              = 9,

    // Disc name. Up to 8 words ( 32 characters),
    // including the null terminator.
    SB_name                     = 10,
    SB_max_name_len             = 32,
    SB_max_name_len_words       = 8,

    DIR_ENT_DATE                = 0,
    DIR_ENT_ADDR                = 1,
    DIR_ENT_FILE_SIZE           = 2,
    DIR_ENT_NAME                = 4,
    DIR_ENT_NAME_LEN            = 12,
    DIR_ENT_SIZE                = 7,

    ONE_BLOCK                   = 1,

    /* ----------------------------------------- */
    /* --- mount ------------------------------- */
    /* ----------------------------------------- */
    max_number_of_discs         = 32,
    DISCS                       = vec max_number_of_discs,

    // Boolean on whether disc has been altered.
    // If true, disc will be written back on dismount.
    disc_has_changed            = 0,

    // Pointer to 128-word vector containing the
    // super block.
    disc_data                   = 1,

    // Pointer to 128-word vector containing the
    // window (one block) into the free block list.
    disc_FBL_window             = 2,

    // Pointer to the 128-word header block of
    // the current directory file.
    disc_current_dir            = 3,

    // size in words of the disc_info vector
    disc_info_size              = 4,
    BLOCK_LEN                   = 128,

    /* ----------------------------------------- */
    /* --- files ------------------------------- */
    /* ----------------------------------------- */
    FILE_TABLE_SIZE             = 32,
    FILE_TABLE                  = vec FILE_TABLE_SIZE,

    FT_ENTRY_SIZE               = 6,

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
    FT_block_tree               = 0,

    // Pointer to 128-word vector to be used for reading
    // and writing data to/from a file.
    FT_buffer                   = 1,
    FT_buffer_size              = 512,
    FT_buffer_size_in_words     = 128,

    // Position within F_buffer.
    FT_buffer_offset            = 2,

    // Is the file being read ('R') or written to ('W')? 
    FT_direction                = 3,

    // Has the file header been modified?
    FT_modified                 = 4,

    // Disc number on which file is located.
    FT_disc_number              = 5,

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
    FH_levels                   = 0,

    // Is it a file 'F' or directory 'D'?
    FH_type                     = 1,

    // File data information.
    FH_date_created             = 2,
    FH_date_accessed            = 3,

    // Length of the file in bytes.
    FH_length                   = 4,

    // Block number of directory containing this file.
    FH_parent_dir               = 5,
    
    // Name of file or directory. Can be up to 4 words long.
    FH_name                     = 6,
    FH_name_len                 = 32,

    FH_first_word               = 10,

    FT_EOF                      = -1,
    FT_FILE                     = 'F',
    FT_DIRECTORY                = 'D'
}

let min (a, b) = a < b -> a, b;
let clear_buffer (buffer, length) be for i = 0 to length - 1 do buffer ! i := 0;
let copy_buffer (source, dest, length) be for i = 0 to length - 1 do dest ! i := source ! i;

let disc_is_formatted (buffer) be {
    let remainder = buffer ! SB_format_check;
    if remainder = 0 then
        resultis false;
    resultis ((buffer ! SB_format_date) rem remainder) = (buffer ! SB_format_check_value);
}

let get_open_disc_slot () be {
    for i = 0 to max_number_of_discs - 1 do {
        if DISCS ! i = nil then {
            let disc = newvec(disc_info_size);

            disc ! disc_has_changed := 0;
            disc ! disc_data := newvec(BLOCK_LEN);
    		disc ! disc_FBL_window := newvec(BLOCK_LEN);
    		disc ! disc_current_dir := newvec(BLOCK_LEN);
            DISCS ! i := disc;

            resultis DISCS + i;
        }
    }
    resultis -1;
}

let check_disc (disc_number) be devctl(DC_DISC_CHECK, disc_number);
let read_from_disc (disc_number, block, num_blocks, buff) be {
    resultis devctl(DC_DISC_READ, disc_number, block, num_blocks, buff);
}
let write_to_disc (disc_number, offset, num_blocks, buff) be {
    resultis devctl(DC_DISC_WRITE, disc_number, offset, num_blocks, buff);
}

let dismount (disc_info) be {
    let distance = disc_info - DISCS;
    let disc_number;

    if distance < 0 \/ 32 <= distance then {
        out("Invalid disc pointer to dismount!\n");
        resultis -1;
    }

    // Only need to write to disc if the in-memory data has been changed.
    if disc_info ! disc_has_changed then {
        disc_number := disc_info ! disc_data ! SB_disc_number;

        // First, write the super block back to disc.
        if write_to_disc(
            disc_number,
            SB_block_addr,
            ONE_BLOCK,
            disc_info ! disc_data
        ) <= 0 then {
            out("Unable to save super block!\n");
            resultis -1;
        }
    
        // Next, write the window into the FBL.
        if write_to_disc(
            disc_number,
            disc_info ! disc_data ! SB_FBL_index,
            ONE_BLOCK, 
            disc_info ! disc_FBL_window
        ) <= 0 then {
            out("Unable to save list of free blocks!\n");
            resultis -1;
        }

    }

    freevec(disc_info ! disc_data);
    freevec(disc_info ! disc_FBL_window);
    freevec(disc_info ! disc_current_dir);
    freevec(DISCS ! distance);

    DISCS ! distance := nil;

    resultis 1;
}

let mount (disc_number, disc_name) be {
    // `buffer` will be used to store data read from disc.
    let buffer = vec BLOCK_LEN, length, disc_info;

    // Attempt to read the super block into `buffer`.
    if read_from_disc(disc_number, SB_block_addr, ONE_BLOCK, buffer) <= 0 then {
        out("Unable to read disc %d!\n", disc_number);
        resultis -1;
    }

    // If the disc is unformatted, then return.
    unless disc_is_formatted(buffer) do {
        out("Disc %d is currently unformatted. Cannot mount an unformatted disc!\n", disc_number);
        resultis -1;
    }

    // If the name of the disc to mount is too long or too short, return.
    length := strlen(disc_name);
    unless 0 < length < SB_max_name_len do {
        out("Cannot mount a disc with name '%s' -- which is %d characters -- when the max length is 31\n", disc_name, length);
        resultis -1;
    }

    // If the names do not match, do not mount disc.
    unless streq(disc_name, buffer + SB_name) do {
        out("Cannot mount disc %d ('%s') with name '%s'. Incorrect name.\n", disc_number, buffer + SB_name, disc_name);
        resultis -1;
    }

    // Otherwise, look for a slot in which to store the disc.
    disc_info := get_open_disc_slot();

    // If every slot was taken, then return;
    if disc_info < 0 then {
        out("Unable to mount disc. Can only mount up to 32 file systems. Out of space.\n");
        resultis disc_info;
    }

    // Copy `buffer` into `disc_info ! disc_data`
    copy_buffer(buffer, disc_info ! disc_data, BLOCK_LEN);

    // Clean `buffer` so it doesn't have any crap left in it.
    clear_buffer(buffer, BLOCK_LEN); 

    // Read the current window into the FBL into memory.
    // If unable to read, return.
    if read_from_disc(
        disc_number,
        disc_info ! disc_data ! SB_FBL_index,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to mount disc. Cannot read free block list.\n");
        resultis -1;
    }

    // Otherwise, copy the FBL window into the correct buffer
    // under disc_info.
    copy_buffer(buffer, disc_info ! disc_FBL_window, BLOCK_LEN);

    // Clean the `buffer` again.
    clear_buffer(buffer, BLOCK_LEN);

    if read_from_disc(
        disc_number,
        disc_info ! disc_data ! SB_root_dir,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to mount disc. Cannot read root directory.\n");
        resultis -1;
    }

    // Copy the current directory into the appropriate place
    // under disc_info.
    copy_buffer(buffer, disc_info ! disc_current_dir, BLOCK_LEN);

    resultis disc_info;
}

let format_disc (disc_number, disc_name, force_write) be {
    let buffer = vec BLOCK_LEN, length = strlen(disc_name);
    let free_blocks = devctl(DC_DISC_CHECK, disc_number);
    let fb_block_num = free_blocks - 1, fb_boundary;
    let root_dir_bn;

    // If not passed the correct number of arguments, return;
    unless 1 < numbargs() < 4 do {
        out("format_disc(disc_number, disc_name, [force_write]) was not called with the correct arguments!\n");
        resultis -1;
    }
    
    // If the disc has no available blocks, return.
    if free_blocks <= 0 then {
        out("Disc number %d has no available (i.e., free or used) blocks!\n", disc_number);
        resultis -1;
    }

    // Make sure the disc_name isn't too short or too long.
    unless 1 <= length < SB_max_name_len do {
        out("Disc name '%s' must be between 1 and 31 characters. You passed a name %d characters long!\n",
            disc_name,
            length
        );
        resultis -1;
    }

    // If unable to read the disc, return.
    if read_from_disc(disc_number, SB_block_addr, ONE_BLOCK, buffer) <= 0 then {
        out("Unable to read disc.\n");
        resultis -1;
    }

    // If the disc is formatted and not told to force write, return.
    if disc_is_formatted(buffer) /\ not force_write then {
        out("disc %d has already been formatted. To force format, call format_disc(disc_number, disc_name, true)\n", disc_number);
        resultis -1;
    }

    // Clear the buffer in case it has some leftover junk.
    clear_buffer(buffer, BLOCK_LEN);


    // As explained in the constants at the top of the file,
    // the super block will be located at block 0 on disc.
    // The FBL will follow. To determine the size of the FBL,
    // recall that it is roughly
    //      free_blocks / BLOCK_LEN
    // However, the FBL itself takes up space, so we 

    // The FBL will be 1 + (free_blocks / 128) blocks long.
    buffer ! SB_FBL_size            := 1 + (free_blocks / BLOCK_LEN);

    // But if the number of free blocks is evenly divisible by 128,
    // then the above calculation will have yielded an extra block.
    if free_blocks rem BLOCK_LEN = 0 then
        buffer ! SB_FBL_size -:= 1;

    // The FBL will be located from blocks 1, 2, …, SB_FBL_size,
    // meaning it will start at SB_FBL_size.
    buffer ! SB_FBL_start           := buffer ! SB_FBL_size;

    // Since the disc is just being formatted, the current window
    // will be the beginning of the FBL.
    buffer ! SB_FBL_index           := buffer ! SB_FBL_size;

    // The offset within the last block will be equal to
    //      free_blocks mod BLOCK_LEN
    // For example, if there are 6000 free blocks, then
    // 6000 / 128 = 46.875 blocks will be needed. This
    // then rounds to 47 blocks. But the last block will
    // not be filled completely.
    // Note that 46 * 128 = 5888 and that 6000 - 5888 = 112
    // Meaning the last block will have 112 free block entries.
    // Thus, the offset within the last block will be
    //      (free_blocks - 1) mod 128
    buffer ! SB_FBL_index_offset    := (free_blocks - 1) rem BLOCK_LEN;

    // The FBL always ends at the block at index 1.
    buffer ! SB_FBL_end             := 1;

    // Record the current date in the super block.
    buffer ! SB_format_date         := seconds();

    // As explained in the constants, these two values are
    // used to determine whether a disc has already been
    // formatted.
    buffer ! SB_format_check        := 1 + random(SB_max_random_check_val);
    buffer ! SB_format_check_value  := (buffer ! SB_format_date) rem (buffer ! SB_format_check);

    // Record the disc number in the super block. When the
    // disc is dismounted, this will allow it to be auto-
    // matically saved. 
    buffer ! SB_disc_number         := disc_number;

    // Copy the disc name into the super block.
    // Already checked that disc_name was no more
    // than 31 characters at the top of the function.
    // Make sure to append the null terminator.
    str_to_fixed(disc_name, buffer + SB_name, length);
    byte 4 * SB_name + length of buffer := 0;

    // Root directory will be located directly after the FBL. 
    buffer ! SB_root_dir            := 1 + (buffer ! SB_FBL_size);
    // And store the root dir block number for future use.
    root_dir_bn := buffer ! SB_root_dir;

    // Save the super block to disc. Report error, if any.
    if write_to_disc(
        disc_number,
        SB_block_addr,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to save super block to disc %d!\n", disc_number);
        resultis -1;
    }

    // Next, need to record the FBL on the disc.
    // The bounds were calculated above, so now we only have
    // to write the numbers into the correct blocks.
    // Since the FBL works like a stack, we'll start at the
    // end and start writing the list of free blocks:
    //      free_blocks - 1, free_blocks - 2, ... free_blocks - 129
    // until free_blocks - N = FBL_start + 1.
    //
    // fb_boundary is the fence post for the last free block, which
    // will be at 1 + FBL_start since that is where the root directory
    // will be located.
    fb_boundary := 1 + buffer ! SB_FBL_start;
    for FBL_block = (buffer ! SB_FBL_end) to (buffer ! SB_FBL_start) do {
        let index = 0;
        clear_buffer(buffer, BLOCK_LEN);

        while index < ONE_BLOCK /\ fb_block_num > fb_boundary do {
            buffer ! index := fb_block_num;
            fb_block_num -:= 1;
        }

        if write_to_disc(disc_number, FBL_block, ONE_BLOCK, buffer) <= 0 then {
            out("Unable to write free block list entry %d to disc %d!\n", FBL_block, disc_number);
            resultis -1;
        }
    }

    // Manually create the root directory.
    clear_buffer(buffer, BLOCK_LEN); 

    buffer ! FH_levels          := 0;
    buffer ! FH_type            := FT_DIRECTORY;
    buffer ! FH_date_created    := seconds();
    buffer ! FH_date_accessed   := buffer ! FH_date_created;
    buffer ! FH_length          := 0;
    buffer ! FH_parent_dir      := 0;
    strcpy("root", buffer + FH_name);

    if write_to_disc(
        disc_number,
        root_dir_bn,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to create root directory!\n");
        resultis -1;
    }

    // Otherwise, return 1 to indicate success;
    resultis 1;
}
