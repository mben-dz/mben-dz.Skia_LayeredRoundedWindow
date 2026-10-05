unit API.CommandLine;

interface

uses
  System.SysUtils,
  System.StrUtils,
  API.Types;

type
  /// <summary>
  /// Robust command line parser for the Console Layered Window application.
  /// Supports flags: -w, --width, -h, --height, -r, --radius, -a, --alpha,
  ///                 -t, --title, --shadow, --no-shadow, -? , --help
  /// </summary>
  TCommandLineParser = class
  private
    class function HexToColor(const aHex: string; const aDefault: Cardinal): Cardinal; static;
  public
    class procedure PrintUsage; static;
    class function ParseArgs(out aConfig: TWindowConfig; out aShouldRun: Boolean): Boolean; static;
  end;

implementation

{ TCommandLineParser }

class function TCommandLineParser.HexToColor(const aHex: string; const aDefault: Cardinal): Cardinal;
var
  LClean: string;
  LVal: UInt64;
begin
  LClean := aHex.Trim.Replace('#', '').Replace('$', '').Replace('0x', '', [rfIgnoreCase]);
  if (Length(LClean) = 6) then
    LClean := 'FF' + LClean;
  if TryStrToUInt64('$' + LClean, LVal) then
    Result := Cardinal(LVal)
  else
    Result := aDefault;
end;

class procedure TCommandLineParser.PrintUsage;
begin
  Writeln('================================================================');
  Writeln(' RoundedWinApiForm - Layered Skia 2D Window (Delphi Florence 13)');
  Writeln('================================================================');
  Writeln('Usage: RoundedWinApiForm [options]');
  Writeln('');
  Writeln('Options:');
  Writeln('  -w, --width <pixels>       Window width  (default: 780)');
  Writeln('  -h, --height <pixels>      Window height (default: 480)');
  Writeln('  -r, --radius <pixels>      Corner radius (default: 28)');
  Writeln('  -a, --alpha <0..255>       Per-window alpha transparency (default: 250)');
  Writeln('  -t, --title <string>       Window title string');
  Writeln('      --subtitle <string>    Window subtitle string');
  Writeln('      --color-primary <hex>  ARGB or RGB hex (e.g. #1E2028)');
  Writeln('      --color-accent <hex>   ARGB or RGB hex (e.g. #3B82F6)');
  Writeln('      --no-shadow            Disable drop shadow around rounded corners');
  Writeln('      --help, -?             Show this help screen and exit');
  Writeln('');
  Writeln('Interactive controls:');
  Writeln('  * Click and drag the window surface to move it freely.');
  Writeln('  * Click the top-right [X] button or press ESC to terminate.');
  Writeln('  * Click the top-right [-] button to minimize to taskbar.');
  Writeln('================================================================');
end;

class function TCommandLineParser.ParseArgs(out aConfig: TWindowConfig; out aShouldRun: Boolean): Boolean;
var
  LIndex: Integer;
  LParam: string;
  LKey: string;
  LVal: string;
  LEqPos: Integer;
  LIntVal: Integer;
begin
  Result := True;
  aShouldRun := True;
  aConfig := TWindowConfig.CreateDefault;

  LIndex := 1;
  while LIndex <= ParamCount do
  begin
    LParam := ParamStr(LIndex);
    LEqPos := Pos('=', LParam);

    if LEqPos > 0 then
    begin
      LKey := Copy(LParam, 1, LEqPos - 1).ToLower;
      LVal := Copy(LParam, LEqPos + 1, Length(LParam));
    end
    else
    begin
      LKey := LParam.ToLower;
      if (LIndex + 1 <= ParamCount) and not ParamStr(LIndex + 1).StartsWith('-') then
      begin
        Inc(LIndex);
        LVal := ParamStr(LIndex);
      end
      else
        LVal := '';
    end;

    if (LKey = '-?') or (LKey = '--help') or (LKey = '/?') or (LKey = '-h' + 'elp') then
    begin
      PrintUsage;
      aShouldRun := False;
      Exit;
    end
    else if (LKey = '-w') or (LKey = '--width') then
    begin
      if TryStrToInt(LVal, LIntVal) and (LIntVal >= 200) and (LIntVal <= 3840) then
        aConfig.Width := LIntVal;
    end
    else if (LKey = '-h') or (LKey = '--height') then
    begin
      if TryStrToInt(LVal, LIntVal) and (LIntVal >= 150) and (LIntVal <= 2160) then
        aConfig.Height := LIntVal;
    end
    else if (LKey = '-r') or (LKey = '--radius') then
    begin
      if TryStrToInt(LVal, LIntVal) and (LIntVal >= 0) and (LIntVal <= 200) then
        aConfig.CornerRadius := LIntVal;
    end
    else if (LKey = '-a') or (LKey = '--alpha') then
    begin
      if TryStrToInt(LVal, LIntVal) and (LIntVal >= 10) and (LIntVal <= 255) then
        aConfig.WindowAlpha := Byte(LIntVal);
    end
    else if (LKey = '-t') or (LKey = '--title') then
    begin
      if LVal <> '' then
        aConfig.Title := LVal;
    end
    else if (LKey = '--subtitle') then
    begin
      if LVal <> '' then
        aConfig.Subtitle := LVal;
    end
    else if (LKey = '--color-primary') then
    begin
      aConfig.PrimaryColor := HexToColor(LVal, aConfig.PrimaryColor);
    end
    else if (LKey = '--color-accent') then
    begin
      aConfig.AccentColor := HexToColor(LVal, aConfig.AccentColor);
    end
    else if (LKey = '--no-shadow') then
    begin
      aConfig.EnableShadow := False;
    end;

    Inc(LIndex);
  end;
end;

end.