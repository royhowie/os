import "io"

export {
    min,
    max,
    math_abs,
    copy_buffer,
    copy_block,
    clear_buffer,
    clear_block,
    check_disc,
    read_from_disc,
    read_block,
    write_to_disc,
    write_block,
    tape_load,
    tape_unload,
    tape_read
}

manifest { BLOCK_LEN = 128 }

let min (a, b) = a < b -> a, b;
let max (a, b) = a > b -> a, b;

let math_abs (num) = num < 0 -> -num, num;

let copy_buffer (source, dest, length) be for i = 0 to length - 1 do dest ! i := source ! i;
let copy_block (source, dest) be copy_buffer(source, dest, BLOCK_LEN);

let clear_buffer (buffer, length) be for i = 0 to length - 1 do buffer ! i := 0;
let clear_block (buffer) be clear_buffer(buffer, BLOCK_LEN);

let check_disc (disc_number) = devctl(DC_DISC_CHECK, disc_number);

let read_from_disc (disc_number, block, num_blocks, buff) be {
    resultis devctl(DC_DISC_READ, disc_number, block, num_blocks, buff);
}
let read_block (disc_number, block, buff) = read_from_disc(disc_number, block, 1, buff);

let write_to_disc (disc_number, block, num_blocks, buff) be {
    resultis devctl(DC_DISC_WRITE, disc_number, block, num_blocks, buff);
}
let write_block (disc_number, block, buff) = write_to_disc(disc_number, block, 1, buff);

let tape_load (tape_num, file_name, mode) = devctl(DC_TAPE_LOAD, tape_num, file_name, mode);
let tape_unload (tape_num) = devctl(DC_TAPE_UNLOAD, tape_num);
let tape_read (tape_num, buff) = devctl(DC_TAPE_READ, tape_num, buff);
