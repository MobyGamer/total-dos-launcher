program showcolors;

uses
  support,
  totFAST,
  totSYS,
  totLOOK;

begin
  {make selected/special text black on white, everything else white on black}
  {a good reference: www.seasip.info/VintagePC/mda.html}
  (*LookTOT^.SetMenu(Bor,Tit,Icon,HiHot,HiNorm,LoHot,LoNorm,Off:byte);*)
  If Monitor^.ColorOn
    then LookTOT^.SetMenu($1b,$1e,$7f,$31,$3f,$1e,$17,$19)
    else LookTOT^.SetMenu($0F,$09,$78,$78,$70,$01,$07,$07);

  screen.clear($0f,#32);
  with LookTOT^ do begin
    screen.writeat(1,1,vWinBorder,'vWinBorder');
    screen.writeat(1,2,vWinBody,'vWinBody');
    screen.writeat(1,3,vWinTitle,'vWinTitle');
    screen.writeat(1,4,vWinIcons,'vWinIcons');
    screen.writeat(1,8,vMenuBorder,'vMenuBorder');
    screen.writeat(1,9,vMenuTitle,'vMenuTitle');
    screen.writeat(1,10,vMenuIcon,'vMenuIcon');
    screen.writeat(1,11,vMenuHiHot,'vMenuHiHot');
    screen.writeat(1,12,vMenuHiNorm,'vMenuHiNorm');
    screen.writeat(1,13,vMenuLoHot,'vMenuLoHot');
    screen.writeat(1,14,vMenuLoNorm,'vMenuLoNorm');
    screen.writeat(1,15,vMenuInActive,'vMenuInActive');

    screen.WriteHI(1,17,LookTOT^.vMenuHiHot,LookTOT^.vMenuHiNorm,'Selected ~M~enubar');
    screen.WriteHI(1,18,LookTOT^.vMenuLoHot,LookTOT^.vMenuLoNorm,'Regular ~T~ext    ');

    screen.writeat(1,21,$70,'vListLeftChar: '+vListLeftChar);
    screen.writeat(1,22,$70,'vListRightChar: '+vListRightChar);
    screen.writeat(1,23,$70,'vListToggleOnChar: '+vListToggleOnChar);
    screen.writeat(1,24,$70,'vListToggleOffChar: '+vListToggleOffChar);
  end;
  readln;
end.