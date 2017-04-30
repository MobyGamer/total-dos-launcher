{$I tdl_dire.inc}

{$IFDEF USEOVERLAYS}
{$O+,F+}
{$ENDIF}

unit tdl_cons;
{Implements mechanisms for interacting with the user,
including a message console, simple pop-up dialogs, etc.}

interface

uses
  objects,
  strings,
  TDL_glob,
  TDL_conf,
  totSYS,
  totWIN,
  totFAST,
  totMSG,
  totLOOK,
  totIO1,
  support;

type
  messageType=(info,warning,error,fatal);

  {Object for logging messages to a file}
  PLog=^TLog;
  TLog=object(TObject)
    logname:string;
    Constructor Init(name:string);
    Destructor Done; virtual;

    Procedure Commit(msg:string);

    private
    loghandle:text;
  end;

  {Message console object.  Messages are tagged with info, warning, or error
  and show up on a virtual screen in different colors.  All messages except
  info are also logged atomically to the application logfile.  If verboselog
  is set, then info messages are logged as well.}
  PMConsole=^TMConsole;
  TMConsole=object(TObject)
    verboseLog:boolean; {if true, "info" messages get written to log}
    ConScreen,savescreen:PScreenOBJ;
    {colors for the console.  Default values work for both color and MDA.}
    _cnormal,_creverse,_chigh,_cunderline,_cblink:byte;

    Constructor Init(logfname:string);
    Destructor Done; virtual;

    Procedure Show;
    Procedure Hide;
    Procedure LogMsg(m:messageType;msg:string);

    private
    fileLog:PLog;
  end;

var
  MsgConsole:PMConsole;
  FStatus:PWinOBJ;
  DOSScreen:PScreenObj;


Procedure PopUserMessage(class:messagetype;s:string);
Procedure PopAbout;
Procedure PopHelp;
Function PromptYN(msg:string):boolean;
Function PromptForFilename(blurb:string):string;
procedure die(s:string);
procedure recordKeyState;
procedure restoreKeyState;
procedure pause;
procedure pauseForUser; {uses DOS and BIOS only}
procedure tmpScreenSave;
procedure tmpScreenRestore;
function setVESA(mode:word):word;

implementation

uses
  totINPUT,
  totIO2;

var
  keyState:word;
  tmpScreen:PScreenObj;

function setVESA(mode:word):word; assembler;
asm
        mov     bx,mode
        mov     mode,0
        mov     ax,4f02h
        int     10h
        cmp     al,4fh
        je      @FunctionSupported
        mov     mode,1                  {function not supported}
        jmp     @done

@FunctionSupported:
        cmp     ah,01h
        jne     @done
        mov     mode,2
@done:
        mov     ax,mode
end;

procedure die(s:string);
begin
  msgConsole^.logMsg(fatal,s);
end;

procedure recordKeyState;
begin
  keyState:=key.vLastKey;
end;

procedure restoreKeyState;
begin
  key.vLastKey:=keyState;
end;

procedure pause;
begin
  recordKeyState;
  key.getkey;
  restoreKeyState;
end;

procedure pauseForUser; assembler;
asm
        push    ds
        jmp     @startit
@msg:
        DB      'Press a key to return to the TDL.$'
@startit:
        push    cs
        pop     ds
        mov     dx,offset @msg
        mov     ah,09h
        int     21h
        xor     ax,ax
        int     16h
        pop     ds
end;

{Okay, so the nil pointer stuff is to prevent if I call tmpScreenSave two or
more times in a row, or try to dispose of it before creating it.
Save me from myself.}

procedure tmpScreenSave;
begin
  if tmpScreen=nil
    then tmpScreen:=new(PScreenOBJ,init);
  tmpScreen^.save;
end;

procedure tmpScreenRestore;
begin
  if tmpScreen<>nil then begin
    tmpScreen^.display;
    dispose(tmpScreen,done);
    tmpScreen:=nil;
  end;
end;

procedure helpdata; external;
{$L helpdata.obj}

procedure help_40c; external;
{$L help_40c.obj}

