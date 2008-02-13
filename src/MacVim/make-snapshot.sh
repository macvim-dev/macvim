#!/bin/sh

# Increment build number
/Developer/Tools/agvtool next-version -all > /dev/null

# Get current build number
BUILDNUM=`/Developer/Tools/agvtool what-version -terse`
DEST=~/Desktop/MacVim-snapshot-$BUILDNUM

echo '****************************************************'
echo "              BUILDING SNAPSHOT $BUILDNUM"
echo '****************************************************'
echo ''

# Build Vim binary
echo 'BUILDING VIM BINARY'
echo '    running configure...'
cd .. && ./configure --enable-gui=macvim --with-mac-arch=both \
    --with-features=huge --enable-pythoninterp --enable-tclinterp \
    --enable-cscope \
    --with-compiledby="Bjorn Winckler <bjorn.winckler@gmail.com>" > /dev/null

echo '    cleaning...'
make clean > /dev/null
echo '    calling make...'
make > /dev/null
echo '    done'

# Build MacVim.app
echo 'BUILDING MacVim.app'
cd MacVim
echo '    cleaning...'
xcodebuild -configuration Universal clean > /dev/null
echo '    calling xcodebuild...'
xcodebuild -configuration Universal > /dev/null
echo '    done'

# Create archive of build/Universal/MacVim.app
echo 'CREATING SNAPSHOT ARCHIVE'
echo '    copying MacVim.app and supporting files...'
mkdir $DEST
cp -pR build/Universal/MacVim.app $DEST/
cp -p mvim $DEST/
cp -p README-snapshot.txt $DEST/
echo '    creating archive....'
cd $DEST && cd ..
tar cjf MacVim-snapshot-$BUILDNUM.tbz MacVim-snapshot-$BUILDNUM
echo '    done'

echo 'ALL DONE'
echo 'Now update the Appcast, commit and tag, then post on vim_mac.'
# Update app-cast

# Commit & tag
# git-commit -a -m "$BUILDNUM"
# git-tag -a -F tagfile $BUILDNUM

# Post on vim_mac
