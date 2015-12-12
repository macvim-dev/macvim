## !! UPDATE !!

Hi all. I'm afriad I don't have time to maintain this project any more. I see the issues mounting but I don't have time to answer them. This was a pet project some time ago and I still use the plugin daily and it works just fine for me in it's current form. If anyone would like to step forward and be added a contributor to move it forward, please send me a message.

Duncan

## Reinforcement have arrived :-)

I have volunteered to bring Duncan's excellent QL plugin a bit more up to date. Don't expect to much though. I will focus on backlogged pull requests to begin with.

Tomas

# QuicklookStephen

QLStephen is a QuickLook plugin that lets you view plain text files without a file extension. Files like:

    README
    INSTALL
    Capfile
    CHANGELOG
    etc...

## Installation


### Pre-compiled

* [Download the latest version of QuickLookStephen](https://github.com/whomwah/qlstephen/releases)
* Unzip
* Copy the file into `/Library/QuickLook` or `~/Library/QuickLook`
  (You can create the `QuickLook` folder if it doesn’t exist)


### Manually Compiled

Compliling the project yourself? Just copy the generated `QLStephen.qlgenerator`
file into the relevant `QuickLook` folder (as above).


## Trouble?

If you’ve installed the plugin, but don’t see any changes:

- Make sure you are editing (a) the correct plist of (b) the correct bundle.
  (For example, you might have two `QLStephen` plugins. It’s possible the plugin in
   another directory—perhaps `/Library/QuickLook/`—is what is being read.)
- Run `qlmanage -r` in the Terminal. (This will restart QuickLook, which reloads all plugins.)


## Why “QLStephen”?

Because I was listening to [Adam and Joe](http://www.bbc.co.uk/blogs/adamandjoe/2009/06/test-1.shtml) when I first wrote it.


## Authors

**Original author:** Duncan Robertson

Special thanks to the following people for submitting patches over the years:

* [Guillermo Ignacio Enriquez Gutierrez](https://github.com/nacho4d)
* [Rob Lourens](https://github.com/roblourens)
* [Avi Flax](https://github.com/aviflax)
* [Tony](https://github.com/Zearin)
* [Nicholas Hutchinson](https://github.com/nickhutchinson)


## Contributing

* Fork the project
* Send a pull request
* Don’t change the build number (I’ll do that when I release a new version)
