import "blocktree"
import "free-blocks"
import "fs-constants"
import "helpers"
import "io"
import "strings"

export { open, open_dir, close, read_byte, write_byte, create, delete, eof, ls }

let read_byte (FILE) be {
    let data;

    if FILE ! FT_direction = FT_WRITE then {
        out("File not open for reading.\n");
        resultis FT_EOF;
    }

    data := block_tree_get(FILE);
    block_tree_advance(FILE);

    resultis data;
}

and write_byte (FILE, data) be {
    if FILE ! FT_direction = FT_READ then {
        out("File not open for writing!\n");
        resultis FT_EOF;
    }

    block_tree_set(data);
    block_tree_advance(FILE);
    resultis 1;
}

and eof (FILE) be {
    resultis FILE ! FT_file_is_EOF
        \/ (FILE ! FT_BT_byte_pos) = (FILE ! FT_block_tree ! 0 ! FH_length);
}

and get_next_dir_entry (DIR, buff) be {
    let index = 0;

    clear_buffer(buff, SIZEOF_DIR_ENT);

    until index = 4 * SIZEOF_DIR_ENT \/ eof(DIR) do {
        byte index of buff := read_byte(DIR);
        index +:= 1;
    }

    resultis index = 4 * SIZEOF_DIR_ENT -> 1, -1;
}

and ls (disc_info) be {
    let buff = vec SIZEOF_DIR_ENT;
    let DIR = disc_info ! disc_current_dir;
    let file_number = 1;

    block_tree_rewind(DIR);

    outs("no. type name size date\n");

    until eof(DIR) do {
        if get_next_dir_entry(DIR, buff) = -1 then {
            out("hit last entry!\n");
            return;
        }
        
        out(
            "%2d: (%c) %32s %4d\t%d\n",
            file_number,
            buff ! DIR_E_file_type,
            buff + DIR_E_name,
            buff ! DIR_E_file_size,
            buff ! DIR_E_date
        );

        file_number +:= 1;
    }
}

and file_in_dir (disc_info, file_name) be {
    let DIR = disc_info ! disc_current_dir;
    let buff = vec SIZEOF_DIR_ENT;

    block_tree_rewind(DIR);

    until eof(DIR) do {
        if get_next_dir_entry(DIR, buff) = -1 then
            resultis -1;

        if file_name %streq (buff + DIR_E_name) then {
            block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);
            resultis buff ! DIR_E_block;
        }
    }

    resultis -1;
}

and delete (disc_info, file_name) be {
    let DIR = disc_info ! disc_current_dir;
    let buff = vec SIZEOF_DIR_ENT;
    let search = vec SIZEOF_DIR_ENT;

    block_tree_wind(DIR);

    block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);

    if get_next_dir_entry(DIR, buff) = -1 then {
        out("Directory has no entries left.");
        resultis -1;
    }

    // If the file is the last one in directory, delete it.
    if file_name %streq (buff + DIR_E_name) then {
        block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);
        for i = 0 to 4 * SIZEOF_DIR_ENT - 1 do write_byte(DIR, 0);
        resultis 1;
    }

    block_tree_rewind(DIR);

    until eof(DIR) do {
        if get_next_dir_entry(DIR, search) = -1 then {
            outs("File not in directory, so it cannot be deleted.\n");
            resultis -1;
        }

        if file_name %streq (search + DIR_E_name) then
            break;
    }

    // If the end of the directory was reached, then the
    // file is not there.
    if eof(DIR) then resultis -1;

    // Otherwise, write over the found dir_ent with the last
    // dir_ent from before (i.e., with `buff`).
    block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);
    for i = 0 to 4 * SIZEOF_DIR_ENT - 1 do
        write_byte(DIR, byte i of buff);

    block_tree_save(DIR);

    resultis 1;
}

and file_already_open (block_number, disc_number) be {
    for index = 0 to FILE_TABLE_SIZE - 1 do {
        let FILE = FILE_TABLE ! index;
        let file_header;

        // If the entry is null, continue searching.
        if FILE = nil then loop;

        // Otherwise, grab the file header from the file
        // entry's block tree.
        file_header := FILE ! FT_block_tree ! 0;

        // If the disc numbers and file header block numbers match, then return the entry
        if (file_header ! FH_current_block) = block_number /\ (file_header ! FH_current_block) = disc_number then
            resultis FILE; 
    }

    // Otherwise, nothing was found, so return nil
    resultis nil;
}

