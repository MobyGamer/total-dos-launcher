{$I tdl_directives.inc}

{$IFDEF USEOVERLAYS}
{$O+,F+}
{$ENDIF}
unit tdl_handlers;
{
Contains logic and data structures necessary to implement file handlers.

- EXTRACTION handlers decompress archive files into cache directories.
- EXECUTION handlers directly run programs, or launch a helper program to
handle the chosen file.

Implementation notes:
- Execution handlers always switch to the supplied directory before
operating, to try to avoid exceeding DOS directory length/depth limits.
}

interface

uses
  DOS,
  objects;

type
  fSplitRec=record
    P:PathStr;
    D:DirStr;
    N:NameStr;
    E:ExtStr;
  end;

  handlerType=(null,extraction,execution);

  PHandler=^THandler;
  THandler=object(TObject)
    PUBLIC
    category:handlerType;
    extension:extStr;
    Template:dirStr;                    {string template from handlers.ini}
    FullPath:dirStr;                    {full path to utility}
    Description:dirStr;                 {user-friendly description}
    UserMessage:string;                 {optional short message to user}

    Constructor Init(ext:extStr;cat:handlerType;temp,fullp,desc:dirStr;usermsg:string);
    Destructor Done; VIRTUAL;
  end;

  PHandlers=^THandlers;
  THandlers=object(TCollection)
    PUBLIC
    defaultHandler:integer;
    Constructor Init(hfile:string);
    Destructor Done; VIRTUAL;
    Function Exists(ext:extStr):handlerType;
    Function handle(ext:extStr;_src,_dst:string):boolean;
  end;

var
  Handlers:PHandlers;

implementation

uses
  spawno,
  support,
  totFAST,
  inifiles,
  tdl_config,
  tdl_console;

Constructor THandler.Init;
begin
  Inherited Init;
  extension:=ext;
  category:=cat;
  template:=temp;
  FullPath:=fullp;
  description:=desc;
  userMessage:=usermsg;
end;

Destructor THandler.Done;
begin
  Inherited Done;
end;



Constructor THandlers.Init;
const
  INIBufSize=18*512*2; {enough to hold an entire 1.44MB track}
var
  h:PHandler;
  t:THandler;
  ini:PINIfile;
  iniresult:PINIResultType;
  s,util,section,upath:string;
  first:boolean;
  b:byte;

