Total DOS Launcher
##################

The Total DOS Launcher is a system for easily loading and running thousands of
DOS programs on vintage hardware.  If you're familiar with vintage gaming
console "flash multicarts" that allow you to load hundreds of games onto a
single console, that's what this is:  Think of the TDL as "console multicart"
software for DOS.

Currently, the TDL is not ready for prime time; this documentation will change
when it is.  If you are testing TDL, please consult "readme_a.txt" for
instructions.

.. contents::
.. section-numbering::

Building TDL
============


Languages
---------
TDL is written in Turbo Pascal 7.0, with a small amount of assembler thrown in
for speed or utility.  Knowledge of Pascal is require to extend TDL.

Libraries
---------
TDL is not 100% self-contained; it uses some support libraries and units to
provide functionality like CUI/TUI primitives, userspace swapping, and stream
extensions.  Ensure you have a copy of both https://github.com/MobyGamer/TPLibs
and https://github.com/MobyGamer/UNITS available in your source path.

Compilers and Tools
-------------------
Borland Pascal 7.0, which includes both Turbo Pascal as well as Turbo
Assembler/linker/debugger, is available via your favorite search engine.  A
full installation of it is rumored to be included in
ftp://ftp.oldskool.org/pub/misc/xtfiles.rar.

Compiler/Assembler restrictions
-------------------------------
You must always ensure that the code you write will execute on any x86 system,
including the 8088.  Don't use 80186+ instructions such as ``PUSHA``, ``POPA``,
``ENTER``, ``LEAVE``, etc.  In Turbo Pascal, always ensure ``$G-,N-,E-`` to
turn off 80286 code generation, 8087 code generation, and 8087 emulation
respectively.  One of TDL's design goals is the ability to work on any IBM PC
or compatible.
