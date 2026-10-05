program RoundedWinApiForm;

{$APPTYPE CONSOLE}
{$R *.res}

uses
  System.SysUtils,
  Winapi.Windows,
  API.Types in 'API\API.Types.pas',
  API.CommandLine in 'API\API.CommandLine.pas',
  API.SkiaRenderer in 'API\Engine\API.SkiaRenderer.pas',
  API.LayeredWindow in 'API\API.LayeredWindow.pas';

var
  LConfig: TWindowConfig;
  LShouldRun: Boolean;
  LWindowMgr: ILayeredWindowManager;
  LExitCode: Integer;

begin
  try
    Writeln('================================================================');
    Writeln(' Delphi 13 Florence - Skia 2D Round Corner Layered Window CLI');
    Writeln('================================================================');

    // Parse command line parameters
    if not TCommandLineParser.ParseArgs(LConfig, LShouldRun) then
    begin
      ExitCode := 1;
      Exit;
    end;

    if not LShouldRun then
    begin
      ExitCode := 0;
      Exit;
    end;

    Writeln(Format('[CLI] Starting Layered Window: %dx%d (Radius: %.1f px, Alpha: %d)',
      [LConfig.Width, LConfig.Height, LConfig.CornerRadius, LConfig.WindowAlpha]));
    Writeln(Format('[CLI] Primary Color: $%x, Accent Color: $%x',
      [LConfig.PrimaryColor, LConfig.AccentColor]));
    Writeln('[CLI] Press [ESC] in the window or terminate the console to exit.');

    // Initialize and run the Layered Win32 Window with Skia 2D direct rendering
    LWindowMgr := TLayeredWindowManager.Create;
    if not LWindowMgr.Initialize(LConfig) then
    begin
      Writeln(ErrOutput, '[Error] Failed to initialize Win32 layered Skia window.');
      ExitCode := 2;
      Exit;
    end;

    Writeln('[CLI] Layered Skia Window successfully presented on screen.');
    Writeln('[CLI] Entering Win32 message dispatch loop...');

    LExitCode := LWindowMgr.RunMessageLoop;
    Writeln(Format('[CLI] Message loop terminated. Exit code: %d', [LExitCode]));
    ExitCode := LExitCode;
  except
    on E: Exception do
    begin
      Writeln(ErrOutput, Format('[Fatal Exception] %s: %s', [E.ClassName, E.Message]));
      ExitCode := -1;
    end;
  end;
end.
