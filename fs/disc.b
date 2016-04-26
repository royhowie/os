import "io"
import "strings"
import "helpers"
import "fs-constants"
import "files"

export { format_disc, mount, dismount }

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
            DISCS ! i := disc;

            resultis DISCS + i;
        }
    }
    resultis -1;
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
        if write_block(
            disc_number,
            SB_block_addr,
            disc_info ! disc_data
        ) <= 0 then {
            out("Unable to save super block!\n");
            resultis -1;
        }
    
        // Next, write the window into the FBL.
        if write_block(
            disc_number,
            disc_info ! disc_data ! SB_FBL_index,
            disc_info ! disc_FBL_window
        ) <= 0 then {
            out("Unable to save list of free blocks!\n");
            resultis -1;
        }

    }

    freevec(disc_info ! disc_data);
    freevec(disc_info ! disc_FBL_window);
    freevec(DISCS ! distance);

    DISCS ! distance := nil;

    resultis 1;
}

let mount (disc_number, disc_name) be {
    let buffer = vec BLOCK_LEN, length, disc_info;

    // Attempt to read the super block into `buffer`.
    if read_block(disc_number, SB_block_addr, buffer) <= 0 then {
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
    copy_block(buffer, disc_info ! disc_data);

    // Clean `buffer` so it doesn't have any crap left in it.
    clear_block(buffer);

    // Read the current window into the FBL into memory.
    // If unable to read, return.
    if read_block(disc_number, disc_info ! disc_data ! SB_FBL_index, buffer) <= 0 then {
        out("Unable to mount disc. Cannot read free block list.\n");
        resultis -1;
    }

    // Copy the FBL window into the correct buffer under disc_info.
    // Make sure to allocate a vector first.
    disc_info ! disc_FBL_window := newvec(BLOCK_LEN);
    copy_block(buffer, disc_info ! disc_FBL_window);

    // Set the current directory equal to the root directory.
    disc_info ! disc_current_dir := open_dir(disc_info,
        disc_info ! disc_data ! SB_root_dir, FT_both);

    // Return the DISC* object.
    resultis disc_info;
}

let format_disc (disc_number, disc_name, force_write) be {
    let buffer = vec BLOCK_LEN;
    let length = strlen(disc_name);
    let free_blocks = check_disc(disc_number);
    let fb_block_num = free_blocks - 1;
    let fb_boundary, root_dir_bn;

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
    clear_block(buffer);

    // As explained in the constants at the top of the file,
    // the super block will be located at block 0 on disc.
    // The FBL will follow. To determine the size of the FBL,
    // recall that it is roughly
    //      free_blocks / BLOCK_LEN
    // However, the FBL itself takes up space, and we know the
    // super block is unavilable, so the FBL is
    //   (free_blocks - 1 - (free_blocks - 1)/BLOCK_LEN) / BLOCK_LEN  
    // which accounts for the length of the free block list.
    buffer ! SB_FBL_size :=
        1 + (free_blocks - 1 - (free_blocks - 1) / BLOCK_LEN) / BLOCK_LEN;

    // But if the number of free blocks is evenly divisible by 128,
    // then the above calculation will have yielded an extra block.
    if (free_blocks - 1 - (free_blocks - 1)/BLOCK_LEN) rem BLOCK_LEN = 0 then
        buffer ! SB_FBL_size -:= 1;

    // The FBL will be located from blocks 1, 2, …, SB_FBL_size,
    // meaning it will start at SB_FBL_size.
    buffer ! SB_FBL_start           := buffer ! SB_FBL_size;

    // Since the disc is just being formatted, the current window
    // will be the beginning of the FBL.
    buffer ! SB_FBL_index           := buffer ! SB_FBL_size;

    // The number of free blocks on disc is equal to the total
    // number of blocks less 1 for the super block and less the
    // size of the free block list and less 1 for the root dir.
    // The offset within the free block list will thus be the
    // number of free blocks mod 128. Subtract 1 for 0-based
    // indexing.
    buffer ! SB_FBL_index offset :=
        ((free_blocks - (buffer ! SB_FBL_size) - 2) rem BLOCK_LEN) - 1;

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
    if write_block(disc_number, SB_block_addr, buffer) <= 0 then {
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
        clear_block(buffer);

        while index < BLOCK_LEN /\ fb_block_num > fb_boundary do {
            buffer ! index := fb_block_num;
            fb_block_num -:= 1;
            index +:= 1;
        }

        if write_block(disc_number, FBL_block, buffer) <= 0 then {
            out("Unable to write free block list entry %d to disc %d!\n", FBL_block, disc_number);
            resultis -1;
        }
    }

    // Manually create the root directory.
    clear_block(buffer);

    buffer ! FH_levels          := 0;
    buffer ! FH_type            := FT_DIRECTORY;
    buffer ! FH_date_created    := seconds();
    buffer ! FH_date_accessed   := buffer ! FH_date_created;
    buffer ! FH_length          := 0;
    buffer ! FH_parent_dir      := root_dir_bn;
    buffer ! FH_current_block   := root_dir_bn;
    strcpy(buffer + FH_name, "root");

    if write_block(disc_number, root_dir_bn, buffer) <= 0 then {
        out("Unable to create root directory!\n");
        resultis -1;
    }

    // Otherwise, return 1 to indicate success.
    resultis 1;
}
