program tdl;
{$I tdl_dire.inc}

{
Total DOS Launcher, main program.
Initial author Jim Leonard, started 20170211

To-Do:
favorites export/import
screensaver (figure out how totinput does idle events)
Info screen
Search-as-you-type
Cache management strategy.  Move all cache management into unit so we can:
  come up with cache purge strategy.
  strategy can be limited to 5 dirs for testing and then avail disk space for final
  strategy should determine exact amount of storage needed from archive header but can estimate 4*archive size 4now
Power user file picker:  Delete a file from cache dir
Power user title picker: Delete a title (will need to remove cache dir, file, and rewrite indexes)
Power user title picker: Command key to switch to cache dir and then exit the program
Power user title picker: Abillity to rewrite a title
Ability to track what titles have been executed, how many times, and top20
}

uses
  {$IFDEF USEOVERLAYS}
  tdl_over, {must be first in uses clause}
  {$ENDIF}
  DOS,
  support,
  strings,
  cmdlin,
  totFAST,
  totSYS,
  totINPUT,
  totLOOK,
  totLIST,
  totKEY,
  tdl_glob,
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

{$ENDIF}


const
  maxTitleSets=16;
  activeSet:byte=0;
  favIconCol:byte=$0f;
  favsOn:boolean=false;

type
  workingTitleSet=record
    numTitles:word;
    TitleIDs:PTitleArray;
  end;

  txtcoords=record
    x,y:byte;
  end;

var
  _memavail:longint;
  Files:PFileIndex;
  Titles:PTitleIndex;
  titleSets:array[0..maxTitleSets-1] of workingTitleSet;
  jcloc:txtcoords; {jumpcursor location}
  Favorites:PFavorites;

procedure StrPadAfter(var str:OpenString;b:byte); assembler;
{Pads a string with nulls after position b}
asm
        les     di,str                  {get location of temp string}
        xor     ax,ax
        mov     al,b                    {al=position to start nulling}
        xor     cx,cx
        mov     cl,es:[di]              {cx=length of string}
        sub     cx,ax                   {cx=how many nulls to write}
        inc     ax
        add     di,ax                   {es:di=starting point for nulls}
        xor     ax,ax
        shr     cx,1
        rep     stosw
        adc     cx,0
        rep     stosb
end;

Procedure PrintHelp;
begin
  asm
    jmp @start
@message:
    db 0ah,'Usage: TDL.EXE <switches>',0dh,0ah,0ah

    db 'Switches:',0dh,0ah
    db '-?, -h  This help',0dh,0ah
    db '-c      Set 43-line (EGA) or 50-line (VGA) mode.',0dh,0ah
    db '        (If you need more lines than that, see TDL.INI for VESA options.)',0dh,0ah
    db '-r      Instructs TDL that it is on read-only media (ie. CDROM or DVDROM)',0dh,0ah
    db '        and that it should not try to write anything to its local filesystem.',0dh,0ah
    db '        This disables "favorites" as well as writing the debug log to disk.',0dh,0ah
    db '-d      Print excessive debugging messages during initialization.',0dh,0ah
    db '        Used for troubleshooting only.',0dh,0ah
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

procedure TDL_Init;
{
Initialize TDL, first with defaults and the refine using the config file.
TDL never changes the initial video mode when initializing, so that
error and status messages are always visible.
}
var
  sf,sd,temps:string;
  w:word;
