unit Main.View;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Diagnostics,
  System.Types,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.ExtCtrls,
  API.Types,
  API.SkiaRenderer;

type
  /// <summary>
  /// Real Win32 layered window, hosted directly on a VCL TForm.
  ///
  /// IMPORTANT: TCustomForm strips WS_EX_LAYERED back off a window created
  /// via CreateParams alone unless its own AlphaBlend property is True - but
  /// AlphaBlend/AlphaBlendValue work by calling SetLayeredWindowAttributes,
  /// and a window can only ever be in ONE of "SetLayeredWindowAttributes
  /// mode" or "UpdateLayeredWindow mode" for its whole life. So AlphaBlend is
  /// never touched here; CreateWnd instead forces WS_EX_LAYERED back on
  /// directly after VCL's own handling runs, keeping this window exclusively
  /// in UpdateLayeredWindow's true per-pixel-alpha mode.
  /// </summary>
  TMainView = class(TForm)
  private
    FConfig: TWindowConfig;
    FMemDC: HDC;
    FBitmap: HBITMAP;
    FOldBitmap: HBITMAP;
    FBits: Pointer;
    FBlendFunc: BLENDFUNCTION;
    FRenderer: ISkiaLayeredRenderer;
    FUiState: TWindowUiState;
    FStopwatch: TStopwatch;
    FTimer: TTimer;

    procedure CreateLayeredBuffer;
    procedure DestroyLayeredBuffer;
    procedure UpdateLayeredWindowSurface;
    procedure TimerTick(aSender: TObject);

    procedure WMEraseBkgnd(var aMessage: TWMEraseBkgnd); message WM_ERASEBKGND;
    procedure WMLButtonDown(var aMessage: TWMLButtonDown); message WM_LBUTTONDOWN;
    procedure WMLButtonUp(var aMessage: TWMLButtonUp); message WM_LBUTTONUP;
    procedure WMMouseMove(var aMessage: TWMMouseMove); message WM_MOUSEMOVE;
    procedure WMMouseLeave(var aMessage: TMessage); message WM_MOUSELEAVE;
    procedure WMKeyDown(var aMessage: TWMKeyDown); message WM_KEYDOWN;
  protected
    procedure CreateParams(var aParams: TCreateParams); override;
    procedure CreateWnd; override;
  public
    constructor Create(aOwner: TComponent); override;
    destructor Destroy; override;
  end;

var
  MainView: TMainView;

implementation

{$R *.dfm}

{ TMainView }

procedure TMainView.CreateParams(var aParams: TCreateParams);
begin
  inherited CreateParams(aParams);
  // Gets the window created with WS_EX_LAYERED from the start; CreateWnd
  // below re-asserts it afterwards since VCL may strip it back off.
  aParams.ExStyle := aParams.ExStyle or WS_EX_LAYERED or WS_EX_APPWINDOW;
  aParams.WindowClass.Style := aParams.WindowClass.Style or CS_HREDRAW or CS_VREDRAW or CS_DBLCLKS;
end;

procedure TMainView.CreateWnd;
begin
  inherited CreateWnd;
  // AlphaBlend is deliberately left at its default False everywhere in this
  // unit - setting it would make VCL call SetLayeredWindowAttributes, which
  // permanently locks the window into "attribute" layered mode and makes
  // every later UpdateLayeredWindow call fail with ERROR_INVALID_PARAMETER
  // (error 87). Instead we force WS_EX_LAYERED back on directly, here, after
  // VCL has finished its own CreateWnd handling, so this window is only ever
  // touched by UpdateLayeredWindow (true per-pixel alpha mode).
  SetWindowLongPtr(Handle, GWL_EXSTYLE, GetWindowLongPtr(Handle, GWL_EXSTYLE) or WS_EX_LAYERED);
end;

