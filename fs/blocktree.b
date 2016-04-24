import "io"
import "free-blocks"
import "fs-constants"
import "helpers"

export {
    block_tree_init,
    block_tree_advance,
    block_tree_get,
    block_tree_set,
    block_tree_rewind,
    block_tree_save,
}

let block_tree_init (FILE, file_header) be {
    // Grab the levels in this file from the header.
    let levels = file_header ! FH_levels;

    // The block tree has 2 entries per level
    // and will follow the pattern:
    //  0:  buffer_level_0
    //  1:  offset within buffer_level_0
    //  2:  buffer_level_1
    //  3:  offset within buffer_level_1
    //  ...
    let block_tree = newvec(2 * levels + 2);

    // Add the block_tree pointer to the file
    FILE ! FT_block_tree := block_tree;

    // The top of the tree is the header block. It is much easier
    // to enter the first level manually, as its offset is not 0
    // but FH_first_word, since it is stored in the file header.
    block_tree ! 0 := newvec(BLOCK_LEN);

    // Clear the buffer just in case.
    clear_block(block_tree ! 0);

    // Copy the file header into the block tree.
    copy_block(file_header, block_tree ! 0);

    // Allocate block-length buffers (128 words) for the rest of
    // the levels in the tree. 
    for i = 1 to levels do
        block_tree ! (2 * i) := newvec(BLOCK_LEN);

    // The block_tree_rewind method can then be used to initialize
    // the rest of the block tree.
    resultis block_tree_rewind(FILE);
}

