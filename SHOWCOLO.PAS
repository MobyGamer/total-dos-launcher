program showcolors;

uses
  support,
  strings,
  tdl_glob,
  totFAST,
  totSYS,
  totMSG,
  totLOOK;

Procedure PopAbout;
var
  foomsg:PMessageObj;
  loop:byte;
  avgobjsize:word;
  s:string[20];
begin
  new(foomsg,init(2,'Window Title'));
  with foomsg^ do begin
    AddLine('Window body text');
    {for loop:=0 to numAboutLines-1 do AddLine(strpas(AboutText[loop]));}
    show;
  end;
  dispose(foomsg,done);
end;



begin
  {make selected/special text black on white, everything else white on black}
  {a good reference: www.seasip.info/VintagePC/mda.html}
  (*LookTOT^.SetMenu(Bor,Tit,Icon,HiHot,HiNorm,LoHot,LoNorm,Off:byte);*)

  LookTOT^.SetMenu($0F,$09,$78,$78,$70,$01,$07,$07);
  drawExampleMenu;
  drawExamplePopup;
  readln;


  if Monitor^.ColorOn
    then begin
      LookTOT^.SetMenu($1b,$1e,$7f,$31,$3f,$1e,$17,$19);
      LookTOT^.SetWindow($19,$1e,$1e,$1b);
      faviconcol:=$1c; {bright red foreground}
    end else begin
      LookTOT^.SetMenu($0F,$09,$78,$78,$70,$01,$07,$07);
    end;

  drawExampleMenu;
  drawExamplePopup;
  readln;


  screen.clear($0f,#32);
  with LookTOT^ do begin
    screen.writeat(1,1,vMenuBorder,'MenuBorder');
    screen.writeat(1,2,vMenuTitle,'MenuTitle');
    screen.writeat(1,3,vMenuIcon,'MenuIcon');
    screen.writeat(1,4,vMenuHiHot,'MenuHiHot');
    screen.writeat(1,5,vMenuHiNorm,'MenuHiNorm');
    screen.writeat(1,6,vMenuLoHot,'MenuLoHot');
    screen.writeat(1,7,vMenuLoNorm,'MenuLoNorm');
    screen.writeat(1,8,vMenuInActive,'MenuInactive');

    screen.writeat(1,10,vWinBorder,'Window Border');
    screen.writeat(1,11,vWinBody,'Windown Body');
    screen.writeat(1,12,vWinIcons,'Window Icons');
    screen.writeat(1,13,vWinTitle,'Window Title');

    screen.WriteHI(1,15,LookTOT^.vMenuHiHot,LookTOT^.vMenuHiNorm,'Selected ~M~enubar');
    screen.WriteHI(1,16,LookTOT^.vMenuLoHot,LookTOT^.vMenuLoNorm,'Regular ~T~ext    ');

    {screen.writeat(1,21,$70,'vListLeftChar: '+vListLeftChar);
    screen.writeat(1,22,$70,'vListRightChar: '+vListRightChar);
    screen.writeat(1,23,$70,'vListToggleOnChar: '+vListToggleOnChar);
    screen.writeat(1,24,$70,'vListToggleOffChar: '+vListToggleOffChar);}
  end;
  readln;

  {popabout;}
end.