{$I tdl_dire.inc}

{$IFDEF USEOVERLAYS}
{$O+,F+}
{$ENDIF}
unit tdl_cach;

{
Encapsulates title file/data cache functionality into an object.
The title cache is the base directory where titles are uncompressed into
before they can be launched.
}

interface

uses
  objects,
  DOS;

type
  PFileCache=^TFileCache;
  TFileCache=object(TObject)
    Constructor Init(cachepath:string);
    Destructor Done; virtual;

    {Refresh free space stats.
    DOS can take up to 15+ seconds on very slow systems to refresh
    this number, so by breaking it out, we might be able to hide it.
    Can use bytesFree and megsFree for cached referencing.}
    Function Remaining:longint;
    Function EstimateCacheUsage(filetype:ExtStr;filepath:PathStr):longint;

    public
    path:PathStr;
    bytesFree:longint;
    megsFree:word;

    private
    {Some functions need the number of the cache's drive letter:
    0 = current drive, 1=A:, 2=B:, 3=C:, etc.}
    cacheDriveNum:byte;
  end;

implementation

uses
  tdl_conf,
  support;

Constructor TFileCache.Init;
begin
  Inherited Init;

  path:=cachePath;

  {Create the cache dir if it doesn't exist}
  if not DirExists(path)
    then begin
      MkDirCDir(path);
      if not DirExists(path)
        then fatalerror(2,'Creation of '+path+' failed');
    end;
  {ensure cache path is fully qualified and sanitized (ends with "\")}
  path:=StdPath(FExpand(path));
  cacheDriveNum:=byte(upcase(path[1]))-64;
end;

Destructor TFileCache.done;
begin
  Inherited Done;
end;

Function TFileCache.Remaining;
begin
  bytesFree:=diskfree(cacheDriveNum);
  megsFree:=bytesFree div (1024*1024);
  Remaining:=bytesFree;
end;

Function TFileCache.EstimateCacheUsage;
{
This attempts to estimate how much cache we'll need to store an extracted
title.  The minimum number returned is the size of available free RAM, in
case all of RAM needs to be swapped to disk to execute the title.

If the title is a compressed file we can deal with, then determine the
total uncompressed size needed, rounding each file upward to the DOS cluster
amount so that the number is accurate.
}

var
  dosclustersize:word;
  estimate:longint;
  f:file;

{===========================================================================}

  Function RoundToNearestCluster(l:longint):longint;
  var
    rounded:longint;
  begin
    rounded:=(l + (DOSClusterSize-1)) AND NOT longint(DOSClusterSize-1);
    RoundToNearestCluster:=rounded;
  end;

{=========================ZIP file support routines=========================}

  Function GetZipUncompSizeCluster:longint;

  const
    pkzip_local_header_sig=$04034B50;
    pkzip_central_header_sig=$02014B50;

  type
    pkzip_local_header=record
      ZIPLOCSIG:longint;           {Local File Header Signature}
      ZIPVER   :word;              {Version needed to extract  }
      ZIPGENFLG:word;              {General purpose bit flag   }
      ZIPMTHD  :word;              {Compression method         }
      ZIPTIME  :word;              {Last mod file time (MS-DOS)}
      ZIPDATE  :word;              {Last mod file date (MS-DOS)}
      ZIPCRC   :longint;           {CRC-32                     }
      ZIPSIZE  :longint;           {Compressed size            }
      ZIPUNCMP :longint;           {Uncompressed size          }
      ZIPFNLN  :word;              {Filename length            }
      ZIPXTRALN:word;              {Extra field length         }
    end;

  var
    plr:pkzip_local_header;
    s:string;
    l:longint;
    numread:word;

  begin
    assign(f,filepath);
    reset(f,1);
    l:=0;
    while not eof(f) do begin
      blockread(f,plr,sizeof(plr),numread);
      {if we hit the end of the file, bail out}
      if numread<sizeof(plr) then exit;
      {if we hit the central header, we're done reading filenames}
      if plr.ziplocsig=pkzip_central_header_sig then break;
      {if we didn't read a local signature, something's wrong, keep going}
      if plr.ziplocsig<>pkzip_local_header_sig then continue;
      l:=l+RoundToNearestCluster(plr.zipuncmp);
      {seek to next local header}
      seek(f,filepos(f)+plr.zipsize+plr.zipfnln+plr.zipxtraln);
    end;
    close(f);
    GetZipUncompSizeCluster:=l
  end;

{===========================================================================}

begin
  {detemine DOS cluster size}
  DOSClusterSize:=clustsize(cacheDriveNum);

  {start with maximum amount of diskspace needed to swap out all of RAM}
  estimate:=RoundToNearestCluster(config^.freeLowDOSRAM);

  {If there's an easy way to estimate uncompressed size, do it}
  if filetype='ZIP'then begin
    estimate:=estimate+GetZipUncompSizeCluster;
  end else begin
    {not something we recognize, so assume we'll need 1x the space for it}
    estimate:=estimate+RoundToNearestCluster(sizeoffile(filepath));
  end;

  EstimateCacheUsage:=estimate;
end;

end.
