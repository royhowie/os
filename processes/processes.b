import "io"

export {
    timer_handler,
    make_process,
    halt_handler, 
    div_zero_handler,
    init_processes
}


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
let timer_handler (int_code, int_addr, intx, PC, FP, SP) be {
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

        // Skip the idle process if there are others which can be run.
        if process_number = 0 /\ number_processes > 1 then loop;
       
        // If back at the process which was originally being processed
        // until the interrupt, i.e., `current_process`, then `break`
        // (since we can just continue running the same process).
        if process_number = current_process then break;

        // If the entry is nil, keep searching.
        if process_table ! process_number = nil then loop;

        // Otherwise, if we come across a process with its PCB_STATE
        // set to 'R' (read?), then it can be run next.
        if process_table ! process_number ! PCB_STATE = 'R' then break;
    }

    // Set a timer on how long the next process will be allowed to run.
    set_interrupt_timer(PROCESS_SWAP_TIME);

    // If there is only a single process running, there is no need
    // to swap in a new process.
    unless process_number = current_process do
       swap_processes(process_number, @int_code, PC); 

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

/*
    this function shouldn't have to be passed anything
    in the future, it should generate its own PC and SP
*/
and make_process (program_counter, stack_pointer) be {
    let process = newvec(PCB_SIZE);
    let index = 0;

    // should also check that the process table isn't filled
    until process_table ! index = nil do index +:= 1;

    // add the process to the table
    process_table ! index := process;

    // and increase the number of processes
    number_processes +:= 1;

    // just some general setup details
    process ! PCB_STACK_POINTER := stack_pointer;
    process ! PCB_FRAME_POINTER := stack_pointer;
    process ! PCB_PROGRAM_COUNTER := program_counter;

    process ! PCB_INT_CODE := 0;
    process ! PCB_INT_ADDR := 0;
    process ! PCB_INT_X := 0;

    process ! PCB_FLAGS := FLAG_R;
    process ! PCB_STATE := 'R';

    resultis index;
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
        jpos    r2,     pc - 4
        push    40
        iret
    }
}

let halt_handler (int_code, int_addr, intx, PC, FP, SP) be {
    let process_number = current_process;
    let process = process_table ! process_number;

    // 1. Remove process from table.
    process_table ! process_number := nil;

    // 2. Clean up current process.
    // NOTE: Will eventually have to clean up memory in page tables.
    freevec(process);

    // 3. Decrement number of processes.
    number_processes -:= 1;

    // 4. Exit interrupt. `timer_handler` will start a new process,
    // if one is available.
    out("Process has halted.\n");
    ireturn;
}

let div_zero_handler (int_code, int_addr, intx, PC, FP, SP) be {
    out("Division by zero!\n");
    halt_handler(int_code, int_addr, intx, PC, FP, SP);
}

let idle_process () be {
    while true do assembly { pause };
}

manifest {
    IDLE_PROCESS_STACK  = vec 32
}

let init_processes () be {
    let p_num = make_process(idle_process, IDLE_PROCESS_STACK + 32);
    start_process(p_num);
}