begin
  if config^.swapping
    then init_spawno(config^.cacheDir,swap_all,32,0);
  {Init the collection with 32 to start and 256 max.
  Anyone needing >256 handlers needs to consider a change of lifestyle.}
  Inherited Init(32,256);

  {Populate collection with contents of handlers.ini}
  if not fileexists(hfile)
    then die('Handler config '+hfile+' not found');
  ini:=new(PINIFile,init(hfile,readfile,INIBufSize));
  if ini=NIL then begin
    die('Problem opening handler INI file: '+hfile);
    exit;
  end;

  {read and parse.  Template for what we are reading:}
  (*
[ARC;SEA]
type=extraction
launcher=pkunpak.exe %s %d
locations=utils;distro\utils;c:\utils\common
  *)

  {read first line}
  first:=true;
  INIResult:=ini^.ReadNextItem; if INIResult=nil then die('Initial INI read failed');
  while (INIResult<>nil) do begin
    INIResult:=ini^.ReadNextItem; {won't go past section header unless we ACK}
    if (ini^.newSection) then begin;
      if not first then begin
        {fill in the rest of the fields, verify input, etc.}
        {determine base utility filename.  Handle special case of just '%s'.}
        util:=t.template;
        if (pos('%',util)=0) then die('Handler launcher string "'+util+'" malformed');
        if util<>'%s' then begin
          system.delete(util,pos(' ',util),length(util));
          {remove it from the template string}
          system.delete(t.template,1,length(util));
          {fully-qualify the utilty}
          s:=util;
          if upstring(util)='COMMAND.COM'
            then util:=FSearch(util,GetEnv('PATH'))
            else util:=FSearch(util,upath);
          if util=''
            then die(s+' handler helper util not found in '+upath);
          {add drive letter to convert relative path to absolute path}
          if pos(':',util)=0 then begin
            getdir(0,s);
            util:=StdPath(s)+util;
          end;
        end;
        {commit as many as are separated by semicolons}
        while section<>'' do begin
          t.extension:=section; byte(t.extension[0]):=3;
          if util='%s'
            then t.fullpath:=''
            else t.fullpath:=util;
          h:=new(PHandler,init(t.extension,t.category,t.template,t.fullpath,t.description,t.usermessage));
          Insert(h);
          system.delete(section,1,4); {remove "XXX;" and do it again}
        end;
      end;
      {start building new handler with each line read}
      ini^.ACKSection;
      {reset optional fields}
      t.description:=''; t.usermessage:='';
      section:=INIResult^.section;
      first:=false;
      continue;
    end;
    with INIResult^ do begin
      if upstring(key)='TYPE' then begin
        if upstring(value)='EXTRACTION'
          then t.category:=extraction
          else t.category:=execution;
      end;
      if upstring(key)='LAUNCHER' then t.template:=value;
      if upstring(key)='LOCATIONS' then upath:=value;
      if upstring(key)='DESCRIPTION' then t.description:=value;
      if upstring(key)='USERMESSAGE' then t.userMessage:=value;
    end;
  end;
  dispose(ini,done);

  {Now that we have our handlers, look for the ??? handler and set that to
  the default.}
  defaultHandler:=-1;
  for b:=0 to Count-1 do
    if PHandler(at(b))^.extension='???'
      then begin
        defaultHandler:=b;
        break;
      end;
end;

Destructor THandlers.Done;
begin
  Inherited Done;
end;

Function THandlers.Exists(ext:extStr):handlerType;
var
  w:word;
begin
  Exists:=null;
  for w:=0 to Count-1 do begin
    if PHandler(at(w))^.extension=ext then begin
      Exists:=PHandler(at(w))^.category;
      break;
    end;
  end;
end;

Function THandlers.handle(ext:extStr;_src,_dst:string):boolean;
{$DEFINE DEBUGLAUNCH}
{
src and dst must always be fully-qualified (ie. c:\dir\file.ext or c:\dir\);

Extraction handlers do this:
  1. chdir to where the helper program is
  2. run utility program template with %s=src and %d=dst

Execution handlers do this:
  1. chdir:
    - if %s present, chdir to %d and run template
    - if %f present, chdir to where helper program is and run template

%f is for helper "programs" that are really batch files that run many progs.
}
var
  tmpsplit,src,dst:fSplitRec;
  execParm:string; {execution template}
  execHead:string;
  hid:integer;
  oldDir,wrkDir:string;
  result:boolean;
  temps:string;
  retval:integer;

  {heap manipulation}
  OldHeapEnd,NewHeapEnd:Word;
  mError:Integer;

begin
  msgConsole^.logmsg(info,'Entering handler framework: '+ext);
  result:=false;
  src.p:=_src; dst.p:=stdPath(_dst);
  with src do fsplit(p,d,n,e);
  with dst do fsplit(p,d,n,e);
  {find handler index}
  {there's a reason why this is Count instead of Count-1 but I can't remember why :-(  }
  for hid:=0 to Count do begin
    if hid=Count
      then die('Unregistered handler: '+ext);
    if PHandler(at(hid))^.extension=ext
      then break;
  end;

  if PHandler(at(hid))^.userMessage<>''
    then popUserMessage(info,PHandler(at(hid))^.userMessage);

  execHead:=PHandler(at(hid))^.fullpath;
  execParm:=PHandler(at(hid))^.template;
  {Replace variables in the launch template.
  %s and %f are handled differently -- see handlers.ini or above for info}
  case PHandler(at(hid))^.category of
    execution:begin
      if pos('%s',execParm)<>0 then strReplace(execParm,'%s',src.n+src.e);
      if pos('%f',execParm)<>0 then begin
        strReplace(execParm,'%f',src.p); {replace with full path}
        dst.p:=PHandler(at(hid))^.fullpath; {grab full path to helper util}
        with dst do fsplit(p,d,n,e); {ensure that dst.d = helper util path}
        execHead:=dst.n+dst.e;
      end;
      {Bare .exe/.coms don't have handler utils -- set up the exec for them.
      An empty header of '' is the indicator we chose to signify this.}
      if execHead='' then begin
        execHead:=execParm;
        execParm:='';
      end;
      wrkDir:=dst.d;
      {check for batch files -- must run them with 'command.com','/c b.bat'}
      if (pos('.bat',execHead)<>0) or (pos('.BAT',execHead)<>0) then begin
        execParm:='/c '+execHead+execParm;
        execHead:=GetEnv('COMSPEC');
      end;
    end;
    extraction:begin
      strReplace(execParm,'%s',src.n+src.e);
      strReplace(execParm,'%d',dst.d);
      wrkDir:=src.d;
    end;
  end;
  msgConsole^.logmsg(info,'Execution template: '+execParm);
  GetDir(0,oldDir);
  temps:='Switching to '+wrkDir+' to execute '+execHead+execParm;
  msgConsole^.logmsg(info,temps);

  {TP's CHDIR can't handle subdirectories with trailing slashes; weird.
  It requires them on root dirs though, like "c:\".  Dumb fix:}
  if (length(wrkdir)<>3) and (wrkdir[length(wrkdir)]='\')
    then system.delete(wrkdir,length(wrkdir),1);
  chdir(wrkDir);

  {determine end of actual memory used}
  NewHeapEnd:=Seg(HeapPtr^)-PrefixSeg;
  OldHeapEnd:=Seg(HeapEnd^)-PrefixSeg;
  {resize our own DOS memory block to end of USED heap}
  asm
        mov     ah,4Ah
        mov     bx,NewHeapEnd
        mov     es,PrefixSeg
        int     21h
        jnc     @EXIT
        mov     mError,ax
@EXIT:
  end; {asm}
  swapvectors;
  if config^.swapping
    then retval:=spawn(execHead,execParm,0)
    else exec(execHead,execParm);
  swapvectors;
  {resize it back to the end of TOTAL heap}
  asm
        mov     ah,4Ah
        mov     bx,OldHeapEnd
        mov     es,PrefixSeg
        Int     21h
        jnc     @EXIT
        mov     mError,ax
@EXIT:
  end; {asm}

  {handle error codes}
  if config^.swapping then begin
    result:=(retval<>-1);
    if result=false
      then msgConsole^.logmsg(tdl_console.error,'Spawn failure; Error code = '+inttostr(spawno_error));
  end else begin
    result:=(DOSError=0);
    if result=false
      then msgConsole^.logmsg(tdl_console.error,'EXEC failure; Error code = '+inttostr(DOSError))
  end;

  msgConsole^.logmsg(info,'Switching back to '+wrkdir);
  chdir(oldDir);
  msgConsole^.logmsg(info,'Saving DOS screen contents');
  DOSScreen^.Save;
  handle:=result;
  {msgConsole^.logmsg(info,'Exiting handler framework.');}
end;



end.