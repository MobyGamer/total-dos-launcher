{$M 16384,0,655360}
uses Dos,memory;
var
  ProgramName, CmdLine: string;
begin
  Write('Program to Exec (full path): ');
  ReadLn(ProgramName);
  Write('Command line to pass to ',
        ProgramName, ': ');
  ReadLn(CmdLine);
  WriteLn('About to Exec...');
  donedosmem;
  SwapVectors;
  Exec(ProgramName, CmdLine);
  SwapVectors;
  initdosmem;
  WriteLn('...back from Exec');
  if DosError <> 0 then{ Error? }
    WriteLn('Dos error #', DosError)
  else
    WriteLn('Exec successful. ',
            'Child process exit code = ',
            DosExitCode);
end.
