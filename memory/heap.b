import "io"
import "osloader"
import "helpers"

export { newvec, freevec, init_heap }

manifest {
    // HEAP_TABLE will be filled with pointers to
    // lists of free blocks of memory. Index 0 will
    // be the list of used blocks. Index 1 will be
    // for free blocks of size less than 4. Otherwise,
    // index n will be for blocks of memory of size of
    // at least 2^n. Index 10 will be the last and will
    // contain a list of blocks of size of at least
    // 1024 words.
    //
    //  index       min size
    //  0           used blocks
    //  1           4
    //  2           8
    //  3           16
    //  4           32
    //  5           64
    //  6           128
    //  7           256
    //  8           512
    //  9           1024
    HEAP_TABLE                  = vec(10),
    SIZEOF_HEAP_TABLE           = 10,
    USED_ENTRIES                = 0,
    LAST_ENTRY_SIZE             = 1024,

    // Blocks of memory will be organized as follows:
    //  pos         desc
    //  -3          prev
    //  -2          next
    //  -1          size
    //   0          ptr       
    //   1          ptr + 1
    //  ...         ...
    //   n-1        last piece of data
    //   n          size of data
    HE_PREV                     = -3,
    HE_NEXT                     = -2,

    // The size will be negative if the block of memory
    // is currently free; otherwise, positive.
    HE_SIZE                     = -1,

    HE_prev_node_size           = -4,

    // A heap entry requires prev & next pointers and
    // two size pointers. In addition, there needs to be
    // room for at least one
    HE_MIN_SIZE                 = 4
}

let math_abs (num) = num < 0 -> -num, num;

let largest_bit (num) be {
    let index = -1;

    until num = 0 do {
        num := num >> 1;
        index +:= 1;
    }

    resultis index;
}

let get_table_pos (size) be {
    test size < 4 then
        resultis 1
    else test size >= 1024 then
        resultis SIZEOF_HEAP_TABLE - 1
    else resultis largest_bit(size);
}

let newvec (size) be {
    let table_pos, index;

    // Newvec must be called with only a single, positive
    // argument.
    if numbargs() < 1 \/ size < 1 then resultis nil;

    // Find the earliest position in the table at which a block
    // of memory of length `size` can be found. Copy into index
    // for later use.
    table_pos := get_table_pos(size);
    index := table_pos;

    // Beginning at index, search through the table for non-nil entry.
    until index = SIZEOF_HEAP_TABLE \/ HEAP_TABLE ! index <> nil do
        index +:= 1;

    // If the index ran past the end of the table, need to ask for
    // a new page of memory, since no block of memory large enough
    // to accomodate the request
    if index = SIZEOF_HEAP_TABLE then {
        // TODO: get new page and assign to HEAP_TABLE ! 10
        // Make sure to set it to +3 since HE_prev is -3.

        // set index back to the last position
        index := SIZEOF_HEAP_TABLE - 1;
    }

    resultis splice_from_table(index, size, index - table_pos);
}

and splice_from_table (index, size, adjustment) be {
    let ptr = HEAP_TABLE ! index;
    let size_diff = math_abs(math_abs(ptr ! HE_size) - size);
    let new_size;

    // Only need to potentially split up the entry at
    // position index if there is room for another entry
    // or if the index is the last position.
    //
    // However, if the size_diff isn't enough to accomodate a
    // new chain in the memory linked lists, then
    // just use the entire block.
    if (index = SIZEOF_HEAP_TABLE - 1 \/ adjustment > 0) /\ size_diff > HE_MIN_SIZE then {
        // Otherwise, move the pointer forward, but first
        // adjust the data.
        new_size := (ptr ! HE_size) - size - 4;

        (ptr + size + 4) ! HE_size := new_size;
        ptr ! (ptr ! HE_size) := new_size;
        (ptr + size + 4) ! HE_prev := HEAP_table ! index;
        (ptr + size + 4) ! HE_next := ptr ! HE_next;
        ptr ! HE_size := size;

        // Add he split off chunk back to the table.
        add_to_table(get_table_pos(new_size), ptr + size + 4);
    } 


    // Otherwise, can just return the first entry. Make sure
    // to adjust the linked list connect to HEAP_TABLE ! index.
    HEAP_TABLE ! index := ptr ! HE_next;
    unless ptr ! HE_next = nil do
        ptr ! HE_next ! HE_prev := HEAP_TABLE ! index;

    ptr ! HE_size := math_abs(ptr ! HE_size);

    resultis add_to_table(USED_ENTRIES, ptr);
}

and add_to_table (index, ptr) be {
    // Set ptr's next to the item in the table.
    ptr ! HE_next := HEAP_TABLE ! index;

    // If the table entry was non-nil, then set that
    // entry's previous to ptr;
    unless HEAP_TABLE ! index = nil do
        HEAP_TABLE ! index ! HE_prev := ptr;

    // Add ptr to the heap table at the appropriate index.
    HEAP_TABLE ! index := ptr;

    resultis ptr;
}

and freevec (ptr) be {
    let prev_node, next_node;
    let size = ptr ! HE_size;
    let prev_size;

    // Attempt to merge with all blocks in front of this node.
    // Will not merge with blocks behind for now because that
    // takes extra time and seems unnecessary.
    while true do {
        let prev_size = ptr ! HE_prev_node_size;

        // Negative is used to indicate that the node is free.
        if prev_size >= 0 then break;

        // Otherwise, combine the two blocks.
        //
        // Set up a pointer to the previous node
        prev_node := (ptr - 3) ! prev_size;

        // Adjust its size and store the second size pointer
        // at the end of the new, combined memory block.
        //
        // Use subtraction since the size is negative.
        prev_node ! HE_size -:= 4 + size;
        ptr ! size := prev_node ! HE_size;

        // Adjust pointers within the used block list.
        unless ptr ! HE_prev = nil do
            ptr ! HE_prev ! HE_next := ptr ! HE_next;
        unless ptr ! HE_next = nil do
            ptr ! HE_next ! HE_prev := ptr ! HE_prev;

        // Set ptr equal to prev_node so nodes can be correctly
        // recombined on the next iteration.
        ptr := prev_node;
    }

    // Check the size again.
    size := ptr ! HE_size;

    // And add to the heap table based on the new size.
    add_to_table(get_table_pos(size), ptr);
}

and init_heap () be {
    for i = 0 to 10 do
        HEAP_TABLE ! i := nil;
}
