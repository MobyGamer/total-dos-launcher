
Total DOS Launcher
##################

The Total DOS Launcher is a system for easily loading and running thousands of
DOS programs on vintage hardware.  If you're familiar with vintage gaming
console "flash multicarts" that allow you to load hundreds of games onto a
single console, that's what this is:  Think of the TDL as "console multicart"
software for DOS.

.. contents::
.. section-numbering::


Introduction
============

In a nutshell, the TDL takes all of your zipped-up long-filename archives:

| A Mind Forever Voyaging r77 (1985)(Infocom, Inc.) [Adventure, Interactive Fiction].zip
| Adventure (1987)(Willie Crowther, Kevin B. Black) [Adventure, Interactive Fiction].zip
| Adventure in Serenia [DC] (1982)(IBM) [Adventure, Interactive Fiction].zip
| Adventures of Buckaroo Banzai Across the Eighth Dimension, The v3.87 (1985)(Adventure International) [Adventure, Interactive Fiction].zip
| Alley Cat [DC] (1984)(IBM) [Action].zip
| Archon- The Light and the Dark [DC] (1984)(Electronic Arts, Inc.) [Action, Strategy].zip
| Arcticfox (1986)(Electronic Arts, Inc.) [Action, Simulation].zip
| Battlezone [DC] (1983)(Atarisoft) [Action, Simulation].zip
| Borrowed Time [DC] (1985)(Activision, Inc.) [Adventure].img.zip
| Bouncy Bee Learns Letters v1.01 (1985)(IBM) [Educational].zip
| California Games v1.01 (1988)(Epyx, Inc.) [Sports].zip
| Centipede [DC] (1983)(Atarisoft) [Action].zip
| Chessmaster 2000, The (1986)(Software Toolworks, Inc., The) [Strategy, Chess].zip
.

...and copies them to files that can be copied over to any DOS system, even those without long-filename support::

 AMINDFOR.ZIP
 ADVENTUR.ZIP
 ADVENTUA.ZIP
 ADVENTUB.ZIP
 ALLEYCAT.ZIP
 ARCHON-T.ZIP
 ARCTICFO.ZIP
 BATTLEZO.ZIP
 BORROWED.ZIP
 BOUNCYBE.ZIP
 CALIFORN.ZIP
 CENTIPED.ZIP
 CHESSMAS.ZIP

...along with a menu program that easily launches them without requiring them to be unzipped beforehand:

.. image:: docs/menu_example.png
   :alt: A sample TDL menu
   :align: center

It can do this with a few hundred programs, or thousands, or *tens of thousands*.  Your only limitation is how much storage space you have on your target DOS system.

The TDL is currently in development and not quite ready for prime time; this paragraph will be removed when it is.  If you are testing TDL for the purpose of providing feedback, please consult "readme_a.txt" for instructions.  Also, feel free to `contribute an issue via the github project. <https://github.com/MobyGamer/total-dos-launcher/issues>`_


Using TDL
=========

Overview
--------

The Total DOS Launcher consists of two programs:  An indexer, and a menu system.  You use the indexer to prepare your files for copying over to the vintage DOS system, and you use the menu program on the DOS system to navigate and launch the programs you copied over.


Prerequisites
-------------

Indexer:  Currently a python script, so you'll need to install python 3.6 or higher on your system if it isn't already there.  (When this project is past the beta stage, native binaries will be provided for Windows, Mac, and Linux.)

Menu program:  The menu program runs on any IBM PC or compatible running DOS 3.1 or higher, with a minimum of 256KB RAM.


Step one: The Indexer
---------------------

To prepare your files for copying over, run TDLIndexer.py with these arguments:

.. code-block:: bash
 
  TDLIndexer.py <source directory> <destination directory>
   
The TDLIndexer.py program MUST be run in the same directory that contains the ``distro`` subdirectory.  This contains all of the menu program elements that will get copied over with your files.

The indexer recurses through subdirectories.  So if your menu structure looks like this::

 DOS Games\
   Adventure\
     1981\
     1982\
     1983\
     
...they will all get picked up by the indexer as long as you specify ``DOS Games`` as the source directory.     
     


Example Usage::

 C:\DOS\D\PROJECTS\TDL>TDLindexer.py ..\dos_program_sources\small.generic.4example output
 Gathering list of files...
 Found 96 files to copy.
 Converting to DOS-friendly 8.3 filenames...
 Generating files index...
 Generating titles index...
 Copying files from ..\dos_program_sources\small.generic.4example to output ...
 Done.
 
This results in a complete distribution ready to copy over to your DOS system.  It consists of the menu program, some index files, and your original source files in a ``files`` subdirectory::

 02/03/2018  11:17 PM    <DIR>          files
 01/18/2018  11:00 PM    <DIR>          utils
 01/20/2018  06:22 PM           139,712 TDL.EXE
 02/03/2018  11:17 PM             8,481 TITLES.IDX
 02/03/2018  11:17 PM             1,346 FILES.IDX
 07/07/2017  03:36 PM             2,988 TDL.INI
 07/07/2017  03:36 PM             4,169 HANDLERS.INI

Step two: Copy to the vintage system
------------------------------------

Using any method you feel comfortable with, copy the entire contents of the output directory you specified over to your vintage DOS system, being careful to preserve the directory structure.  

Instructing the user on copying files from a modern system to a vintage system is beyond the scope of this documentation, but here are a few pointers to get you started:

- Removable hard drives:  You can use a Compact Flash card instead of a physical IDE drive with a cheap CF-to-IDE adapter; then all you need to do is insert it into your modern system with a CF card reader to do the copy.  For very old systems that can't use IDE drives, there are homebrew ISA hard drive adapters that use CF cards directly; search the internet for "XTIDE Compact Flash" to find a few examples.
- TCP/IP: Install a network card that has a supported DOS packet driver, then install and use some sort of transport to copy the files over.  This can be Microsoft LAN Manager, Novel Netware, etc., or a simpler and faster option like Mike Brutman's mTCP suite.  If your system can load programs into upper memory, you can also get away with running MS LANMAN resident, and just access your files as a driver letter over the network.
- CD or DVD: Burn everything to a CD or DVD and just run from there.


Step three: Launch the menu program
-----------------------------------

Type ``TDL`` from the directory where it is installed.


Configuring TDL
==============

TDL, out of the box, does not need to be configured.  If you want to configure it to your liking, such as specifying multiple source directories (to get past the DOS 2G partition limit), forcing a specific location for the cache directory, using a high-res VESA text mode, etc. then edit the ``TDL.INI`` and ``HANDLERS.INI`` files.  Both .INI files contain a description of what each option does.

``TDL.EXE`` also has some command-line options to control how it operates:

-?, -h  Print a summary the most current set of command-line options.
-c      Set 43-line (EGA) or 50-line (VGA) mode.  (If you need more lines than that, see TDL.INI for VESA options.)
-r      Instructs TDL that it is on read-only media (ie. CDROM or DVDROM)' and that it should not try to write anything to its local filesystem.  This disables "favorites" as well as writing the debug log to disk.
-d      Print excessive debugging messages during initialization.  Used for troubleshooting only.'
-f      Always use fast display routines on all CGA systems.  This may cause "snow" or display corruption on true CGA adapters.',0dh,0ah



Building TDL
============

*Building the TDL is not required to use it.*  This section is only for those who want to hack on the code and contribute back to the project  -- however, be prepared to get (re)acquainted with DOS compilers and tools!


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