Procedure PopHelp;
const
  x1=1;
  y1=4;
  margin:byte=72;
  curx:byte=x1;
  cury:byte=y1;
var
  c:^char;
  col:byte;
  {$IFDEF USEOVERLAYS}
  placeholder:string[80];
  {$ENDIF}
begin
  {This simple text wrapping algo is not smart enough to look ahead to the
  next word boundary; it only does margin wrapping.  On the to-do list.}
  margin:=screen.width-(screen.width div 10);
  curx:=x1;
  cury:=y1;
  screen.TitledBox(1,1,Screen.Width,Screen.Depth,
    LookTOT^.vmenuborder,LookTOT^.vmenutitle,LookTOT^.vmenuborder,
    6,'Total DOS Launcher Help');
  {$IFDEF USEOVERLAYS}
  placeholder:='help text not present when using overlays - complain to programmer$';
  c:=@placeholder;
  {$ELSE}
  if screen.width<80
    then c:=@help_40c
    else c:=@helpdata;
  {$ENDIF}
  col:=LookTOT^.vmenulonorm;
  while c^ <> '$' do begin
    case c^ of
      #13:curx:=x1;
      #10:inc(cury);
      '~':if col=LookTOT^.vmenulonorm
            then col:=LookTOT^.vmenulohot
            else col:=LookTOT^.vmenulonorm;
      '$':break;
      else begin
        screen.writeat(curx,cury,col,c^);
        inc(curx);
        if (c^=#32) and (curx>margin) then begin
          curx:=x1;
          inc(cury);
        end;
      end;
    end;
    inc(word(c)); {advance pointer}
  end;
  screen.writecenter(screen.depth,LookTOT^.vmenulohot,'Press any key to dismiss');
  key.getkey;
end;


Constructor TLog.Init;
begin
  Inherited Init;

  logname:=name;
  assign(loghandle,logname);
  if not fileexists(logname)
    then rewrite(loghandle)
    else append(loghandle);
  writeln(loghandle,stdDate+': Log opening');
  close(loghandle);
end;

Destructor TLog.Done;
begin
  append(loghandle);
  writeln(loghandle,stdDate+': Log closing');
  close(loghandle);
  Inherited Done;
end;

Procedure TLog.commit(msg:string);
begin
  append(loghandle);
  writeln(loghandle,msg);
  close(loghandle);
end;


Constructor TMConsole.Init;

begin
  Inherited Init;

  _cnormal:=$07;
  _creverse:=$70;
  _chigh:=$0f;
  _cunderline:=$01;
  _cblink:=$8c;

  if logfname<>''
    then new(fileLog,init(logfname))
    else fileLog:=nil;
  verboseLog:=false;

  new(ConScreen,init);
  ConScreen^.create(Monitor^.Width,Monitor^.Depth,$08);
  ConScreen^.writeAt(1,1,_creverse,'Debug message console.  Only recent entries displayed.  Press a key to dismiss. ');
end;

Destructor TMConsole.Done;
begin
  logMsg(info,'Debug Console closing...');
  dispose(ConScreen,done);
  if fileLog<>nil then dispose(fileLog,done);

  Inherited Done;
end;

Procedure TMConsole.Show;
begin
  new(savescreen,init);
  savescreen^.save;
  ConScreen^.gotoxy(ConScreen^.vwidth,ConScreen^.vDepth);
  ConScreen^.Display;
end;

Procedure TMConsole.Hide;
begin
  savescreen^.display;
  dispose(savescreen,done);
end;

Procedure TMConsole.LogMsg;
var
  color:byte;
begin
  {prepend a standardized date onto the message to help with troubleshooting}
  msg:=stdDate+': '+msg;
  {first, make sure it gets into the log file if it is important}
  if fileLog<>nil then case m of
    info:if verboseLog then fileLog^.Commit(msg);
    warning:fileLog^.Commit('Warning: '+msg);
    error  :fileLog^.Commit('=ERROR=  '+msg);
    fatal  :fileLog^.Commit('=FATAL=  '+msg);
  end;
  {then, insert it into the message console}
  ConScreen^.Scroll(up,1,2,ConScreen^.Width,ConScreen^.Depth);
  case m of
    info:color:=_cnormal;
    warning:color:=_chigh;
    error,
    fatal:color:=_cblink;
  end;
  {full message committed to file log; truncate for screen printing}
  if length(msg)>Monitor^.Width then byte(msg[0]):=Monitor^.Width;
  ConScreen^.WriteAt(1,ConScreen^.Depth,color,msg);
  {if we have a fatal error,
  MAYDAY MAYDAY TOPBENCH IS BUDDY-SPIKED ABORT ABORT ABORT}
  if m=fatal then begin
    RestoreDOSScreen;
    system.writeln('FATAL ERROR: '+msg);
    if fileLog<>nil
      then system.writeln('It might be prudent to check '+fileLog^.logname+' for clues.');
    halt(1);
  end;
end;

Procedure PopUserMessage(class:messagetype;s:string);
const
  maxlines=8;
var
  foomsg:PMessageObj;
  loop:byte;
  ts:string[12];
  margin:byte;
  numlines:byte;
  wrapped:array[0..maxlines-1] of titleStrType;
begin
  {reformat message to wrap lines if it exceeds our margin}
  margin:=round(Monitor^.width * 0.66);
  if length(s)<margin then begin
    numlines:=1;
    wrapped[0]:=s;
  end else begin
    for numlines:=0 to maxlines-1 do begin
      if s[1]=#32 then delete(s,1,1);
      if length(s)<margin then begin
        wrapped[numlines]:=s;
        break;
      end;
      if s='' then break;
      for loop:=0 to length(s) do begin
        if loop>margin then begin
          if s[loop]=#32
            then break;
        end;
      end;
      wrapped[numlines]:=copy(s,0,loop);
      delete(s,0,loop);
    end;
  end;

  case class of
    info   :ts:='Information';
    warning:ts:='Warning:';
    error  :ts:='Error!';
  end;
  new(foomsg,init(2,ts));
  with foomsg^ do begin
    for loop:=0 to numlines do addline(wrapped[loop]);
    addline(' ');
    show;
    MsgConsole^.LogMsg(class,s);
  end;
  dispose(foomsg,done);
end;

Procedure PopAbout;
var
  foomsg:PMessageObj;
  loop:byte;
  avgobjsize:word;
  s:string[20];
begin
  new(foomsg,init(2,TDLTitleFull));
  with foomsg^ do begin
    for loop:=0 to numAboutLines-1 do AddLine(strpas(AboutText[loop]));
    case config^.userlevel of
      kiosk:s:='Kiosk';
      regular:s:='Default';
      power:s:='Power User';
    end;
    addline(' TDL operating mode: '+s);
    addline(' Memory free: '+inttostr(memavail div 1024)+' KB (largest: '+inttostr(maxavail div 1024)+' KB)');
    addline(' ');
    show;
  end;
  dispose(foomsg,done);
end;

function PromptYN(msg:string):boolean;
var
  PromptWin:PPromptOBJ;
  result:tAction;
begin
  new(promptwin,Init(1,''));
  with PromptWin^ do begin
    AddLine(msg);
    AddLine(' ');
    SetOption(1,'  ~Y~es  ',89,Finished);
    SetOption(2,'  ~N~o  ',78,Escaped);
    Result := Show;
  end;
  PromptYN:=(Result = Finished);
  dispose(promptwin,done);
end;

Function PromptForFilename(blurb:string):string;
var
  PromptWin:PWinOBJ;
  fname:PLateralIOOBJ;
  wid:byte;
begin
  new(PromptWin,init);
  wid:=Monitor^.width;
  with PromptWin^ do begin
    SetSize(4,2,wid-5,4,1);
    SetTitle(blurb);
    SetClose(false);
    draw;
    screen.writeplain(1,1,'Filename: ');
  end;
  new(fname,init(10,1,wid-10,127));
  with fname^ do begin
    SetLabel('Filename: ');
    Activate;
    PromptForFilename:=GetValue;
  end;
  dispose(fname,done);
  dispose(PromptWin,done);
end;



end.