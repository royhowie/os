import "files"
import "disc"
import "strings"
import "io"
import "fs-constants"
import "parser"

static {
    command_format      = "format disc_number disc_name",
    command_mount       = "mount disc_number disc_name",
    command_touch       = "touch file_name",
    command_read        = "read file_name",
    command_write       = "write file_name",
    command_delete      = "delete file_name"
}


let start () be {
    let heap = vec 10000;
    let args = vec 10;
    let ret;
    let current_disc = nil, current_file = nil;

    init(heap, 10000);

    while true do {
        let cmd = vec 25;
        outs("> ");
        ins(cmd, 99);

        test cmd %str_begins_with "help" \/ cmd %str_begins_with "?" then {
            outs("The following commands are available:\n");
            out("  %s\n", command_format);
            out("  %s\n", command_mount);
            out("  %s\n", command_touch);
            out("  %s\n", command_read);
            out("  %s\n", command_write);
            out("  %s\n", command_delete);
        } else test cmd %str_begins_with "format" then {
            ret := parse(cmd, "sds", args);

            if ret = -1 then {
                error_msg("format", command_format);
                loop;
            }

            out("%s disc %d with name '%s'.\n",
                (format_disc(args ! 1, args ! 2, true) < 0 ->
                    "Unable to format", "Successfully formatted"),
                args ! 1,
                args ! 2
            );

            freevec(ret);
        } else test cmd %str_begins_with "mount" then {
            unless current_disc = nil do {
                outs("Dismount current disc first!\n");
                loop;
            }

            ret := parse(cmd, "sds", args);

            if ret = -1 then {
                error_msg("mount", command_mount);
                loop;
            }

            current_disc := mount(args ! 1, args ! 2);

            out("%s disc %d with name '%s'.\n",
                (current_disc < 0 ->
                "Unable to mount", "Successfully mounted"),
                args ! 1,
                args ! 2
            );

            freevec(ret);
        } else test cmd %str_begins_with "dismount" then {
            if current_disc = nil then {
                outs("Must mount a disc first!\n");
                loop;
            }

            test dismount(current_disc) < 0 then {
                outs("Unable to dismount disc.\n");
            } else {
                outs("Current disc dismounted.\n");
                current_disc := nil;
            }
        } else test cmd %str_begins_with "ls" then {
            test current_disc = nil then
                outs("Must mount a disc first!\n")
            else
                ls(current_disc);
        } else test cmd %str_begins_with "touch" then {
            if current_disc = nil then {
                outs("Must mount a disc first");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("touch", command_touch);
                loop;
            }

            out("%s file '%s'.\n",
                (create(current_disc, args ! 1, FT_FILE) < 0 ->
                    "Unable to create", "Created"),
                args ! 1
            );

            freevec(ret);
        } else test cmd %str_begins_with "read" then {
            if current_disc = nil then {
                outs("Mount a disc first!\n");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("read", command_read);
                loop;
            }

            current_file := open(current_disc, args ! 1, FT_READ);

            test current_file = nil then {
                out("Unable to open file '%s' for reading.\n", args ! 1);
            } else {
                outs("--- begin ---\n");
                until eof(current_file) do
                    outch(read_byte(current_file));
                outs("\n--- end ---\n");

                close(current_file);
                current_file := nil;
            }

            freevec(ret);
        } else test cmd %str_begins_with "write" then {
            if current_disc = nil then {
                outs("Mount a disc first!\n");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("write", command_write);
                loop;
            }

            current_file := open(current_disc, args ! 1, FT_WRITE);

            test current_file = nil then {
                out("Unable to open file '%s' for writing.\n", args ! 1);
            } else {
                let holder = vec 1;
                while true do {
                    ins(holder, 1);
                    if byte 0 of holder = 'X' - 64 then break;
                    write_byte(current_file, byte 0 of holder);
                }
                outs("\n--- end ---\n");
                close(current_file);
                current_file := nil;
            }

            freevec(ret);
        } else test cmd %str_begins_with "delete" then {
            if current_disc = nil then {
                outs("Mount a disc first!\n");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("delete", command_delete);
                loop;
            }

            test delete(current_disc, args ! 1) < 0 then
                out("Unable to delete '%s'.\n", args ! 1)
            else
                out("'%s' deleted.\n", args ! 1);

            freevec(ret);
        } else test cmd %str_begins_with "exit" \/ cmd %str_begins_with "logout" then
            finish
        else out("Unknown command: '%s'!\n", cmd);
    }
}

and error_msg(cmd_name, cmd_help) be {
    out("Incorrect usage of %s: '%s'\n", cmd_name, cmd_help);
}
