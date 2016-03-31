import "io"
import "memory"

let print (str, var, size) be {
    out("%s\t%d\t\t%d\n", str, var rem 10000, size);
}

let start () be {
    let heap = vec 1000;
    let a, b, c, d, e;

    init2(heap, 1000);

    out("name\tlocation\tsize\n");

    a := newvec2(10);
    b := newvec2(10);
    c := newvec2(20);    
    d := newvec2(20);
    e := newvec2(30);

    print("a", a, 10);
    print("b", b, 10);
    print("c", c, 20);
    print("d", d, 20);
    print("e", e, 30);

    freevec2(b);
    freevec2(c);
    freevec2(d);

    b := newvec2(20);
    
    out("b should now be where c was\n");
    print("b", b, 20);

    c := newvec2(4);
    out("c should now be where b was\n");
    print("c", c, 4);

    d := newvec2(4);

    out("d should fall between c and b\n");
    print("d", d, 4);

    out("and this should cause the program to exit:\n");
    while true do {
        a := newvec2(100);
        print("a", a, 100);
    }
}
