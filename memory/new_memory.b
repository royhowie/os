import "io"

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

	// Each entry in the heap has a pointer to the list of used chunks
	// And a pointer to the list of free chunks of a specific size
	// The sizes are predetermined as 4, 8, 16, 32, ..., 65536 
	size_of_free_list = 30, // 15 lists, each with two ptrs

	used_list_offset = 0,
	free_list_offset = 1,

	free = 10101010,
	used = 01010101,

	//arbitrary max chunk
	max_chunk_size = 65536 
}

static {heap, next_free_addr}

// sets size to nearest power of two
let adjust_size(size) be {
	let new_size = size + size_of_chunk_data, current_size = 4;
	let difference = 0;

	if size > max_chunk_size then {
		out("no memory left. exiting.\n");
		finish;
	}

	while current_size <= max_chunk_size / 2 do {
		if new_size <= current_size then {
			difference = current_size - new_size;
			new_size +:= difference;
			resultis new_size;
		}	

		current_size *= 2;
	}
	resultis new_size;
}

// returns a pointer to the correct used list
let pos_in_list(size) be {
	let pos = 0, current_size = 4;
	while current_size <= max_chunk_size / 2 do {
		if size = current_size then resultis pos;

		pos +:= 2;
		current_size *:= 2;
	}

	resultis pos;
}

// allocates a new chunk on top of the heap if there are no other chunks
let new_chunk(size, index) be {
	let chunk, new_size;
	chunk := next_free_addr;

	next_free_addr +:= size;

	if heap ! index /= nil then
		heap ! index ! chunk_previous := chunk;

	chunk ! pattern := used;
	chunk ! chunk_previous := @(heap ! index); // location on heap
	chunk ! chunk_next := heap ! index; // first chunk at pos
	chunk ! chunk_size := size;

	resultis chunk;
}

let newvec(size) be {
	let index;
	size := adjust_size(size);
	index := pos_in_list(size);

	test heap ! index = 0 then 	
		heap ! index := new_chunk(size, index);
	else
		// TODO, if there is a chunk in the used list

	resultis heap ! index;
}

let init(addr) be {
	heap := addr;
	next_free_addr := heap + size_of_free_list + size_of_chunk_data;
}
