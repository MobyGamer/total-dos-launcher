{$I tdl_dire.inc}
unit tdl_audi;
{
Auditing routines for tracking user activity
}

interface

uses
  DOS,
  objects,
  tdl_glob,
  tdl_conf;

type
  PAuditRec=^TAuditRec;
  TAuditRec=record
    titleID:word;
    titleHash:MD5hash;
    startTime,
    endTime:DateTime;
    minsActive:word;
  end;

  PAuditLog=^TAuditLog;
  TAuditLog=object(TObject)
    PUBLIC
    Entry:TAuditRec;
    totalEntries:word;

    {Creates new audit log if absent or empty, opens existing log if present}
    Constructor Init(auditLogPath:PathStr);
    Destructor Done; VIRTUAL;

    {Creates new entry using system time}
    function newEntry(tID:word):boolean;

    {Functions for seeking/iterating through all audit log entries.
    Data returned via this object's .Entry public variable.}
    function getFirst:boolean;
    function getNext:boolean;
    function getLast:boolean;

    {Records return from launched program}
    function closeEntry:boolean;

    PRIVATE
    curEntry:word;
    fpath:string;
    aStream:PDOSStream;
  end;

var
  auditLog:PAuditLog;

implementation

uses
  support,
  tdl_inde;

Constructor TAuditLog.Init;
var
  l:longint;
begin
  if not Inherited Init then fail;
  if config=nil then fail;
  fpath:=auditLogPath;
  {register index as a stream on disk}
  if fileExists(fpath)
    then aStream:=new(pDOSStream,init(fpath,stOpen))
    else aStream:=new(pDOSStream,init(fpath,stCreate));

  {$IFDEF DEBUG}
  if aStream^.status<>stOK then stCheck(data);
  {$ENDIF}

  totalEntries:=aStream^.getsize div sizeof(TAuditRec);
end;

Destructor TAuditLog.Done;
begin
  dispose(aStream,done);
  Inherited Done;
end;

procedure grabTime(var tempDateTime:DateTime);
var
  y,mo,d,dow,h,mi,s,s100:word;
begin
  getdate(y,mo,d,dow);
  gettime(h,mi,s,s100);
  with tempDateTime do begin
    year:=y;
    month:=mo;
    day:=d;
    hour:=h;
    min:=mi;
    sec:=s;
  end;
end;

Function TAuditLog.newEntry(tID:word):boolean;
var
  tmpEntry:TAuditRec;
  tDT:DateTime;
  ttbuf:PTitleStruct;

begin
  {prepare an audit log entry}
  fillchar(tmpEntry,sizeof(tmpEntry),0);
  grabTime(tDT);
  with tmpEntry do begin
    titleID:=tID;
    startTime:=tDT;
    endTime:=startTime;
    titles^.retrieve(tID,ttbuf);
    titleHash:=ttbuf^.hash
  end;

  {seek to the end}
  aStream^.seek(aStream^.getsize);
  aStream^.write(tmpEntry,sizeof(tmpEntry));
  newEntry:=(aStream^.status=stOK);
end;

{Functions for seeking/iterating through all audit log entries.
Data returned via this object's .Entry public variable.}
Function TAuditLog.getFirst:boolean;
begin
  aStream^.seek(0);
  aStream^.read(Entry,sizeof(Entry));
  getFirst:=(aStream^.status=stOK);
end;

Function TAuditLog.getNext:boolean;
begin
  aStream^.read(Entry,sizeof(Entry));
  getNext:=(aStream^.status=stOK);
end;

Function TAuditLog.getLast:boolean;
begin
  aStream^.seek(aStream^.getsize-sizeof(Entry));
  aStream^.read(Entry,sizeof(Entry));
  getLast:=(aStream^.status=stOK);
end;

{Records return from launched program}
Function TAuditLog.closeEntry;
var
  tDT:DateTime;
begin
  getLast;
  grabTime(tDT);
  entry.endTime:=tDT;
  Entry.minsActive:=0; {this will be populated later by a call to a monitoring TSR}
  {seek to the beginning of the last entry}
  aStream^.seek(aStream^.getsize-sizeof(Entry));
  {update the last entry}
  aStream^.write(Entry,sizeof(Entry));
  totalEntries:=aStream^.getsize div sizeof(TAuditRec);
  closeEntry:=(aStream^.status=stOK);
end;

end.
