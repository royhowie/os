// source: http://rabbit.eng.miami.edu/class/een521/a203ba.txt
import "io"

let twotimes(x) be
{ let sptr, prev;
  if x = 0 then resultis 0;
  prev := twotimes(x-1);
  resultis prev+2 }

/* Will use pages 6, 7, and 8 for 
       the page table directory
       the page table for addresses          0000000000xxxxxxxxxxxxxxxxxxxxxx
       and the page table for the stack area 0111111111xxxxxxxxxxxxxxxxxxxxxx
   respectively. Shift page number left 11 bits to make a physical address */

let getpage() be
{ static { nextfreepage = 6 }
  let p = nextfreepage;
  nextfreepage +:= 1;
  resultis p << 11 }

let start() be
{ let pdir = getpage();
  let ptablow = getpage();
  let ptabhigh = getpage();
  let a, b;
  for i = 0 to 2047 do
  { pdir ! i := 0;
    ptablow ! i := 0;
    ptabhigh ! i := 0 }

/* page table entries: 
      bit 0 (least significant) = valid resident entry,
      bit 1 = only accessible in system mode,
      bits 2 - 10 not used,
      bits 11 - 31 = physical page number */

  pdir !   0 := ptablow bitor 1;
  pdir ! 511 := ptabhigh bitor 1;

        /* physical page 0 (addresses 000000000000000000000xxxxxxxxxxx)
           already occupied by executable code, so well put it in the
           page table for virtual page 0 */
  ptablow  !    0 := 1;

        /* physical page 1048575 (addresses 011111111111111111111xxxxxxxxxxx)
           already occupied by the stack, so well put it in the
           page table for virtual page 1048575 */
  ptabhigh ! 2047 := 0x7FFFF801;

        /* page 1048574 is the second stack page. We're going to map it
           to a totally different physical page so we know things are working */
  ptabhigh ! 2046 := getpage() bitor 1;

  out("pdir     = %x\n", pdir);
  out("pdir!  0 = %x\n", pdir ! 0);
  out("pdir!511 = %x\n", pdir ! 511);

  outs("Dangerous place\n");
  assembly
  { load   r1, [<pdir>]
    setsr  r1, $pdbr    // special register PDBR, page directory address
    getsr  r1, $flags   // spec reg FLAGS = all flag values in one word.
    sbit   r1, $vm
    flagsj r1, pc }     // jump to PC leaves PC unchanged.

  outs("still alive\n");
  a := 500;   // so this works when a is 500, but not when a is 1000
  b := twotimes(a);
  out("twotimes(%d) = %d\n", a, b) }


