import "io"
import "files"
import "disc"

manifest {
    sizeof_page         = 2048,
    infopage            = 0xC0000000,
    intvec_va           = 0xC0000000,
    proclist_va         = 0xC0000010,
    pgdir_va            = 0xC0000800,
    ptspec_va           = 0xC0001000,
    pgates_va           = 0xC0001800,
    proclist_max        = 32,
    proclist_max_bits   = 5,
    ifp_freelistempty   = 48,
    ifp_freelistptr     = 49,
    ifp_freelistnum     = 50,
    ifp_intvec_pa       = 51,
    ifp_curproc         = 52,
    p1_va               = 0xC0002000,
    spec_p1e            = 4,
    p2_va               = 0xC0002800,
    spec_p2e            = 5,
    p3_va               = 0xC0003000,
    spec_p3e            = 6,
    p4_va               = 0xC0003800,
    spec_p4e            = 7
}

export { infopage, intvec_va, ifp_freelistempty, ifp_freelistptr,
         ifp_freelistnum, ifp_intvec_pa, pgdir_va, ptspec_va,
         pgates_va, proclist_va, proclist_max, proclist_max_bits,
         ifp_curproc, p1_va, spec_p1e, p2_va, spec_p2e, p3_va,
         spec_p3e, p4_va, spec_p4e }

static { last_page, next_page, boundary }

let setup_memory () be {
    let first_word = ! 0x101;
    let last_word = (! 0x100) - 1;

    // >> 11 is the same as dividing by 2048
    last_page := (first_word - 1) >> 11;
    next_page := (first_word + 2047) >> 11;
    boundary := (last_word >> 11) + 1;
}

let get_page () be {
    let page = next_page;

    // update the page index
    next_page +:= 1;

    // out of memory, so exit
    if next_page > boundary then finish;

    resultis page;
}

let load_os (os_name) be {
    let pgdir, ptcode, ptstack, ptspec, freelist, page, pinfopage, r, n, avail, pos, addr, pgates;
    let disc_info = mount(1, "test");
    let FILE = open(disc_info, os_name, 'r');

    if FILE = nil then {
        out("Could not load os.\n");
        finish;
    }

    pgdir := get_page() << 11;
    ptcode := get_page() << 11;
    ptstack := get_page() << 11;
    ptspec := get_page() << 11;
    pgates := get_page() << 11;

    assembly {
        clrpp   [<pgdir>]
        clrpp   [<ptcode>]
        clrpp   [<ptstack>]
        clrpp   [<ptspec>]
        clrpp   [<pgates>]
        load    r1,     [<pgates>]
        setsr   r1,     $cgbr
    }

    pgdir ! 0x200 := ptcode bitor 1;
    pgdir ! 0x2FF := ptstack bitor 1;
    pgdir ! 0x300 := ptspec bitor 1;
    ptstack ! 2047 := (get_page() << 11) bitor 1;
    page := get_page() << 11;
    ptcode ! 0 := page bitor 1;
    pinfopage := get_page() << 11;
    pinfopage ! ifp_intvec_pa := pinfopage;
    ptspec ! 0 := pinfopage bitor 1;
    ptspec ! 1 := pgdir bitor 1;
    ptspec ! 2 := ptspec bitor 1;
    ptspec ! 3 := pgates bitor 1;


    // n = number of pages required to hold free page list
    n := (boundary + 2047) / 2048;

    for i = n-1 to 0 by -1 do {
        freelist := get_page() << 11;
        ptspec ! (2047 - i) := freelist bitor 1;
    }
    
    freelist +:= 2048;
    
    n := 0;
    avail := 8;
    pos := 1;
    addr := page + 0x400;

    until eof(FILE) do {
        for i = 0 to 127 do {
            let v = vec 1;
            let index = 0;
            until eof(FILE) \/ index = 4 do
                byte index of v := read_byte(FILE);
            ! addr := ! v;
            addr +:= 1;
        }

        avail -:= 1;

        if avail = 0 then {
            page := get_page() << 11;
            ptcode ! pos := page bitor 1;
            pos +:= 1;
            addr := page;
            avail := 16;
        }
    }

    n := 0;

    for i = boundary-1 to next_page by -1 do { freelist -:= 1;
        ! freelist := i;
        n +:= 1
    }

    for i = last_page to 1 by -1 do {
        freelist -:= 1;
        ! freelist := i;
        n +:= 1;
    }

    pinfopage ! ifp_freelistptr := 0xC0400000 - n;
    pinfopage ! ifp_freelistnum := n;
    resultis pgdir
}

let start () be {
    let page_dir;

    setup_memory();

    page_dir := load_os("run.exe");
  
    assembly {
        load   r1,  [<page_dir>]
        load   sp,  0x0000
        loadh  sp,  0xC000
        load   fp,  sp
        setsr  r1,  $pdbr
        getsr  r1,  $flags
        sbit   r1,  $vm
        load   r2,  0x0400
        loadh  r2,  0x8000
        flagsj r1,  r2
    }
}
