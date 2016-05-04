import "io"

// each chunk of size n has the following setup:
// chunk_size
// user word n
// user word n-1
// ...
// user word 0 (location which newvec returns)
// chunk_size
// chunk_next
// chunk_previous
// chunk_pattern (to say whether or not the chunk is used)

manifest {

	// ***************** Chunk Indices *******************
	// a pattern to denote whether the chunk is used or not
	chunk_pattern = -4,

	// the previous pointer
	chunk_previous = -3,

	// the next pointer
	chunk_next = -2,

	// the size of the chunk
	chunk_size = -1,

	// ******************* Sizes **********************
	// number of indices for the chunk
	size_of_chunk_data = 4,

	// added to the heap to create a new chunk
	size_of_offset = 5, 

	// index of the end of the previous chunk
	size_of_previous_offset = -5,

	// Each entry in the heap has a pointer to the list of free chunks of a specific size
	// The sizes are predetermined as 4, 8, 16, 32, ..., 65536 
	size_of_free_list = 15, // 15 lists, each with two ptrs

	free = 101010,
	used = 010101,

	//arbitrary max chunk
	max_chunk_size = 65536 
}

static {heap, heap_size, next_free_addr}

let is_free(chunk) be resultis chunk ! chunk_pattern;
let clear_words(chunk, i, j) be for k = i to j - 1 do chunk ! k := 0;

// sets size to nearest power of two
let adjust_size(size) be {
	let new_size = size + size_of_chunk_data, current_size = 4;
	//let difference = 0;

	if size > max_chunk_size then {
		out("no memory left. exiting.\n");
		finish;
	}

	// for a chunk of size zero, there is only one size pointer
	if new_size <> current_size then new_size +:= 1;

	while current_size <= max_chunk_size / 2 do {
		if new_size <= current_size then {
			//difference = current_size - new_size;
			//new_size +:= difference;

			new_size := current_size;
			resultis new_size;
		}	

		current_size *:= 2;
	}

	resultis new_size;
}

// returns a pointer to the correct free list
let pos_in_list(size) be {
	let pos = 0, current_size = 4;
	while current_size <= max_chunk_size / 2 do {
		if size <= current_size then resultis pos;

		pos +:= 1;
		current_size *:= 2;
	}

	resultis pos;
}

// allocates a new chunk on top of the heap if there are no other chunks in the free lists
let new_chunk(size) be {
	let chunk, prev_chunk, offset = 0, size_offset;

	chunk := next_free_addr;
	heap_size -:= size;
	if heap_size <= 0 then {
		out("the heap is full. please free some memory.\n");
		finish;	
	}

    next_free_addr +:= size;

	// if it's the first chunk
	if chunk ! size_of_previous_offset = nil then {
		chunk ! chunk_previous := nil;
		chunk ! chunk_next := nil;
		chunk ! chunk_pattern := used;
		chunk ! chunk_size := size;
		if size > 4 then size_offset := size + size_of_previous_offset;
		chunk ! size_offset := size;
		
		resultis chunk;
	}
	
	// move the pointer down till the size index of the previous chunk
	prev_chunk := chunk + size_of_previous_offset; 
	test size > 4 then {
		// offset to move the pointer down to the 0th word of the previous chunk
		size_offset := (chunk ! size_of_previous_offset) + size_of_previous_offset; // to move the pointer to the "0th" location of the chunk
		prev_chunk -:= size_offset;
	}

	else test size = 4 then prev_chunk ! (chunk_next + 1) := chunk // newvec(0) case
	else out("Error size is < 4\n"); // we shouldn't reach this

	chunk ! chunk_pattern := used;
	chunk ! chunk_previous := prev_chunk;
	chunk ! chunk_next := nil; // chunk at the top of the heap
	chunk ! chunk_size := size;
	chunk ! (size + size_of_previous_offset) := size; // size index on top of the chunk

	prev_chunk ! chunk_next := chunk;
	
	resultis chunk;
}

/*
let get_free_chunk_from_free_list(free_list, pos) be {
	//let size_of_free_chunk = free_list ! chunk_size;

	// To take out the chunk from the free list we have to change the 
	// next and previous pointers of the chunk we are removing and 
	// the pointers in the used list for the chunk we're adding
	

}

let find_free_chunk(size, pos) be {
	let free_list = heap ! pos;

	until free_list = nil do {
		if free_list ! chunk_size >= size then {
			resultis get_free_chunk_from_free_list(free_list, pos);
		}

		free_list := free_list ! chunk_next;
	}
}
*/

let newvec2(size) be {
	let pos = 0, chunk;

	size := adjust_size(size);	
	chunk := new_chunk(size);

	//TODO: get chunk from corresponding size free list

	resultis chunk;
}

let freevec2(chunk) be {
	let next_chunk, prev_chunk, size;
	let is_recombined = false;

	//let next_chunk = chunk ! chunk_next;
	//let prev_chunk = chunk ! chunk_previous;

	if is_free(chunk) = free then {
		out("chunk is already free\n");
		return;
	}

	chunk ! chunk_pattern := free;

	//out("prev chunk 0x%x and prev chunk size %d\n", prev_chunk, prev_chunk ! chunk_size);

	size := chunk ! chunk_size;
	chunk := recombine_free_chunks(chunk, size);

	if size <> chunk ! chunk_size then {
		is_recombined := true;
		size := chunk ! chunk_size;
	} 
	
	//out("After recombine, chunk at 0x%x\n", chunk);		
	//prev_chunk := chunk ! chunk_previous;
	//next_chunk := chunk ! chunk_next;
	
	next_chunk := chunk + size;
    prev_chunk := chunk + size_of_previous_offset;
    prev_chunk -:= ((! prev_chunk) + size_of_previous_offset);

	if next_chunk <> nil /\ prev_chunk <> nil then {
		if next_chunk ! chunk_pattern = used then next_chunk ! chunk_previous := prev_chunk;
    	if prev_chunk ! chunk_pattern = used then prev_chunk ! chunk_next := next_chunk;
	}

	add_chunk_to_free_list(chunk, size, is_recombined);
}

