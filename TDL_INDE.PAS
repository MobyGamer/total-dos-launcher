{$I tdl_dire.inc}
unit tdl_inde;
{
Indexing routines for working with the files we've copied over.
Also contains structures for working with title metadata, such as favorites.
}

interface

uses
  DOS,
  objects,
  tdl_glob,
  tdl_conf;

const
  {Metadata bitflags:}
  numMetaFlags=2;
  m_favorite=1;
  m_unpacked=2;
  m_reserved=4;

type
  {base class for indexes in general}
  PIndex=^TIndex;
  TIndex=object(TObject)
    PUBLIC
    entries:word;
    {cached:boolean;}

    Constructor Init(fpath:PathStr;caching:boolean); {caching=are we allowed to}
    Destructor Done; VIRTUAL;
    Function verify:boolean; VIRTUAL;

    PRIVATE
    data:PStream;
  end;

  PFileIndex=^TFileIndex;
  TFileIndex=object(TIndex)
    Constructor Init(fpath:PathStr;caching:boolean);
    Destructor Done; VIRTUAL;

    {retrieval functions return a pointer because we might have the data
    cached in memory already}
    Function retrieve(i:word;var d:pFileStruct):boolean;
    Function verify:boolean; VIRTUAL;

    PRIVATE
    tmpdata:PFileStruct;
  end;

  PTitleIndex=^TTitleIndex;
  TTitleIndex=object(TIndex)
    Constructor Init(fpath:PathStr;caching:boolean);
    Destructor Done; VIRTUAL;
    Function retrieve(i:word;var d:pTitleStruct):boolean;
    Function retrieve1c(i:word):char; {first char of title returned}
    Function verify:boolean; VIRTUAL;

    PRIVATE
    tmpdata:PTitleStruct;
    headerCached:boolean;
    headerCache:PTitleOffsets;
    headerCacheSize:word;
  end;

  {
  Not yet written:
    Mapping index (contains what titles contain which search words)
  }

  PMetadataArray=^TMetadataArray;
  TMetadataArray=array[0..maxTitles-1] of byte;

  PMetadata=^TMetadata;
  TMetadata=object(TObject)
    PUBLIC
    numEntries:word;
    metaFlags:pMetadataArray;
    changed:boolean;

    Constructor Init(favcache:PathStr;ne:word);
    Destructor Done; VIRTUAL;
    (*
    Procedure FileExport(fname:PathStr);
    Procedure FileImport(fname:PathStr);
    *)
    function Flush:boolean;
    function Used:word; {returns how entries are in use}

    function getFlag(tid:word;flag:byte):boolean; {returns if a title has a certain flag set}
    function setFlag(tid:word;flag:byte):boolean; {sets a flag for a title}
    function clearFlag(tid:word;flag:byte):boolean; {sets a flag for a title}
    function toggleFlag(tid:word;flag:byte):boolean; {flips a flag bit}
    function countFlag(flag:byte):word; {counts how many titles have a certain set}

    PRIVATE
    fname:string;
    fhandle:file;
  end;

procedure stCheck(st:PStream);

var
  Files:PFileIndex; {holds all fileIDs and their 8.4 filenames}
  Titles:PTitleIndex; {holds all titleIDs and their full title strings}

implementation

uses
  support,
  streams;

const
  {Leave these values alone.  Reducing these values may cause breakage.
  Increasing these values will not significantly speed anything up.}
  minReadSize=sizeof(TTitleStruct);  {minimum size of bytes to read from title stream}
  indexMinRAM=4096; {minimum size of RAM bytes to preload a stream}

procedure stCheck(st:PStream);
begin
  case st^.status of
    stError     :fatalerror(21,'Access error');
    stInitError :fatalerror(22,'Cannot initialize stream');
    stReadError :fatalerror(23,'Read beyond end of stream');
    stWriteError:fatalerror(24,'Cannot expand stream');
    stGetError  :fatalerror(25,'Get of unregistered object type');
    stPutError  :fatalerror(26,'Put of unregistered object type');
  end;
end;

Constructor TIndex.Init;
var
  odata:PBufStream;
  l:longint;
