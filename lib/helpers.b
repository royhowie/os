import "io"

export {
    min,
    max,
    copy_buffer,
    clear_buffer,
    check_disc,
    read_from_disc,
    write_to_disc
}

manifest { BLOCK_LEN = 128 }

let min (a, b) = a < b -> a, b;
let max (a, b) = a > b -> a, b;

let copy_buffer (source, dest, length) be for i = 0 to length - 1 do dest ! i := source ! i;
let clear_buffer (buffer, length) be for i = 0 to length - 1 do buffer ! i := 0;
let clear_block (buffer) be clear_buffer(buffer, BLOCK_LEN);

let check_disc (disc_number) be devctl(DC_DISC_CHECK, disc_number);

let read_from_disc (disc_number, block, num_blocks, buff) be {
    resultis devctl(DC_DISC_READ, disc_number, block, num_blocks, buff);
}

let write_to_disc (disc_number, offset, num_blocks, buff) be {
    resultis devctl(DC_DISC_WRITE, disc_number, offset, num_blocks, buff);
}
