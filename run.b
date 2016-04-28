import "interrupts"
import "processes"
import "shell"
import "io"

let start () be {
    let heap = vec 30000;
    let shell_stack = vec 3000;

    init(heap, 30000);

    init_interrupts();
    init_processes();

    // Start the shell
    make_process(run_shell, shell_stack + 3000);

}
