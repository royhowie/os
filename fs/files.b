import "io"
import "strings"

export {
    open, close, create, delete_file, ls, read_byte, write_byte, eof,
    get_file_size_in_blocks
}

manifest {
    /* ------------------------ */
    /* --- format_disk -------- */
    /* ------------------------ */
    SB_block_addr               = 0,
    SB_first_free_block         = 0,
    SB_blocks_available         = 1,
    SB_format_date              = 2,
    SB_format_check             = 3,
    SB_format_check_value       = 4,
    // approximately 2^29 seconds from Jan 1 2000 to
    // March 21 2016, so pick a random value between 1
    // and 2 ** 26 so that x mod SB_format_check is not
    // necessarily equal to x.
    // If max value was 2**32 - 1, then there would be a
    // 7 in 8 chance that x mod SB_format_check = x
    SB_max_random_check_val     = 2 ** 26,
    SB_disc_number              = 5,
    SB_files_in_root            = 6,
    SB_name                     = 7,
    // 8 words; last character is null
    SB_max_name_len             = 32,
    SB_max_name_len_words       = 8,

    root_dir_block_addr         = 1,

    max_entries_in_dir          = 18,

    DIR_ENT_DATE                = 0,
    DIR_ENT_ADDR                = 1,
    DIR_ENT_FILE_SIZE           = 2,
    DIR_ENT_NAME                = 4,
    DIR_ENT_NAME_LEN            = 12,
    DIR_ENT_SIZE                = 7,

    ONE_BLOCK                   = 1,

    /* ------------------------ */
    /* --- mount -------------- */
    /* ------------------------ */
    max_number_of_discs         = 32,
    DISCS                       = vec max_number_of_discs,
    disc_has_changed            = 0,
    // store the super block in memory in a 128-word vector
    disc_data                   = 1,
    // size in words of the disc_info vector
    disc_info_size              = 2,
    block_length                = 128,

    /* ------------------------ */
    /* --- files -------------- */
    /* ------------------------ */
    FILE_TABLE_SIZE             = 32,
    FILE_TABLE                  = vec FILE_TABLE_SIZE + 1,

    FT_ENTRY_SIZE               = 11,

    FT_buffer                   = 0,
    FT_buffer_size              = 512,
    FT_buffer_size_words        = 128,
    FT_position_in_buffer       = 1,
    FT_first_block              = 2,
    FT_current_block            = 3,
    FT_last_available_block     = 4,
    FT_disc_number              = 5,
    FT_direction                = 6,
    FT_index                    = 7,
    FT_file_name                = 8,
    FT_file_name_len            = 12,

    FT_EOF                      = -1
}

let min (a, b) = a < b -> a, b;
let copy_buffer (source, dest, length) be for i = 0 to length - 1 do dest ! i := source ! i;
let clear_buffer (buffer, length) be for i = 0 to length - 1 do buffer ! i := 0;

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

