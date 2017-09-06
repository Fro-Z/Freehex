# Freehex
Freehex is a Free open-source multiplatform hex editor written in D. Freehex uses GtkD bindings of GTK+ library.
Supported platforms include Windows 7 or newer, Ubuntu 17.04, macOS 10.12 Sierra, but it should work anywhere where GTK+ 3 and DMD are supported.

[![Build Status](https://travis-ci.org/Fro-Z/Freehex.svg?branch=master)](https://travis-ci.org/Fro-Z/Freehex)

## Features
- Edit files in hexadecimal and text format (ASCII + UTF8 support)
- Large file support (Open multi-gigabyte files without loading everything into RAM)
- Data translator (View data as several most common datatypes)
- Search and Replace (Currently done in main thread, needs improving)
- Copy and Paste to and from system-shared clipboard
- Undo & Redo
- Go to

## Screenshot
![Freehex screenshot](http://i.imgur.com/qK7wlXv.png "Freehex screenshot")

## Requirements
To run Freehex you must build it from source.
Requirements:
- D compiler (DMD is recommended  http://dlang.org/download.html#dmd)
- DUB package manager https://code.dlang.org/download
- GtkD library 3.6.2 (downloaded automatically through DUB)
- Gtk+3 Runtime
### Installing Gtk+3 Runtime
#### Windows
- Download and run http://master.dl.sourceforge.net/project/gtkd-packages/gtk3-runtime/gtk3-runtime_3.22.4_64-bit.exe
- Latest link is also available on https://gtkd.org/ website.
#### Ubuntu / Linux
- Ubuntu 17.04 has GTK+3 Runtime installed by default.
- Other distributions can refer to https://www.gtk.org/download/linux.php
#### macOS
- Recommended method is to use Homebrew (https://brew.sh/)

With Homebrew installation is done using
~~~~
brew install gtk+3
~~~~

### Building from source
#### Windows
Build by running 'build.bat' file.
#### Linux / macOS
Build by running 'build.sh' file.

## Generating project files
You can generate project files for your IDE of choice using DUB.
For example:
Generating project files for Visual D:
~~~~
dub generate visuald -a=x86_64 -b debug
~~~~

