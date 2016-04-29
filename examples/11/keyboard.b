
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

let stop = false;

let kbbuff = vec(25),
    kbbs = 0, kbbe = 0, kbbn = 0, kbbmax = 99, kbblines = 0;

let kbbadd(c) be
{ if kbbn >= kbbmax then resultis 0;
  byte kbbe of kbbuff := c;
  if c = '\n' then kbblines +:= 1;
  kbbn +:= 1;
  kbbe +:= 1;
  if kbbe > kbbmax then kbbe := 0;
  resultis 1 }

let kbbunadd() be
{ let newkbbe = kbbe - 1, c;
  if newkbbe < 0 then newkbbe := kbbmax;
  c := byte newkbbe of kbbuff;
  if c = '\n' \/ kbbn = 0 then resultis 0;
  kbbe := newkbbe;
  kbbn -:= 1;
  resultis 1 }

let kbbremove() be
{ let c;
  if kbblines = 0 then resultis 0;
  c := byte kbbs of kbbuff;
  kbbn -:= 1;
  kbbs +:= 1;
  if kbbs > kbbmax then kbbs := 0;
  if c = '\n' then kbblines -:= 1;
  resultis c }

let kbbackch() be
{ let c;
  if kbbn >= kbbmax + 1 then return;
  kbbs -:= 1;
  if kbbs < 0 then kbbs := kbbmax;
  kbbn +:= 1;
  c := byte kbbs of kbbuff;
  if c = '\n' then kbblines +:= 1 }

let minch() be
{ let c = 0;
  while true do
  { c := kbbremove();
    if c <> 0 then
      resultis c;
    assembly { pause } } }

let keyboard_handler() be
{ let c, v = vec 3;
  assembly
  { load  r1, [<v>]
    load  r2, $terminc
    store r2, [r1+0]
    load  r2, 1
    store r2, [r1+1]
    load  r2, <c>
    store r2, [r1+2]
    peri  r2, r1 }
  test c = 'H'-64 then
  { if kbbunadd() then
      assembly
      { type 8
        type ' '
        type 8 } }
  else test c = 'X'-64 then 
    stop := true
  else
  { if kbbadd(c) then
      assembly
      { type [<c>] } }
  ireturn }

let compute() be
{ let x = 0;
  for i = 0 to 1000 do
  { out("%d ", x);
    if stop then break;
    for j = 1 to 500 do
    { if stop then break;
      for k = 0 to 1000 do
        x +:= 1;
      for k = 0 to 999 do
        x -:= 1 } }
  out("\nall done\n") }

manifest
{ iv_none = 0,        iv_memory = 1,      iv_pagefault = 2,   iv_unimpop = 3,
  iv_halt = 4,        iv_divzero = 5,     iv_unwrop = 6,      iv_timer = 7,
  iv_privop = 8,      iv_keybd = 9,       iv_badcall = 10,    iv_pagepriv = 11,
  iv_debug = 12,      iv_intrfault = 13 }

let start() be
{ let ivec = vec(20), n;
  let user_stack = vec(2000);

  for i = 0 to 19 do
    ivec ! i := nil;
  ivec ! iv_timer := timer_handler;
  ivec ! iv_keybd := keyboard_handler;
  
  enable_ints(ivec);
  inch := minch;
  set_timer(50000000);

  compute();

  out("What is your favourite number? ");
  n := inno();
  out("Yuck! %d is terrible\n", n); }


