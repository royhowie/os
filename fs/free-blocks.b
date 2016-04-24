import "fs-constants"
import "helpers"
import "io"

export { get_free_block, release_block }

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
    if write_block(disc_number, index, disc_info ! disc_FBL_window) <= 0 then {
        out("Unable to save FBL window to disc!\n");
        resultis -1;
    }  

    // Clear the buffer just in case.
    clear_block(disc_info ! disc_FBL_window);

    // And read the new FBL window into memory.
    if read_block(disc_number, index - 1, disc_info ! disc_FBL_window) <= 0 then {
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
    if write_block(disc_number, index, disc_info ! disc_FBL_window) <= 0 then {
        out("Unable to write FBL window back to disc!\n");
        resultis -1;
    }

    // Clean the buffer.
    clear_block(disc_info ! disc_FBL_window);

    // Read the new FBL window into memory
    if read_block(disc_number, index + 1, disc_info ! disc_FBL_window) <= 0 then {
        out("Unable to read FBL window into memory!\n");
        resultis -1;
    }

    // Increment the index of the FBL window.
    disc_info ! disc_data ! SB_FBL_index := index + 1;
    
    // Offset within the FBL window is the beginning.
    disc_info ! disc_data ! SB_FBL_index_offset := 0;

    resultis block_number;
}