constructor TMainView.Create(aOwner: TComponent);
begin
  FConfig := TWindowConfig.CreateDefault;

  inherited Create(aOwner);

  // Must be set before the HWND is realized so CreateParams/CreateWnd pick
  // these up.
  BorderStyle := bsNone;
  Position := poDesigned;
  Caption := FConfig.Title;
  SetBounds(
    (Screen.WorkAreaWidth - FConfig.Width) div 2,
    (Screen.WorkAreaHeight - FConfig.Height) div 2,
    FConfig.Width,
    FConfig.Height
  );

  FUiState := TWindowUiState.Init;
  FRenderer := TSkiaLayeredRenderer.Create;
  FStopwatch := TStopwatch.StartNew;

  CreateLayeredBuffer;
  FRenderer.Initialize(FConfig, FMemDC, FBits);

  FTimer := TTimer.Create(Self);
  FTimer.Interval := 16; // ~60 fps, same cadence as the console app's SetTimer
  FTimer.OnTimer := TimerTick;
  FTimer.Enabled := True;

  UpdateLayeredWindowSurface;
end;

destructor TMainView.Destroy;
begin
  if Assigned(FTimer) then
    FTimer.Enabled := False;
  DestroyLayeredBuffer;
  FRenderer := nil;
  inherited Destroy;
end;

procedure TMainView.CreateLayeredBuffer;
var
  LScreenDC: HDC;
  LBi: TBitmapInfo;
begin
  DestroyLayeredBuffer;

  LScreenDC := GetDC(0);
  try
    FMemDC := CreateCompatibleDC(LScreenDC);

    ZeroMemory(@LBi, SizeOf(LBi));
    LBi.bmiHeader.biSize        := SizeOf(TBitmapInfoHeader);
    LBi.bmiHeader.biWidth       := FConfig.Width;
    LBi.bmiHeader.biHeight      := -FConfig.Height; // Top-down DIB
    LBi.bmiHeader.biPlanes      := 1;
    LBi.bmiHeader.biBitCount    := 32;
    LBi.bmiHeader.biCompression := BI_RGB;

    FBitmap := CreateDIBSection(FMemDC, LBi, DIB_RGB_COLORS, FBits, 0, 0);
    FOldBitmap := SelectObject(FMemDC, FBitmap);
  finally
    ReleaseDC(0, LScreenDC);
  end;

  FBlendFunc.BlendOp             := AC_SRC_OVER;
  FBlendFunc.BlendFlags          := 0;
  FBlendFunc.SourceConstantAlpha := FConfig.WindowAlpha;
  FBlendFunc.AlphaFormat         := AC_SRC_ALPHA;
end;

procedure TMainView.DestroyLayeredBuffer;
begin
  if FMemDC <> 0 then
  begin
    if FOldBitmap <> 0 then
    begin
      SelectObject(FMemDC, FOldBitmap);
      FOldBitmap := 0;
    end;
    if FBitmap <> 0 then
    begin
      DeleteObject(FBitmap);
      FBitmap := 0;
    end;
    DeleteDC(FMemDC);
    FMemDC := 0;
  end;
  FBits := nil;
end;

procedure TMainView.UpdateLayeredWindowSurface;
var
  LScreenDC: HDC;
  LWindowSize: TSize;
  LSourcePoint: TPoint;
  LNow: UInt64;
  LOk: BOOL;
begin
  if (not HandleAllocated) or (FMemDC = 0) or (FBits = nil) then
    Exit;

  Inc(FUiState.FrameCount);
  LNow := FStopwatch.ElapsedMilliseconds;
  if LNow - FUiState.LastFpsTime >= 1000 then
  begin
    FUiState.FpsCounter := FUiState.FrameCount;
    FUiState.FrameCount := 0;
    FUiState.LastFpsTime := LNow;
  end;

  FRenderer.RenderFrame(FUiState, FStopwatch.ElapsedMilliseconds / 1000.0);

  LScreenDC := GetDC(0);
  try
    LWindowSize.cx := FConfig.Width;
    LWindowSize.cy := FConfig.Height;
    LSourcePoint := Point(0, 0);

    LOk := UpdateLayeredWindow(
      Handle,
      LScreenDC,
      nil,
      @LWindowSize,
      FMemDC,
      @LSourcePoint,
      0,
      @FBlendFunc,
      ULW_ALPHA
    );

    if not LOk then
      OutputDebugString(PChar('ULW: UpdateLayeredWindow FAILED, GetLastError=' + IntToStr(GetLastError)));
  finally
    ReleaseDC(0, LScreenDC);
  end;
end;

