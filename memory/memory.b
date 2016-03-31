import "io"

export { init2, newvec2, freevec2 }

let HEAP_MAX_SIZE = 0, HEAP_USED = 0, HEAP_MEMORY, HEAP_FREE, HEAP_DELTA = 4;

let getNextMemLoc (size) be {
    let ptr = HEAP_FREE, lastptr = HEAP_FREE;

    if size + HEAP_USED + 1 > HEAP_MAX_SIZE then {
        out("no memory left. exiting.\n");
        finish;
    }
        
    until ptr ! 0 = nil \/ ptr ! -1 >= size do {
        lastptr := ptr;
        ptr := ptr ! 0;
    }

    resultis lastptr; 
}

let newvec2 (words) be {
    let prevLoc = getNextMemLoc(words), nextLoc, size;

    // if prevLoc = nil, free memory is at the "top" of the heap
    if prevLoc ! 0 = nil then {
        prevLoc ! -1 := words;
        HEAP_FREE := prevLoc + words + 1;
        HEAP_USED +:= words + 1;
        resultis prevLoc
    }

    // nextLoc is the memory location held by previous location
    nextLoc := prevLoc ! 0;
    
    // size is the value sitting right before the beginning of the next
    // location of free memory
    size := nextLoc ! -1;

    // if the difference between the requested and available memory
    // is more than delta (that is, at least 4 free words would be
    // left unused), then split the block and add it to the list
    // of free memory locations
    // otherwise, leave the 3 free words to be used for later 
    test size - words >= HEAP_DELTA then {
        // set the size of this block of memory
        nextLoc ! -1 := words;

        // move the pointer to the next free memory location to
        // its new location, nextLoc + words + 1
        nextLoc ! (words + 1) := nextLoc ! 0;

        // set the length of the next block of free memory
        nextLoc ! words := size - words - 1;

        // set prevLoc, which held the memory location currently being
        // put into use, to the next available spot, which is
        // nextLoc + words + 1
        prevLoc ! 0 := nextLoc + words + 1;
    } else {
        prevLoc ! 0 := nextLoc ! 0;
    }

    // increase the amount of "used" bytes by the requested space
    // plus the additional word used to store the size
    HEAP_USED +:= words + 1;
    
    resultis nextLoc;
}

let freevec2 (ptr) be {
    // decrease the amount of bytes in use by the size + 1
    HEAP_USED -:= (ptr ! -1) + 1;
    
    // the first memory location points to the next free
    // memory location, i.e., `free` 
    ptr ! 0 := HEAP_FREE;

    // `ptr` is now the first free memory location
    HEAP_FREE := ptr;
}

let init2 (heap, size) be {
    HEAP_MAX_SIZE := size; 
    HEAP_USED := 0;
    HEAP_MEMORY := heap;
    HEAP_FREE := HEAP_MEMORY + 1;

    resultis HEAP_MEMORY;
}
