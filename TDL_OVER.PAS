unit tdl_over;
{needed to get the overlay manager initialized before all others}

{$DEFINE USEEMS}

{$DEFINE BUFEXPAND}

interface

procedure __doswrite(s:string);
procedure __doswriteln(s:string);

implementation

Uses
  overlay;

const
  {$IFDEF BUFEXPAND}
  minfreeram=128 * 1024; {amount of free RAM we can't dip below}
  ovrsize=64 * 1024;
  {$ENDIF}

var
  ovrname:string;

procedure __doswrite(s:string); assembler;
asm
  push    ds
  cld
  lds     si,s
  lodsb
  xor     ah,ah
  xchg    cx,ax           {cx=#0 of string which contains length}
  jcxz    @exit           {if string is length 0 then bail}
@L1:
  lodsb
  int     29h             {do it}
  loop @L1
@exit:
  pop     ds
end;

procedure __doswriteln(s:string);
begin
  __doswrite(s+#13#10);
end;

Function __IntToStr(I:LongInt):string;
Var
  S:string;
Begin
  Str(I,S);
  __IntToStr:=S;
End;

Procedure ReportError;
begin
  case OvrResult of
    ovrOK            :__dosWriteln('Overlay operation successful');
    ovrError         :__dosWriteln('Error initializing overlay');
    ovrNotFound      :__dosWriteln('Overlay file not found');
    ovrNoMemory      :__dosWriteln('Not enough memory for overlay');
    ovrIOError       :__dosWriteln('Overlay I/O error');
    {$IFDEF USEEMS}
    ovrNoEMSDriver   :__dosWriteln('No EMS driver found');
    ovrNoEMSMemory   :__dosWriteln('Not enough EMS available');
    {$ENDIF}
  else
    __dosWriteln('Unknown overlay error');
  end; {case}
end;

var
  b:byte;

begin
  (*
  {perform name fixup}
  ovrname:=copy(paramstr(0),length(paramstr(0))-sizeof(ovrname)+2,sizeof(ovrname)-4)+'ovr';
  *)

  {First, initialize the overlay, since we can't continue until this succeeds.}
  __dosWrite('Initializing overlay manager... ');
  ovrname:=paramstr(0);
  OvrInit(ovrname);
  if OvrResult <> ovrOk then begin
    delete(ovrname,length(ovrname)-3+1,3);
    ovrname:=ovrname+'ovr';
    OvrInit(ovrname);
    if OvrResult <> ovrOk then begin
      ReportError;
      Halt(1);
    end;
  end;
  {$IFDEF USEEMS}
  OvrInitEMS;
  if OvrResult <> ovrOk then begin
    ReportError;
    {Halt(1);}
  end;
  {$ENDIF}
  {$IFDEF BUFEXPAND}
  {Do we have room to expand the buffer?  If so, do it}
  if (memavail > (minfreeram+ovrsize))
    then OvrSetBuf(ovrsize);
  {$ENDIF}
  __doswriteln('using '+__inttostr(OvrGetBuf div 1024)+'KB with '+__inttostr(memavail div 1024)+'KB remaining.')
end.