and block_tree_advance (FILE, writing) be {
    let block_tree = FILE ! FT_block_tree;
    let levels = block_tree ! 0 ! FH_levels;
    let level_reached;
    let new_block_tree, new_buffer, free_block;

    let recurse_up (FILE, level, max_level, writing) be {
        let block_tree = FILE ! FT_block_tree;
        let buff = block_tree ! (2 * level);
        let offset_ptr = block_tree + 2 * level + 1;
        let block_num, prev_buff, prev_offset;

        // Increment the offset.
        ! offset_ptr +:= 1;

        // If on level 0, cannot recurse any higher, so return 0
        // to indicate the highest level was reached.
        if level = 0 then resultis 0;

        // If on a leaf block, only need to recurse when the offset
        // is 512 or more. Otherwise, only need to recurse_up if
        // the offset is 128. That is, if level = max_level and
        // offset >= 512 OR level < max_level and offset >= 128.
        // This can be slightly simplifed to:
        if (level < max_level /\ ! offset_ptr >= BLOCK_LEN)
        \/ (! offset_ptr >= 4 * BLOCK_LEN) then {
            // If writing, need to write the current block to disc.
            if writing then {
                // But first need to find where the current block is
                // to be written. This is done by looking up the tree.
                //
                // For example, if level = 2, then block_tree might look
                // like this:
                //      0:  buff0           = [...]
                //      1:  buff0_offset    = 20
                //      2:  buff1           = [...]     <-- prev buff
                //      3:  buff1_offset    = 115       <-- prev offset
                //      4:  buff2           = [...]     <-- current buff
                //      5:  buff2_offset    = 128       <-- current offset
                // so prev_buff is block_tree[2], or at position
                // 2 * level - 2 = 2.
                // and prev_offset is at position 2 * level - 1 = 3
                // or block_tree[3].
                //
                // The block_number of the current buffer can thus be found
                // at prev_buff ! prev_offset.
                //
                // No need for guard clauses since recurse_up will never
                // be run on level 0.
                prev_buff := block_tree ! (2 * level - 2);
                prev_offset := block_tree ! (2 * level - 1);
                block_num := prev_level ! prev_offset;

                write_block(FILE ! FT_disc_number, block_num, buff);
            }

            // Then move up the tree to determine whether the next level
            // needs to be read from disc back into memory.
            resultis recurse_up(FILE, level - 1, max_level, writing);
        }

        // Otherwise, return the level recurse_up reached.
        resultis level;
    }

    let recurse_down (FILE, level, max_level, writing) be {
        let block_tree = FILE ! FT_block_tree;
        let buff = block_tree ! (2 * level);
        let offset = block_tree ! (2 * level + 1);
        let next_block;

        // If the bottom of the tree has been hit, return,
        // as there is nothing left to do.
        if level = max_level then resultis level;

        // Clear the next level's buffer (important to do now
        // since the block tree depends on 0s).
        clear_block(block_tree ! (2 * level + 2);

        // Find the next block from the disc to be read into
        // the block tree.
        next_block := buff ! offset;

        // If the next block to read in is 0, then there is
        // nothing left in the tree. If writing to the tree,
        // can just add blocks. If reading, however, the file
        // has nothing left, so return the level reached.
        if next_block = 0 then {
            test writing then {
                // Ask for a free block.
                next_block := get_free_block(FILE ! FT_disc_info);

                // Record it in the current level of the  block tree.
                buff ! offset := next_block;

                // Set the next level's offset to 0 (since its block
                // is just now being created).
                block_tree ! (2 * level + 3) := 0;

                // And write a blank block (all zeros) for the next
                // level in the block tree back to disc.
                // This is important, as explained above, since the
                // block tree depends on 0s to know when it has hit
                // the last data point within a block.
                write_block(
                    FILE ! FT_disc_number,
                    next_block,
                    block_tree ! (2 * level + 2)
                );

                // Don't want to read a blank block that we just wrote to
                // disc back, so recurse from here instead of below.
                resultis recurse_down(FILE, level + 1, max_levels, writing);

            // Nothing left, so return the current level, to be used below
            // to recognize the file has hit EOF.
            } else {
                resultis level;
            }
        }

        // Read in the next block. Clear old buffer just in case.
        read_block(
            FILE ! FT_disc_number,
            next_block,
            block_tree ! (2 * level + 2)
        );

        resultis recurse_down(FILE, level + 1, max_levels, writing);
    }

    level_reached := recurse_up(FILE, levels, levels, writing);

    // If level 0 was reached and the end of level 0 has been reached
    // i.e. if levels_in_tree = 1 and offset = 512
    //      OR levels_in_tree > 1 and offset = 128
    if level_reached = 0 /\ (
        (block_tree ! 1 = 4 * BLOCK_LEN) \/
        (block_tree ! 1 = BLOCK_LEN /\ levels = 0)
    ) then {
        // If writing, need to expand the block tree
        test writing then {
            // Increment the number of levels in the tree and record
            // in the header block.
            levels +:= 1;
            block_tree ! 0 ! FH_levels := levels;

            // Create a new block_tree of size 2 * levels + 2
            new_block_tree := newvec(2 * levels + 2);

            // Copy the old block_tree into the new block tree
            // starting at index 2. Note that the old block tree
            // is 2 * levels words long.
            copy_buffer(block_tree, new_block_tree + 2, levels * 2);

            // Move the header block back to position 0.
            new_block_tree ! 0 = new_block_tree ! 2;

            // Set its offset to the first word available in the
            // header block.
            new_block_tree ! 1 = FH_first_word;

            // Next, move the block pointers which are located in the
            // header block to their own block on disc.
            // Do this by copying everything in the file header from
            // FH_first_word onwards into a new buffer.
            new_buffer := newvec(BLOCK_LEN);
            // Cleanse the buffer just in case.
            clear_buffer(new_buffer, BLOCK_LEN);
            copy_buffer(
                (new_block_tree ! 0) + FH_first_word,
                new_buffer,
                BLOCK_LEN - FH_first_word + 1
            );

            // Store this new buffer in the block tree.
            new_block_tree ! 3 := new_buffer;

            // If the tree has data in level 1, then the offset for the next
            // level needs to be recorded in bytes.
            test levels = 1 then
                new_block_tree ! 4 := 4 * (BLOCK_LEN - FH_first_word + 1) + 1;
            // Otherwise, just record the offset based on words.
            else
                new_block_tree ! 4 := BLOCK_LEN - FH_first_word + 1;

            // Cleanse the rest of the header block.
            clear_buffer(
                (new_block_tree ! 0) + FH_first_word,
                BLOCK_LEN - FH_first_word + 1
            );

            // Request a free block on disc.
            free_block := get_free_block(FILE ! FT_disc_info);
            
            // Store this in the file header block.
            new_block_tree ! 0 ! FH_first_word := free_block;
            
            // Write the new buffer back to disc at location free_block.
            write_block(FILE ! FT_disc_number, free_block, new_buffer);

            // Make sure to now use the new block_tree
            FILE ! FT_block_tree := new_block_tree;

            // And free the old block_tree.
            freevec(block_tree);

            // Get rid of the old pointer just in case.
            block_tree := new_block_tree;

        // Otherwise, there is nothing left to read in the file,
        // so mark is as fully read.
        } else {
            FILE ! FT_file_is_EOF := true;
            return;
        }
    }

    level_reached := recurse_down(FILE, level_reached, levels, writing);

    // If not writing and the file couldn't reach the bottom of the tree,
    // then there is nothing left to read, so mark the file as EOF.
    if level_reached < levels /\ not writing then
        FILE ! FT_file_is_EOF := true;
}

and block_tree_get (FILE) be {
    let block_tree = FILE ! FT_block_tree;
    let levels = block_tree ! 0 ! FH_levels;
    let buff = block_tree ! (2 * levels);
    let offset = block_tree ! (2 * levels + 1);

    resultis byte offset of buff;
}

and block_tree_set (FILE, data) be {
    let block_tree = FILE ! FT_block_tree;
    let levels = block_tree ! 0 ! FH_levels;
    let buff = block_tree ! (2 * levels);
    let offset = block_tree ! (2 * levels + 1);

    byte offset of buff := data;
}

and block_tree_rewind (FILE) be {
    let block_tree = FILE ! FT_block_tree;
    let levels = block_tree ! 0 ! FH_levels;

    // Reset the offset of the first level buffer. If working
    // with a 0-level block tree, then set the offset in terms
    // of bytes; otherwise, set it in terms of words.
    test levels = 0 then
        block_tree ! 1 := 4 * FH_first_word;
    else
        block_tree ! 1 := FH_first_word;

    // Set up the rest of the block tree. This is a naturally
    // recursive process, but it ends up being just as easy to
    // do it iteratively.
    //
    // The idea is to first read in a block. If it is not a leaf
    // block, i.e., if it is not actual data, then use the first
    // available offset  to read another block in, i.e., look at
    // the first word to find the block number of the next level
    // in the tree.
    //
    // Start at level 1 because the header block does not need
    // to be read into memory again.
    for i = 1 to levels - 1 do {
        // Grab the previous entry's buffer and offset, which are
        // needed to find the next block in the tree.
        let prev_index = 2 * i - 2;
        let prev_buff = block_tree ! prev_index;
        let prev_offset = block_tree ! (prev_index + 1);

        // Clear the block's buffer just in case.
        clear_block(block_tree ! (2 * i));

        // And set the buffer offset to 0 since every buffer
        // except level 0 (the header) will start at 0.
        block_tree ! (2 * i + 1) := 0;

        // The block number of the next step in the block tree
        // is record at prev_entry_buff ! prev_entry_offset,
        // so copy it into the current buffer.
        if read_block(
            FILE ! FT_disc_number,
            prev_buff ! prev_offset,
            block_tree ! (2 * i)
        ) <= 0 then resultis -1;
    }

    resultis 1;
}

and block_tree_save (FILE, zero_last_block) be {
    let block_tree = FILE ! FT_block_tree;
    let levels = block_tree ! 0 ! FH_levels;
    // Should the last block be zeroed out (almost always a
    // yes).
    let option = numbargs() >= 2 -> zero_last_block, false;
    
    // In saving the block tree back to disc, the idea will
    // be to grab the block_number from the level above and
    // use it to write the current level's buffer back to disc.
    // However, because the file header block (block_tree ! 0)
    // is the highest level, its block number needs to be grabbed
    // in a different manner from all the others. Hence,
    // initialize block_number to the block stored in the file's
    // header block.
    let block_number = block_tree ! 0 ! FH_current_block;

    for index = 0 to levels do {
        let cur_buff = block_tree ! (2 * index);
        let cur_offset = block_tree ! (2 * index + 1);

        // If option to zero out the last block (i.e., the leaf
        // block) is set and on the last level (i.e., if
        // index = levels), then zero out the rest of the buffer.
        if option /\ index = levels then {
            for j = cur_offset to 4 * BLOCK_LEN - 1 do
                byte j of cur_buff := 0;
        }

        // Write the buffer at level `index` back to disc.
        write_block(FILE ! FT_disc_number, block_number, cur_buff);

        // And store the block number of the next level's buffer.
        block_number := cur_buff ! cur_offset;
    }
}

