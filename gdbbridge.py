insert into def importPlainDumpers(args):
    gdb.execute('set var k_debugging=1')
    gdb.execute('continue')
