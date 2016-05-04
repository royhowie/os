import "interrupts"
import "processes"
import "shell"
import "io"

let start () be {
    let heap = vec 10000;
    let shell_stack = vec 3000;

    init(heap, 10000);

    // Start the shell
    make_idle_process();
    make_process(run_shell, shell_stack + 3000);

    init_interrupts();
    init_processes();
}
