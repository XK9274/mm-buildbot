# Miyoo tcpdump

This bundle contains `bin/tcpdump` and its private shared dependency
`lib/libpcap.so.1`, both cross-built with the Union Miyoo toolchain. The
binary uses an `$ORIGIN/../lib` runtime search path, so copy both directories
together and invoke `bin/tcpdump` directly.

Packet capture generally requires root privileges and can increase CPU use.
Use a capture filter and write captures to SD storage when collecting more than
a brief diagnostic sample.
