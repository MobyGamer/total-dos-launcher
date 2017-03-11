program tdl;

{$I tdl_directives.inc}

{
Total DOS Launcher, main program.
Initial author Jim Leonard, started 20170211

todo:
power user file picker, show everything but only highlight files that can be handled
command key in title picker to extract/switch to cache dir and then exit the program
move all cache management into unit, so that we can:
 come up with cache purge strategy.
 strategy can be limited to 5 dirs for testing and then avail disk space for final
 strategy should determine exact amount of storage needed from archive header but can estimate 4*archive size 4now
}

uses
  {$IFDEF USEOVERLAYS}
  tdl_overlay, {must be first in uses clause}
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
  tdl_global,
  tdl_config,
  tdl_index,
  tdl_console,
  tdl_handlers;

{$IFDEF USEOVERLAYS}
  {Note: documentation discourages overlaying TOTSYS, TOTINPUT, and TOTFAST}
  {{$O totDATE}
  {{$O totDIR}
  {$O totFAST}
  {$O totINPUT}
  {$O totINPUT}
  {$O totIO1}
  {{$O totIO2}
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

  {$O tdl_config}
  {$O tdl_console}
  {$O tdl_handlers}

{$ENDIF}


const
  maxSearchTerms=8;
  activeSet:byte=0;

type
  workingTitleSet=record
    numTitles:word;
    TitleIDs:PTitleArray;
  end;

var
  _memavail:longint;
  Files:PFileIndex;
  Titles:PTitleIndex;
  titleSets:array[0..maxSearchTerms-1] of workingTitleSet;

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

procedure TDL_Init;
{
Initialize TDL, first with defaults and the refine using the config file.
TDL never changes the initial video mode when initializing, so that
error and status messages are always visible.
}
var
  sf,sd:string;
  w:word;
begin
  RecordDOSScreen;

  writeln('Configuring '+TDLtitle);

  {determine TDL base directory and configuration file to use}
  if paramcount>0 then sf:=paramstr(1) else sf:='tdl.ini';
  if paramcount>1 then sd:=paramstr(2) else sd:='';
  sd:=StdPath(FExpand(sd));
  {attempt TDL config init}
  config:=new(pconfig,init(sf,sd));
  if config=nil
    then fatalerror(1,'Error while configuring; check '+sd+'\'+sf);
  {attempt TDL handlers init}
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

  if config^.userlevel=power then begin
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
    {reset mouse and screen so that they pick up new dimensions}
    Mouse.done;
    Mouse.init;
    fastDone;
    fastInit;
  end;

  DOSScreen:=new(PScreenObj,init);
  DOSScreen^.save;
  with config^ do begin
    tpos.y2:=screen.depth-1;
    tpos.x2:=screen.width;
    screen.clear(colors.background,#176);
    screen.PartClear(1,1,screen.width,3,colors.pickern,' ');
    screen.WriteCenter(1,colors.pickerh,TDLTitle);
    screen.WriteAt(1,tpos.y1-2,colors.pickern,'Jump by letter: '); screen.gotoxy(17,tpos.y1-2);
    screen.WriteAt(1,tpos.y1-1,colors.pickern,'Or, choose from the following programs:');

    {status bar}
    screen.PartClear(1,screen.depth,screen.width,screen.depth,
      LookTOT^.vMenuLoNorm,' ');
    screen.WriteHI(1,screen.depth,
      LookTOT^.vMenuLoHot,LookTOT^.vMenuLoNorm,TDLStatus);

    {init message console now that we have our screen mode locked in}
    MsgConsole:=new(PMConsole,init(config^.basedir+'tdl.log'));
    if (userlevel=power) or (logging=true) then begin
      MsgConsole^.verboseLog:=true;
      MsgConsole^.logmsg(info,'Avoiding CGA Snow: '+booltostr(boolean(snowprone)));
    end;
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

  s,filemasks:string;
  b:byte;
  p:pointer;

  procedure prepExec;
  begin
    screen.clear($07,' ');
    screen.writeCenter(1,$0f,'Executing: '+filepath);
    screen.gotoxy(1,2);
  end;

begin
  msgConsole^.logmsg(info,'Attempting to Launch title #'+inttostr(titleSets[activeSet].titleids^[tid])+':');
  titles^.retrieve(titleSets[activeSet].titleIDs^[tid],ttbuf);
  msgConsole^.logmsg(info, ttbuf^.title);
  {determine cache directory}
  if not files^.retrieve(titleSets[activeSet].titleIDs^[tid],tfbuf)
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
  if filepath='' then die('Could not find '+full+' in '+config^.ProgLocs);
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
          screen.writeCenter(1,$0f,'This program requires unpacking before it can be executed.');
          screen.writeCenter(2,$07,'Starting unpacking, please wait...');
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
             win^.setTitle('Multiple components found; pick one to execute:');
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

var
  w,dl:word;
  b:byte;
  s:string;
  a:array[0..15] of string;
  ch:char;
  p:pointer;
  tid:word;

  ttbuf:PTitleStruct;
  pcursor,opcursor:longint;             {picker cursor location(s)}
  pwheight:byte;                        {picker window height}
  pwwidth:word;                         {picker window width}
  pwinloc,opwinloc:longint;             {picker window location(s)}

  procedure updateStatus;
  const
    negofs=11;
  var
    s2:string;
  begin
    s2:='#'+intPadded(pcursor,5,'0')
       +'/'+intpadded(titleSets[activeSet].numTitles-1,5,'0');
    screen.WriteAT(screen.width-negofs,screen.depth,
      LookTOT^.vMenuLoHot,s2);
  end;

begin
  if config^.userlevel=kiosk
    then escapeKey:=kAltMinus;
  with config^.tpos do Screen.Box(X1,Y1,X2,Y2,config^.colors.pickern,4);
  pcursor:=0; pwinloc:=0;
  pwheight:=config^.tpos.y2-config^.tpos.y1-1;
  {if we have less titles than screen lines, truncate}
  if pwheight>titleSets[activeSet].numTitles
    then pwheight:=titleSets[activeSet].numTitles;
  pwwidth:=config^.tpos.x2-config^.tpos.x1-iconsPad-iconsPad+1; {leave room for icon column}
  p:=@s;
  updateStatus;
  opwinloc:=pwinloc+1;
  opcursor:=pcursor+1;
  repeat
    {msgConsole^.logmsg(info,'Refreshing display');}
    (*{update vertical scrollbar}
    with config^.tpos do
      screen.WriteVScrollBar(X2,Y1,Y2,config^.colors.pickern,pcursor+1,titleSets[activeSet].numTitles);*)

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
      if pwinloc+dl=pcursor
        then b:=config^.colors.pickerh
        else b:=config^.colors.pickern;
      with config^.tpos do screen.writeat(x1+iconsPad,y1+dl+1,b,s);
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
        {Crude "search by letter" until we implement actual searching}
        ch:=upcase(chr(key.lastkey));
        for w:=0 to titleSets[activeSet].numTitles-1 do begin
          titles^.retrieve(titleSets[activeSet].titleIDs^[w],ttbuf);
          if upcase(ttbuf^.title[1])=ch then begin
            pcursor:=w;
            pwinloc:=w;
            opwinloc:=-1;               {force window refresh}
            break;
          end;
        end;
      end;
      kEnter:begin
        recordKeyState;
        tmpScreenSave;
        Launch(titleSets[activeSet].titleids^[pcursor]);
        tmpScreenRestore;
        restoreKeyState;
      end;
      kCtlF3:begin {show debug console}
        MsgConsole^.show;
        pause;
        MsgConsole^.hide;
      end;
      kF10:begin
        recordKeyState;
        popAbout;
        restoreKeyState;
      end;
      kF1:begin
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
      then pwinloc:=titleSets[activeSet].numTitles-pwheight;

    {msgConsole^.logmsg(info,'Updating status line');}
    updateStatus;
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
  {free message console}
  dispose(MsgConsole,done);

  {free any working title sets }
  for w:=maxSearchTerms-1 downto 0 do
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
