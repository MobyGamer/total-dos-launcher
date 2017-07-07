TDL (Total DOS Launcher) ALPHA TEST INSTRUCTIONS

Thank you for offering to test the TDL!  The TDL is a DOS program launcher
currently in devlopment.  The goal of the TDL is to make it very easy to load
vintage systems up with very many programs, and make it easy to search for
and launch them.  (If you're familiar with videogame console "multicarts"
that allow you to play hundreds of game ROMs on a console, that's essentially
what TDL is striving to be, but for vintage DOS systems.)  Testing on real
vintage DOS hardware is preferred, but if you don't own a vintage machine,
you can use an emulator such as DOSBox.

There are two packages to choose from, depending on how you want to test:

- tdl_small.zip:  A small package with 100 games that takes up less than
20MB, which can be installed onto any vintage system.  These games are
mostly compatible with earlier PC systems (1981-1985) and are not really
meant to be run in emulators or fast machines.

- tdl_large.zip:  A large package with over 6100 games that takes up nearly
2 GiB, which can still be installed onto a vintage system if a 2 gig
partition exists.  These games range from 1981 to 1991.

To use either package, burst the .zip file into a subdirectory and run
TDL.EXE to test it out.  Usage should be obvious; pick anything with arrow
keys, and hit enter to run what you picked.  TDL will unpack your selection
if it needs unpacking, then launch it.  (If there is more than one executable
file in the title you picked, it will give you a choice of what to run.)



How you can help test:
======================

I'm looking for feedback on:

- The look and feel of the TDL (especially on slower systems/drives)
- Bug reports on TDL operation
- Anything that is confusing or not obvious
- Suggestions, criticism, feature requests

I am *NOT* looking for feedback on:

- There was no way to exit the game (that's not my problem, some of
  these are converted bootable disks or badly-cracked games)
- The game sucks
- The game crashes on my emulator/system (not everything included works on
  every system -- if it TRIES to run, that should be considered a success)
- My favorite game isn't included

Please submit your feedback in the forum where you learned about this
project.  Alternately, you can email your feedback to trixter_oldskool_org



Additional things to try as an Alpha tester:
============================================

- Use ALT-F5 to view the DOS screen.  (This is helpful if you want to read
any text printed onscreen as the game exited, but the TDL returns so quickly
that you cannot read it.)

- Run TDL /? to see command-line parameters.  They're optional, but you
might find them interesting.

- Look at the TDL.INI and HANDLERS.INI files to see if you understand what's
going on and how to reconfigure TDL if you want to.

- Run the 0FREERAM program and use ALT-F5 to check its output -- if
everything is working correctly, you should see the TDL taking up less than
1K of RAM when executing programs (using SPACE-AGE SWAPPING TECHNOLOGY)

- TDL will try to use EMS and XMS for speeding up the program.  It
should still work fine on any system without EMS or XMS, but if you have
them, it will use them.  TDL also uses EMS, XMS, and raw extended memory
(ie. no HIMEM.SYS loaded) to speed up swapping; if they aren't present,
TDL will swap to disk which can take a few seconds inbetween launching
programs and returning to the TDL.

- The TDL uses whatever screen mode is already in use when it starts up.
This should work well for most situations, but you can control this with the
DOS MODE command if necessary.  For example:  If your vintage system is
hooked up to a TV, you can run MODE CO40 at the DOS prompt to switch into
40-column mode for a more readable screen; TDL will still work, although the
screen is generally a bit crowded.  Also, if your vintage system uses a B&W,
grayscale, or green/amber monitor hooked up to a color card and you can't
see different shades very well, run MODE BW80 at the DOS prompt and TDL will
start with a monochrome color scheme.  You can also switch into VGA
80x50 mode before starting TDL and it will use that for more text
onscreen.  The only exception to this are VESA text modes; you can use
them, but you have to turn them on in the TDL.INI file.


Known bugs and missing features:

- These are pre-packaged distros for testing TDL's launcher only.  You
cannot add your own files to these distros.  When the TDL is ready for
release, it will come with Windows/Mac/Linux programs for easily
packaging up your own distros.

- Search-as-you-type is not yet implemented.  To hold people over until
then, you can search-by-first-letter (which helps a lot with the 6100+
large distro on slow systems).

