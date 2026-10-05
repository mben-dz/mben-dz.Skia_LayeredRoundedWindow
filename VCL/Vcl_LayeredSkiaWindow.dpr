program Vcl_LayeredSkiaWindow;

uses
  Vcl.Forms,
  API.Types in 'API\API.Types.pas',
  API.SkiaRenderer in 'API\API.SkiaRenderer.pas',
  Main.View in 'Main.View.pas' {MainView};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  Application.CreateForm(TMainView, MainView);
  Application.Run;
end.
