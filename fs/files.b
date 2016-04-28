import "blocktree"
import "free-blocks"
import "fs-constants"
import "helpers"
import "io"
import "strings"

export {
    open,
    open_by_block_num,
    close,
    read_byte,
    write_byte,
    create,
    delete,
    eof,
    ls,
    create_dir_entry,
    copy_from_tape
}

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

    block_tree_set(FILE, data);
    block_tree_advance(FILE, true);

    FILE ! FT_modified := true;

    resultis 1;
}

and eof (FILE) be {
    resultis FILE ! FT_BT_byte_pos = FILE ! FT_block_tree ! 0 ! FH_length;
}

and get_next_dir_entry (DIR, buff) be {
    let index = 0;

    clear_buffer(buff, SIZEOF_DIR_ENT);

    until index = 4 * SIZEOF_DIR_ENT \/ eof(DIR) do {
        byte index of buff := read_byte(DIR);
        index +:= 1;
    }

    resultis buff ! DIR_E_file_type <> 0 /\ index = 4 * SIZEOF_DIR_ENT -> 1, -1;
}

and ls (disc_info) be {
    let buff = vec SIZEOF_DIR_ENT;
    let date_buff = vec 7;
    let DIR = disc_info ! disc_current_dir;
    let file_number = 1;

    block_tree_rewind(DIR);

    out("%s %s %16s %s %s\t  %s\n", " # ", "type", "name", " size", "block", "date");

    until eof(DIR) do {
        if get_next_dir_entry(DIR, buff) = -1 then return;

        datetime(buff ! DIR_E_date, date_buff);

        out(
            "%2d: (%c)  %16s %4db %4d\t  %4d %2d %2d %2d:%2d:%2d\n",
            file_number,
            buff ! DIR_E_file_type,
            buff + DIR_E_name,
            buff ! DIR_E_file_size,
            buff ! DIR_E_block,
            date_buff ! 0,  // year
            date_buff ! 1,  // month
            date_buff ! 2,  // day
            date_buff ! 4,  // hour
            date_buff ! 5,  // minute
            date_buff ! 6   // second
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

and delete_file (disc_info, file_name) be {
    let FILE = open(disc_info, file_name, FT_BOTH); 
    let header;

    // If the file cannot be found, it cannot be deleted.
    if FILE = nil then resultis -1;

    header := FILE ! FT_block_tree ! 0;

    // If the file is of type directory and it has more than
    // two directory entries, i.e., if it has more than the default
    // ./ and ../ entries, then the file cannot be deleted.
    if header ! FH_type = FT_DIRECTORY
       /\ header ! FH_length > 2 * 4 * SIZEOF_DIR_ENT then {
        outs("Can only delete empty directories.\n");
        resultis -1;
    }

    // Dismantle the block tree.
    block_tree_destruct(FILE);

    resultis 1;
}

and delete (disc_info, file_name) be {
    let DIR = disc_info ! disc_current_dir;
    let buff = vec SIZEOF_DIR_ENT;
    let search = vec SIZEOF_DIR_ENT;

    // Prevent users from doing destructive things.
    if file_name %streq "./" \/ file_name %streq "../" then {
        out("Cannot delete '%s'.\n", file_name);
        resultis -1;
    }

    if DIR ! FT_block_tree ! 0 ! FH_length <= 2 * 4 * SIZEOF_DIR_ENT then {
        outs("Directory empty.\n");
        resultis -1;
    }

    // Want to first delete the file first, since this might
    // pose problems.
    if delete_file(disc_info, file_name) = -1 then {
        resultis -1;
    }

    // Grab the last dir entry by moving to the end of the file,
    // going back an entry, and grabbing the next entry.
    block_tree_wind(DIR);
    block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);

    // If the file is the last one in directory, delete it directly.
    if file_name %streq (buff + DIR_E_name) then {
        // Move back the distance of a directory entry.
        block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);

        // Reduce the file length by a directory entry.
        DIR ! FT_block_tree ! 0 ! FH_length -:= 4 * SIZEOF_DIR_ENT;

        // And save with zeroing enabled (this zeros out the last
        // directory entry automagically).
        block_tree_save(DIR, true);

        resultis 1;
    }

    // Otherwise, the last entry was not the one we sought to delete,
    // so rewind the block tree and search for it.
    block_tree_rewind(DIR);
    until eof(DIR) do {
        if get_next_dir_entry(DIR, search) = -1 then {
            out("'%s' does not exist in the current directory.\n", file_name);
            resultis -1;
        }

        if file_name %streq (search + DIR_E_name) then break;
    }

    // Otherwise, write over the found dir_ent with the last
    // dir_ent from before (i.e., with `buff`).
    block_tree_go_back(DIR, 4 * SIZEOF_DIR_ENT);
    for i = 0 to 4 * SIZEOF_DIR_ENT - 1 do
        write_byte(DIR, byte i of buff);

    // Decrease the size of the directory to account for the
    // removed directory entry.
    DIR ! FT_block_tree ! 0 ! FH_length -:= 4 * SIZEOF_DIR_ENT;

    block_tree_wind(DIR);

    block_tree_save(DIR, true);

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
    let DIR = disc_info ! disc_current_dir;

    // Can only create a directory or a file.
    unless type = FT_FILE \/ type = FT_DIRECTORY do {
        outs("Incompatible file type. Only 'F' (file) and 'D' (directory) allowed.\n");
        resultis -1;
    }

    // If the file_name is not the correct length, return.
    unless 1 <= strlen(file_name) < FH_name_len do {
        out("File name must be between 1 and %d characters! '%s' invalid name.\n",
            FH_name_len - 1,
            file_name
        );
        resultis -1;
    }

    unless file_in_dir(disc_info, file_name) = -1 do {
        out("'%s' already exists in the current directory.\n", file_name);
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

    // Directories have ./ and ../ entries.
    if type = FT_DIRECTORY then {
        let dir_entry = vec SIZEOF_DIR_ENT;

        // Directories have 2 entries by default.
        buffer ! FH_length := 2 * 4 * SIZEOF_DIR_ENT;

        // create_dir_entry (buff, fname, block_num, size, type, date) be {
        create_dir_entry(
            dir_entry,
            "./",
            free_block,
            buffer ! FH_length,
            FT_DIRECTORY,
            buffer ! FH_date_created
        );

        for index = 0 to SIZEOF_DIR_ENT - 1 do
            (buffer + FH_first_word) ! index := dir_entry ! index;

        create_dir_entry(
            dir_entry,
            "../",
            parent_block_number,
            DIR ! FT_block_tree ! 0 ! FH_length,
            FT_DIRECTORY,
            DIR ! FT_block_tree ! 0 ! FH_date_created
        );

        for index = 0 to SIZEOF_DIR_ENT - 1 do
            (buffer + FH_first_word + SIZEOF_DIR_ENT) ! index := dir_entry ! index;
    }


    // Write the file header to disc.
    if write_block(disc_number, free_block, buffer) <= 0 then {
        out("Unable to save file to disc!\n");
        resultis -1;
    }

    // Add the file to the current directory
    add_dir_entry(disc_info, file_name, free_block, 0, type, buffer ! FH_date_created);

    // Save the current directory.
    block_tree_save(DIR, true);

    resultis 1;
}

and create_FT_entry (file_buffer, disc_info, direction) be {
    let index = 0, FILE;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let file_open = file_already_open(file_buffer + FH_name, disc_number);

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

    // Record the index within the file table.
    FILE ! FT_index := index;

    // And, naturally, the file has not yet been modified.
    FILE ! FT_modified := false;

    if block_tree_init(FILE, file_buffer) = -1 then {
        // Ideally, should clean up block tree if initialization fails.
        out("Oh no! Unable to initialize block tree correctly!\n");
        resultis nil;
    }

    resultis FILE;
}

and create_dir_entry (buff, fname, block_num, size, type, date) be {
    buff ! DIR_E_date       := date;
    buff ! DIR_E_block      := block_num;
    buff ! DIR_E_file_size  := size;
    buff ! DIR_E_file_type  := type;
    strcpy(buff + DIR_E_name, fname);
}

and add_dir_entry (disc_info, fname, block_num, size, type, date) be {
    let DIR = disc_info ! disc_current_dir;
    let buff = vec SIZEOF_DIR_ENT;

    block_tree_wind(DIR);

    create_dir_entry(buff, fname, block_num, size, type, date);

    for index = 0 to 4 * SIZEOF_DIR_ENT - 1 do
        write_byte(DIR, byte index of buff);

    block_tree_save(DIR, false);

    resultis 1;
}

and open_by_block_num (disc_info, block_number, direction) be {
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let buffer = vec BLOCK_LEN;

    // Read header file into memory
    if read_block(disc_number, block_number, buffer) <= 0 then {
        outs("Unable to read file header block from disc!\n");
        resultis -1;
    }

    resultis create_FT_entry(buffer, disc_info, direction); 
}

and open (disc_info, file_name, direction) be {
    let block_number;
    let FILE;

    // If not passed 'r' (reading), 'w' (writing), or 'b' (both), return
    unless direction = FT_READ \/ direction = FT_WRITE \/ direction = FT_BOTH do {
        out("Invalid file direction. 'r' for reading, 'w' for writing, 'b' for both.\n");
        resultis nil;
    }

    block_number := file_in_dir(disc_info, file_name);

    // If the block number is -1, then the file is not
    // present in the current directory.
    if block_number = -1 then {
        out("File does not exist in current directory!\n");
        resultis nil;
    }

    FILE := open_by_block_num(disc_info, block_number, direction);

    // Guard clause for checking whether a file is a directory.
    if FILE = nil then resultis nil;

    if FILE ! FT_block_tree ! 0 ! FH_type = FT_DIRECTORY then {
        close(disc_info ! disc_current_dir);
        disc_info ! disc_current_dir := FILE;
    }

    resultis FILE;
}

and close (FILE) be {
    let levels, block_tree;
    let index = FILE ! FT_index;

    // If the file is a directory, wind it to the end.
    if FILE ! FT_block_tree ! 0 ! FH_type = FT_DIRECTORY then
        block_tree_wind(FILE);

    // If the file was modified and was not opened for reading,
    // then save it.
    if FILE ! FT_modified /\ FILE ! FT_DIRECTION <> FT_READ then {
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
    FILE_TABLE ! index := nil;

    // And return 1 to indicate success.
    resultis 1;
}

and copy_from_tape (disc_info, tape_num, file_name) be {
    let buff = vec BLOCK_LEN;
    let FILE;
    let bytes_read = 512;

    if tape_load(tape_num, file_name, 'R') < 0 then {
        out("Unable to read file from tape.\n");
        resultis -1;
    }

    if create(disc_info, file_name, FT_FILE) = -1 then {
        out("Unable to create file '%s' in current directory.\n", file_name);
        resultis -1;
    }

    FILE := open(disc_info, file_name, FT_WRITE);

    if FILE = nil then {
        out("Unable to open file '%s' for writing.\n", file_name);
        resultis -1;
    }

    until bytes_read < 512 do {
        bytes_read := tape_read(tape_num, buff);

        for i = 0 to bytes_read - 1 do
            write_byte(FILE, byte i of buff);
    }

    close(FILE);

    resultis tape_unload(tape_num) > 0 -> 1, -1;
}

