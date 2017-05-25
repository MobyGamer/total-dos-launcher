program tdl;
{$I tdl_dire.inc}

{
Total DOS Launcher, main program.
Initial author Jim Leonard, started 20170211

To-Do:
formalize favorites to be a bit flag in cache.dat and rewrite that whole system into its own unit
color schemes in tdl.ini -- do cga remapping as well as vga palette stuff
power user: decompress all files (will require cache stuff first)
when importing handlers, add a special check for command.com to check comspec
info-box where full title and other stuff can be read
Power user title picker: Abillity to rewrite a title
Power user title picker: Delete a title (will need to remove cache dir, file, and rewrite indexes)
favorites export/import
screensaver (figure out how totinput does idle events)
Info screen for highlighted title
Search-as-you-type
Cache management strategy.  Move all cache management into unit so we can:
  come up with cache purge strategy.
  strategy can be limited to 5 dirs for testing and then avail disk space for final
  strategy should determine exact amount of storage needed from archive header but can estimate 4*archive size 4now
Power user file picker:  Delete a file from cache dir
Power user title picker: Command key to switch to cache dir and then exit the program
Ability to track what titles have been executed, how many times, and top20
}

uses
  {$IFDEF USEOVERLAYS}
  tdl_over, {must be first in uses clause}
  {$ENDIF}
  support,
  tdl_main,
  tdl_conf,
  tdl_inde,
  tdl_cons,
  tdl_hand;

{$IFDEF USEOVERLAYS}
  {Note: documentation discourages overlaying TOTSYS, TOTINPUT, and TOTFAST}
  {$O totDATE}
  {{$O totDIR}
  {$O totFAST}
  {$O totINPUT}
  {$O totIO1}
  {$O totIO2}
  {{$O totIO3}
  {$O totKEY}
  {$O totLINK}
  {$O totLIST}
  {$O totLOOK}
  {{$O totMENU}
  {$O totMISC}
  {$O totMSG}
  {$O totREAL}
  {$O totSTR}
  {$O totSYS}
  {$O totWIN}

  {$O dos}
  {$O support}
  {$O objects}
  {$O cmdlin}
  {$O inifiles}

  {$O tdl_conf}
  {$O tdl_cons}
  {$O tdl_hand}
  {$O tdl_main}
  {{$O tdl_glob} {no need to overlay global, it has no code}
  {{$O tdl_inde} {the indexing routines MUST be fast, do not overlay}

{$ENDIF}

var
  _memavail:longint;

begin
  {memory leak detection -- this MUST be the first line of the program}
  _memavail:=memavail;

  TDL_Init;
  TDL_EventLoop;
  TDL_Done;

  {memory leak detection -- these MUST be the last lines of the program}
  if _memavail<>memavail
    then fatalerror(255,'Memory leak detected: '
         +inttostr(_memavail-memavail)+' bytes unaccounted for');
end.