begin
  if not Inherited Init then fail;
  if config=nil then fail;
  if not fileexists(fpath) then fail;
  {register index as a stream on disk}
  odata:=new(pbufstream,init(fpath,stOpenRead,indexMinRAM));

  if caching then begin
    {create a new RAM-based stream and copy index into it (STREAM16)}
    l:=indexMinRAM;
    {if index is tiny, just load entire thing}
    if l > odata^.getsize then l:=odata^.getsize;
    data:=TempStream(l,odata^.getsize,ForSpeed);
    if data=nil
      then fatalerror(16,fpath+' failed during init');
    {copy disk-based stream into memory-based stream}
    FastCopy(odata^,data^,odata^.GetSize);
    if data^.status <> stOK
      then fatalerror(16,fpath+' failed during copy');
    dispose(odata,done);
  end else begin
    {Just use the stream on disk as-is.  Slow, but low RAM usage.}
    data:=odata;
  end;

  data^.seek(0);
end;

Destructor TIndex.Done;
begin
  {close our index file handle}
  dispose(data,done);
  Inherited Done;
end;

Function TIndex.verify:boolean;
begin
  if data=nil then fatalerror(3,'Index not initialized');
end;

Constructor TFileIndex.Init;
begin
  if not Inherited Init(fpath,caching) then fail;
  data^.read(entries,2);
  config^.NumTitles:=entries;
  getmem(tmpdata,sizeof(tfilestruct));
end;

Destructor TFileIndex.done;
begin
  freemem(tmpdata,sizeof(tfilestruct));
  Inherited Done;
end;

Function TFileIndex.Retrieve(i:word;var d:pFileStruct):boolean;
begin
  {find offset in stream header, then grab the data into temporary buffer}
  data^.seek(2+longint(i)*sizeof(TFileStruct));
  data^.read(tmpdata^,sizeof(TFileStruct));
  d:=tmpdata;
  retrieve:=(data^.status=stOK);
end;

Function TFileIndex.Verify:boolean;
var
  w,numf:word;
