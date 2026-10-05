unit API.Types;

{$ALIGN 8}
{$MINENUMSIZE 4}

interface

uses
  Winapi.Windows,
  System.SysUtils;

type
  /// <summary>
  /// Configuration options parsed from command line or set programmatically.
  /// </summary>
  TWindowConfig = record
    Width: Integer;
    Height: Integer;
    CornerRadius: Single;
    WindowAlpha: Byte;
    Title: string;
    Subtitle: string;
    PrimaryColor: Cardinal;
    SecondaryColor: Cardinal;
    AccentColor: Cardinal;
    EnableShadow: Boolean;
    ShadowBlur: Single;
    ShadowOffset: Single;
    ShowCloseButton: Boolean;
    ShowMinimizeButton: Boolean;
    IsDraggable: Boolean;
    class function CreateDefault: TWindowConfig; static;
  end;

  /// <summary>
  /// State of interactive UI elements rendered on the layered Skia surface.
  /// </summary>
  TButtonState = (bsNormal, bsHovered, bsPressed);

  TWindowUiState = record
    CloseBtnState: TButtonState;
    MinBtnState: TButtonState;
    ActionBtnState: TButtonState;
    IsDragging: Boolean;
    LastMouseX: Integer;
    LastMouseY: Integer;
    FpsCounter: Integer;
    FrameCount: Integer;
    LastFpsTime: UInt64;
    StatusMessage: string;
    class function Init: TWindowUiState; static;
  end;

  /// <summary>
  /// Skia layered renderer interface contract.
  /// </summary>
  ISkiaLayeredRenderer = interface
    ['{8E1A5B72-9214-4B33-9E9A-C1A2B5E749F1}']
    procedure Initialize(const aConfig: TWindowConfig; const aHdcTarget: HDC; const aBits: Pointer);
    procedure Resize(const aWidth, aHeight: Integer; const aBits: Pointer);
    procedure RenderFrame(const aUiState: TWindowUiState; const aTimeSec: Double);
    function GetHitTestArea(const aX, aY: Integer): Integer;
  end;

  /// <summary>
  /// Win32 layered host interface contract.
  /// </summary>
  ILayeredWindowManager = interface
    ['{3D66A8C2-114F-4C87-8A7B-9022EB74601A}']
    function Initialize(const aConfig: TWindowConfig): Boolean;
    function RunMessageLoop: Integer;
    procedure RequestRedraw;
    procedure Close;
  end;

const
  cHitNowhere     = 0;
  cHitTitleBar    = 1;
  cHitCloseBtn    = 2;
  cHitMinBtn      = 3;
  cHitActionBtn   = 4;
  cHitClientBody  = 5;

implementation

{ TWindowConfig }

class function TWindowConfig.CreateDefault: TWindowConfig;
begin
  Result.Width              := 780;
  Result.Height             := 480;
  Result.CornerRadius       := 28.0;
  Result.WindowAlpha        := 250;
  Result.Title              := 'Skia 2D Layered Window';
  Result.Subtitle           := 'Pure Win32 Headless Console Backend - Delphi 13 Florence';
  Result.PrimaryColor       := $FF1A1C23;  // Dark slate (AARRGGBB)
  Result.SecondaryColor     := $FF282B37;  // Gradient bottom
  Result.AccentColor        := $FF3B82F6;  // Electric Blue
  Result.EnableShadow       := True;
  Result.ShadowBlur         := 24.0;
  Result.ShadowOffset       := 12.0;
  Result.ShowCloseButton    := True;
  Result.ShowMinimizeButton := True;
  Result.IsDraggable        := True;
end;

{ TWindowUiState }

class function TWindowUiState.Init: TWindowUiState;
begin
  Result.CloseBtnState  := bsNormal;
  Result.MinBtnState    := bsNormal;
  Result.ActionBtnState := bsNormal;
  Result.IsDragging     := False;
  Result.LastMouseX     := 0;
  Result.LastMouseY     := 0;
  Result.FpsCounter     := 0;
  Result.FrameCount     := 0;
  Result.LastFpsTime    := 0;
  Result.StatusMessage  := 'Ready. Click or Drag Window Body.';
end;

end.