begin
  {If user requested help, then print it and exit}
  if is_param('?') or is_param('h') then PrintHelp;

  RecordDOSScreen;

  {determine TDL base directory and configuration file to use}
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

  {attempt TDL handlers init}
  writeln('Registering handlers from handlers.ini...');
  Handlers:=new(PHandlers,init(sd+'handlers.ini'));
  {We can only show files properly for up to 42 filemasks.  If we have
  more handlers than that, switch to power user mode so that we only have
  to use one mask (*.*).}
  if Handlers^.Count>42 then config^.userlevel:=power;
  {attempt initializing indexes}
  writeln('Initializing files index...');
  files:=new(PFileIndex,
         init(config^.baseDir+config^.filesIDXname,config^.preloading));
  if files=nil then fatalerror(1,'Files index init failed');
  writeln('Initializing titles index...');
  titles:=new(PTitleIndex,
          init(config^.baseDir+config^.titlesIDXname,config^.preloading));
  if titles=nil then fatalerror(1,'Titles index init failed');

  write('Title flags cache: ');
  temps:=sd+'\'+'cache.dat';
  if config^.readonly then begin
    writeln('Read-only mode: Cache disabled');
    favorites:=new(PFavorites,init('',config^.numTitles));
  end else begin
    writeln('Initializing cache using '+temps);
    favorites:=new(PFavorites,init(temps,config^.numTitles));
  end;

  if (config^.userlevel=power) or (config^.edebug=true) then begin
    writeln('Performing additional checks:');
    with config^ do begin
      {power users like to ensure they copied the stuff over correctly}
      write('Index locations: ');
      write(filesIDXloc);
      writeln(' ',titlesIDXloc);
      write('Checking index files for correctness: ');
      write('files... ');
      if files^.verify=false
        then fatalerror(1,'File index inconsistent');
      write('titles... ');
      if titles^.verify=false
        then fatalerror(1,'Title index inconsistent');
      writeln('passed.');

      {power users want to know everything}
      writeln('Number of titles: ',numTitles);
      writeln('Base directory: ',baseDir);
      writeln('Swapping enabled: ',swapping);
      writeln('Preloading enabled: ',preloading);
      writeln('Cache Directory: ',cacheDir);
    end;
  end;

  {populate the initial list of titles we're working with}
  with titleSets[activeSet] do begin
    numTitles:=config^.numTitles;
    getmem(TitleIDs,numTitles*2);
    for w:=0 to numTitles-1 do titleIDs^[w]:=w;
  end;


  {set up the screen}

  {If changing screen mode, we need to re-enable the screen. construct to
  pick up the new dimensions.}
  if is_param('c') then begin
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
    end else begin
      LookTOT^.SetMenu($0F,$09,$78,$78,$70,$01,$07,$07);
    end;

  DOSScreen:=new(PScreenObj,init);
  DOSScreen^.save;
  with config^ do begin
    tpos.y2:=screen.depth-1;
    tpos.x2:=screen.width;
    screen.clear(LookTOT^.vMenuBorder,#0);
    {screen.PartClear(1,1,screen.width,3,LookTOT^.vMenuHiHot.pickern,' ');}
    screen.WriteCenter(1,LookTOT^.vMenuTitle,TDLTitle);
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
    if boolean(snowprone)
      then MsgConsole^.logmsg(info,'Slower display routines enabled to avoid CGA "snow"');
  end;

  {power users want to know everything}
  with MsgConsole^ do begin
    with config^ do begin
      logmsg(info,'Number of titles: '+inttostr(numTitles));
      logmsg(info,'Base directory: '+baseDir);
      logmsg(info,'Swapping enabled: '+boolToStr(swapping));
      logmsg(info,'Preloading enabled: '+boolToStr(preloading));
      logmsg(info,'Cache Directory: '+cacheDir);
    end;
  end;
end;

procedure Launch(tid:word);
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
  tcachedir:PathStr;                    {title cache directory}
  filepath:PathStr;                     {fully-qualified path to source file}

  tfbuf:PFileStruct;
  ttbuf:PTitleStruct;

  ListWin:pListDirSortObj;
  x1,y1,x2,y2,style:byte;

  s,filemasks:string;
  b:byte;
  p:pointer;

  procedure prepExec;
  begin
    screen.clear($07,' ');
    screen.writeCenter(1,$0f,'Executing:');
    screen.writeCenter(2,$07,filepath);
    screen.gotoxy(1,3);
  end;

begin
  msgConsole^.logmsg(info,'Attempting to Launch title #'+inttostr(titleSets[activeSet].titleids^[tid])+':');
  if favorites^.changed then begin
    msgConsole^.logmsg(info,'Flushing favorites cache');
    favorites^.flush;
  end;
  {grab title so that we can determine the id needed for file}
  titles^.retrieve(tid,ttbuf);
  msgConsole^.logmsg(info, ttbuf^.title);
  {determine cache directory}
  if not files^.retrieve(tid,tfbuf)
      then die('Could not retrieve file info');
  if tfbuf^.id<>tid then die('Wrong file retrieved');
  {extract basename and fullname}
  base:='';
  for b:=0 to 7 do
    if tfbuf^.name[b]='.'
      then break
      else base:=base+tfbuf^.name[b];
  full:='';
  for b:=0 to 11 do
    if tfbuf^.name[b]<>#0
      then full:=full+tfbuf^.name[b]
      else break;
  {determine our operating environment}
  tcachedir:=config^.cachedir+base;
  {files can be in multiple drives/paths; find where we put our file}
  filepath:=fsearch(full,config^.ProgLocs);
  if filepath='' then begin
    popUserMessage(error,'PATH "'+config^.ProgLocs+'" did not contain "'+full+'".  Did you delete it?');
    exit;
  end;
  {determine extension so we know which handler to use}
  fsplit(filepath,dir,base,ext);
  delete(ext,1,1); {remove period}
  {Is the file directly launchable?  (ie. .txt, .gif, etc.)
  If so, launch it; if not, it is an archive that needs extraction.}
  if Handlers^.Exists(ext)=execution
    then begin
      prepExec;
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
          if not Handlers^.handle(ext,filepath,tcachedir)
            then die('Failed to extract '+filepath+' to '+tcachedir);
        end;

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
          exit; {get out of Launch()}
        end;

        {determine extension so we know which handler to use}
        filepath:=s;
        fsplit(filepath,dir,base,ext);
        delete(ext,1,1); {remove period}
        prepExec;
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

procedure TDL_EventLoop;
{
Picker draw logic:
  sliding window always shows where picker cursor (pcursor) is
  sliding window only moves if pcursor moves
  if pgup/dn, window slides by one unit, leaving pcursor in same place
  home/end do exactly that, with pcursor at top and bottom of list
  Don't repaint entire list if you don't have to!  Think of snowy 8088s!
}
const
  iconsPad=2;                           {padding on left edge for icons}
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

  bsl,bsr,bsm:integer;
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
       +'/'+intpadded(titleSets[activeSet].numTitles-1,5,'0');
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
  if config^.userlevel=kiosk
    then escapeKey:=kAltMinus;
  with config^.tpos do Screen.Box(X1,Y1,X2,Y2,LookTOT^.vMenuLoNorm,4);
  pcursor:=0; pwinloc:=0;
  pwwidth:=config^.tpos.x2-config^.tpos.x1-iconsPad-iconsPad+1; {leave room for icon column}
  p:=@s;
  updateStatusBar;
  opwinloc:=pwinloc+1;
  opcursor:=pcursor+1;
  repeat
    {msgConsole^.logmsg(info,'Refreshing display');}
    (*{update vertical scrollbar}
    with config^.tpos do
      screen.WriteVScrollBar(X2,Y1,Y2,config^.colors.pickern,pcursor+1,titleSets[activeSet].numTitles);*)

    {determine height of our drawloop}
    pwheight:=config^.tpos.y2-config^.tpos.y1-1;
    {if we have less titles than screen lines, truncate}
    if pwheight>titleSets[activeSet].numTitles
      then begin
        pwheight:=titleSets[activeSet].numTitles;
        {Clear the part of the display that will never get updated.
        We only need to do this once, so keep track if we've done it.
        Otherwise, 8088 systems will suffer}
        if clearblank then begin
          with config^.tpos do
            screen.partclear(x1+iconspad-1,y1+pwheight+1,x2-1,y2-1,LookTOT^.vMenuLoNorm,#0);
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
      tid:=titleSets[activeSet].titleIDs^[pwinloc+dl];
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
      with config^.tpos do begin
        screen.writeat(x1+iconsPad,y1+dl+1,b,s);
        if favorites^.userChoices^[tid]
          then screen.writeat(x1+iconspad-1,y1+dl+1,faviconcol,favicon)
          else screen.writeat(x1+iconspad-1,y1+dl+1,LookTOT^.vMenuLoNorm,' ')
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
        pcursor:=titleSets[activeSet].numTitles-1; {point to last title}
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
        bsl:=0; bsr:=titleSets[activeSet].numTitles-1; bsm:=bsr shr 1;
        while bsl<=bsr do begin
          bsm:=(bsl+bsr) shr 1;
          bsch:=upcase(titles^.retrieve1c(titleSets[activeSet].titleIDs^[bsm]));
          if bsch<ch
            then bsl:=bsm+1
            else bsr:=bsm-1;
        end;
        {The above code was written to handle duplicates, but can land on N-1.
        To fix this, we check if that happened and adjust:}
        if (bsch<ch) and (bsm<titleSets[activeSet].numTitles-1)
          then inc(bsm);

        pcursor:=bsm;
        pwinloc:=bsm;
        opwinloc:=-1;               {force window refresh}

        {showStatus(false,'Seeking, please wait'); not necessary with binary search}
      end;
      kF2:begin {Toggle favorite for where the picker cursor is on}
        with favorites^ do begin
          {get the real full title id we are sitting on}
          w:=titlesets[activeSet].TitleIDs^[pcursor];
          userChoices^[w] := not userChoices^[w];
          changed:=true;
          if not userChoices^[w] then opwinloc:=-1 {force window refresh}
        end;
      end;
      kCtlF:begin
        if not favson then begin
          {build a new title set out of just the favorites}
          {find how many favorites there are}
          w:=0;
          for dl:=0 to titleSets[activeSet].numTitles-1 do begin
            with favorites^ do begin
              if userChoices^[dl] then inc(w);
            end;
          end;
          {no favorites?  Get out of here}
          if w=0
            then goto nofavorites; {yes, not pure pascal-elegant. So sue me.}
          {build new title set}
          inc(activeSet);
          with titleSets[activeSet] do begin
            numTitles:=w;
            getmem(TitleIDs,numTitles*2);
          end;
          {populate new title set}
          w:=0;
          with titleSets[activeSet-1] do begin
            for dl:=0 to numTitles-1 do begin
              if Favorites^.userChoices^[TitleIDs^[dl]]
                then begin
                  titleSets[activeSet].TitleIDs^[w]:=dl;
                  inc(w);
                end;
            end;
          end;
          clearBlank:=true;
        end else begin
          {discard our favorites titleset}
          with titleSets[activeSet] do begin
            freemem(TitleIDs,numTitles*2);
            numTitles:=0;
          end;
          titleSets[activeSet].TitleIDs:=nil;
          dec(activeSet);
        end;
        pcursor:=0;
        pwinloc:=0;
        opwinloc:=-1;                   {force a window refresh}
        favson:=not favson;             {toggle "favorites on" status}
nofavorites:
      end;
      kEnter:begin {LAUNCH!}
        recordKeyState;
        tmpScreenSave;
        showStatus(true,'Preparing for launch...');
        Launch(titleSets[activeSet].titleids^[pcursor]);
        RestoreDOSScreen;
        {showStatus(false,'Preparing for launch...');}
        {if we have any goofy modes set, restore them}
        if config^.customVidMode<>0 then begin
          case config^.customVidMode of
            3:Monitor^.SetCondensed;
            $100..$110:setVESA(config^.customVidMode);
          end;
        end;
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
    if pcursor>=titleSets[activeSet].numTitles
      then pcursor:=titleSets[activeSet].numTitles-1;
    if pwinloc<0 then pwinloc:=0;
    if pwinloc+pwheight>titleSets[activeSet].numTitles-1
      then begin
        pwinloc:=titleSets[activeSet].numTitles;
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
begin
  Favorites^.flush;
  dispose(Favorites,done);
  {free message console}
  dispose(MsgConsole,done);

  {free any working title sets }
  for w:=maxTitleSets-1 downto 0 do
    if titleSets[w].TitleIDs<>nil
      then freemem(titleSets[w].TitleIDs,titleSets[w].numTitles*2);

  dispose(files,done);
  dispose(titles,done);
  dispose(handlers,done);
  dispose(config,done);
  dispose(DOSScreen,done);
  tmpScreenRestore; {this will also deallocate it}
  RestoreDOSScreen;

  writeln('Exiting '+TDLtitleFull);
  writeln('Have a nice DOS!');
end;

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
