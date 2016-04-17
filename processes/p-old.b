import "io"

manifest {
    PROCESS_SWAP_TIME   = 500000
}

// flag constants
manifest {
    FLAG_R              = 1,
    FLAG_Z              = 2,
    FLAG_N              = 4,
    FLAG_ERR            = 8,
    FLAG_SYS            = 16,
    FLAG_IP             = 32,
    FLAG_VM             = 64
}

// process flags
manifest {
    PCB_FLAGS           = 0,
    PCB_INT_CODE        = 1,
    PCB_INT_ADDR        = 2,
    PCB_INT_X           = 3,
    PCB_PROGRAM_COUNTER = 4,
    PCB_FRAME_POINTER   = 5,
    PCB_STACK_POINTER   = 6,
    PCB_R12             = 7,
    PCB_R11             = 8,
    PCB_R10             = 9,
    PCB_R9              = 10,
    PCB_R8              = 11,
    PCB_R7              = 12,
    PCB_R6              = 13,
    PCB_R5              = 14,
    PCB_R4              = 15,
    PCB_R3              = 16,
    PCB_R2              = 17,
    PCB_R1              = 18,
    PCB_R0              = 19,
    PCB_STATE           = 20,
    
    PCB_SIZE            = 21
}

// interrupt constants
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
    IV_INTERRUPT_FAULT  = 13    // failure to process interrupt
}


static {
    current_process     = 0;
    number_processes    = 0;
    process_table       = vec 64
}
/*
    This method is called when a timer interrupt is set off.
    The goal is to allow processes somewhat equal access to
    the CPU.
*/
let timer_handler (interrupt_code, interrupt_addr, intx,
    program_counter, frame_pointer, stack_pointer,
    r12, r11, r10, r9, r8, r7, r6, r5, r4, r3, r2, r1, r0) be {

    // NOTE:
    // It is VERY important that this function reach
    // `set_interrupt_timer` after the while loop.
    // Otherwise, a process will be allowed an indefinite
    // amount of time on the CPU.

    let process_number = current_process;
    
    // Find the next process to let run. If there are no processes,
    // we (obviously) don't need to do any looping.
    while number_processes > 0 do {
        // Loop through every process. If the end if reached, return to zero.
        process_number := (process_number + 1) rem number_processes;
       
        // If back at the process which was originally being processed
        // until the interrupt, i.e., `current_process`, then `break`
        // (since we can just continue running the same process).
        if process_number = current_process then
            break;

        // Otherwise, if we come across a process with its PCB_STATE
        // set to 'R' (read?), then it can be run next.
        if process_table ! process_number ! PCB_STATE = 'R' then
            break;
    }

    // Set a timer on how long the next process will be allowed to run.
    set_interrupt_timer(PROCESS_SWAP_TIME);

    // If there is only a single process running, there is no need
    // to swap in a new process.
    unless process_number = current_process do
       swap_processes(process_number, @interrupt_code, program_counter); 

    ireturn;
}

/*
    Set the timer special register to `time`, which
    will eventually cause a timed interrupt.
*/
and set_interrupt_timer (time) be {
    assembly {
        load    r1, [<time>]
        setsr   r1, $timer
    }
}

and enable_interrupts (interrupt_vector) be {
    assembly {
        load    r1,     [<interrupt_vector>]

        // set special register for interrupts
        setsr   r1,     $intvec
        load    r1,     0

        // interrupts being processed
        setfl   r1,     $ip
    }
}


and swap_processes (process_number, interrupt_code_addr, pc) be {
    let process = process_table ! current_process;
    let ptr = interrupt_code_addr - 1;

    // Swap out the process which was running until the interrupt (?)
    assembly {
        load        r1,         [<process>]
        load        r2,         [<ptr>]
        load        r3,         19
        load        r4,         [r2]
        store       r4,         [r1]
        inc         r1
        inc         r2
        dec         r3
        jpos        r3,         pc - 6
    }

    // Update the current process number.
    current_process := process_number;

    // Grab the next process to process.
    process := process_table ! current_process;

    // Reset `ptr` (because the assembly changed it?)
    ptr := interrupt_code_addr - 1;

    // Swap in the next process to be run.
    assembly {
        load        r1,         [<process>]
        load        r2,         [<ptr>]
        load        r3,         19
        load        r4,         [r1]
        store       r4,         [r2]
        inc         r1
        inc         r2
        dec         r3
        jpos        r3,         pc - 6
    }
}

and make_process (process, program_counter, stack_pointer, code) be {
    // Set each register for the process to register position * code
    for i = PCB_R12 to PCB_R0 do
        process ! i := (PCB_R0 - i) * code;

    process ! PCB_STACK_POINTER := stack_pointer;
    process ! PCB_FRAME_POINTER := stack_pointer;
    process ! PCB_PROGRAM_COUNTER := program_counter;

    process ! PCB_INT_CODE := 0;
    process ! PCB_INT_ADDR := 0;
    process ! PCB_INT_X := 0;

    process ! PCB_FLAGS := FLAG_R;
    process ! PCB_STATE := 'R';
}

and start_process (process_number) be {
    let process = process_table ! process_number;
    let stack_pointer = process ! PCB_STACK_POINTER;
    let frame_pointer = process ! PCB_FRAME_POINTER;

    current_process := process_number;

    assembly {
        load    r1,     [<stack_pointer>]
        setsr   r1,     $usrsp
        load    r1,     [<frame_pointer>]
        setsr   r1,     $usrfp
        load    r1,     [<process>]
        add     r1,     <PCB_R0>
        load    r2,     19
        push    [r1]
        dec     r1
        dec     r2
        jpos    r2,     pc-4
        push    40
        iret
    }
}



let compute_1 () be {
    let x = 0;
    for i = 0 to 5 do {
        out("1(%d) ", x);
        for j = 0 to 500 do {
            for k = 0 to 1000 do
                x +:= 1;
            for k = 0 to 999 do
                x -:= 1;
        }
    }
    out("\n all done with compute 1!\n");
}

let compute_2 () be {
    let x = -1;
    for i = 0 to 5 do {
        out("2(%d) ", x);
        for j = 0 to 500 do {
            for k = 0 to 1000 do
                x -:= 1;
            for k = 0 to 999 do
                x +:= 1;
        }
    }
    out("\n all done with compute 2!\n");
}

manifest {
    USER_STACK_SIZE     = 1000
}

let start () be {
    let interrupt_vec = vec 20;
    let user_stack_1 = vec USER_STACK_SIZE;
    let user_stack_2 = vec USER_STACK_SIZE;

    let process1 = vec PCB_SIZE;
    let process2 = vec PCB_SIZE;

    // process_table ! 0 := nil;
    process_table ! 0 := process1;
    process_table ! 1 := process2;
    number_processes := 2;

    make_process(process1, compute_1, user_stack_1 + USER_STACK_SIZE, 1);
    make_process(process2, compute_2, user_stack_2 + USER_STACK_SIZE, 1010101);

    interrupt_vec ! IV_TIMER := timer_handler;
    
    enable_interrupts(interrupt_vec);

    set_interrupt_timer(PROCESS_SWAP_TIME);
    
    start_process(1);

    out("\nDo we ever get here?\n");    // probably not
}

