program tdl;
{$I tdl_dire.inc}

{
Total DOS Launcher, main program.
Initial author Jim Leonard, started 20170211

See "todo.txt" for a list of features that are planned but not yet implemented.
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
