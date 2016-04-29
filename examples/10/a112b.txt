
import "io"

let enable_ints(v) be
{ assembly
  { load  r1, [<v>]
    setsr r1, $intvec      // set special register
    load  r1, 0
    setfl r1, $ip          // set flag "interrupt being processed"
} }

let set_timer(t) be
{ assembly
  { load  r1, [<t>]
    setsr r1, $timer } }

let timer_handler() be
{ out("\n  Boo!\n");
  set_timer(50000000);
  ireturn }

let stop = false;          // ugly global variable, only used for this experiment

let keyboard_handler() be
{ let c, v = vec 3;
  assembly                 // see the "Advanced Hardware Operations" document,
  { load  r1, [<v>]        // pages 6 and 12 for this.
    load  r2, $terminc
    store r2, [r1+0]
    load  r2, 1
    store r2, [r1+1]
    load  r2, <c>
    store r2, [r1+2]
    peri  r2, r1 }
  out("you typed '%c' = %d\n", c, c);
  if c = 'X'-64 then stop := true;       // that's control-X
  ireturn }

let compute() be                 // all this does is compute slowly so that there
{ let x = 0;                     // is some ongoing task for the interrupts to
  for i = 0 to 1000 do           // interrupt. Please don't do this for real, use
  { out("%d\n", x);              // assembly { pause } in a small loop to idle
    if stop then break;          // instead
    for j = 1 to 500 do
    { if stop then break;
      for k = 0 to 1000 do
        x +:= 1;
      for k = 0 to 999 do
        x -:= 1 } }
  out("all done\n") }

manifest
{ iv_none = 0,        iv_memory = 1,      iv_pagefault = 2,   iv_unimpop = 3,
  iv_halt = 4,        iv_divzero = 5,     iv_unwrop = 6,      iv_timer = 7,
  iv_privop = 8,      iv_keybd = 9,       iv_badcall = 10,    iv_pagepriv = 11,
  iv_debug = 12,      iv_intrfault = 13 }

let start() be
{ let ivec = vec(20), n;

  for i = 0 to 19 do
    ivec ! i := nil;
  ivec ! iv_timer := timer_handler;
  ivec ! iv_keybd := keyboard_handler;
  
  enable_ints(ivec);
  set_timer(50000000);

  compute();

  out("What is your favourite number? ");
  n := inno();                              // this stops working of course.
  out("Yuck! %d is terrible\n", n); }


