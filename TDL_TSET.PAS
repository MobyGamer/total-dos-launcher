{$I tdl_dire.inc}

{$IFDEF USEOVERLAYS}
{$O+,F+}
{$ENDIF}

unit tdl_tset;

{
Unit to handle "title sets": Data structures that contain a set of
16-bit word title IDs.  The main menu screen "title picker" works
against a title set.

The initial title set contains all titleIDs in the index (ie. everything).
Later, if the user wants to see only favorites via CTRL-F, a new title set
is built from only titles marked as a favorite, and then that
title set becomes the active title set.

Title sets are also used with search-as-you-type:
Each successful word input by the user is used to build subsequent title sets
that narrow down the filter results.  If the user's filter goes backwards
by the user backspacing, previous title sets can be cached so that the
results display updates instantly.

The intrepid coder will no doubt be wondering at this point why there are
no .insert() or .delete() or other routines in the TTitleSet object
other than init() and done:  This is because we need to be able to build
and tear down title sets very quickly, and populating a 1000-item title set
using 1000 .insert() CALLs on a 4.77 MHz system is not going to fly here.
So, the object mostly serves to correctly alloc/dealloc title set arrays.
}

interface

uses
  objects,
  tdl_glob;

const
  maxTitleSets=16;
  activeSet:byte=0;

type
  PTitleSet=^TTitleSet;
  TTitleSet=object(TObject)
    PUBLIC
    numTitles:word;
    TitleIDs:PTitleArray;

    Constructor Init(numElements:word);
    Destructor Done; VIRTUAL;
  end;

implementation

Constructor TTitleSet.Init;
begin
  Inherited Init;
  numTitles:=numElements;
  getmem(TitleIDs,numTitles * sizeof(word));
end;

Destructor TTitleSet.Done;
begin
  freemem(TitleIDs,numTitles * sizeof(word));
  Inherited Done;
end;

end.