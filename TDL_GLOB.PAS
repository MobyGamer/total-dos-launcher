unit tdl_glob;
{
Contains global constants and type definitions.
}

interface

uses
  support;

const
  maxTitles=maxbufsize div sizeof(word);
  maxCacheableTitles=maxbufsize div sizeof(longint);
  TDLtitleFull='The Total DOS Launcher, v. 0.2, 20170320';
  TDLtitle='The Total DOS Launcher';
  (*TDLstatus='F1=Help~³~'#24'/'#25'/PgUp/PgDn/Home/End = Navigate~³~Enter = START~³~ESC=exit~³~';*)
  TDLstatus='F1=Help~³~'#24'/'#25'/PgUp/PgDn/Home/End = Navigate~³~Enter = LAUNCH~³~ESC = exit~³~';
  jumpLabel='Jump by letter: ';

  numAboutLines=9;
  AboutText:array[0..numAboutLines-1] of pChar=(
    '',
    ' Project originator: Jim Leonard',
    ' ',
    ' We owe a debt of gratitude to:',
    '   Randy Hyde (swapping tech)',
    '   Duncan Murdoch (stream tricks)',
    '   Norbert Juffa (system library optimization)',
    '   Bob Ainsbury (interface primitives)',
    ''
  );

  favicon=#03;

type
  PTitleArray=^TTitleArray;
  TTitleArray=array[0..maxTitles] of word;

  PTitleOffsets=^TTitleOffsets;
  TTitleOffsets=array[0..maxCacheableTitles-1] of longint;

  PFavoritesArray=^TFavoritesArray;
  TFavoritesArray=array[0..maxTitles-1] of boolean;

  baseftype=string[12];
  cmdlinetype=string[127-sizeof(baseftype)];
  titleStrType=string[132]; {Max screenmode we'll support is 132x60}

  handlertype=(extraction,execution);
  userlevels=(kiosk,regular,power);

  MD5hash=array[0..15] of byte;

implementation

end.