begin
  Verify:=false;
  {verify length is correct}
  if ((data^.GetSize-2) mod (2+12)) <> 0 then exit;
  {verify Entries is correct}
  w:=((data^.GetSize-2) div (2+12));
  if w<>entries then exit;

  {verify all fileIDs are correct}
  data^.seek(2);
  for numf:=0 to Entries-1 do begin
    data^.read(w,2);
    if w<>numf then exit;
    data^.seek(data^.GetPos+12);
  end;

  {if we get here, we didn't detect anything wrong}
  Verify:=true;
end;

Constructor TTitleIndex.Init;
begin
  if not Inherited Init(fpath,caching) then fail;
  data^.read(entries,2);
  headerCached:=false;
  {We can eliminate nearly half of all seeks if we cache the header offsets in RAM}
  if caching and (entries<maxCacheableTitles) then begin
    headerCacheSize:=entries*4;
    if maxavail>headerCacheSize then begin;
      getmem(headerCache,headerCacheSize);
      data^.read(headerCache^,headerCacheSize);
      headerCached:=true;
    end;
  end;
  getmem(tmpdata,minReadSize);
end;

Destructor TTitleIndex.done;
begin
  freemem(tmpdata,minReadSize);
  if headerCached
    then freemem(headerCache,headerCacheSize);
  Inherited Done;
end;

Function TTitleIndex.retrieve(i:word;var d:pTitleStruct):boolean;
{
Seeks are costly on slow I/O systems.  Normally we would seek to the title
length, read it, then read only the title characters we need.  To remove
one seek per retrieval, we are just going to read 256 bytes.  This will
always dip into the next record, but the extra junk won't be visible
to the calling program.
}
var
  l:longint;
  status:integer;
  b:byte;
begin
  {find offset in stream header, then grab the data into temporary buffer}
  if headerCached then begin
    l:=headerCache^[i];
  end else begin
    data^.seek(2+(longint(i)*sizeof(longint)));
    data^.read(l,sizeof(longint));
  end;
  data^.seek(l);
  data^.read(tmpdata^,minReadSize);
  {Our speed optimization of reading minReadSize can go past the end of the
  stream.  If we do this, we'll fall back to slower but 100% accurate reading.}
  if data^.status<>stOK then begin
    data^.status:=stOK;
    data^.seek(l);
    data^.read(tmpdata^.id,sizeof(tmpdata^.id)+sizeof(tmpdata^.hash));
    {get exact length of title}
    data^.read(b,1);
    data^.seek(data^.getpos-1);
    data^.read(tmpdata^.title,b+1);
  end;
  {$IFDEF DEBUG}
  {If still getting an error, fatal abort with the reason}
  if data^.status<>stOK then stCheck(data);
  {$ENDIF}
  d:=tmpdata;
  retrieve:=(data^.status=stOK);
end;

Function TTitleIndex.retrieve1c(i:word):char;
{
Retrieves only the first character of the title. Used for title binary search.
}
const
  tcofs=2+16+1;
var
  l:longint;
  c:char;
begin
  {find offset in stream header, then grab the data into temporary buffer}
  if headerCached then begin
    {l:=headerCache^[i];
    data^.seek(l+tcofs);}
    data^.seek(headerCache^[i]+tcofs);
  end else begin
    data^.seek(2+(longint(i)*sizeof(longint)));
    data^.read(l,sizeof(longint));
    data^.seek(l+tcofs);
  end;
  data^.read(c,1);
  retrieve1c:=c;
end;

Function TTItleIndex.Verify:boolean;
var
  w,tmpid:word;
  l,oldpos:longint;

begin
  Verify:=false;
  {check to see if we have same number of entries as filenames}
  if entries <> config^.numTitles then exit;
  {verify title offsets and titleIDs are correct}
  data^.seek(2);
  for w:=0 to config^.numTitles-1 do begin
    if headerCached then begin
      data^.seek(headerCache^[w]);
      data^.read(tmpid,2);
    end else begin
      oldpos:=data^.GetPos;
      data^.read(l,4);
      data^.seek(l);
      data^.read(tmpid,2);
      data^.seek(oldpos+4);
    end;
    if tmpid <> w
      then exit;
  end;

  {Verifying md5 hash is beyond the scope of slow vintage computers.}
  {Verifying title strings isn't possible without end-of-string markers.}

  {if we get here, we didn't detect anything wrong}
  Verify:=true;
end;

Constructor TMetadata.init;
var
  makeNewCache:boolean;
begin
  Inherited Init;
  numEntries:=ne;
  fname:=favcache;
  changed:=false;
  getmem(metaFlags,numEntries);
  fillchar(metaFlags^,numEntries,0);
  if fname<>'' then begin {if '' then read-only filesystem, can't work with files}
    makeNewCache:=false;
    if not fileexists(fname)
      then begin
        makeNewCache:=true
      end else begin
        if sizeoffile(fname)<>ne {if size doesn't match our index files, invalidate the cache}
          then makeNewCache:=true;
      end;
    assign(fhandle,fname);
    if makeNewCache then begin
      rewrite(fhandle,1);
      blockwrite(fhandle,metaFlags^,numEntries);
    end else begin
      reset(fhandle,1);
      blockread(fhandle,metaFlags^,numEntries);
    end;
    close(fhandle);
  end;
end;

Destructor TMetadata.done;
begin
  freemem(metaFlags,numEntries);
  Inherited Done;
end;

function TMetadata.Used;
var
  w,count:word;
begin
  count:=0;
  for w:=0 to numEntries-1 do
    if metaFlags^[w]<>0
      then inc(count);
  Used:=count;
end;

function TMetadata.countFlag;
var
  w,count:word;
begin
  count:=0;
  for w:=0 to numEntries-1 do
    if (metaFlags^[w] AND flag)=flag
      then inc(count);
  countFlag:=count;
end;

function TMetadata.setFlag;
var
  rc:boolean;
begin
  rc:=false;
  if tid<numEntries then begin
    metaFlags^[tid] := metaFlags^[tid] OR flag;
    rc:=true;
  end;
  setFlag:=rc;
end;

function TMetadata.clearFlag;
var
  rc:boolean;
begin
  rc:=false;
  if tid<numEntries then begin
    metaFlags^[tid] := metaFlags^[tid] AND NOT flag;
    rc:=true;
  end;
  clearFlag:=rc;
end;

function TMetadata.toggleFlag;
var
  rc:boolean;
begin
  rc:=false;
  if tid<numEntries then begin
    metaFlags^[tid] := metaFlags^[tid] XOR flag;
    rc:=true;
  end;
  toggleFlag:=rc;
end;

function TMetadata.getFlag;
var
  rc:boolean;
begin
  rc:=false;
  if (metaFlags^[tid] AND flag) = flag
    then rc:=true;
  getFlag:=rc;
end;

function TMetadata.Flush;
begin
  if (fname<>'') and changed then begin
    assign(fhandle,fname);
    rewrite(fhandle,1);
    blockwrite(fhandle,metaFlags^,numEntries);
    close(fhandle);
    changed:=false;
  end;
end;

end.
