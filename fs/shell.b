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
    command_delete      = "rm file_name",
    command_mkdir       = "mkdir dir_name",
    command_cd          = "cd dir_name"
}


let start () be {
    let heap = vec 10000;
    let args = vec 10;
    let ret;
    let current_disc = nil, current_file = nil;

    init(heap, 10000);

    outs("? for help\n");

    while true do {
        let cmd = vec 25;
        outs("> ");
        ins(cmd, 99);

        test cmd %str_begins_with "help" \/ cmd %str_begins_with "?" then {
            outs("The following commands are available:\n");
            out("  %30s - format a disc\n", command_format);
            out("  %30s - mount a disc's file system\n", command_mount);
            out("  %30s - create a file\n", command_touch);
            out("  %30s - read the contents of a file\n", command_read);
            out("  %30s - write to a file\n", command_write);
            out("  %30s - delete a file or directory\n", command_delete);
            out("  %30s - create a directory\n", command_mkdir);
            out("  %30s - change directories\n", command_cd);
            out("  ? or help to display this message\n");
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

            if create(current_disc, args ! 1, FT_FILE) < 0 then
                out("Unable to create file '%s'.\n", args ! 1);

            freevec(ret);
        } else test cmd %str_begins_with "mkdir" then {
            if current_disc = nil then {
                outs("Must mount a disc first");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("mkdir", command_mkdir);
                loop;
            }

            if create(current_disc, args ! 1, FT_DIRECTORY) < 0 then
                out("Unable to create directory '%s'.\n", args ! 1);

            freevec(ret);
        } else test cmd %str_begins_with "cd" then {
            if current_disc = nil then {
                outs("Mount a disc first!\n");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("cd", command_cd);
                loop;
            }

            current_file := open(current_disc, args ! 1, FT_BOTH);

            test current_file = nil then {
                out("Could not find '%s' in current directory.\n", args ! 1);
            } else if current_file ! FT_block_tree ! 0 ! FH_type <> FT_DIRECTORY then {
                out("'%s' is not a directory.\n");
                close(current_file);
            }

            current_file := nil;

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
                out("Unable to read '%s'.\n", args ! 1);
            } else test current_file ! FT_block_tree ! 0 ! FH_type = FT_DIRECTORY then {
                outs("Use `ls` to read directories.\n");
                open(current_disc, "../", FT_BOTH);
                current_file := nil;
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
        } else test cmd %str_begins_with "rm" then {
            if current_disc = nil then {
                outs("Mount a disc first!\n");
                loop;
            }

            ret := parse(cmd, "ss", args);

            if ret = -1 then {
                error_msg("rm", command_delete);
                loop;
            }

            if delete(current_disc, args ! 1) < 0 then
                out("Unable to delete '%s'.\n", args ! 1);

            freevec(ret);
        } else test cmd %str_begins_with "exit" \/ cmd %str_begins_with "logout" then
            finish
        else test strlen(cmd) = 0 then
            loop
        else out("Unknown command: '%s'!\n", cmd);
    }
}

and error_msg (cmd_name, cmd_help) be {
    out("Incorrect usage of %s: '%s'\n", cmd_name, cmd_help);
}
