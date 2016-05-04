import "io"
import "osloader"

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
    //  1           any
    //  2           4
    //  3           8
    //  4           16
    //  5           32
    //  6           64
    //  7           128
    //  8           256
    //  9           512
    //  10          1024
    HEAP_TABLE                  = vec(11),
    SIZEOF_HEAP_TABLE           = 11,


    // Blocks of memory will be organized as follows:
    //  pos         desc
    //  -3          prev
    //  -2          next
    //  -1          size
    //   0          ptr       
    //  ...         ...
    //  size        next block in memory


}

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
        resultis 10
    else resultis largest_bit(size);
}


let newvec (size) be {
    let table_pos = get_table_pos(size);
    let index = table_pos;

    // Find a spot in the table
    until index = SIZEOF_HEAP_TABLE \/ HEAP_TABLE ! index <> nil do
        index +:= 1;

    

}

let freevec (ptr) be {

}


let init_heap () be {
    for i = 0 to 10 do
        HEAP_TABLE ! i := nil;
}
