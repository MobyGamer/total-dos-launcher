{$I tdl_dire.inc}

{$IFDEF USEOVERLAYS}
{$O+,F+}
{$ENDIF}
unit tdl_main;

{
Main application functionality.  Keeping the main program (event loop and
supporting code) in its own unit allows us to:
  - Develop and compile directly in a slow, memory-constrained DOS environment
  - Enable more granular overlay management if it turns out we need it
  - Program defensively
}

interface

Procedure PrintHelp;
Function Launch(tid:word):boolean;
procedure TDL_Init;
procedure TDL_EventLoop;
procedure TDL_Done;

implementation

uses
  DOS,
  objects,
  support,
  strings,
  cmdlin,
  totFAST,
  totSYS,
  totINPUT,
  totLOOK,
  totLIST,
  totKEY,
  totMSG,
  streams,
  tdl_glob,
  tdl_cach,
  tdl_conf,
  tdl_inde,
  tdl_cons,
  tdl_hand,
  tdl_tset,
  tdl_audi;

const
  favsOn:boolean=false;
  unpackedOn:boolean=false;

type
  txtcoords=record
    x,y:byte;
  end;

var
  jcloc:txtcoords; {jumpcursor location}

var
  titleSets:array[0..maxTitleSets-1] of PTitleSet;
  titleMetadata:PMetadata;

procedure TDL_Init;
{
Initialize TDL, first with defaults and the refine using the config file.
TDL never changes the initial video mode when initializing, so that
error and status messages are always visible.
}
var
  sf,sd,temps:string;
  base:nameStr;
  full:string[12];
  ext:extStr;
  dir:dirStr;
  filepath:PathStr;
  w:word;
  {wantNlines:byte;}
  tf:PFileStruct;
  t:pointer;

  procedure expressType;
  var
    ws:string[24];
  begin
    ws:='on disk';
    if t=typeof(TEMSStream)      then ws:='in EMS';
    if t=typeof(TEMSStream2)     then ws:='in EMS';
    (*
    if t=typeof(TNamedBufStream) then ws:='on disk';
    if t=typeof(TTempBufStream)  then ws:='on disk';
    *)
    if t=typeof(TMemoryStream)   then ws:='in lower DOS RAM';
    if t=typeof(TXMSStream)      then ws:='in XMS';
    temps:=temps+ws;
  end;

