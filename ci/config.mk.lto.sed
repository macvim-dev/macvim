# Add link-time optimization for even better performance
/^CFLAGS[[:blank:]]*=/s/$/ -flto/
/^LDFLAGS[[:blank:]]*=/s/$/ -flto/