and recombine_free_chunks(chunk, size) be {
	// prev and next chunks next to the chunk on the heap
	let next_chunk = chunk + size;
    let prev_chunk = chunk + size_of_previous_offset;
	prev_chunk -:= ((! prev_chunk) + size_of_previous_offset); 

	//out("Entered recombine\n");
	//out("chunk 0x%x\t prev chunk 0x%x\t next chunk 0x%x\n", chunk, prev_chunk, next_chunk);
	
	if is_free(next_chunk) = free then {
		let new_size = size + next_chunk ! chunk_size;
		
		//out("recombining chunk and next chunk\n");
		//out("newsize is %d\n", new_size);

		next_chunk ! ((next_chunk ! chunk_size) + size_of_previous_offset) := new_size;
		chunk ! chunk_size := new_size;
		size := new_size;
		
		//chunk ! chunk_next := next_chunk ! chunk_next;
		//clear_words(chunk, 0, size - size_of_chunk_data - 1);
	}

	if is_free(prev_chunk) = free then {
        let new_size = size + prev_chunk ! chunk_size;
    	
		//out("recombining chunk and prev	chunk\n");
    	//out("newsize is	%d\n", new_size);

        prev_chunk ! chunk_size := new_size;
		chunk ! (size + size_of_previous_offset) := new_size;
		size := new_size;
		
		//prev_chunk ! chunk_next := chunk ! chunk_next;
		
		chunk := prev_chunk;
        //clear_words(chunk, 0, size - size_of_chunk_data - 1);
	}

	resultis chunk;
}

and add_chunk_to_free_list(chunk, size, is_recombined) be {
	let pos = pos_in_list(size);
	let previous_ptr = @(heap ! pos); // location on heap
	let next_ptr = heap ! pos; // first free chunk

	/*
	// if the free list has a free chunk
	if next_ptr <> nil then 
		next_ptr ! chunk_previous := chunk;

	chunk ! chunk_previous := @(heap ! pos); // the previous is set to the heap
	chunk ! chunk_next := heap ! pos; // the next is set to the first free chunk or nil
	heap ! pos := chunk; 
	*/

	//out("chunk 0x%x\t chunk next 0x%x\t chunk prev 0x%x\n", chunk, chunk ! chunk_next, chunk ! chunk_previous);

	// if the chunk has been recombined, part of the chunk is in a smaller free list
	// this code block removes the chunk from the old free list
	if is_recombined = true then {
		for i = pos - 1 to 0 by -1 do {
			let temp_ptr = heap ! i;

			unless temp_ptr = nil do {
				if temp_ptr >= chunk - size_of_chunk_data /\ 
					temp_ptr <= chunk + (size + size_of_previous_offset) then {
					//out("temp ptr 0x%x\n", temp_ptr);	
					//out("temp ptr prev 0x%x\n", temp_ptr ! chunk_previous);
					//out("heap ! i 0x%x\n", heap ! i); 

					test temp_ptr ! chunk_previous = @(heap ! i) then heap ! i := temp_ptr ! chunk_next
					else (temp_ptr ! chunk_previous) ! chunk_next := temp_ptr ! chunk_next;
					
					if temp_ptr ! chunk_next <> nil then 
						(temp_ptr ! chunk_next) ! chunk_previous := temp_ptr ! chunk_previous;
				}

				temp_ptr := temp_ptr ! chunk_next;
			}
		}
	
		if next_ptr <> nil then
        	next_ptr ! chunk_previous := chunk;

		chunk ! chunk_previous := @(heap ! pos); // the previous is set to the heap
    	chunk ! chunk_next := heap ! pos; // the next is set to the first free chunk or nil
    	heap ! pos := chunk;

	    //out("chunk 0x%x\t chunk next 0x%x\t chunk prev 0x%x\n", chunk, chunk ! chunk_next, chunk ! chunk_previous);

		clear_words(chunk, 0, size - size_of_chunk_data - 1);
	}
}

let init2(addr, size) be {
	heap := addr;
	next_free_addr := heap + size_of_free_list + size_of_chunk_data;
	heap_size := size;
}

let printChunk(chunk) be {
	let size = chunk ! chunk_size;
	let start = -size_of_chunk_data;	
	size +:= start;

	for i = start to size - 1 do {
        out("0x%x -- ", @(chunk ! i));
		test chunk ! i <= 10000 then out("%d", chunk ! i) //If there is data at the heap index
		else out("0x%x", chunk ! i); //if there are addresses stored
		outs("\n");
	} 

	outs("\n\n");
}

let printHeap(heap) be {
    for i = 0 to 60 do {
        out("0x%x -- ", @(heap ! i));
        test heap ! i <= 10000 then out("%d", heap ! i) //If there is data at the heap index
        else out("0x%x", heap ! i); //if there are addresses stored
        outs("\n")
    }
  
    outs("\n\n");
}

let start() be {
	let heap = vec 10000;
	let a, b, c, d;

	init2(heap, 10000);
	a := newvec2(1);
	//printChunk(a);

	b := newvec2(2);
	//printChunk(b);

	c := newvec2(2);
	//printChunk(c);
	
	d := newvec2(1);

	freevec2(c);
	freevec2(b);
	freevec2(d);
	
	printHeap(heap);
