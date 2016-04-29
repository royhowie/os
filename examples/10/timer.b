
import "io"

let timer_handler() be
{ out("\n  Boo!\n");
  ireturn }

let compute() be
{ let x = 0;
  for i = 0 to 1000 do
  { out("%d\n", x);
    for j = 1 to 500 do
    { for k = 0 to 1000 do
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
{ let ivec = vec(20);

  for i = 0 to 19 do
    ivec ! i := nil;
  ivec ! iv_timer := timer_handler;
  
  assembly
  { load  r1, [<ivec>]
    setsr r1, $intvec      // set special register
    load  r1, 0
    setfl r1, $ip          // set flag "interrupt being processed"
    load  r1, 50000000L
    loadh r1, 50000000H
    setsr r1, $timer }

  compute() }


