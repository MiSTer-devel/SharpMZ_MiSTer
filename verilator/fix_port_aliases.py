#!/usr/bin/env python3
"""Restore port-alias assignments that ghdl's Verilog writer drops.

Usage: fix_port_aliases.py netlist.v netlist.vhd

ghdl synth (5.1) loses "SIG <= in_port;" when SIG is a pure alias of an input
port that only feeds sub-instances: the Verilog netlist declares the wire and
connects it, but never drives it. The VHDL netlist from the same run keeps it,
as "sig <= wrap_PORT; -- (signal)" at the top level or "sig <= port; -- (signal)"
below it. For every such line whose wire has no driver in the Verilog module,
add "assign sig = PORT;" before endmodule.
"""
import re
import sys


def main(vpath, vhdpath):
    vhd = open(vhdpath).read()
    aliases = {}   # entity -> [(sig, port)]
    for m in re.finditer(r'(?ms)^architecture (\w+) of (\w+) is(.*?)^end (?:architecture|\1);', vhd):
        pairs = re.findall(r'^\s*(\w+) <= (?:wrap_)?(\w+);\s*-- \(signal\)', m.group(3), re.M)
        if pairs:
            aliases.setdefault(m.group(2).lower(), []).extend(pairs)

    src = open(vpath).read()
    chunks = re.split(r'(?m)^(?=module\s)', src)
    added = []
    for i, chunk in enumerate(chunks):
        mm = re.match(r'module\s+(\S+)', chunk)
        if not mm or mm.group(1).lower() not in aliases:
            continue
        name = mm.group(1)
        ports = {p.lower(): p for p in re.findall(r'^\s*input\s+(?:\[[^\]]*\]\s*)?(\w+)', chunk, re.M)}
        extra = []
        for sig, port in aliases[name.lower()]:
            if re.search(r'^\s*assign\s+%s\s*=' % re.escape(sig), chunk, re.M):
                continue
            if port.lower() not in ports:
                continue
            extra.append('  assign %s = %s; // restored port alias (fix_port_aliases.py)\n' % (sig, ports[port.lower()]))
            added.append('%s.%s' % (name, sig))
        if extra:
            chunks[i] = re.sub(r'(?m)^endmodule', ''.join(extra) + 'endmodule', chunk, count=1)
    open(vpath, 'w').write(''.join(chunks))
    print('fix_port_aliases: restored %d: %s' % (len(added), ', '.join(added) or '-'))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])
