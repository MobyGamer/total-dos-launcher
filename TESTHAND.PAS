program testhand;
{test handler unit}

uses
  support,
  tdl_console,
  tdl_config,
  tdl_handlers;

var
  _memavail:longint;
  w:word;
  th:PHandler;
  s:string;

begin
  _memavail:=memavail;

  config:=new(pconfig,init('tdl.ini','distro'));

  MsgConsole:=new(PMConsole,init('d:\projects\tdl\testhand.log'));
  MsgConsole^.verboselog:=true;
  Handlers:=new(PHandlers,init('d:\projects\tdl\distro\handlers.ini'));
  if Handlers=nil then die('Handlers nil!');

  writeln('---');
  for w:=0 to Handlers^.count-1 do begin
    th:=Handlers^.at(w);
    with th^ do s:=extension+':'+template+':'+fullpath;
    if length(s)>79 then byte(s[0]):=79;
    writeln(s);
  end;

  Writeln('Handler exists for EXE: ',Handlers^.Exists('EXE')<>null);
  Writeln('Handler exists for ZIP: ',Handlers^.Exists('ZIP')<>null);
  Writeln('Handler exists for 123: ',Handlers^.Exists('123')<>null);

  Handlers^.Handle('BAT','c:\temp\test.bat','c:\temp\');
  Handlers^.Handle('IMG','c:\temp\image.img','c:\temp\');
  {execute something}
  Handlers^.Handle('COM','d:\projects\tdl\output\files\freeram.com','d:\projects\tdl\output\files\');
  readln;
  Handlers^.Handle('ZIP','d:\projects\tdl\output\files\pac-gal1.zip','c:\temp\testzip');
  Handlers^.Handle('EXE','c:\temp\pac-gal1\pac-gal.exe','c:\temp\pac-gal1');
  Handlers^.Handle('EXE','c:\utils\common\valet.exe','c:\utils\common\');
  Handlers^.Handle('TXT','c:\autoexec.bat','c:\');

  dispose(Handlers,done);
  dispose(msgConsole,done);
  dispose(config,done);

  if _memavail<>memavail
    then fatalerror(255,'Memory leak detected: '
         +inttostr(_memavail-memavail)+' bytes unaccounted for');
end.