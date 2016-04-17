import "io"
import "processes"
/*
    `processes.b` is needed for the following functions:
        timer_handler
        halt_handler
        div_zero_handler
        init_processes (starts the idle process)
*/
import "keyboard"
/*
    `keyboard.b` is needed for the following functions:
        keyboard_handler
        init_keyboard (sets up the keyboard buffer)
*/

export {
    init_interrupts
}

manifest {
    IV_NONE             = 0,
    IV_MEMORY           = 1,
    IV_PAGE_FAULT       = 2,
    IV_UN_IMP_OP_CODE   = 3,    // unimplemented op-code
    IV_HALT             = 4,
    IV_DIV_ZERO         = 5,
    IV_UN_WRIT_OP_CODE  = 6,    // unwritable instruction operand
    IV_TIMER            = 7,
    IV_PRIV_OP          = 8,    // privileged operation made in user mode
    IV_KEYBD            = 9,
    IV_BAD_CALL         = 10,   // bad SYSCALL index
    IV_PAGE_PRIV        = 11,   // user access to system mode page
    IV_DEBUG            = 12,   // debug trap
    IV_INTERRUPT_FAULT  = 13,   // failure to process interrupt

    interrupt_vec       = vec 14
}

// read http://rabbit.eng.miami.edu/class/een521/hardware-2a.pdf
let general_handler (int_code, int_addr, intx, PC, FP, SP) be {
    switchon interrupt_code into {
        case IV_MEMORY:         out("Physical memory access failed.\n"); break;        
        case IV_PAGE_FAULT:     out("Page fault.\n"); break;
        case IV_UN_IMP_OP_CODE: out("Unimplemented op-code.\n"); break;
        // case IV_HALT: handle specifically
        // case IV_DIV_ZERO: handle specifically 
        case IV_UN_WRIT_OP_CODE:out("Unwritable instruction operand.\n"); break;
        // case IV_TIMER: handle specifically
        case IV_PRIV_OP:        out("Privileged operation attempted by user mode program.\n"); break;
        // case IV_KEYBD: handle specifically
        case IV_BAD_CALL:       out("Bad system call index.\n"); break;
        case IV_PAGE_PRIV:      out("User mode access to system mode page.\n"); break;
        case IV_DEBUG:          out("Debug trap. Currently unimplemented.\n"); break;
        case IV_INTERRUPT_FAULT:out("Unable to process interrupt.\n"); break;
    }

    out("Fatal interrupt. Shutting down.\n");
    finish;
}

let enable_interrupts (ivec) be {
    assembly {
        load    r1,     [<ivec>]
        // set special register for interrupts
        setsr   r1,     $intvec
        load    r1,     0
        // interrupts being processed
        setfl   r1,     $ip
    }
}

let init_interrupts () be {
    interrupt_vec ! IV_NONE             := nil;
    interrupt_vec ! IV_MEMORY           := general_handler;
    interrupt_vec ! IV_PAGE_FAULT       := general_handler;
    interrupt_vec ! IV_UN_IMP_OP_CODE   := general_handler;
    interrupt_vec ! IV_HALT             := halt_hander;
    interrupt_vec ! IV_DIV_ZERO         := div_zero_handler;
    interrupt_vec ! IV_UN_WRIT_OP_CODE  := general_handler;
    interrupt_vec ! IV_TIMER            := timer_handler;
    interrupt_vec ! IV_PRIV_OP          := general_handler;
    interrupt_vec ! IV_KEYBD            := keyboard_handler;
    interrupt_vec ! IV_BAD_CALL         := general_handler;
    interrupt_vec ! IV_PAGE_PRIV        := general_handler;
    interrupt_vec ! IV_DEBUG            := general_handler;
    interrupt_vec ! IV_INTERRUPT_FAULT  := general_handler;

    // start the idle process
    init_processes();
    
    // set up the keyboard interrupt handler
    init_keyboard();

    enable_interrupts(interrupt_vec);
}
