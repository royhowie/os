import "files"
import "disc"
import "strings"
import "io"
import "fs-constants"

let start () be {
    let current_disc, current_file, disc_number, data, heap = vec 10000;

    init(heap, 10000);

    while true do {
        let cmd = vec 10;
        out("> ");
        ins(cmd, 39);

        if strcmp(cmd, "format") = 0 then {
            out("disc number: ");
            disc_number := inno();
            out("enter a name: ");
            ins(cmd, 31);

            test format_disc(disc_number, cmd, true) > 0 then
                out("successfully formatted disc %d with name '%s'.\n", disc_number, cmd)
            else
                out("failed to mount disc %d with name '%s'\n", disc_number, cmd);

            loop;
        }

        if strcmp(cmd, "mount") = 0 then {
            out("disc number: ");
            disc_number := inno();
            out("name: ");
            ins(cmd, 31);

            current_disc := mount(disc_number, cmd); 
            if current_disc < 0 then {
                out("Unable to mount disc.\n");
                loop;
            }

            out("Successfully mounted disc %d with name '%s'.\n", disc_number, cmd);

            loop;
        }

        if strcmp(cmd, "dismount") = 0 then {
            if current_disc = nil then {
                out("Mount a disc first.\n");
                loop;
            }

            test dismount(current_disc) >= 0 then {
                out("Current disc dismounted.\n");
                current_disc := nil;
            } else {
                out("Unable to dismount disc.\n");
            }

            loop;
        }

        if strcmp(cmd, "ls") = 0 then {
            test current_disc = nil then
                out("Must mount a disc before attempting to print directory.\n")
            else
                ls(current_disc);

            loop;
        }

        if strcmp(cmd, "create") = 0 then {
            if current_disc = nil then {
                out("Mount a disc first!\n");
                loop;
            }

            out("file name (31 chars max): ");
            ins(cmd, 31);

            test create(current_disc, cmd, FT_FILE) > 0 then
                out("Successfully created file '%s'\n", cmd)
            else
                out("Unable to create file '%s'.\n", cmd);
             
            loop;
        }

        if strcmp(cmd, "read") = 0 then {
            let blocks_available, b = vec 128;

            if current_disc = nil then {
                out("Mount a disc first!\n");
                loop;
            }
            
            out("file to read: ");
            ins(cmd, 31);

            current_file := open(current_disc, cmd, 'r');

            if current_file = nil then {
                out("Unable to open file with name '%s' for reading.\n", cmd);
                loop;
            }

            out("-- begin file --\n");
            while not eof(current_file) do outch(read_byte(current_file));

            out("\n-- end file --\n");

            close(current_file);
            current_file := nil;
            
            loop;
        }

        if strcmp(cmd, "write") = 0 then {
            let blocks_available, holder = vec 1;

            if current_disc = nil then {
                out("Mount a disc first!\n");
                loop;
            }

            out("file to write to: ");
            ins(cmd, 31);

            current_file := open(current_disc, cmd, 'w');

            if current_file = nil then {
                out("Unable to open file with name '%s' for writing.\n", cmd);
                loop;
            }

            while true do {
                ins(holder, 1);
                if byte 0 of holder = 'X' - 64 then break;
                write_byte(current_file, byte 0 of holder);
            }

            out("\n-- finishing writing data --\n");

            close(current_file);
            current_file := nil;
            
            loop;
        }
        if strcmp(cmd, "delete") = 0 then {
            let blocks_available;

            if current_disc = nil then {
                out("Mount a disc first!\n");
                loop;
            }

            out("file to delete: ");
            ins(cmd, 11);

            test delete(current_disc, cmd) > 0 then 
                out("'%s' deleted!\n", cmd)
            else 
                out("Failed to delete '%s'!\n", cmd);
        
            loop;
        }

        if cmd %streq "exit" then finish;

        out("No command by that name!\n");

    }
}
