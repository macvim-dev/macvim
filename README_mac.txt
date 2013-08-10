README_mac.txt for version 7.4 of Vim: Vi IMproved.

This file explains the installation of MacVim.
See "README.txt" for general information about Vim.
See "src/MacVim/README" for an overview of the MacVim specific source code.

MacVim uses the usual configure/make steps to build the binary but instead of
"make install" you just drag the app bundle into the directory you wish to
install in (usually `/Applications').


How to build and install
========================

Run `./configure` in the `src/` directory with the flags you want (call
`./configure --help` to see a list of flags) e.g.:

    $ cd src
    $ ./configure --with-features=huge \
                  --enable-rubyinterp \
                  --enable-pythoninterp \
                  --enable-perlinterp \
                  --enable-cscope

Now build the project using `make`:

    $ make

The resulting app bundle will reside under `MacVim/build/Release`.  To try it
out quickly, type:

    $ open MacVim/build/Release/MacVim.app

To install MacVim, type

    $ open MacVim/build/Release

and drag the MacVim icon into your `Applications` folder.
