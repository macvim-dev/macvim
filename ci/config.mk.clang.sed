/^CFLAGS[[:blank:]]*=/s/$/ -Wno-error=missing-field-initializers -Wno-error=deprecated-declarations -Wno-error=unused-function/
/^RUBY_CFLAGS_EXTRA[[:blank:]]*=/s/$/ -Wno-error=unknown-attributes -Wno-error=ignored-attributes/
