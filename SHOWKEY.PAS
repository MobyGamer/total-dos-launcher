program showkey;

uses
  totKEY,
  totINPUT;

var
  w:word;

begin
  repeat
    key.getkey;
    writeln('Pressed: ',key.lastchar,' (',key.lastkey,')');
  until key.lastkey=kEsc;
end.