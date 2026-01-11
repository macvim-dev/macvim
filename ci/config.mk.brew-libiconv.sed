# Use Homebrew GNU libiconv to work around broken Apple iconv. Use static
# linking as we don't want our binary releases to pull in third-party
# dependencies.
#
# If gettext is configured in the build, it also needs to be built against GNU
# libiconv. Otherwise we would get a link error from this.
/^CFLAGS[[:blank:]]*=/s/$/ -I\/opt\/homebrew\/opt\/libiconv\/include/
/^LIBS[[:blank:]]*=/s/-liconv/\/opt\/homebrew\/opt\/libiconv\/lib\/libiconv.a/
