import "strings"
import "io"

export { parse }

let parse (command, format, buffer) be {
    let max_length = strlen(command);
    let f_len = strlen(format);
    let holder = newvec(max_length + 4 * f_len);
    let command_offset = 0, holder_offset = 0;
    let ret;

    for index = 0 to f_len - 1 do {
        switchon byte index of format into {
            case 'S': case 's':
                ret := parse_word(command, command_offset, max_length, holder + holder_offset);

                // Unable to find a word, so cleanup and exit.
                if ret = -1 then goto parse_error_cleanup;

                // Otherwise, parseWord was successful and returned the
                // position of the next ' ' character in command. This
                // will be the next location in `command` we begin searching
                // for data, so set command_offset equal to ret.
                command_offset := ret;

                // We want to store a pointer to the string just parsed,
                // so set buffer ! index equal to holder + holder_offset.
                buffer ! index := holder + holder_offset;

                // Since buffer contains pointers to strings within holder,
                // those strings need to begin at multiples of 4, i.e., they
                // need to start at the beginning of a word.
                // Since ret returned the length of the word found, holder_offset
                // needs to be moved to the next multiple of 4. For example,
                // if the string to be parsed was "format 1 test", ret would be
                // 6 after "format" is parsed. This, holder looks like this:
                //      f o r m a t 0 - - - -
                //      0 1 2 3 4 5 6 7 8 9 10
                // so holder_offset needs to be moved to 8.
                //
                // This is equivalent to adding 4 * (ret / 4 + 1) to holder_offset.
                holder_offset +:= 4 * (ret / 4 + 1);

                // Loop instead of endcase. See explanation above other cases.
                loop;

            // Attempt to parse a number in a certain base.
            //
            // These cases are bundled together because they were all so similar.
            // It was "more efficient" to record the base of the number being
            // parsed and then continue.
            //
            // Since the end of the S case loops instead of jumping to the end
            // of the switch, it is safe for these cases to simply continue to
            // the end of the for loop. 
            case 'D': case 'd': ret := 10; endcase;
            case 'X': case 'x': ret := 16; endcase;
            case 'O': case 'o': ret := 8; endcase;
            case 'B': case 'b': ret := 2; endcase;

            // Bad format option given, so cleanup and exit.
            default: goto parse_error_cleanup;
        }

        // This is the fall-through from the non-string and non-default cases.
        // `ret` has been set to the correct base at this point, so use it to
        // parse the next digit.
        ret := parse_number(command, command_offset, max_length, ret, buffer + index);

        // Unable to parse number in given base. Cleanup and exit.
        if ret = -1 then goto parse_error_cleanup;

        // Update the position within the string.
        command_offset := ret;
    }

    resultis holder;

    parse_error_cleanup:
        freevec(holder);
        resultis -1;
}

// Determines whether a character is allowed to be within a number
// for a given base.
and valid_char (char, base) be {
    // If dealing with bases 1 through 10, then only 0 through
    // 9 are valid ASCII codes.
    test base < 11 /\ '0' <= char <= '9' - 10 + base then
        resultis true
    // Otherwise, if working in bases 11 through 36,
    else resultis
        // 0 through 9 are always valid.
        '0' <= char <= '9'
        // Furthermore, letters are also valid in greater bases.
        // Note: A represents 10 and Z represents 35 (in base 36).
        // So, e.g., if working in base 16, then A through F
        // are valid, since 'Z' - 36 + 16 = 'Z' - 20 = 'F'.
        // This formula makes intuitive sense since it sets the
        // upper bound to a distance of 36 less the base from
        // the letter 'Z'.
        // Another upper bound would be 'A' + base - 11.
        \/ 'A' <= char <= 'Z' - 36 + base
        \/ 'a' <= char <= 'z' - 36 + base;
}

and parse_number (str, offset, max_offset, base, loc_ptr) be {
    let is_negative = false;
    let num = 0;
    let char = byte offset of str;

    // Can only handle bases 1 through 36.
    unless 1 <= base <= 36 do resultis num;

    // Move forward through the string until either the
    // end of the string, a valid character is found,
    // or a plus or minus is found. 
    until offset = max_offset
        \/ valid_char(char, base)
        \/ char = '-'
        \/ char = '+'
    do {
        offset +:= 1;
        char := byte offset of str;
    }

    // If offset is the max_offset, then there's nothing
    // left to parse, so return -1 to indicate that a
    // a number was not found while parsing.
    if offset = max_offset then resultis -1;

    // Handle - and + signs. Make sure to advance the string
    // afterwards, since these characters will mess up the
    // calculation of the number's value.
    if char = '-' \/ char = '+' then {
        is_negative := char = '-';
        offset +:= 1;
        char := byte offset of str;
    }

    // Read characters until the end of the string or until
    // an invalid character is found.
    until offset = max_offset \/ not valid_char(char, base) do {
        // Multiply the current value of num by the base.
        // This makes sense. For example, if reading in "123"
        // in base 10, then num would be
        //      offset  char    pre-num     post-num 
        //      0       1       0           0
        //      1       2       1           10
        //      2       3       12          120
        // Then, at the end of the loop, the last character would
        // be added to the total.
        num := num * base;

        // a-z have higher ASCII codes than A-Z, which in turn
        // have higher ASCII codes than 0-9, so attempt to
        // calculate the next digit from the top down.
        //
        // 'a' is 97 in ASCII and will be used for any base
        // greater than 10 and will represent 10. 'b' will
        // represent 11, and so on. Thus, the next digit will
        // be the distance from `char` in ASCII and 'a' plus 10.
        test 'a' <= char then
            num +:= char - 'a' + 10
        // Same as above, but with capital letters.
        else test 'A' <= char then
            num +:= char - 'A' + 10
        // Otherwise, the next digit is the distance from '0'.
        else
            num +:= char - '0';

        // Increment offset and grab the next character.
        offset +:= 1;
        char := byte offset of str;
    }

    // Store the result. Make sure to account for negative numbers.
    ! loc_ptr := is_negative -> -1 * num, num;

    // Return the position within the string reached while
    // parsing the current number.
    resultis offset;
}

and parse_word (str, offset, max_offset, loc_ptr) be {
    let index = 0;

    // Move forward until a non-space character is found.
    until offset = max_offset \/ byte offset of str <> ' ' do
        offset +:= 1;

    // If offset = max_offset, then nothing was found, so
    // return -1 to indicate a mistake.
    if offset = max_offset then resultis -1;

    // Copy characters from loc_ptr onwards until a space
    // is found.
    until offset = max_offset \/ byte offset of str = ' ' do {
        byte index of loc_ptr := byte offset of str;
        index +:= 1;
        offset +:= 1;
    } 

    // Cap the string with a null pointer.
    byte index of loc_ptr := 0;

    // Return the length of the word found.
    resultis offset;
}

