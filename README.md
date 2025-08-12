Testing push 3
<h1 align=center>
<img src=https://macvim.org/docs/MacVim.png alt="MacVim logo" style="height:4em"><br>
MacVim
</h1>

<p align="center">
<a href="https://macvim.org/">Website</a> · <a href="https://macvim.org/docs/gui_mac.txt">Documentation</a>
</p>
<p align="center">
<a href="https://github.com/macvim-dev/macvim/actions/workflows/ci-macvim.yaml?query=branch%3Amaster+event%3Apush"><img src="https://github.com/macvim-dev/macvim/actions/workflows/ci-macvim.yaml/badge.svg" alt="MacVim GitHub CI"></a>
<a href="https://github.com/macvim-dev/macvim/releases/latest"><img src="https://img.shields.io/github/v/release/macvim-dev/macvim?label=GitHub%20Release&display=release" alt="GitHub release"></a>
<a href="https://repology.org/project/macvim/versions"><img src="https://repology.org/badge/tiny-repos/macvim.svg" alt="Packaging status"></a>
</p>


MacVim is a macOS version of the [Vim](https://github.com/vim/vim) text editor, providing a graphical user interface for Vim, while tightly integrating with macOS and providing features specific to the platform.

<hr>

<p align="center">
  <picture>
    <source srcset="https://macvim.org/images/macvim-screenshot-light.png"  media="(prefers-color-scheme: light)"/>
    <source srcset="https://macvim.org/images/macvim-screenshot-dark.png"  media="(prefers-color-scheme: dark)"/>
    <img width="535" alt="macvim-screenshot-light" src="https://macvim.org/images/macvim-screenshot-light.png" />
  </picture>
</p>

## Features

- Smooth native GUI that supports menus, dialog boxes, toolbars, and scroll bars.
- Native and non-native full-screen modes.
- Trackpad gestures, Touch Bar, and Command key shortcuts can be mapped to Vim actions.
- Integrates with system services, dictionary lookup, and Apple Intelligence Writing Tools.
- Vim GUI tabs with customizable colors.
- Font ligatures and accurate text rendering.

## Getting Started

See [installation documentation](https://github.com/macvim-dev/macvim/wiki/Installing) for more details and alternative methods to install.

### Download

You can download the latest version of MacVim from the [Releases](https://github.com/macvim-dev/macvim/releases/latest) page.

### Install via Package Manager

If you would like to install using a package manager, MacVim can be installed via Homebrew:

  ```zsh
  brew install macvim
  ```

MacVim is also available as a Homebrew cask. It will install the same pre-built binary as the one available from GitHub release:

  ```zsh
  brew install --cask macvim-app
  ```

After installation, MacVim can be launched using the Dock or in the terminal using the `mvim` command.

### Building from Source

If you prefer to build MacVim from source, detailed instructions are provided in the [Building MacVim](https://github.com/macvim-dev/macvim/wiki/Building) guide.

## Relationship with Vim

MacVim is a downstream fork of Vim, and routinely [merges from upstream](https://github.com/macvim-dev/macvim/wiki/Merging-from-upstream-Vim). The original Vim README can be found at [README_vim.md](README_vim.md). Vim itself is also available for macOS, but it does not have a GUI.

In Homebrew, there are both a `macvim` and `vim` package. Both packages will provide a terminal version of Vim with similar features. The `vim` package is from the upstream Vim project and is usually a bit more up-to-date in core Vim features, while the `macvim` package will provide the additional GUI version bundled as an app.

## License

MacVim is released under the [Vim License](https://github.com/macvim-dev/macvim/blob/master/LICENSE).

## Support

If you encounter any issues or have questions, feel free to [open an issue](https://github.com/macvim-dev/macvim/issues) or visit the [discussions](https://github.com/macvim-dev/macvim/discussions) page.

