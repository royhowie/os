import "io"
import "strings"

export { format_disk, mount, dismount }

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
    FILE_TABLE                  = vec FILE_TABLE_SIZE,

    FT_ENTRY_SIZE               = 10,

    FT_buffer                   = 0,
    FT_buffer_size              = 512,
    FT_buffer_size_words        = 128,
    FT_position_in_buffer       = 1,
    FT_first_block              = 2,
    FT_current_block            = 3,
    FT_last_available_block     = 4,
    FT_disc_number              = 5,
    FT_direction                = 6,
    FT_file_name                = 7,
    FT_file_name_len            = 12,

    FT_EOF                      = -1
}

let min (a, b) = a < b -> a, b;
let clear_buffer (buffer, length) be for i = 0 to length - 1 do buffer ! i := 0;
let copy_buffer (source, dest, length) be for i = 0 to length - 1 do dest ! i := source ! i;

let disk_is_formatted (buffer) be {
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
            disc ! disc_data := newvec(block_length);
            DISCS ! i := disc;

            resultis DISCS + i;
        }
    }
    resultis -1;
}

let dismount (disc_info) be {
    let distance = disc_info - DISCS;

    if distance < 0 \/ 32 <= distance then {
        out("Invalid disc pointer to dismount!\n");
        resultis -1;
    }

    if disc_info ! disc_has_changed then {
        devctl(DC_DISC_WRITE, disc_info ! disc_data ! SB_disc_number, SB_block_addr, ONE_BLOCK, disc_info ! disc_data);
    }

    freevec(disc_info ! disc_data);
    freevec(DISCS ! distance);

    DISCS ! distance := nil;

    resultis 1;
}

let mount (disc_number, disc_name) be {
    let buffer = vec 128, bytes_read, length, disc_info;

    bytes_read := devctl(DC_DISC_READ, disc_number, SB_block_addr, ONE_BLOCK, buffer);

    if bytes_read <= 0 then {
        out("Unable to read disc %d!\n", disc_number);
        resultis -1;
    }

    unless disk_is_formatted(buffer) do {
        out("Disc %d is currently unformatted. Cannot mount an unformatted disc!\n", disc_number);
        resultis -1;
    }

    length := strlen(disc_name);
    unless 0 < length < SB_max_name_len do {
        out("Cannot mount a disc with name '%s' -- which is %d characters -- when the max length is 31\n", disc_name, length);
        resultis -1;
    }

    unless strcmp(disc_name, buffer + SB_name) = 0 do {
        out("Cannot mount disc %d ('%s') with name '%s'. Incorrect name.\n", disc_number, buffer + SB_name, disc_name);
        resultis -1;
    }

    disc_info := get_open_disc_slot();

    if disc_info < 0 then {
        out("Unable to mount disc. Can only mount up to 32 file systems. Out of space.\n");
        resultis disc_info;
    }

    copy_buffer(buffer, disc_info ! disc_data, 128);

    resultis disc_info;
}

let format_disk (disc_number, disc_name, force_write) be {
    let buffer = vec 128, bytes_written, length;
    let free_blocks = devctl(DC_DISC_CHECK, disc_number);

    unless 0 < numbargs() < 4 do {
        out("format_disk(disc_number, disc_name, [force_write]) was not called with the correct arguments!\n");
        resultis -1;
    }

    if free_blocks <= 0 then {
        out("Disc number %d has no free blocks!\n", disc_number);
        resultis -1;
    }

    bytes_written := devctl(DC_DISC_READ, disc_number, SB_block_addr, ONE_BLOCK, buffer);

    if disk_is_formatted(buffer) /\ not force_write then {
        out("disc %d has already been formatted. To force format, call format_disk(disc_number, disc_name, true)\n", disc_number);
        resultis -1;
    }

    clear_buffer(buffer, 128);

    buffer ! SB_first_free_block := 2;     // 1st block is the super block; 2nd is the root dir
    buffer ! SB_blocks_available := free_blocks - 2;
    buffer ! SB_format_date := seconds();
    buffer ! SB_format_check := random(2**31);
    buffer ! SB_format_check_value := (buffer ! SB_format_date) rem (buffer ! SB_format_check);
    buffer ! SB_disc_number := disc_number;
    buffer ! SB_files_in_root := 0;

    // disc_name can be up to 32 characters, including the null terminator
    // so if its length is more than 31 characters, need to truncate it
    length := min(strlen(disc_name), SB_max_name_len - 1);
    
    // copy disc_name into the buffer at position
    str_to_fixed(disc_name, buffer + SB_name, length);

    // set the 32nd byte after SB_name to 0
    // null terminate the string
    byte 4 * SB_name + length of buffer := 0;

    bytes_written := devctl(DC_DISC_WRITE, disc_number, SB_block_addr, ONE_BLOCK, buffer);

    if bytes_written <= 0 then {
        out("Unable (error) to write super block to disc %d!\n", disc_number);
        resultis -1;
    }

    clear_buffer(buffer, 128);
    // create_empty_directory(buffer); // optional, since we're writing all 0s anyway

    bytes_written := devctl(DC_DISC_WRITE, disc_number, root_dir_block_addr, ONE_BLOCK, buffer);

    // no need to print an error statement since only 0s are being written

    resultis bytes_written;
}

