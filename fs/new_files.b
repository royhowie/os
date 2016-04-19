import "io"
import "strings"
import "helpers"

export {
    open, close, create, delete_file,
    ls, read_byte, write_byte, eof
}

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

    /* ----------------------------------------- */
    /* --- directory entry---------------------- */
    /* ----------------------------------------- */
    SIZEOF_DIR_ENT              = 8,

    DIR_E_date                  = 0,
    DIR_E_block                 = 1,
    DIR_E_file_size             = 2,
    DIR_E_file_type             = 3,
    DIR_E_name                  = 4,
    DIR_E_name_len              = 32,

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

    // FILE* to the current directory.
    disc_current_dir            = 3,

    // size in words of the disc_info vector
    disc_info_size              = 4,
    BLOCK_LEN                   = 128,

    /* ----------------------------------------- */
    /* --- files ------------------------------- */
    /* ----------------------------------------- */
    FILE_TABLE_SIZE             = 32,
    FILE_TABLE                  = vec FILE_TABLE_SIZE,

    FT_ENTRY_SIZE               = 5,
    FTB_size                    = 512,
    FTB_size_words              = 128,

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
    FT_block_tree               = 0,

    // Is the file being read ('R') or written to ('W')? 
    FT_direction                = 1,

    // Has the file header been modified?
    FT_modified                 = 2,

    // Pointer to the disc object.
    FT_disc                     = 3,

    // Number of disc on which file is located.
    FT_disc_number              = 4,

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

    // Block number where the file header is located.
    FH_current_block            = 6,
    
    // Name of file or directory. Can be up to 4 words long.
    FH_name                     = 7,
    FH_name_len                 = 32,

    FH_first_word               = 11,

    FT_EOF                      = -1,
    FT_FILE                     = 'F',
    FT_DIRECTORY                = 'D'
}

