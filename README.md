# Old MacVim website

This is the old branch for the MacVim website and is no longer used. Please see https://github.com/macvim-dev/macvim-dev.github.io (available as https://macvim.org) instead.

When visiting this site, there is now a meta refresh to redirect to the new location.

## Note

The file appcast/latest.xml is still in use and should not be deleted or moved. Older versions of MacVim point directly to the raw GitHub URL for that file in this branch for updates (before it was moved to point to https://macvim.org/appcast/latest.xml instead). To prevent breaking software update for people running older versions of MacVim (since they may not use the software frequently), we keep the file around for now. Also, the versions of MacVim pointing to this appcast XML file are still using Sparkle 1, and as such we should avoid adding Sparkle 2 features (e.g. beta channels) if we update the file.