begin
  {If user requested help, then print it and exit}
  if is_param('?') or is_param('h')
    then PrintHelp;

  RecordDOSScreen;

  {determine TDL base directory and configuration file to use:
  sf = startup configuration file
  sd = startup directory}
  if non_flag_count>0 then sf:=non_flag_param(1) else sf:='tdl.ini';
  if non_flag_count>1 then sd:=non_flag_param(2) else sd:='';
  sd:=StdPath(FExpand(sd));
  {attempt TDL config init}
  writeln('Configuring '+TDLtitle+'.  Use "-h" for command-line options.');
  writeln('Reading '+sf+'...');
  config:=new(pconfig,init(sf,sd));
  if config=nil
    then fatalerror(1,'Error while configuring; check '+sd+'\'+sf);

  {set config options based on command-line options}
  if is_param('d') then config^.edebug:=true;
  if is_param('r') then config^.readonly:=true;
  if is_param('c') then config^.wantCondensed:=true;
  if is_param('f') then config^.wantSnow:=true;
  if is_param('s') then config^.wantAuditExport:=true;

  {attempt TDL handlers init}
  writeln('Registering handlers from handlers.ini...');
  Handlers:=new(PHandlers,init(config^.basedir+'handlers.ini'));
  {We can only show files properly for up to 42 filemasks.  If we have
  more handlers than that, switch to power user mode so that we only have
  to use one mask (*.*).}
  if Handlers^.Count>42 then config^.userlevel:=power;

  {Now that we have our handlers, let's try to use our swapping mechanism
  to determine how much memory is available for programs by running
  FREERAM (if it's available) and storing the result to show the user.
  config^.freeLowDOSRAM is 0 unless we change it in this code.}
  filepath:=fsearch('FREERAM.COM','utils;distro\utils');
  if filepath<>'' then begin
    {determine extension so we know which handler to use}
    fsplit(filepath,dir,base,ext);
    delete(ext,1,1); {remove period}
    if not Handlers^.handle(ext,filepath,dir)
      then fatalerror(2,'Couldn''t launch '+filepath +' -- Try swapping=disabled in TDL.INI')
      else config^.freeLowDOSRAM:=word(ptr($40,$f0)^);
  end else begin
    {if we couldn't find freeram, then fake it with an estimate}
    config^.freeLowDOSRAM:=memavail;
  end;

  {If we used SWAPPO, our PSP is gone, so all command-line parameters after
  this point are now empty!  Hope you got what you needed before this line!}

  {Track our EMS and XMS usage}
  config^.EMSatStartup:=ems_memavail;
  config^.XMSatStartup:=xms_memavail;

  {Initialize indexes. Titles is more important to be fast, so
  try to init it first in case there's enough lower RAM to hold it.}
  writeln('Initializing titles index...');
  titles:=new(PTitleIndex,
          init(config^.baseDir+config^.titlesIDXname,config^.preloading));
  if titles=nil then fatalerror(1,'Titles index init failed');

  writeln('Initializing files index...');
  {never cache files index; doesn't need it, accessed infrequently}
  files:=new(PFileIndex,
         init(config^.baseDir+config^.filesIDXname,false));
  if files=nil then fatalerror(1,'Files index init failed');

  write('Title metadata: ');
  temps:=stdpath(sd)+'titles.dat';

  if config^.readonly then begin
    writeln('Read-only mode: disabled');
    titleMetadata:=new(PMetadata,init('',config^.numTitles));
  end else begin
    writeln('Initializing using '+temps);
    titleMetadata:=new(PMetadata,init(temps,config^.numTitles));
  end;

  {Ensure cache size is known before continuing}
  writeln('Inspecting file cache at ',fileCache^.path);
  fileCache^.Remaining;
  writeln(fileCache^.megsfree,' MB available for cache use.');
  if config^.startupCacheScan then begin
    write('Validating cache entries...');
    for w:=0 to config^.numtitles-1 do begin
      if titleMetadata^.getFlag(w,m_unpacked)=true then begin
        files^.retrieve(w,tf);
        if fileCache^.cDirExists(tf)=false then begin
          titleMetadata^.clearFlag(w,m_unpacked);
          titleMetadata^.changed:=true;
        end;
      end;
    end;
    writeln('done.');
  end;

  if (config^.userlevel=power) or (config^.edebug=true) then begin
    writeln('Performing additional checks:');

    temps:='Files index is located ';
    t:=typeof(files^.data^);
    expressType;
    writeln(temps);

    temps:='Titles index is located ';
    t:=typeof(titles^.data^);
    expressType;
    writeln(temps);

    with config^ do begin
      {power users like to ensure they copied the stuff over correctly}
      write('Index locations: ');
      write(filesIDXloc);
      writeln(' ',titlesIDXloc);
      write('Checking index files for correctness: ');
      write('files... ');
      if files^.verify=false then fatalerror(1,'File index inconsistent');
      write('titles... ');
      if titles^.verify=false then fatalerror(1,'Title index inconsistent');
      writeln('passed.');

      {power users want to know everything}
      writeln('Number of titles: ',numTitles);
      writeln('Base directory: ',baseDir);
      writeln('Swapping enabled: ',swapping);
      writeln('Auditing enabled: ',auditing);
      writeln('Preloading enabled: ',preloading);
      writeln('Cache Directory: ',fileCache^.path);
      writeln('Startup Directory: ',startupDir);
    end;
    writeln('Hit a key to continue TDL startup.');
    asm
        xor     ax,ax
        int     16h
    end;
  end;

  {populate the initial list of titles we're working with}
  titleSets[activeSet]:=New(PTitleset,init(config^.numTitles));

  with titleSets[activeSet]^ do
    for w:=0 to numTitles-1 do
      titleIDs^[w]:=w;

  {init the audit log}
  if config^.auditing then begin
    auditLog:=new(PAuditLog,init(config^.basedir+'AUDIT.DAT'));
  end;

  {set up the screen}

  {If changing screen mode, we need to re-enable the screen. construct to
  pick up the new dimensions.}
  {Also: If we noticed we're already in a condensed mode coming in, make
  sure we record that fact so that restores go correctly.}
  if (oldScreenParams.videorows=43) or (oldScreenParams.videorows=50)
    then config^.wantCondensed:=true;
  if config^.wantCondensed then begin
    Monitor^.SetCondensed;
    config^.customvidmode:=3;
  end;
  {if VESA text mode specified, set it}
  w:=config^.customvidmode;
  if w>$100 then begin
    w:=setVESA(w);
    if w<>0 then begin
      write('Attempt to set VESA mode ',hexword(config^.customvidmode),'failed: ');
      case w of
        1:writeln('VESA not installed');
        2:writeln('VESA BIOS cannot set mode');
      end;
    end;
  end;
  if config^.customvidmode<>0 then begin
    {reset mouse, totsys.monitor, and screen so that they pick up new dimensions}
    Mouse.done;
    fastDone;
    dispose(monitor,done);

    SysInit;
    Mouse.init;
    fastInit;
  end;
  {set a marker for 40-col mode}
  if Monitor^.width=40
    then config^.customVidMode:=40;

  {
  Customize color choices.  For MDA, make selected/special text black on white, everything else white on black.
  For color, pick blue background and some reasonable choices for others.
  At some point, the user will be able
  to pick any color set they like, but for now, these are the defaults.
  }
  {Bor,Tit,Icon,HiHot,HiNorm,LoHot,LoNorm,Off}
  {SetWindow(Border,Body,Icons,Title:byte);}
  if Monitor^.ColorOn
    then begin
      LookTOT^.SetMenu($1b,$1e,$7f,$31,$3f,$1e,$17,$19);
      LookTOT^.SetWindow($19,$1e,$1e,$1b);
      faviconcol:=$1c; {bright red foreground}
      unpiconcol:=$19; {bright blue foreground}
    end else begin
      LookTOT^.SetMenu($0F,$09,$78,$78,$70,$01,$07,$07);
    end;

  DOSScreen:=new(PScreenObj,init);
  DOSScreen^.save;
  with config^ do begin
    tpos.y2:=screen.depth-1;
    tpos.x2:=screen.width;
    screen.clear(LookTOT^.vMenuBorder,#0);
    {If provided a subheader in TDL.INI, use it.  Truncate if necessary.}
    temps:=TDLTitle + config^.subheader;
    if length(temps) > screen.width-1
      then temps[0]:=char(screen.width-1);
    screen.WriteCenter(1,LookTOT^.vMenuTitle,temps);
    jcloc.x:=17;
    jcloc.y:=tpos.y1-2;
    screen.WriteAt(1,tpos.y1-2,LookTOT^.vMenuLoNorm,jumplabel); screen.gotoxy(jcloc.x,jcloc.y);
    screen.WriteAt(1,tpos.y1-1,LookTOT^.vMenuLoNorm,'Or, choose from the following programs:');

    {status bar}
    screen.PartClear(1,screen.depth,screen.width,screen.depth,
      LookTOT^.vMenuHiNorm,' ');
    screen.WriteHI(1,screen.depth,
      LookTOT^.vMenuHiHot,LookTOT^.vMenuHiNorm,TDLStatus);

    {init message console now that we have our screen mode locked in}
    if config^.readonly
      then begin
        MsgConsole:=new(PMConsole,init(''));
        MsgConsole^.logmsg(warning,'Read-only filesystem: Debug log will not be written to a file!');
      end else
        MsgConsole:=new(PMConsole,init(config^.basedir+'tdl.log'));
    if (userlevel=power) or (logging=true) then begin
      MsgConsole^.verboseLog:=true;
    end;
    if config^.wantSnow
      then boolean(snowprone):=false;
    if boolean(snowprone)
      then MsgConsole^.logmsg(info,'Slower display routines enabled to avoid CGA "snow"')
      else MsgConsole^.logmsg(info,'No CGA "snow" checking will be performed when writing to screen RAM.');
  end;

  {power users want to know everything}
  with MsgConsole^ do begin
    with config^ do begin
      logmsg(info,'Number of titles: '+inttostr(numTitles));
      logmsg(info,'Base directory: '+baseDir);
      logmsg(info,'Swapping enabled: '+boolToStr(swapping,'',''));
      logmsg(info,'Preloading enabled: '+boolToStr(preloading,'',''));
      logmsg(info,'Data Cache Directory: '+fileCache^.path);
    end;
  end;

end;

Procedure PrintHelp;
begin
  writeln(TDLTitleFull);
  asm
    jmp @start
@message:
    db 'Usage: TDL.EXE <switches>',0dh,0ah,0ah

    db 'Switches:',0dh,0ah
    db '-?, -h  This help',0dh,0ah
    db '-c      Set 43-line (EGA) or 50-line (VGA) mode.',0dh,0ah
    db '        (If you need more lines than that, see TDL.INI for VESA options.)',0dh,0ah
    db '-r      Instructs TDL that it is on read-only media (ie. CDROM or DVDROM)',0dh,0ah
    db '        and that it should not try to write anything to its local filesystem.',0dh,0ah
    db '        This disables "favorites" as well as writing the debug log to disk.',0dh,0ah
    db '-d      Print excessive debugging messages during initialization.',0dh,0ah
    db '        Used for troubleshooting only.',0dh,0ah
    db '-f      Always use fast display routines on all CGA systems.',0dh,0ah
    db '        This may cause "snow" or display corruption on true CGA adapters.',0dh,0ah
(*  db '-nXX    Override screen detection and force XX lines onscreen.',0dh,0ah
    db '        Debugging option; submit an issue if you''re forced to use this.',0dh,0ah*)
    db '-s      Export the AUDIT.DAT audit log to .CSV format.',0dh,0ah
    db 0ah,'$'

@start:
    push ds
    mov ax,0900h
    lea dx,@message
    mov bx,cs
    mov ds,bx
    int 21h
    pop ds
  end;
  halt(255);
end;


Procedure PopGeneralInfo;
var
  foomsg:PMessageObj;
  s:string[12];
  s2:string;
begin
  new(foomsg,init(2,'TDL info and stats'));
  with foomsg^ do begin
    case config^.userlevel of
      kiosk:s:='KIOSK';
      regular:s:='default';
      power:s:='Power User';
    end;
    with config^ do begin
      addline(' Swapping: '+boolToStr(swapping,'ENABLED','disabled'));
      if freeLowDOSRAM <> 0 then begin
        addline(' '+inttostr((longint(freeLowDOSRAM) * longint(16)) div 1024)
                   +' KB DOS RAM availble to launched programs ');
        addline(' ');
      end;
      addline(' TDL operating mode: '+s);
      addline(' TDL Heap remaining: '+inttostr(memavail div 1024)+' KB');

      {Report how much EMS or XMS we're using.  The logic below accounts
      for QEMM, DOSBox, and others reporting the same amount of EMS and XMS
      always available (they both draw EMS and XMS from an internal pool
      of managed RAM).  This code favors EMS use over XMS (because it's
      faster) so we favor reporting on EMS in a dual EMS/XMS situation.}
      s2:='';
      if config^.XMSatStartup > xms_memavail
        then s2:=inttostr((config^.XMSatStartup - xms_memavail) div 1024)+' KB of XMS';
      if config^.EMSatStartup > ems_memavail
        then s2:=inttostr((config^.EMSatStartup - ems_memavail) div 1024)+' KB of EMS';
      if s2<>''
        then addline(' TDL is using '+s2+' to accelerate index operations');

      addline(' # of Titles: '+inttostr(numtitles)+' ('+inttostr(titleMetadata^.Used)+' with additional metadata) ');
      addline(' Debug messsages logged to disk: '+boolToStr(logging,'ENABLED','disabled'));
      addline(' Treating filesystem as read-only: '+boolToStr(readonly,'YES','no'));
      {addline(' Excessive debug messages: '+boolToStr(edebug,'ENABLED','disabled'));}
      addline(' Pause after execution: '+boolToStr(pauseAfterRun,'ENABLED','disabled'));
      addline(' ');
      if fileCache^.bytesfree > (1024*1024)
        then s:=inttostr(fileCache^.megsFree)+' MB free)'
        else s:=inttostr(fileCache^.bytesFree div 1024)+' KB free)';
      addline(' Cache directory: '+fileCache^.path+' ('+s+' ');
    end;
    addline(' ');
    show;
  end;
  dispose(foomsg,done);
end;

Procedure PopTitleInfo(tid:word);
var
  foomsg:PMessageObj;
  s:string[12];
  tfbuf:PFileStruct;
  ttbuf:PTitleStruct;
  s2:string;

begin
  new(foomsg,init(2,'Information on this title'));
  titles^.retrieve(tid,ttbuf);
  files^.retrieve(tid,tfbuf);
  with foomsg^ do begin
    addline(' Title: '+ttbuf^.title);
    addline(' Filename: '+tfbuf^.name);
    s2:=' Cache Directory: ';
    if fileCache^.cDirExists(tfbuf)
      then s2:=s2+fileCache^.cDir(tfbuf)
      else s2:=s2+'(not yet unpacked)';
    addline(s2);
    show;
  end;
  dispose(foomsg,done);
end;


function Launch(tid:word):boolean;
{
Execution flow:

After picking a title, extraction handler is searched for.
  (If extraction handler not found, try using execution handler, in case
  the user copied over .txt or .gif files too)
Once extraction handler found, cache directory is searched for.
  If cache dir not found, create via extraction handler.
Once cache dir found/created, all extensions in it are searched for and
checked against all execution handlers, then only those with handlers
are displayed for user to choose.
  If only one found, launches automatically based on user level.

Notes:  It might be tempting to eliminate the distinction between
extraction and execution handlers, but this is necessary because we need
to handle the use case of the user copying over both "game.zip" and
"game.txt".  Otherwise, a blind search for the game\ cache directory
will always succeed if .zip launched first, and game.txt will never launch.

*** DEMDR4 and also note custom chartask if you want to trap different keys
*** actually, will probably do it myself.  use a listarrayobj
*** with a custom messagetask (chapter 9)
}
var
  base:nameStr;                       {basename of title we want to run}
  full:string[12];
  ext:extStr;
  dir:dirStr;
  wrkDir:string;
  temps:string;
  filepath:PathStr;                     {fully-qualified path to source file}
  tcachedir:PathStr;
  unpackEstimate:longint;

  tfbuf:PFileStruct;
  ttbuf:PTitleStruct;

  ListWin:pListDirSortObj;
  x1,y1,x2,y2,style:byte;

  s,filemasks:string;
  b:byte;
  p:pointer;

  procedure prepScreenForExec;
  begin
    screen.clear($07,' ');
    screen.writeCenter(1,$0f,'Executing:');
    screen.writeCenter(2,$07,filepath);
    screen.gotoxy(1,3);
  end;

begin
  {assume everything will go ok}
  Launch:=true;
  msgConsole^.logmsg(info,'Attempting to Launch title #'+inttostr(titleSets[activeSet]^.titleids^[tid])+':');
  if titleMetadata^.changed then begin
    msgConsole^.logmsg(info,'Flushing metadata cache');
    titleMetadata^.flush;
  end;
  {grab title so that we can determine the id needed for file}
  titles^.retrieve(tid,ttbuf);
  msgConsole^.logmsg(info, ttbuf^.title);
  {determine cache directory}
  if not files^.retrieve(tid,tfbuf)
      then die('Could not retrieve file info');
  if tfbuf^.id<>tid then die('Wrong file retrieved');
  tcachedir:=fileCache^.cDir(tfbuf);
  {files can be in multiple drives/paths; find where we put our file}
  full:=StrPas(tfbuf^.name);
  filepath:=fsearch(full,config^.ProgLocs);
  if filepath='' then begin
    popUserMessage(error,'PATH "'+config^.ProgLocs+'" did not contain "'+full+'".  Did you delete it?');
    Launch:=false;
    exit;
  end;
  {determine extension so we know which handler to use}
  fsplit(filepath,dir,base,ext);
  delete(ext,1,1); {remove period}

  {Diskspace check: Do we have the disk space to handle this?}
  unpackEstimate:=fileCache^.EstimateCacheUsage(ext,filepath);
  if (DirExists(tcachedir) = false)
  and (fileCache^.bytesfree < unpackEstimate) then begin
    s:='This title could require up to '
      +inttostr(unpackEstimate div 1024)
      +' KB of disk space to run properly, but your cache only has '
      +inttostr(fileCache^.bytesfree div 1024)
      +' KB free.  Please remove files from '
      +fileCache^.path
      +' to free up enough disk space.';
    popUserMessage(error,s);
    Launch:=false;
    exit;
  end;

  {Is the file directly launchable?  (ie. .txt, .gif, etc.)
  If so, launch it; if not, it is an archive that needs extraction.}
  if Handlers^.Exists(ext)=execution
    then begin
      {This file is already "unpacked" so mark it as such}
      titleMetadata^.setFlag(tid,m_unpacked);
      titleMetadata^.changed:=true;
      prepScreenForExec;
      Handlers^.handle(ext,filepath,dir);
    end else begin
      if Handlers^.Exists(ext)=extraction then begin
        if not DirExists(tcachedir) then begin
          msgConsole^.logmsg(info,'cache dir '+tcachedir+' not found; attempting to create');
          MkDirCDir(tcachedir);
          if not DirExists(tcachedir) then die('Could not create '+tcachedir);
          {burst archive into cache dir}
          screen.clear($07,' ');
          if screen.width<80
            then s:='This program requires unpacking.'
            else s:='This program requires unpacking before it can be executed.';
          screen.writeCenter(1,$0f,s);
          screen.writeCenter(2,$87,'Please wait...');
          screen.gotoxy(1,3);
          {Perform extraction.
          If extraction didn't go well, warn the user, but keep going.}
          if not Handlers^.handle(ext,filepath,tcachedir) then begin
            msgConsole^.logmsg(tdl_cons.error,'Error code received during extraction');
            PopUserMessage(warning,
              'There was an error reported while unpacking this title.  TDL will '+
              'attempt to continue.  If your progam doesn''t work, '+
              'consult tdl.log to see the exact command-line that failed, '+
              'then exit TDL and run it yourself to determine the exact error.'
            );
          end else begin
            {After successful unpack, update cache stats}
            fileCache^.Remaining;
          end;
        end;

        {If we are here, then this file was unpacked successfully}
        titleMetadata^.setFlag(tid,m_unpacked);
        titleMetadata^.changed:=true;

        {Switch to unpacked cache dir and obtain list of files we have
         registered execution handlers for.  Helper logic ensues:
           If power user, always give full list to users and let them pick.
           Otherwise:
             If only one found, execute immediately
             If multiple found but only one is exe or com, execute immediately
             Anything else, show list to users and let them pick}

        GetDir(0,WrkDir);
        chdir(tcachedir);
        s:='';
        {Power users see everything; others only see what we have handlers for.
        Power users can also sort the list if they want.  Also, power users
        can select an unknown file and it will use the "???" handler.}
        ListWin:=new(pListDirSortObj,init);
        filemasks:='';
        if config^.userlevel=power then begin
          filemasks:='*.*';
        end else begin
          {build file masks from registered executable handlers.
          Avoid the default handler.}
          for b:=0 to Handlers^.count-1 do begin
            if (PHandler(Handlers^.at(b))^.category=execution)
            and (b<>Handlers^.defaultHandler)
              then filemasks:=filemasks+'*.'+PHandler(Handlers^.at(b))^.extension+' ';
          end;
        end;
        ListWin^.settagging(false);
        with ListWin^ do begin
           {Init;}
           setTagging(false); {do not want user to "tag" files}
           {Power users can navigate directories; all others are "chrooted"}
           if config^.userlevel=power
             then ReadFiles(filemasks,AnyFile)
             else ReadFiles(filemasks,AnyFile-directory);
           if vTotPicks=0
             then msgConsole^.logMsg(warning,'No files found in '+tcachedir)
             else msgConsole^.logMsg(info,'Found '+inttostr(vTotPicks)+' files in '+tcachedir);
           {If we only have one file, launch immediately}
           {s:=vActiveDir + GetString(pred(vTopPick+vActivePick),0,0);}
           s:='';
           if (vTotPicks=1) and (config^.userlevel<>power) then begin
             s:=vActiveDir + GetString(vTopPick,0,0);
           end else begin
             if Monitor^.width<80
               then begin
                 win^.setTitle('Pick one to execute');
                 win^.getsize(x1,y1,x2,y2,style);
                 x1:=x1 div 2; x2:=x2 div 2;
                 win^.setsize(x1,y1,x2,y2,style);
               end else begin
                 win^.setTitle('Multiple components found; pick one to execute:');
               end;
             Go; {display the file picker dialog}
           end;
           if s=''
             then if (LastKey = kEsc) or (Lastkey = wClose)
               then s:='ABORTED*'
               else s:=GetHiString;
        end;
        dispose(ListWin,done);

        if s='ABORTED*' then begin
          chdir(WrkDir);
          MsgConsole^.logmsg(info,'User declined to choose a program');
          Launch:=false;
          exit; {get out of Launch()}
        end;

        {determine extension so we know which handler to use}
        filepath:=s;
        fsplit(filepath,dir,base,ext);
        delete(ext,1,1); {remove period}
        prepScreenForExec;
        {if we have an execution handler for this, use it,
        otherwise we use the default (fallback) handler}
        if Handlers^.Exists(ext)=execution
          then Handlers^.handle(ext,filepath,dir)
          else Handlers^.handle('???',filepath,dir);

        MsgConsole^.logmsg(info,'Switching back to '+WrkDir);
        chdir(WrkDir);
      end else begin
        die('Don''t know how to handle "'+ext+'" files - add to handlers.ini');
      end;
    end;
end;

procedure exportAuditLog;
var
  ol:text;
  s,ds:string;
  w:word;
  ttbuf:PTitleStruct;

  function DTString(td:datetime):string;
  begin
    DTString:=inttostr(auditLog^.Entry.StartTime.month)+'/'
             +inttostr(auditLog^.Entry.StartTime.day)+'/'
             +inttostr(auditLog^.Entry.StartTime.year)+' '
             +inttostr(auditLog^.Entry.StartTime.hour)+':'
             +inttostr(auditLog^.Entry.StartTime.min);

  end;

  function buildASCIILine(_tid:word):string;
  begin
    titles^.retrieve(_tid,ttbuf);
    buildASCIILine:=DTString(auditLog^.Entry.StartTime)+','
      +DTString(auditLog^.Entry.EndTime)+','
      +inttostr(auditLog^.Entry.minsActive)+','
      +ttbuf^.title;
  end;

begin
  assign(ol,'audit.csv');
  rewrite(ol);
  writeln('Start Time,End Time,Minutes Active,Title');

  auditLog^.getFirst;
  writeln(ol,buildASCIILine(auditLog^.Entry.titleID));
  for w:=1 to auditLog^.totalEntries-1 do begin
    auditLog^.getNext;
    writeln(ol,buildASCIILine(auditLog^.Entry.titleID));
  end;
  close(ol);
end;

procedure TDL_EventLoop;
{
Picker draw logic:
  sliding window always shows where picker cursor (pcursor) is
  sliding window only moves if pcursor moves
  if pgup/dn, window slides by one unit, leaving pcursor in same place
  home/end do exactly that, with pcursor at top and bottom of list
  Don't repaint entire list if you don't have to!  Think of the snowy CGAs!
  (I swear to $DEITY I'm going to be the last human alive to remeber CGA snow)
}
const
  iconsPad=1+numMetaFlags;                 {padding on left edge for icons}
  escapeKey:word=kEsc;
  clearBlank:boolean=false;

label
  nofavorites;

var
  w,dl:word;
  b:byte;
  s:string;
  a:array[0..15] of string;
  ch:char;
  p:pointer;
  tid:word;
  iconPosX,iconPosY:byte;

  bsl,bsr,bsm:longint;
  bsch:char;

  ttbuf:PTitleStruct;
  pcursor,opcursor:longint;             {picker cursor location(s)}
  pwheight:byte;                        {picker window height}
  pwwidth:word;                         {picker window width}
  pwinloc,opwinloc:longint;             {picker window location(s)}

  procedure updateStatusBar;
  const
    negofs=11;
  var
    s2:string;
  begin
    s2:='#'+intPadded(pcursor,5,'0')
       +'/'+intpadded(titleSets[activeSet]^.numTitles-1,5,'0');
    screen.WriteAT(screen.width-negofs,screen.depth,
      LookTOT^.vMenuHiNorm,s2);
  end;

  procedure showStatus(on:boolean;s:string);
  var
    b:byte;
  begin
    b:=LookTOT^.vMenuLoNorm AND $F0;
    b:=b OR (b SHR 4);
    if on
      then screen.writeat(jcloc.x+3,jcloc.y,LookTOT^.vMenuLoNorm OR $80,s)
      else screen.writeat(jcloc.x+3,jcloc.y,b,s);
  end;

begin
  {check for short-circuit operations here and avoid the entire event loop
  if we are doing a one-off operation}

  {export the audit log?}
  if config^.wantAuditExport then begin
    PopUserMessage(info,' Hit ENTER to export audit log to AUDIT.CSV ');
    exportAuditLog;
    exit;
  end;

  if config^.userlevel=kiosk
    then escapeKey:=kAltMinus;
  with config^.tpos do Screen.Box(X1,Y1,X2,Y2,LookTOT^.vMenuLoNorm,4);
  pcursor:=0; pwinloc:=0;
  pwwidth:=config^.tpos.x2 - config^.tpos.x1 - (iconsPad+1); {leave room for icon columns}
  p:=@s;
  updateStatusBar;
  opwinloc:=pwinloc+1;
  opcursor:=pcursor+1;
  repeat
    {msgConsole^.logmsg(info,'Refreshing display');}

    {update vertical scrollbar}
    with config^.tpos do
      screen.WriteVScrollBar(X2,Y1,Y2,LookTOT^.vMenuLoNorm,pcursor+1,titleSets[activeSet]^.numTitles);

    {determine height of our drawloop}
    pwheight:=config^.tpos.y2-config^.tpos.y1-1;
    {if we have less titles than screen lines, truncate}
    if pwheight>titleSets[activeSet]^.numTitles
      then begin
        pwheight:=titleSets[activeSet]^.numTitles;
        {Clear the part of the display that will never get updated.
        We only need to do this once, so keep track if we've done it.
        Otherwise, 8088 systems will suffer}
        if clearblank then begin
          with config^.tpos do
            screen.partclear(x1+iconspad-numMetaFlags,y1+pwheight+1,x2-1,y2-1,LookTOT^.vMenuLoNorm,#0);
          clearblank:=false;
        end;
      end;

    {draw our choices}
    for dl:=0 to pwheight-1 do begin
      {If we're not scrolling, we don't need to repaint the entire screen.
      Only repaint the changed lines.}
      if (opwinloc=pwinloc)
        then if not (abs((pwinloc+dl)-pcursor) in [0..1])
          then continue;
      tid:=titleSets[activeSet]^.titleIDs^[pwinloc+dl];
      if not titles^.retrieve(tid,ttbuf)
        then die('Could not retrieve title: '+inttostr(tid));
      s:=ttbuf^.title;
      b:=byte(s[0]);
      byte(s[0]):=pwwidth;              {clamp to window width}
      if b<pwwidth
        then strPadAfter(s,b);          {pad to window width}
      {determine when to use highlight color}
      if pwinloc+dl=pcursor {this is where the menu bar is}
        then b:=LookTOT^.vMenuHiNorm
        else b:=LookTOT^.vMenuLoNorm;
      {Now draw the title line in the picker:}
      with config^.tpos do begin
        screen.writeat(x1+iconsPad+1,y1+dl+1,b,s);
        iconPosX:=x1+iconspad;
        iconPosY:=y1+dl+1;
        {Is this title a favorite?  If so, print the "favorite" icon}
        if titleMetadata^.getFlag(tid,m_favorite)
          then screen.writeat(iconPosx,iconPosY,faviconcol,favicon)
          else screen.writeat(iconPosx,iconPosY,LookTOT^.vMenuLoNorm,' ');
        {Has this title been unpacked already?}
        dec(iconPosX);
        if titleMetadata^.getFlag(tid,m_unpacked)
          then screen.writeat(iconPosx,iconPosY,unpiconcol,unpicon)
          else screen.writeat(iconPosx,iconPosY,LookTOT^.vMenuLoNorm,' ');
      end;
    end;
    {msgConsole^.logmsg(info,'Getting input');}
    key.getinput;

    opwinloc:=pwinloc;
    opcursor:=pcursor;

    {handle cursor movement}
    case key.lastkey of
      kUp:begin
        dec(pcursor);
        if pcursor<pwinloc then dec(pwinloc);
      end;
      kDown:begin
        inc(pcursor);
        if pcursor>pwinloc+pwheight-1 then inc(pwinloc);
      end;
      kPgUp:begin
        dec(pcursor,pwheight);
        dec(pwinloc,pwheight);
        opwinloc:=-1;                   {force a window refresh}
      end;
      kPgDn:begin
        inc(pcursor,pwheight);
        inc(pwinloc,pwheight);
        opwinloc:=-1;                   {force a window refresh}
      end;
      kHome:begin
        pcursor:=0;                     {re-home picker cursor}
        pwinloc:=0;                     {re-home sliding window}
        opwinloc:=-1;                   {force a window refresh}
      end;
      kEnd:begin
        pcursor:=titleSets[activeSet]^.numTitles-1; {point to last title}
        pwinloc:=pcursor;               {this will get clamped later}
        opwinloc:=-1;                   {force a window refresh}
      end;
      ord('0')..ord('9'),
      ord('A')..ord('Z'),
      ord('a')..ord('z'):begin
        {Crude "search by letter" until we implement actual search-as-you-type}
        ch:=upcase(chr(key.lastkey));
        screen.writeat(jcloc.x,jcloc.y,LookTOT^.vMenuLoHot,ch);
        {showStatus(true,'Seeking, please wait'); not necessary with binary search}

        (* Slow, linear search
        for w:=0 to titleSets[activeSet].numTitles-1 do begin
          {check first character only}
          if upcase(titles^.retrieve1c(titleSets[activeSet].titleIDs^[w]))=ch then begin
            pcursor:=w;
            pwinloc:=w;
            opwinloc:=-1;               {force window refresh}
            break;
          end;
        end;
        *)

        {Binary search:}
        bsl:=0; bsr:=titleSets[activeSet]^.numTitles-1; bsm:=bsr shr 1;
        while bsl<=bsr do begin
          bsm:=(bsl+bsr) shr 1;
          bsch:=upcase(titles^.retrieve1c(titleSets[activeSet]^.titleIDs^[bsm]));
          if bsch<ch
            then bsl:=bsm+1
            else bsr:=bsm-1;
        end;
        {The above code was written to handle duplicates, but can land on N-1.
        To fix this, we check if that happened and adjust:}
        if (bsch<ch) and (bsm<titleSets[activeSet]^.numTitles-1)
          then inc(bsm);

        pcursor:=bsm;
        pwinloc:=bsm;
        opwinloc:=-1;               {force window refresh}

        {showStatus(false,'Seeking, please wait'); not necessary with binary search}
      end;
      kF2:begin {Toggle favorite for where the picker cursor is on}
        with titleMetadata^ do begin
          {get the real full title id we are sitting on}
          w:=titlesets[activeSet]^.TitleIDs^[pcursor];
          toggleFlag(w,m_favorite);
          changed:=true;
          (* if not metaFlags^[w] then opwinloc:=-1 {force window refresh} *)
          if not getFlag(w,m_favorite) then opwinloc:=-1 {force window refresh if not set (why are we doing this again??)}
        end;
      end;
      kCtlF:begin
        {code isn't yet flexible enough to deal with multiple filters}
        if unpackedOn then continue;
        if not favson then begin
          {build a new title set out of just the favorites}
          {find how many favorites there are}
          w:=titleMetadata^.countFlag(m_favorite);
          {no favorites?  Get out of here}
          if w=0
            then continue;
          {build new title set}
          inc(activeSet);
          titleSets[activeSet]:=New(PTitleSet,init(w));
          {populate new title set}
          w:=0;
          {we use "with" to preload addressing to the existing larger titleset, as each of its elements will be iterated}
          with titleSets[activeSet-1]^ do begin
            for dl:=0 to numTitles-1 do begin
              {intentionally not using getFlag() here because we need the speed}
              if (titleMetadata^.metaFlags^[TitleIDs^[dl]] AND m_favorite)=m_favorite then begin
                titleSets[activeSet]^.TitleIDs^[w]:=dl;
                inc(w);
              end;
            end;
          end;
          clearBlank:=true;
        end else begin
          {discard our favorites titleset}
          dispose(titleSets[activeSet],done);
          titleSets[activeSet]:=nil;
          dec(activeSet);
        end;
        pcursor:=0;
        pwinloc:=0;
        opwinloc:=-1;                   {force a window refresh}
        favson:=not favson;             {toggle "favorites on" status}
nofavorites:
      end;
      {this is a modified copy of the above; can they be combined without side effects?}
      kCtlU:begin
        {code isn't yet flexible enough to deal with multiple filters}
        if favsOn then continue;
        if not unpackedOn then begin
          {build a new title set out of just the favorites}
          {find how many favorites there are}
          w:=titleMetadata^.countFlag(m_unpacked);
          {nothing unpacked?  Get out of here}
          if w=0
            then continue;
          {build new title set}
          inc(activeSet);
          titleSets[activeSet]:=New(PTitleSet,init(w));
          {populate new title set}
          w:=0;
          {we use "with" to preload addressing to the existing larger titleset, as each of its elements will be iterated}
          with titleSets[activeSet-1]^ do begin
            for dl:=0 to numTitles-1 do begin
              {intentionally not using getFlag() here because we need the speed}
              if (titleMetadata^.metaFlags^[TitleIDs^[dl]] AND m_unpacked)=m_unpacked then begin
                titleSets[activeSet]^.TitleIDs^[w]:=dl;
                inc(w);
              end;
            end;
          end;
          clearBlank:=true;
        end else begin
          {discard our unpacked titleset}
          dispose(titleSets[activeSet],done);
          titleSets[activeSet]:=nil;
          dec(activeSet);
        end;
        pcursor:=0;
        pwinloc:=0;
        opwinloc:=-1;                   {force a window refresh}
        unpackedOn:=not unpackedOn;     {toggle "unpacked on" status}
      end;
      kEnter:begin {LAUNCH!}
        recordKeyState;
        tmpScreenSave;
        showStatus(true,'Preparing for launch...');
        if config^.auditing
          then auditLog^.newEntry(titleSets[activeSet]^.titleids^[pcursor]);
        {Launch it!  If launch was successful, clean up:}
        if Launch(titleSets[activeSet]^.titleids^[pcursor]) then begin
          if config^.pauseAfterRun then pauseForUser;
          RestoreDOSScreen;
          {if we have any goofy modes set, restore them}
          if config^.customVidMode<>0 then begin
            case config^.customVidMode of
              3:Monitor^.SetCondensed;
              $100..$110:setVESA(config^.customVidMode);
            end;
          end;
        end;
        if config^.auditing
          then auditLog^.closeEntry;
        tmpScreenRestore;
        restoreKeyState;
      end;
      kCtlF3:begin {show debug console}
        MsgConsole^.show;
        pause;
        MsgConsole^.hide;
      end;
      kF10:begin {show About This Program window}
        recordKeyState;
        popAbout;
        restoreKeyState;
      end;
      kF9:begin {show program info dialog}
        recordKeyState;
        popGeneralInfo;
        restoreKeyState;
      end;
      kCtlI:begin {show title info dialog}
        recordKeyState;
        popTitleInfo(titleSets[activeSet]^.titleids^[pcursor]);
        restoreKeyState;
      end;
      kF1:begin {show help screen}
        recordKeyState;
        tmpScreenSave;
        popHelp;
        tmpScreenRestore;
        restoreKeyState;
      end;
      kAltF5:begin {show DOS screen}
        tmpScreenSave;
        DOSScreen^.display;
        pause;
        tmpScreenRestore;
      end;
    else
      begin
      end;
    end;
    {adjust/clamp cursor and sliding window movement}
    {msgConsole^.logmsg(info,'Adjusting picker window vars');}
    if pcursor<0 then pcursor:=0;
    if pcursor>=titleSets[activeSet]^.numTitles
      then pcursor:=titleSets[activeSet]^.numTitles-1;
    if pwinloc<0 then pwinloc:=0;
    if pwinloc+pwheight>titleSets[activeSet]^.numTitles-1
      then begin
        pwinloc:=titleSets[activeSet]^.numTitles;
        pwinloc:=pwinloc-pwheight;
        if pwinloc<0 then pwinloc:=0;
      end;

    {msgConsole^.logmsg(info,'Updating status line');}
    updateStatusBar;
  until key.lastkey=escapeKey;
  {msgConsole^.logmsg(info,'Exiting picker loop');}
end;

procedure TDL_Done;
{
Close TDL down gracefully so we can check for programming errors
}
var
  w:word;
  s,s2:string;
  b:byte;
begin
  titleMetadata^.flush;
  dispose(titleMetadata,done);
  {free message console}
  dispose(MsgConsole,done);

  {free any working title sets}
  for w:=maxTitleSets-1 downto 0 do
    if titleSets[w]<>nil
      then if titleSets[w]^.TitleIDs<>nil
        then dispose(titleSets[w],done);

  s:=config^.startupDir; {grab startup dir before we trash object}

  if config^.auditing then dispose(auditLog,done);
  dispose(files,done);
  dispose(titles,done);
  dispose(handlers,done);
  dispose(fileCache,done);
  dispose(config,done);
  dispose(DOSScreen,done);
  tmpScreenRestore; {this will also deallocate it}
  RestoreDOSScreen;

  writeln('Exiting '+TDLtitleFull);
  writeln('Have a nice DOS!');

  {$IFDEF FINAL}
  {Switch back to the directory we started from. Massage path into a form
  that works with CHDIR. If raw drive, preserve slash so that CHDIR does
  what we want if the user called TDL from the root dir of any drive.}
  if length(s)<>3 then dec(byte(s[0]));
  CHDIR(s);
  {$ENDIF}
end;

end.