let get_file_size_in_blocks (file) be {
    resultis (file ! FT_last_available_block) - (file ! FT_first_block) + 1;
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

let write_file_buffer (file) be {
    // out("\nI was called!\n");
    // out("disc number: %d\nblock to write to: %d\ndistance: %d\nbuffer %x\n", file ! FT_disc_number, file ! FT_current_block, ONE_BLOCK, file ! FT_buffer);
    // out("buffer: %s\n", file ! FT_buffer);
    resultis devctl(DC_DISC_WRITE, file ! FT_disc_number, file ! FT_current_block, ONE_BLOCK, file ! FT_buffer);
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

let find_file_in_directory (disc_info, file_name, dir) be {
    for i = 0 to (disc_info ! disc_data ! SB_files_in_root) - 1 do {
        let ptr = dir + i * DIR_ENT_SIZE;
        if strcmp(file_name, ptr + DIR_ENT_NAME) = 0 then
            resultis ptr;
    }
    resultis nil;
}

let delete_file (disc_info, file_name) be {
    let buffer = vec 128, bytes_operated, num_files, last_entry, dir_entry;

    bytes_operated := devctl(DC_DISC_READ, disc_info ! disc_data ! SB_disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    if bytes_operated <= 0 then
        resultis -1;

    dir_entry := find_file_in_directory(disc_info, file_name, buffer);

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

let file_already_open (file_name, disc_number) be {
    for i = 0 to FILE_TABLE_SIZE - 1 do {
        let file = FILE_TABLE ! i;
        if file = nil
            then loop;
        if strcmp(file_name, file + FT_file_name) = 0 /\ (file ! FT_disc_number) = disc_number then
            resultis file;
    }
    resultis nil;
}

let add_file_to_table (file_name, dir_entry, disc_number, direction, disc_info) be {
    /*
        There seems to be a bug with starting with i = 0; too tired to figure out why.
        Decided to temporarily fix it by starting at index 1 and making the file table
        have 33 entries, with the first one always going unused.
    */
    let i = 1, file, length;
    while i < FILE_TABLE_SIZE /\ FILE_TABLE ! i <> nil do {
        i +:= 1;
    }

    if i = FILE_TABLE_SIZE then {
        out("Could not open file because %d files (the maximum) are already open!\n", FILE_TABLE_SIZE);
        resultis nil;
    }

    file := newvec(FT_ENTRY_SIZE);

    file ! FT_buffer := newvec(FT_buffer_size_words);
    file ! FT_position_in_buffer := 0;
    file ! FT_first_block := dir_entry ! DIR_ENT_ADDR;
    file ! FT_current_block := dir_entry ! DIR_ENT_ADDR;
    file ! FT_last_available_block := (dir_entry ! DIR_ENT_ADDR) + (dir_entry ! DIR_ENT_FILE_SIZE) - 1;
    file ! FT_disc_number := disc_number;
    file ! FT_direction := direction;
    file ! FT_index := i;

    length := min(strlen(file_name), FT_file_name_len - 1);
    str_to_fixed(file_name, file + FT_file_name, length);
    byte length of (file + FT_file_name) := 0;

    FILE_TABLE ! i := file;

    resultis file;
}

let create (disc_info, file_name, file_size) be {
    let buffer = vec 128, bytes_read, file_loc, length;
    let disc_number = disc_info ! disc_data ! SB_disc_number;
    let files_in_root = disc_info ! disc_data ! SB_files_in_root;

    bytes_read := devctl(DC_DISC_READ, disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    if bytes_read <= 0 then {
        out("Unable to create file '%s'.\n", file_name);
        resultis -1;
    }

    file_loc := buffer + (DIR_ENT_SIZE * files_in_root);
    length := min(strlen(file_name), DIR_ENT_NAME_LEN - 1);

    file_loc ! DIR_ENT_DATE := seconds();

    str_to_fixed(file_name, file_loc + DIR_ENT_NAME, length);
    byte length of (file_loc + DIR_ENT_NAME) := 0;
 
    file_loc ! DIR_ENT_ADDR := disc_info ! disc_data ! SB_first_free_block;

    // out("%s begins at %d and goes for %d blocks\n", file_name, file_loc ! DIR_ENT_ADDR, file_size);

    file_loc ! DIR_ENT_FILE_SIZE := file_size;

    disc_info ! disc_data ! SB_first_free_block := (disc_info ! disc_data ! SB_first_free_block) + file_size;
    disc_info ! disc_data ! SB_blocks_available := (disc_info ! disc_data ! SB_blocks_available) - file_size;
    disc_info ! disc_data ! SB_files_in_root := files_in_root + 1;
    disc_info ! disc_has_changed := 1;

    resultis devctl(DC_DISC_WRITE, disc_number, root_dir_block_addr, ONE_BLOCK, buffer);
}

let open (disc_info, file_name, direction) be {
    let buffer = vec 128, bytes_read, file_open, file_in_dir;
    let disc_number = disc_info ! disc_data ! SB_disc_number;

    unless direction = 'r' \/ direction = 'w' do {
        out("Invalid file direction. open(disc_info, file_name, direction) where direction is 'r' or 'w'.\n");
        resultis nil;
    }

    unless numbargs() = 3 do {
        out("open requires 3 arguments: disc_info, file_name, direction.\n");
        resultis nil;
    }

    bytes_read := devctl(DC_DISC_READ, disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    if bytes_read <= 0 then {
        out("Unable to read root directory!\n");
        resultis nil;
    }

    file_in_dir := find_file_in_directory(disc_info, file_name, buffer);

    if file_in_dir = nil then {
        out("Disc %d does not contain a file named '%s'.\n", disc_number, file_name);
        out("To create a file, call create(disc_info, file_name, file_size)\n");
        resultis nil;
    }

    file_open := file_already_open(file_name, disc_number);

    if file_open then {
        out("File '%s' was already open on disc %d!\n", file_name, disc_number);
        resultis file_open;
    }

    resultis add_file_to_table(file_name, file_in_dir, disc_number, direction, disc_info);
}

let close (file) be {
    let index = file ! FT_index;

    if file ! FT_direction = 'w' then {
        out("blocks written: %d\n", write_file_buffer(file));
    }

    freevec(file ! FT_buffer);
    freevec(file);

    FILE_TABLE ! index := nil;    
}
