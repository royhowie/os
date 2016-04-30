import "io"

static { freepagelist, freepagelist_number }

let check_memory() be
{ let firstfreeword = ! 0x101;
  let lastexistingword = (! 0x100) - 1;
  let lastoccupiedpage = (firstfreeword - 1) / 2048;
  let nextfreepage = (firstfreeword + 2047) / 2048;
  let firstnonpage = (lastexistingword / 2048) + 1;
  let totalpages = firstnonpage;
  let pagesneededfortable = totalpages / 2048 + 1;

  freepagelist := lastexistingword - pagesneededfortable * 2048 + 1;
  freepagelist_number := 0;
  for i = nextfreepage to firstnonpage-1-pagesneededfortable do
  { freepagelist ! freepagelist_number := i;
    freepagelist_number +:= 1 }

  out("first free page = %d = 0x%x\n", pn, pn) where pn = freepagelist ! 0;
  out("last free page = %d = 0x%x\n", pn, pn) where pn = freepagelist ! (freepagelist_number - 1) }

let get_free_page() be
{ if freepagelist_number <= 0 then
  { outs("\nget_free_pn(): OUT OF MEMORY\n");
    resultis -1 }
  freepagelist_number -:= 1;
  resultis (freepagelist ! freepagelist_number) << 11 }

let make_page_free(pa) be
{ freepagelist ! freepagelist_number := pa >> 11;
  freepagelist_number +:= 1 }

let print_mem_map(pdaddr) be
{ out("pp %d:\n", pdaddr >> 11);    // pp = physical page
  for ptn = 0 to 1023 do
    if pdaddr ! ptn <> 0 then
    { let ptppn = (pdaddr ! ptn) >> 11;
      let ptaddr = ptppn << 11;
      out("  %d: pp %d for VAs 0x%x to 0x%x:\n",
             ptn,   ptppn,     ptn << 22, ((ptn+1) << 22)-1);
      for pn = 0 to 2047 do
        if ptaddr ! pn bitand 1 then
        { let pppn = (ptaddr ! pn) >> 11;
          let baseva = (ptn << 22) + (pn << 11);
          out("      %d: pp %d for VAs 0x%x to 0x%x:\n",
                     pn,    pppn,      baseva, baseva+2047); } } }

static { PCB_addr, PD_addr, OS_stack_PT, OS_code_PT, USR_stack_PT, USR_code_PT }

manifest { VALID = 1 }

let compute() be
{ let x = 0;
  for i = 0 to 15 do
  { let ch = i + 'A';
    /*
       only the compute function is going to be copied into the user address
       space, not the whole library. So we can't print things in the normal
       way. The out() at the end of this function will fail.
    */
    assembly
    { type [<ch>] }
    for j = 1 to 500 do
    { for k = 0 to 1000 do
        x +:= 1;
      for k = 0 to 999 do
        x -:= 1 } }
  out("\nall done\n") }

let run_user() be
{ outs("Jumping to 0x200\n");
  /* switch to user mode by turning off the SYS flag */
  assembly
  { getsr  r1, $flags
    cbit   r1, $sys
    setsr  r1, $flags }
  /* compute() has been copied into memory that will now appear to be at
     virtual addresses starting from 0x200, so we just jump there. */
  0x200() }

let start() be
{ let start_address, code_addr, addr;
  check_memory();
  PCB_addr := get_free_page();
  PD_addr := PCB_addr + 1024;

  OS_stack_PT := get_free_page();
  OS_code_PT := get_free_page();
  USR_stack_PT := get_free_page();
  USR_code_PT := get_free_page();

  /* clrpp = clear physical page.
     we don't want any uninitialised page table entries */
  assembly
  { clrpp [<PCB_addr>]
    clrpp [<OS_stack_PT>]
    clrpp [<OS_code_PT>]
    clrpp [<USR_stack_PT>]
    clrpp [<USR_code_PT>] }

  PD_addr ! 767 := OS_stack_PT bitor VALID;
  PD_addr ! 512 := OS_code_PT bitor VALID;
  PD_addr ! 511 := USR_stack_PT bitor VALID;
  PD_addr ! 0   := USR_code_PT bitor VALID;

  OS_stack_PT ! 2047 := get_free_page() bitor VALID;
  /* This is a small program, I know it doesn't even fill the first three pages
     (0, 1, and 2). This makes physical pages 0, 1, and 2 appear at virtual
     addresses starting from 0x80000000, making this program apear to move. */
  OS_code_PT ! 0 := 0 bitor VALID;
  OS_code_PT ! 1 := (1 << 11) bitor VALID;
  OS_code_PT ! 2 := (2 << 11) bitor VALID;

  USR_stack_PT ! 2047 := get_free_page() bitor VALID;
  code_addr := get_free_page();
  USR_code_PT ! 0 := code_addr bitor VALID;

  print_mem_map(PD_addr);

  /* Now copy the compute function into the physical page selected as the one
     and only user code page. It is offset by 0x200 just to make it stand out
     as having been moved. */
  addr := code_addr + 0x200;
  out("copying compute to %x\n", addr);
  for i = compute to run_user do
  { ! addr := ! i;
    addr +:= 1; }

  /* Now set the special register PDBR with the address of the page directory,
     then turn on VM and simultaneously jump to the virtual address for run_user */
  start_address := run_user + 0x80000000;
  assembly
  { load   r1, [<PD_addr>]
    setsr  r1, $pdbr
    getsr  r1, $flags
    sbit   r1, $vm
    load   r2, [<start_address>]
    flagsj r1, r2 }

  /* It will never say "finished program" */
  out("Finished program\n"); }
