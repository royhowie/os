import "io"

export {
    keyboard_handler,
    init_keyboard,
    new_inch
}

manifest {
    SIZEOF_KB_BUFF  = 99,
    KB_BUFF         = vec 25,

    KB_BUFF_START   = 0,
    KB_BUFF_END     = 1,
    KB_BUFF_NUM     = 2,
    KB_BUFF_LINES   = 3,
    SIZEOF_KB_INFO  = 4,
    KB_INFO         = vec SIZEOF_KB_INFO
}

let init_keyboard () be {
    KB_INFO ! KB_BUFF_START := 0;
    KB_INFO ! KB_BUFF_END := 0;
    KB_INFO ! KB_BUFF_NUM := 0;
    KB_INFO ! KB_BUFF_LINES := 0;
}

let kb_add (char) be {
    // If no room for an additional character in buffer, return 0.
    if KB_INFO ! KB_BUFF_NUM >= SIZEOF_KB_BUFF then
        resultis 0;

    // Cannot add backspace characters.
    if char = 8 then
        resultis 0;

    // Otherwise, add the character at position KB_BUFF_END.
    byte (KB_INFO ! KB_BUFF_END) of KB_BUFF := char;

    // If the character was a newline, inc KB_BUFF_LINES
    if char = '\n' then
        KB_INFO ! KB_BUFF_LINES +:= 1;

    // Increment the number of characters in buffer.
    KB_INFO ! KB_BUFF_NUM +:= 1;

    // Increment the end (last) character fence post.
    // Make sure it "wraps" around, since KB_BUFF is
    // a circular queue.
    // Basically, if 1 + KB_BUFF_END = 1 + SIZEOF_KB_BUFF = 100,
    // then set the end fence post to 0.
    KB_INFO ! KB_BUFF_END := (1 + KB_INFO ! KB_BUFF_END) rem (1 + SIZEOF_KB_BUFF);

    resultis 1;
}

let kb_unadd () be {
    // (size + end) mod (1 + size) == -1 + end mod 1 + size
    // This ensures new_kb_end is postive.
    let new_kb_end = (SIZEOF_KB_BUFF + (KB_INFO ! KB_BUFF_END)) rem (1 + SIZEOF_KB_BUFF);
    let char = byte new_kb_end of KB_BUFF;

    // If a newline is hit or there are no characters in the buffer,
    // cannot unadd a char.
    if char = '\n' \/ KB_INFO ! KB_BUFF_NUM  = 0 then
        resultis 0;

    KB_INFO ! KB_BUFF_END := new_kb_end;
    KB_INFO ! KB_BUFF_NUM -:= 1;

    resultis 1;
}

let kb_remove () be {
    let char;

    // If no characters are in the buffer, cannot remove a char.
    if KB_INFO ! KB_BUFF_NUM = 0 then
        resultis 0;

    // Grab the character at position (byte) KB_BUFF_START
    char := byte (KB_INFO ! KB_BUFF_START) of KB_BUFF;

    // Decrement KB_BUFF_NUM since a character was removed from the buffer.
    KB_INFO ! KB_BUFF_NUM -:= 1;

    // Increment the start fence post; make sure it wraps around.
    KB_INFO ! KB_BUFF_START := (1 + KB_INFO ! KB_BUFF_START) rem (1 + SIZEOF_KB_BUFF);

    if char = '\n' then
        KB_INFO ! KB_BUFF_LINES -:= 1;

    resultis char;
}

let keyboard_handler (int_code, int_addr, intx, PC, FP, SP) be {
    let char, v = vec 3;

    assembly {
        load        r1,     [<v>]
        load        r2,     $terminc
        store       r2,     [r1 + 0]
        load        r2,     1
        store       r2,     [r1 + 1]
        load        r2,     <char>
        store       r2,     [r1 + 2]
        peri        r2,     r1
    }

    // Handle backspace characters separately.
    test char = 8 /\ kb_unadd() then
        assembly {
            type    8
            type    ' '
            type    8
        }
    else if kb_add(char) then
        assembly {
            type    [<char>]
        }

    ireturn;
}

let new_inch () be {
    let char = 0;
    while true do {
        char := kb_remove();
        unless char = 0 do
            resultis char;
        assembly { pause }
    }
}

