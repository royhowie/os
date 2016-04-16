import "io"

export { strcmp, streq, strcpy, strncpy, strdup, strcat, strncat, ins, fixed_to_str, str_to_fixed }

let strcmp (str1, str2) be {
    let index = 0;

    until (byte index of str1 = 0) \/ (byte index of str2 = 0) do {
        unless byte index of str1 = byte index of str2 do 
            resultis (byte index of str1) - (byte index of str2);
        index +:= 1;
    }

    test byte index of str1 = 0 then
        test byte index of str2 = 0 then
            resultis 0          // str1 = str2
        else resultis -1        // str1 is a substring of str2
    else resultis 1;            // str2 is a substring of str1
}

let streq (str1, str2) be {
    resultis strcmp(str1, str2) == 0;
}

/*
    copies a string from source to dest
    expects source to be null-terminated
    returns the memory location of dest
*/
let strcpy (dest, source) be {
    let index = 0;

    until byte index of source = 0 do {
        byte index of dest := byte index of source;
        index +:= 1;
    }

    byte index of dest := 0;

    resultis dest;
}

let strncpy (destination, source, n) be {
    let index = 0;
  
    until index = n do {
        byte index of destination := byte index of source;
        index +:= 1;
    }

    if n = strlen(source) + 1 then
        byte index of destination := 0; 

    resultis destination;
}

let strdup (source) be {
    let start = newvec((1 + strlen(source)) / 4);
    let index = 0;

    until byte index of source = 0 do {
        byte index of start := byte index of source;
        index +:= 1;
    }

    byte index of start := 0;

    resultis start;
}

let strcat (dest, source) be {
    let len = strlen(dest);
    let index = 0;

    until byte index of source = 0 do {
        byte (len + index) of dest := byte index of source;
        index +:= 1;
    }

    byte (len + index) of dest := 0;

    resultis dest;
}

let strncat(destination, source, n) be {
  let len = strlen(destination);
  let index = 0;

  until index = n do
  {
    byte len of destination := byte index of source;
    index +:= 1;
    len +:= 1;
  }

  if n = strlen(source) + 1 then byte len of destination := 0;
  resultis destination;
}

let inch_unbuff () be {
    assembly {
        inch R1
        jpos R1, PC+2
        pause
        jump PC-4
    }
}

let ins (A, size) be {
    let index = 0, char;

    while index < size do {
        char := inch_unbuff();

        // if a DEL (127) is read, transform it to a backspace (8)
        if char = 127 then char := 8;

        outch(char);

        // if backspace or delete, move back a character
        // output a space, move back a character again
        if char = 8 then {
            test index > 0 then index -:= 1 else loop;
            // can't backspace if at index 0
            outch(' ');
            outch(8);
            loop;
        }

        // if new-line encountered, terminate string
        if char = '\n' then char := 0;

        // add character to array A
        byte index of A := char;

        // if null terminator encountered, stop looping
        if char = 0 then break;

        index +:= 1;
    }

    resultis A;
}

let fixed_to_str (A, size, S) be {
    for index = 0 to size do {
        byte index of S := byte index of A;
    }
    byte size of S := 0;

    resultis S;
}

let str_to_fixed (S, A, size) be {
    let index = 0;

    until index >= size \/ byte index of S = 0 do {
        byte index of A := byte index of S;
        index +:= 1;
    }

    if index < size then byte index of A := 0;

    resultis A;
}
