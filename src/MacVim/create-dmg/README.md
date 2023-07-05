create-dmg
==========

A shell script to build fancy DMGs.

Status and contribution policy
------------------------------

Create-dmg is mostly maintained by [@aonez](https://github.com/aonez) and the contributors who send pull requests.
The project home page is <https://github.com/create-dmg/create-dmg>.

We will merge any pull request that adds something useful and does not break existing things.

If you're an active user and want to be a maintainer, or just want to chat, please ping us on Gitter at [gitter.im/create-dmg/Lobby](https://gitter.im/create-dmg/Lobby), or [email Andrew directly](floss@apjanke.net).

Create-dmg was originally created by [Andrey Tarantsov](https://github.com/andreyvit).
In May 2020 [Andrew Janke](https://github.com/apjanke) helped vastly with the project.

Installation
------------

- You can install this script using [Homebrew](https://brew.sh):

  ```sh
  brew install create-dmg
  ```

- You can download the [latest release](https://github.com/create-dmg/create-dmg/releases/latest) and install it from there:

  ```sh
  make install
  ```

- You can also clone the entire repository and run it locally from there:

  ```sh
  git clone https://github.com/create-dmg/create-dmg.git
  ```

Usage
-----

```sh
create-dmg [options ...] <output_name.dmg> <source_folder>
```

All contents of source\_folder will be copied into the disk image.

**Options:**

- **--volname \<name\>:** set volume name (displayed in the Finder sidebar and window title)
- **--volicon \<icon.icns\>:** set volume icon
- **--background \<pic.png\>:** set folder background image (provide png, gif, jpg)
- **--window-pos \<x\> \<y\>:** set position the folder window
- **--window-size \<width\> \<height\>:** set size of the folder window
- **--text-size \<text_size\>:** set window text size (10-16)
- **--icon-size \<icon_size\>:** set window icons size (up to 128)
- **--icon \<file_name\> \<x\> \<y\>:** set position of the file's icon
- **--hide-extension \<file_name\>:** hide the extension of file
- **--custom-icon \<file_name|custom_icon|sample_file\> \<x\> \<y\>:** set position and -tom icon
- **--app-drop-link \<x\> \<y\>:** make a drop link to Applications, at location x, y
- **--ql-drop-link \<x\> \<y\>:** make a drop link to /Library/QuickLook, at location x, y
- **--eula \<eula_file\>:** attach a license file to the dmg
- **--rez \<rez_path\>:** specify custom path to Rez tool used to include license file
- **--no-internet-enable:** disable automatic mount&copy
- **--format:** specify the final image format (UDZO|UDBZ|ULFO|ULMO) (default is UDZO) 
- **--add-file \<target_name\> \<file|folder\> \<x\> \<y\>:** add additional file or folder (can be used multiple times)
- **--disk-image-size \<x\>:** set the disk image size manually to x MB
- **--hdiutil-verbose:** execute hdiutil in verbose mode
- **--hdiutil-quiet:** execute hdiutil in quiet mode
- **--bless:** bless the mount folder (deprecated, needs macOS 12.2.1 or older, [#127](https://github.com/create-dmg/create-dmg/pull/127))
- **--codesign \<signature\>:** codesign the disk image with the specified signature
- **--notarize \<credentials>:** notarize the disk image (waits and staples) with the keychain stored credentials
    For more information check [Apple's documentation](https://developer.apple.com/documentation/security/notarizing_macos_software_before_distribution/customizing_the_notarization_workflow)
- **--skip-jenkins:** skip Finder-prettifying AppleScript, useful in Sandbox and non-GUI environments, [#72](https://github.com/create-dmg/create-dmg/pull/72)
- **--sandbox-safe:** hdiutil with sandbox compatibility, do not bless and do not execute the cosmetic AppleScript
- **--version:** show tool version number
- **-h, --help:** display the help

Example
-------

```sh
#!/bin/sh
test -f Application-Installer.dmg && rm Application-Installer.dmg
create-dmg \
  --volname "Application Installer" \
  --volicon "application_icon.icns" \
  --background "installer_background.png" \
  --window-pos 200 120 \
  --window-size 800 400 \
  --icon-size 100 \
  --icon "Application.app" 200 190 \
  --hide-extension "Application.app" \
  --app-drop-link 600 185 \
  "Application-Installer.dmg" \
  "source_folder/"
```

See the `examples` folder in the source tree for more examples.

Requirements
------------

Nothing except a standard installation of macOS/OS X is required.

We think this works in OS X 10.6 Snow Leopard and later.

We'd like to keep it working in as many versions as possible, but unfortunately, we just don't have test boxes running old versions of OS X adequate to make this happen. Development and testing mostly happens in the last 3-5 years' worth of macOS releases; as of 2020, this means macOS 10.12 and later.

But if you find a bug in an older version, go ahead and report it! We'll try to work with you to get it fixed.

If you're running OS X 10.5 or later, you're SOL. That's just too hard to deal with in 2020. ;)

Alternatives
------------

- [node-appdmg](https://github.com/LinusU/node-appdmg)
- [dmgbuild](https://pypi.python.org/pypi/dmgbuild)
- see the [StackOverflow question](http://stackoverflow.com/questions/96882/how-do-i-create-a-nice-looking-dmg-for-mac-os-x-using-command-line-tools)
