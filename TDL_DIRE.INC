{ Global TDL compilation directives}
{undefine this next line if still debugging}
{{$DEFINE FINAL}

{$G-} {No 286+ instructions -- must run on every IBM PC and compatible}

{Overlays are only used while trying to run and debug the program within the
Turbo Pascal real-mode IDE.  There is NO reason to distribute the program
with overlays because it is a massive slowdown and only saves about 128K.}

{$IFNDEF FINAL}
  {$DEFINE USEOVERLAYS}
{$ENDIF}

{$IFDEF DPMI}
  {$UNDEF USEROVERLAYS}
{$ENDIF}

{$IFDEF FINAL}
  {$A+,B-,D+,E-,F-,G-,I+,L+,N-,O-,P-,Q-,R-,S-,T-,V+,X+}
{$ELSE}
  {$Q+,R+,S+}
{$ENDIF}

{$IFDEF USEOVERLAYS}
  {$O+,F+}
{$ENDIF}