let ls (disc_info) be {
    let buffer = vec 128, bytes_read;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let files_in_root_dir = disc_info ! disc_data ! SB_files_in_root;

    bytes_read := devctl(DC_DISC_READ, disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    if bytes_read <= 0 then {
        out("Unable to print contents of disc.\n");
        resultis -1;
    }

    out("disc #%d: '%s'\n", disc_number, disc_info ! disc_data + SB_name);
    out("blocks available: %d\nfirst free block: %d\n", disc_info ! disc_data ! SB_blocks_available, disc_info ! disc_data ! SB_first_free_block);

    out("no. name         size\tdate\n");
    for i = 0 to files_in_root_dir - 1 do {
        let dir_entry = buffer + i * DIR_ENT_SIZE;

        // stop looping when an empty entry is hit
        if dir_entry = nil then break;

        out("%2d: %12s %4d\t%d\n",
            i + 1,
            dir_entry + DIR_ENT_NAME,
            dir_entry ! DIR_ENT_FILE_SIZE,
            dir_entry ! DIR_ENT_DATE);
    }
}

let read_byte (file) be {
    let pos_in_buffer, bytes_read;

    unless file ! FT_direction = 'r' do {
        out("file ! FT_direction: %d\n", file ! FT_direction);
        out("File '%s' is not currently opened for reading.\n", file ! FT_file_name);
        resultis FT_EOF;
    }

    pos_in_buffer := file ! FT_position_in_buffer;

    if pos_in_buffer = 0 /\ file ! FT_first_block = file ! FT_current_block then
        devctl(DC_DISC_READ, file ! FT_disc_number, file ! FT_first_block, ONE_BLOCK, file ! FT_buffer);

    if pos_in_buffer < FT_buffer_size then {
        file ! FT_position_in_buffer := pos_in_buffer + 1;
        resultis byte pos_in_buffer of (file ! FT_buffer);
    }

    file ! FT_current_block +:= 1;
    file ! FT_position_in_buffer := 0;

    if file ! FT_current_block > file ! FT_last_available_block then
        resultis FT_EOF;

    bytes_read := devctl(DC_DISC_READ, file ! FT_disc_number, file ! FT_current_block, ONE_BLOCK, file ! FT_buffer);

    if bytes_read <= 0 then
        resultis FT_EOF;

    resultis byte 0 of (file ! FT_buffer);
}

let add_byte_to_file_buffer (file, data) be {
    byte (file ! FT_position_in_buffer) of (file ! FT_buffer) := data;
    file ! FT_position_in_buffer := (file ! FT_position_in_buffer) + 1;
    resultis 1;
}

let write_byte (file, data) be {
    let block_tree = file ! FT_block_tree;
    let file_header = block_tree ! 0;
    let fh_offset = block_tree ! 1;
    let levels = file_header ! FH_levels;
    let free_block, curr_buff, curr_offset;

    unless file ! FT_direction = 'w' do {
        out("File '%s' is not currently opened for writing.\n", file ! FT_file_name);
        resultis FT_EOF;
    }

    file ! FT_modified := true;

    // If the entry is 0, then a block needs to be
    // allocated before anything can be written.
    if levels = 1 /\ file_header ! fh_offset = 0 then {
        free_block := get_free_block(file ! FT_disc);
        block_tree ! 2 := newvec(BLOCK_LEN);
        block_tree ! 3 := 0;

        file_header ! fh_offset := free_block;

        // Clear the buffer so no junk is left over.
        clear_buffer(block_tree ! 2, BLOCK_LEN);

        // Write the empty block to disc.
        write_to_disc(
            file ! FT_disc_number,
            free_block,
            ONE_BLOCK,
            block_tree ! 2
        )
    }

    // Add the byte to a leaf at the end of the block tree.
    curr_buff := block_tree ! (2 * levels - 2);
    curr_offset := block_tree ! (2 * levels - 1);

    // If the current offset within a leaf is less than 511,
    // then just add the byte to the buffer and then increment
    // the offset.
    // Return 1 to indicate success.
    if curr_offset < 511 then {
        byte curr_offset of curr_buff := data;
        block_tree ! (2 * levels - 1) +:= 1;
        resultis 1;
    }

    // Otherwise, the leaf buffer will be full after writing
    // the next byte, so
    //      1. add byte to buffer
    //      2. write buffer to disc
    //      3. obtain the next block
    //      4. load it as a leaf node
    //      5. recurse, if necessary.


    for index = levels - 1 to 0 by -1 do {
        let buff = block_tree ! (2 * index);
        let offset = block_tree ! (2 * index + 1);

        if index = levels 
    }
}


let write_byte (file, data) be {
    let pos_in_buffer, bytes_written;

    unless file ! FT_direction = 'w' do {
        out("File '%s' is not currently opened for writing.\n", file ! FT_file_name);
        resultis FT_EOF;
    }

    if file ! FT_position_in_buffer < FT_buffer_size then
        resultis add_byte_to_file_buffer(file, data);

    bytes_written := write_file_buffer(file);

    if bytes_written <= 0 then {
        out("Unable to write to file '%s'.\n", file ! FT_file_name);
        resultis FT_EOF;
    }

    file ! FT_position_in_buffer := 0;
    file ! FT_current_block     +:= 1;

    byte 0 of (file ! FT_buffer) := data;

    resultis 1;
}

let eof (file) be {
    resultis file ! FT_position_in_buffer >= 511 /\ file ! FT_current_block = file ! FT_last_available_block;
}

let file_in_dir (disc_info, file_name) be {
    let current_dir = disc_info ! disc_current_dir;
    let block_number = current_dir ! FT_disc_number;
    let dir_entry = vec SIZEOF_DIR_ENT;

    // It would be more efficient to write a "rewind" function, but oh well.
    close(current_dir);
    disc_info ! disc_current_dir := open_dir(disc_info, block_number, 'r');
    current_dir := disc_info ! disc_current_dir;

    until eof(current_dir) do {
        // read a dir-entry-sized chunk from the file
        for i = 0 to 4 * SIZEOF_DIR_ENT do
            byte i of dir_entry := read_byte(current_dir);
        
        // If file_name matches the name of the dir_entry, then
        if streq(file_name, dir_entry + DIR_E_name) then {
            // clean up by closing and reopening the current directory.
            close(current_dir);
            disc_info ! disc_current_dir := open_dir(disc_info, block_number, 'r');

            // And return the block number of the file header.
            resultis dir_entry ! DIR_E_block;
        }
    }

    // No match found, so return -1.
    resultis -1;
}

let delete_file (disc_info, file_name) be {
    let buffer = vec 128, bytes_operated, num_files, last_entry, dir_entry;

    bytes_operated := devctl(DC_DISC_READ, disc_info ! disc_data ! SB_disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    if bytes_operated <= 0 then
        resultis -1;

    dir_entry := file_in_dir(disc_info, file_name, buffer);

    if dir_entry = nil then
        resultis -1;

    num_files := disc_info ! disc_data ! SB_files_in_root;
    last_entry := buffer + ((num_files - 1) * DIR_ENT_SIZE);

    // out("dir_entry: %x\tlast_entry: %x\n", dir_entry, last_entry);

    copy_buffer(last_entry, dir_entry, DIR_ENT_SIZE);
    clear_buffer(last_entry, DIR_ENT_SIZE);

    disc_info ! disc_data ! SB_files_in_root -:= 1;
    disc_info ! disc_has_changed := 1;
    
    resultis devctl(DC_DISC_WRITE, disc_info ! disc_data ! SB_disc_number, root_dir_block_addr, ONE_BLOCK, buffer);
}

let file_already_open (block_number, disc_number) be {
    for index = 0 to FILE_TABLE_SIZE - 1 do {
        let file_entry = FILE_TABLE ! index;
        let file_header;

        // If the entry is null, continue searching.
        if file_entry = nil then loop;

        // Otherwise, grab the file header from the file
        // entry's block tree.
        file_header := file_entry ! FT_block_tree ! 0;

        // If the disc numbers and file header block numbers match, then return the entry
        if (file_header ! FH_current_block) = block_number /\ (file_header ! FH_current_block) = disc_number then
            resultis file; 
    }

    // Otherwise, nothing was found, so return nil
    resultis nil;
}

let get_free_block (disc_info) be {
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let end = disc_info ! disc_data ! SB_FBL_end;
    let index = disc_info ! disc_data ! SB_FBL_index;
    let offset = disc_info ! disc_data ! SB_FBL_index_offset;
    let free_block_number = -1;

    // If the index block of the FBL is equal to the end block
    // and the offset within the window is -1, then the disc
    // has no more free blocks. 
    if index = end /\ offset = -1 then {
        out("Unable to write: no free blocks left on disc %d!\n", disc_number);
        resultis -1;
    }

    // Disc has been altered, so make sure it saves on dismount.
    disc_info ! disc_has_changed := true;

    // Grab the next free block number and scrub it from the window.
    free_block_number := disc_info ! disc_FBL_window ! offset;
    disc_info ! disc_FBL_window ! offset := -1;

    // If the offset within the FBL window is greater than 0,
    // then simply update the offset and return the block number.
    if 0 < offset then {
        disc_info ! disc_data ! SB_FBL_index_offset := offset - 1;
        resultis free_block_number;
    }

    // Otherwise, if offset is 0, the FBL window will be empty after
    // the free block number is taken from it. Thus, a new window
    // must be read into memory.

    // So write the old window back to disc.
    if write_to_disc(
        disc_number,
        index,
        ONE_BLOCK,
        disc_info ! disc_FBL_window
    ) <= 0 then {
        out("Unable to save FBL window to disc!\n");
        resultis -1;
    }  

    // Clear the buffer just in case.
    clear_buffer(disc_info ! disc_FBL_window, BLOCK_LEN);

    // And read the new FBL window into memory.
    if read_from_disc(
        disc_number,
        index - 1,
        ONE_BLOCK,
        disc_info ! disc_FBL_window
    ) <= 0 then {
        out("Unable to read further blocks of disc!\n");
        resultis -1;
    }

    // Set the offset to the last word in the block.
    disc_info ! disc_data ! SB_FBL_index_offset := BLOCK_LEN - 1;

    // Update the index of the FBL window.
    disc_info ! disc_data ! SB_FBL_index := index - 1;

    // Save the offset within the FBL in the SB.
    disc_info ! disc_data ! SB_FBL_index_offset := offset - 1;

    resultis free_block_number;
}

let release_block (disc_info, block_number) be {
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let start = disc_info ! disc_data ! SB_FBL_start;
    let index = disc_info ! disc_data ! SB_FBL_index;
    let offset = disc_info ! disc_data ! SB_FBL_index_offset;

    if block_number <= start then {
        out("Cannot free block #%d, since it will always be in use!\n", block_number);
        resultis -1;
    }

    if index = start /\ offset = 128 then {
        out("Error. Every block on disc has been freed. Cannot free block #%d\n", block_number);
        resultis -1;
    }

    // Disc has been altered, so make sure it saves on dismount.
    disc_info ! disc_has_changed := true;

    // The newly freed block will be appended to the list, so
    // increment offset (since offset has a free block already).
    offset +:= 1;

    // If offset is within the bounds of the FBL window,
    // i.e., if 0 <= offset < 128 = BLOCK_LEN,
    // then just add to the list and return. 
    if offset < BLOCK_LEN then {
        disc_info ! disc_FBL_window ! offset := block_number;

        // Update the offset for the FBL window in the SB.
        disc_info ! disc_data ! SB_FBL_index_offset := offset;

        resultis block_number;
    }

    // Otherwise, if offset = BLOCK_LEN, then a new block
    // needs to be read into the FBL window in order to
    // store the newly freed block.

    // First, write the FBL window back to disc.
    if write_to_disc(
        disc_number,
        index,
        ONE_BLOCK,
        disc_info ! disc_FBL_window
    ) <= 0 then {
        out("Unable to write FBL window back to disc!\n");
        resultis -1;
    }

    // Clean the buffer.
    clear_buffer(disc_info ! disc_FBL_window, BLOCK_LEN);

    // Read the new FBL window into memory
    if read_from_disc(
        disc_number,
        index + 1,
        ONE_BLOCK,
        disc_info ! disc_FBL_window
    ) <= 0 then {
        out("Unable to read FBL window into memory!\n");
        resultis -1;
    }

    // Increment the index of the FBL window.
    disc_info ! disc_data ! SB_FBL_index := index + 1;
    
    // Offset within the FBL window is the beginning.
    disc_info ! disc_data ! SB_FBL_index_offset := 0;

    resultis block_number;
}

let create (disc_info, file_name, type) be {
    let buffer = vec 128;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let free_block = -1, parent_block_number;

    // Can only create a directory or a file.
    unless type = FT_FILE \/ type = FT_DIRECTORY do {
        out("File can only be of type 'F' (file) or 'D' (directory)!\n");
        resultis -1;
    }

    // If the file_name is not the correct length, return.
    unless 1 <= strlen(file_name) < FH_name_len do {
        out("File name must be between 1 and 31 characters! '%s' invalid name.\n");
        resultis -1;
    }

    // Clean the buffer just in case.
    clear_buffer(buffer, BLOCK_LEN);

    // Files are always at least of level 1. 
    buffer ! FH_levels          := 1;

    buffer ! FH_type            := type;
    buffer ! FH_date_created    := seconds();
    buffer ! FH_date_accessed   := buffer ! FH_date_created;
    buffer ! length             := 0;

    // disc_info ! disc_current_dir is FILE*,
    // so ! current_block is the block number of
    // the file header.
    parent_block_number         := disc_info ! disc_current_dir ! current_block;
    buffer ! parent_dir         := parent_block_number;

    // Copy the file name into the file header.
    strcpy(buffer + FH_name, file_name);

    // Request a free block with which to store the file header.
    free_block := get_free_block(disc_info);
    if free_block = -1 then {
        out("No room on disc!\n");
        resultis -1;
    }

    // Store the header block in the file header.
    buffer ! current_block := free_block;

    // Write the file header to disc.
    if write_to_disc(
        disc_number,
        free_block,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to save file to disc!\n");
        resultis -1;
    }

    // Add the file to the current directory
    add_dir_entry(
        disc_info,
        file_name,
        free_block,
        0,
        FT_FILE,
        buffer ! FH_date_created
    );

    // Directories should have ./ and ../ entries.
    // This should probably involve a change of directories function.
    if type = FT_DIRECTORY then {
        // NEED TO WRITE `add_dir_entry`.
        // add_dir_entry(disc_info, "./", free_block);
        // add_dir_entry(disc_info, "../", parent_block_number); 
    }

    resultis 1;
}

and open_dir (disc_info, block_number, direction) be {
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let buffer = vec 128;

    // Read header file into memory
    if read_from_disc(disc_number, block_number, ONE_BLOCK, buffer) <= 0 then {
        out("Unable to read directory located at block %d\n", block_number);
        resultis -1;
    }

    resultis create_FT_entry(buffer, disc_number, direction); 
}

let create_FT_entry (file_buffer, disc_number, direction) be {
    // Grab the levels in this file from the header.
    let levels := file_buffer ! FH_levels;
    let file_open := file_already_open(file_buffer + FH_name, disc_number);
    let index = 0;

    // If the file is already open, then just return its entry.
    unless file_open = nil resultis file_open;

    // Search for a null entry in the file table.
    until index = FILE_TABLE_SIZE \/ (FILE_TABLE ! index) = nil do
        index +:= 1;

    // If the end of the file table was reached, then there is no room
    // in the file table for new entries, so return.
    if index = FILE_TABLE_SIZE then {
        out("Could not open file because the maximum of %d files are already open!\n", FILE_TABLE_SIZE);
        resultis nil;
    }

    // Create a file entry and store it in the file table.
    file_entry := newvec(FT_ENTRY_SIZE);
    FILE_TABLE ! index := file_entry;

    // Next, read a partial block tree into memory.
    // FT_block_tree will be a vector of length
    // 2 * levels and will follow the pattern
    //  0:  buffer_level_1
    //  1:  offset within buffer_level_1
    //  2:  buffer_level_2
    //  3:  offset within buffer_level_2
    //  ...
    // Thus, create a vector for the block tree.
    file_entry ! FT_block_tree := newvec(2 * levels);

    // The first entry is a part of the header block,
    // so enter it manually:
    file_entry ! FT_block_tree ! 0 := newvec(BLOCK_LEN);
    file_entry ! FT_block_tree ! 1 := FH_first_word;
    copy_buffer(file_buffer, file_entry ! FT_block_tree ! 0, BLOCK_LEN);

    // If the block tree has more than 1 level, then need to loop
    // and collect the other parts of the partial block tree.
    if 1 < levels then
        for i = 1 to levels - 1 do {
            let prev_entry_buff = file_entry ! FT_block_tree ! (2 * i - 2); 
            let prev_entry_offset = file_entry ! FT_block_tree ! (2 * i - 1);

            // If the entry at the offset within the buffer is nil,
            // then there is no attached block.
            // This is a guard clause for a newly minted file
            // without any attached blocks of data.
            if prev_entry_buff ! prev_entry_offset = 0 then break;

            // Otherwise, create a buffer a block long and record its
            // offset (which will be zero since file is being opened).
            file_entry ! FT_block_tree ! (2 * i) := newvec(BLOCK_LEN);
            file_entry ! FT_block_tree ! (2 * i + 1) := 0;

            // The block number of the next step in the block tree
            // is record at prev_entry_buff ! prev_entry_offset,
            // so copy it into the current buffer.
            read_from_disc(
                disc_number,
                prev_entry_buff ! prev_entry_offset,
                ONE_BLOCK,
                file_entry ! FT_block_tree ! (2 * i)                
            );
        }

    // Record the direction (r or w) of the file being opened.
    file_entry ! FT_direction := direction;

    // Record a pointer to the disc object.
    file_entry ! FT_disc := disc_info;

    // Record the disc number.
    file_entry ! FT_disc_number := disc_info ! disc_data ! SB_disc_number;

    // And, naturally, the file has not yet been modified.
    file_entry ! FT_modified := false;

    resultis file_entry;
}

and add_dir_entry (disc_info, fname, block, size, type, date) {
    let current_dir = disc_info ! disc_current_dir;

    // Write data to the directory in the following order:
    // DIR_E_date                  = 0,
    // DIR_E_block                 = 1,
    // DIR_E_file_size             = 2,
    // DIR_E_file_type             = 3,
    // DIR_E_name                  = 4,

    let dir_block_tree = current_dir ! FT_block_tree;
    let dir_header = dir_block_tree ! 0;
    let offset = dir_block_tree ! 1;

    let dir_entries = dir_header ! FH_length;
    let levels = dir_header ! FH_levels;

    let free_block;

    // If dir_header ! offset is 0, then this is a newly
    // minted directory, i.e., it has no entries.
    // So we need to request a free block
    if dir_header ! offset = 0 then {
        free_block := get_free_block(disc_info);

        // If unable to allocate a new block, return.
        if free_block = -1 then {
            out("No free blocks on disc. Unable to continue writing.\n");
            resultis -1;
        }

        // Otherwise, record the new block.
        dir_header ! offset := free_block;

        // Mark the directory as having been modified
        current_dir ! FT_modified = true;

    }



    
}

and open (disc_info, file_name, direction) be {
    let buffer = vec 128;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let block_number;

    // If not passed 'r' for reading or 'w' for writing, return;
    unless direction = 'r' \/ direction = 'w' do {
        out("Invalid file direction. 'r' is for reading and 'w' for writing.\n");
        resultis nil;
    }

    // If not passed 3 arguments, return.
    unless numbargs() = 3 do {
        out("open(disc_info, file_name, direction) called with incorrect number of arguments\n");
        resultis nil;
    }

    block_number := file_in_dir(disc_info, file_name);

    // If the block number is -1, then the file is not
    // present in the current directory.
    if block_number = -1 then {
        out("File does not exist in current directory!\n");
        resultis nil;
    }

    // If a directory, open by block number, set as the current directory
    test (buffer ! FH_TYPE) = FT_DIRECTORY then {
        close(disc_info ! disc_current_dir);
        disc_info ! disc_current_dir := open_dir(disc_info, block_number, direction);
        resultis disc_info ! disc_current_dir;
    }

    // Otherwise, open like a normal file.
    if read_from_disc(
        disc_number,
        block_number,
        ONE_BLOCK,
        buffer
    ) <= 0 then {
        out("Unable to read header block from disc!\n");
        resultis nil;
    }

    resultis create_FT_entry(buffer, disc_number, direction);
}

let close (file) be {
    let distance = @file - FILE_TABLE;
    let levels, block_tree, disc_number;

    unless 0 <= distance < FILE_TABLE_SIZE do {
        out("Invalid file pointer!\n");
        resultis -1;
    }

    block_tree := file ! FT_block_tree;
    levels := block_tree ! 0 ! FH_levels;
    disc_number := file ! FT_disc_number;

    // If the file was in write mode and it was modified,
    // make sure to write the buffers in the block tree
    // back to disc.
    if file ! FT_modified /\ file ! FT_direction = 'w' then {
        for i = levels - 1 to 1 by -1 do {
            let prev_buff = block_tree ! (2 * i - 2);
            let offset = block_tree ! (2 * i - 1);
            let current_buff = block_tree ! (2 * i);

            // Write an intermediary file in the block tree back to disc.
            write_to_disc(
                disc_number,
                prev_buff ! offset,
                ONE_BLOCK,
                current_buff
            );
        }

        // write the file header back to disc
        write_to_disc(
            disc_number,
            block_tree ! 0 ! FH_current_block,
            ONE_BLOCK,
            block_tree ! 0
        );
        
    }

    // Free the buffers from the block tree.
    for i = 0 to levels - 1 by -1 do
        freevec(file ! FT_block_tree ! (i * 2));

    // Along with the actual block tree.
    freevec(file ! FT_block_tree);

    // And the file entry itself.
    freevec(file);

    // Erase from the file table.
    FILE_TABLE ! distance := nil;

    // And return 1 to indicate success.
    resultis 1;
}
