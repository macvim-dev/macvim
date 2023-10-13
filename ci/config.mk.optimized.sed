# Add link-time optimization for even better performance
/^CFLAGS[[:blank:]]*=/s/-O2/-O3 -flto/
/^LDFLAGS[[:blank:]]*=/s/$/ -flto/
