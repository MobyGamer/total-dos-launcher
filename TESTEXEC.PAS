program testexec;

uses
  DOS,
  memory;

var
  programName,cmdline:string;

begin
  chdir('c:\utils');
  (*chdir('c:\utils\'); {FAILS!}*)
  chdir('c:');
  chdir('c:\');
  chdir('c:\.');



  initmemory;
  programName:='d:\projects\tdl\output\files\freeram.com';
  cmdline:='';
  DoneDOSMem;
  SwapVectors;
  Exec(ProgramName, CmdLine);
  SwapVectors;
  InitDOSMem;
end.
