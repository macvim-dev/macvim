#!/bin/sh
#
# This shell script passes all its arguments to the binary inside the
# MacVim.app application bundle.  If you make links to this script as view,
# gvim, etc., then it will peek at the name used to call it and set options
# appropriately.
#
# Based on a script by Wout Mertens and suggestions from Laurent Bihanic.  This
# version is the fault of Benji Fisher, 16 May 2005 (with modifications by Nico
# Weber and Bjorn Winckler, Aug 13 2007).
# First, check "All the Usual Suspects" for the location of the Vim.app bundle.
# You can short-circuit this by setting the VIM_APP_DIR environment variable
# or by un-commenting and editing the following line:
# VIM_APP_DIR=/Applications

if [ -z "$VIM_APP_DIR" ]
then
	myDir="`dirname "$0"`"
	myAppDir="$myDir/../Applications"
	for i in ~/Applications ~/Applications/vim $myDir $myDir/vim $myAppDir $myAppDir/vim /Applications /Applications/vim /Applications/Utilities /Applications/Utilities/vim; do
		if [ -x "$i/MacVim.app" ]; then
			VIM_APP_DIR="$i"
			break
		fi
	done
fi
if [ -z "$VIM_APP_DIR" ]
then
	echo "Sorry, cannot find MacVim.app.  Try setting the VIM_APP_DIR environment variable to the directory containing MacVim.app."
	exit 1
fi
binary="$VIM_APP_DIR/MacVim.app/Contents/MacOS/Vim"

# Next, peek at the name used to invoke this script, and set options
# accordingly.

name="`basename "$0"`"
gui=
opts=

# GUI mode, implies forking
case "$name" in m*|g*|rm*|rg*) gui=true ;; esac

# Restricted mode
case "$name" in r*) opts="$opts -Z";; esac

# vimdiff, view, and ex mode
case "$name" in
	*vimdiff)
		opts="$opts -dO"
		;;
	*view)
		opts="$opts -R"
		;;
	*ex)
		opts="$opts -e"
		;;
esac

# Last step:  fire up vim.
# The program should fork by default when started in GUI mode, but it does
# not; we work around this when this script is invoked as "gvim" or "rgview"
# etc., but not when it is invoked as "vim -g".
if [ "$gui" ]; then
	# Note: this isn't perfect, because any error output goes to the
	# terminal instead of the console log.
	# But if you use open instead, you will need to fully qualify the
	# path names for any filenames you specify, which is hard.
	exec "$binary" -g $opts ${1:+"$@"}
else
	exec "$binary" $opts ${1:+"$@"}
fi