procedure TMainView.TimerTick(aSender: TObject);
begin
  UpdateLayeredWindowSurface;
end;

procedure TMainView.WMEraseBkgnd(var aMessage: TWMEraseBkgnd);
begin
  aMessage.Result := 1;
end;

procedure TMainView.WMKeyDown(var aMessage: TWMKeyDown);
begin
  if aMessage.CharCode = VK_ESCAPE then
  begin
    Close;
    aMessage.Result := 0;
    Exit;
  end;
  inherited;
end;

procedure TMainView.WMLButtonDown(var aMessage: TWMLButtonDown);
var
  LHitCode: Integer;
begin
  LHitCode := FRenderer.GetHitTestArea(aMessage.XPos, aMessage.YPos);

  SetCapture(Handle);
  case LHitCode of
    cHitCloseBtn:
      begin
        FUiState.CloseBtnState := bsPressed;
        FUiState.StatusMessage := 'Close button clicked.';
        UpdateLayeredWindowSurface;
      end;

    cHitMinBtn:
      begin
        FUiState.MinBtnState := bsPressed;
        FUiState.StatusMessage := 'Minimize button clicked.';
        UpdateLayeredWindowSurface;
      end;

    cHitActionBtn:
      begin
        FUiState.ActionBtnState := bsPressed;
        FUiState.StatusMessage := 'Console ping executed successfully!';
        UpdateLayeredWindowSurface;
      end;

    cHitTitleBar, cHitClientBody:
      begin
        if FConfig.IsDraggable then
        begin
          ReleaseCapture;
          SendMessage(Handle, WM_NCLBUTTONDOWN, HTCAPTION, 0);
        end;
      end;
  end;

  aMessage.Result := 0;
end;

procedure TMainView.WMLButtonUp(var aMessage: TWMLButtonUp);
var
  LHitCode: Integer;
begin
  ReleaseCapture;
  LHitCode := FRenderer.GetHitTestArea(aMessage.XPos, aMessage.YPos);

  if FUiState.CloseBtnState = bsPressed then
  begin
    FUiState.CloseBtnState := bsNormal;
    if LHitCode = cHitCloseBtn then
    begin
      Close;
      Exit;
    end;
  end;

  if FUiState.MinBtnState = bsPressed then
  begin
    FUiState.MinBtnState := bsNormal;
    if LHitCode = cHitMinBtn then
      ShowWindow(Handle, SW_MINIMIZE);
  end;

  if FUiState.ActionBtnState = bsPressed then
  begin
    if LHitCode = cHitActionBtn then
      FUiState.ActionBtnState := bsHovered
    else
      FUiState.ActionBtnState := bsNormal;
  end;

  UpdateLayeredWindowSurface;
  aMessage.Result := 0;
end;

procedure TMainView.WMMouseMove(var aMessage: TWMMouseMove);
var
  LHitCode: Integer;
  LTm: TTrackMouseEvent;
begin
  LHitCode := FRenderer.GetHitTestArea(aMessage.XPos, aMessage.YPos);

  ZeroMemory(@LTm, SizeOf(LTm));
  LTm.cbSize := SizeOf(TTrackMouseEvent);
  LTm.dwFlags := TME_LEAVE;
  LTm.hwndTrack := Handle;
  TrackMouseEvent(LTm);

  FUiState.CloseBtnState := bsNormal;
  FUiState.MinBtnState   := bsNormal;
  if FUiState.ActionBtnState <> bsPressed then
    FUiState.ActionBtnState := bsNormal;

  case LHitCode of
    cHitCloseBtn:
      FUiState.CloseBtnState := bsHovered;
    cHitMinBtn:
      FUiState.MinBtnState := bsHovered;
    cHitActionBtn:
      if FUiState.ActionBtnState <> bsPressed then
        FUiState.ActionBtnState := bsHovered;
  end;

  UpdateLayeredWindowSurface;
  aMessage.Result := 0;
end;

procedure TMainView.WMMouseLeave(var aMessage: TMessage);
begin
  FUiState.CloseBtnState  := bsNormal;
  FUiState.MinBtnState    := bsNormal;
  FUiState.ActionBtnState := bsNormal;
  UpdateLayeredWindowSurface;
end;

end.
