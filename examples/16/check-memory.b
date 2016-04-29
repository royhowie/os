import "io"

static { freepagelist, freepagelist_number }

let check_memory() be
{ /* the emulator leaves certain information in certain memory locations
     just before starting your program.
     0x100: the number of words of contiguously existing memory
     0x101: the address of the word following the last one that was
            loaded from the executable */
  let firstfreeword = ! 0x101;
  let lastexistingword = (! 0x100) - 1;
  let lastoccupiedpage = (firstfreeword - 1) / 2048;
  let nextfreepage = (firstfreeword + 2047) / 2048;
  let firstnonpage = (lastexistingword / 2048) + 1;
  let totalpages = firstnonpage;
  let pagesneededfortable = totalpages / 2048 + 1;

  /* the last few pages will be sacrificed to store the list of
     free page numbers. For the usual setup, there are only 512
     pages in all, so less than one whole page is needed to store
     all their numbers */

  freepagelist := lastexistingword - pagesneededfortable * 2048 + 1;

  freepagelist_number := 0;
  out("The free page list:\n");
  for i = nextfreepage to firstnonpage - 1 - pagesneededfortable do
  { freepagelist ! freepagelist_number := i;
    out("  %x: %d\n", freepagelist + freepagelist_number, i);
    freepagelist_number +:= 1 }

  out("first free page = %d = 0x%x\n", pn, pn) where pn = freepagelist ! 0;
  out("last free page = %d = 0x%x\n", pn, pn) where pn = freepagelist ! (freepagelist_number - 1) }

let get_free_pn() be
{ if freepagelist_number <= 0 then
  { outs("\nget_free_pn(): OUT OF MEMORY\n");
    resultis -1 }
  freepagelist_number -:= 1;
  resultis freepagelist ! freepagelist_number }

let make_pn_free(pn) be
{ freepagelist ! freepagelist_number := pn;
  freepagelist_number +:= 1 }

let start() be
{ check_memory(); }