and create (disc_info, file_name, type) be {
    let buffer = vec BLOCK_LEN;
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
    clear_block(buffer);

    // Files start as a 0-level block tree. 
    buffer ! FH_levels          := 0;

    buffer ! FH_type            := type;
    buffer ! FH_date_created    := seconds();
    buffer ! FH_date_accessed   := buffer ! FH_date_created;
    buffer ! FH_length          := 0;

    // disc_info ! disc_current_dir is FILE*,
    // so ! current_block is the block number of
    // the file header.
    parent_block_number         := disc_info ! disc_current_dir ! FT_block_tree ! 0 ! FH_current_block;
    buffer ! FH_parent_dir      := parent_block_number;

    // Copy the file name into the file header.
    strcpy(buffer + FH_name, file_name);

    // Request a free block with which to store the file header.
    free_block := get_free_block(disc_info);
    if free_block = -1 then {
        out("No room on disc!\n");
        resultis -1;
    }

    // Store the header block in the file header.
    buffer ! FH_current_block := free_block;

    // Write the file header to disc.
    if write_block(disc_number, free_block, buffer) <= 0 then {
        out("Unable to save file to disc!\n");
        resultis -1;
    }

    // Add the file to the current directory
    add_dir_entry(disc_info, file_name, free_block, 0, FT_FILE, buffer ! FH_date_created);

    // Directories should have ./ and ../ entries.
    // This should probably involve a change of directories function.
    if type = FT_DIRECTORY then {
        open(disc_info, file_name, FT_BOTH);

        add_dir_entry(disc_info, "./", free_block, 0, FT_DIRECTORY, buffer ! FH_date_created);
        add_dir_entry(disc_info, "../", parent_block_number, 0, FT_DIRECTORY, seconds());

        open(disc_info, "../", FT_BOTH);
    }

    resultis 1;
}

and open_dir (disc_info, block_number, direction) be {
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let buffer = vec BLOCK_LEN;

    // Read header file into memory
    if read_block(disc_number, block_number, buffer) <= 0 then {
        out("Unable to read directory located at block %d\n", block_number);
        resultis -1;
    }

    resultis create_FT_entry(buffer, disc_info, direction); 
}

and create_FT_entry (file_buffer, disc_info, direction) be {
    let index = 0, FILE;
    let file_open = file_already_open(file_buffer + FH_name, disc_number);
    let disc_number = disc_info ! disc_data ! SB_disc_number;

    // If the file is already open, then just return its entry.
    unless file_open = nil do resultis file_open;

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
    FILE := newvec(FT_ENTRY_SIZE);
    FILE_TABLE ! index := FILE;

    // Record the direction (r or w) of the file being opened.
    FILE ! FT_direction := direction;

    // Record a pointer to the disc object.
    FILE ! FT_disc_info := disc_info;

    // Record the disc number.
    FILE ! FT_disc_number := disc_number;

    // And, naturally, the file has not yet been modified.
    FILE ! FT_modified := false;

    if block_tree_init(FILE, file_buffer) = -1 then {
        // Ideally, should clean up block tree if initialization fails.
        out("Oh no! Unable to initialize block tree correctly!\n");
        resultis nil;
    }

    resultis FILE;
}

and add_dir_entry (disc_info, fname, block_num, size, type, date) be {
    let DIR = disc_info ! disc_current_dir;
    let buff = vec SIZEOF_DIR_ENT;

    block_tree_wind(DIR);

    buff ! DIR_E_date       := date;
    buff ! DIR_E_block      := block_num;
    buff ! DIR_E_file_size  := size;
    buff ! DIR_E_file_type  := type;
    strcpy(buff + DIR_E_name, fname);

    for index = 0 to 4 * SIZEOF_DIR_ENT - 1 do
        write_byte(DIR, byte index of buff);    

    block_tree_save(DIR, true);

    resultis 1;
}

and open (disc_info, file_name, direction) be {
    let buffer = vec BLOCK_LEN;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let block_number;

    // If not passed 3 arguments, return.
    unless numbargs() = 3 do {
        out("open(disc_info, file_name, direction) called with incorrect number of arguments\n");
        resultis nil;
    }

    // If not passed 'r' (reading), 'w' (writing), or 'b' (both), return
    unless direction = FT_READ \/ direction = FT_WRITE \/ direction = FT_BOTH do {
        out("Invalid file direction. 'r' is for reading and 'w' for writing.\n");
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
    if buffer ! FH_TYPE = FT_DIRECTORY then {
        close(disc_info ! disc_current_dir);
        disc_info ! disc_current_dir := open_dir(disc_info, block_number, direction);
        resultis disc_info ! disc_current_dir;
    }

    // Otherwise, open like a normal file.
    if read_block(disc_number, block_number, buffer) <= 0 then {
        out("Unable to read header block from disc!\n");
        resultis nil;
    }

    resultis create_FT_entry(buffer, disc_info, direction);
}

and close (FILE) be {
    let distance = @FILE - FILE_TABLE;
    let levels, block_tree;

    unless 0 <= distance < FILE_TABLE_SIZE do {
        outs("Invalid file pointer!\n");
        resultis -1;
    }

    // If the file wasn't modified or it's a read-only file,
    unless not FILE ! FT_modified \/ FILE ! FT_DIRECTION = FT_READ do {
        block_tree_save(FILE, true);

        // Should only remove excess blocks from the tree if
        // the file was in write-only mode.
        if FILE ! FT_DIRECTION = FT_WRITE then
            block_tree_pare(FILE);
    }

    block_tree := FILE ! FT_block_tree;
    levels := block_tree ! 0 ! FH_levels;

    // Free the buffers from the block tree.
    for i = 0 to levels do
        freevec(block_tree ! (i * 2));

    // Along with the actual block tree.
    freevec(block_tree);

    // And the file entry itself.
    freevec(file);

    // Erase from the file table.
    FILE_TABLE ! distance := nil;

    // And return 1 to indicate success.
    resultis 1;
}

