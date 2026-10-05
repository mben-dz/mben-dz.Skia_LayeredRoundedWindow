unit API.LayeredWindow;

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Diagnostics,
  System.Types,
  API.Types,
  API.SkiaRenderer;

type
  /// <summary>
  /// Manages pure Win32 Layered Window lifecycle, HDC double buffer allocation,
  /// 32-bit DIBSection, mouse events, dragging, and Skia rendering pipeline.
  /// </summary>
  TLayeredWindowManager = class(TInterfacedObject, ILayeredWindowManager)
  private
    FConfig: TWindowConfig;
    FHWnd: HWND;
    FMemDC: HDC;
    FBitmap: HBITMAP;
    FOldBitmap: HBITMAP;
    FBits: Pointer;
    FBlendFunc: BLENDFUNCTION;
    FRenderer: ISkiaLayeredRenderer;
    FUiState: TWindowUiState;
    FStopwatch: TStopwatch;
//    FIsHoveredClose: Boolean;
//    FIsHoveredMin: Boolean;
//    FIsHoveredAction: Boolean;
    FTimerId: UINT_PTR;

    procedure CreateLayeredBuffer;
    procedure DestroyLayeredBuffer;
    procedure UpdateLayeredWindowSurface;
    function WindowProc(aHwnd: HWND; aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT;
  public
    constructor Create;
    destructor Destroy; override;

    function Initialize(const aConfig: TWindowConfig): Boolean;
    function RunMessageLoop: Integer;
    procedure RequestRedraw;
    procedure Close;
  end;

implementation

const
  cWindowClassName = 'Skia2D_Layered_WindowClass';
  cTimerIdRender   = 1001;

function GlobalWindowProc(aHwnd: HWND; aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT; stdcall;
var
  LManager: TLayeredWindowManager;
begin
  if aMsg = WM_NCCREATE then
  begin
    LManager := TLayeredWindowManager(PCreateStruct(aLParam)^.lpCreateParams);
    SetWindowLongPtr(aHwnd, GWLP_USERDATA, LONG_PTR(LManager));
    Result := DefWindowProc(aHwnd, aMsg, aWParam, aLParam);
    Exit;
  end;

  LManager := TLayeredWindowManager(GetWindowLongPtr(aHwnd, GWLP_USERDATA));
  if Assigned(LManager) then
    Result := LManager.WindowProc(aHwnd, aMsg, aWParam, aLParam)
  else
    Result := DefWindowProc(aHwnd, aMsg, aWParam, aLParam);
end;

{ TLayeredWindowManager }

constructor TLayeredWindowManager.Create;
begin
  inherited Create;
  FHWnd := 0;
  FMemDC := 0;
  FBitmap := 0;
  FOldBitmap := 0;
  FBits := nil;
  FUiState := TWindowUiState.Init;
  FRenderer := TSkiaLayeredRenderer.Create;
  FStopwatch := TStopwatch.StartNew;
end;

destructor TLayeredWindowManager.Destroy;
begin
  Close;
  DestroyLayeredBuffer;
  inherited Destroy;
end;

procedure TLayeredWindowManager.CreateLayeredBuffer;
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
    LBi.bmiHeader.biPlanes     := 1;
    LBi.bmiHeader.biBitCount    := 32;
    LBi.bmiHeader.biCompression := BI_RGB;

    FBitmap := CreateDIBSection(FMemDC, LBi, DIB_RGB_COLORS, FBits, 0, 0);
    FOldBitmap := SelectObject(FMemDC, FBitmap);
  finally
    ReleaseDC(0, LScreenDC);
  end;

  // Configure 32-bit Alpha Blend parameters for UpdateLayeredWindow
  FBlendFunc.BlendOp             := AC_SRC_OVER;
  FBlendFunc.BlendFlags          := 0;
  FBlendFunc.SourceConstantAlpha := FConfig.WindowAlpha;
  FBlendFunc.AlphaFormat         := AC_SRC_ALPHA; // Premultiplied Alpha
end;

procedure TLayeredWindowManager.DestroyLayeredBuffer;
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

function TLayeredWindowManager.Initialize(const aConfig: TWindowConfig): Boolean;
var
  LWndClass: TWndClassEx;
  LExStyle: DWORD;
  LStyle: DWORD;
  LScreenW, LScreenH: Integer;
  LPosX, LPosY: Integer;
begin
  Result := False;
  FConfig := aConfig;

  // 1. Register Win32 Window Class
  ZeroMemory(@LWndClass, SizeOf(LWndClass));
  LWndClass.cbSize        := SizeOf(TWndClassEx);
  LWndClass.style         := CS_HREDRAW or CS_VREDRAW or CS_DBLCLKS;
  LWndClass.lpfnWndProc   := @GlobalWindowProc;
  LWndClass.cbClsExtra    := 0;
  LWndClass.cbWndExtra    := 0;
  LWndClass.hInstance     := HInstance;
  LWndClass.hIcon         := LoadIcon(0, IDI_APPLICATION);
  LWndClass.hCursor       := LoadCursor(0, IDC_ARROW);
  LWndClass.hbrBackground := 0; // Layered windows require null background brush
  LWndClass.lpszMenuName  := nil;
  LWndClass.lpszClassName := cWindowClassName;
  LWndClass.hIconSm       := LoadIcon(0, IDI_APPLICATION);

  RegisterClassEx(LWndClass);

  // 2. Compute screen centered position
  LScreenW := GetSystemMetrics(SM_CXSCREEN);
  LScreenH := GetSystemMetrics(SM_CYSCREEN);
  LPosX := (LScreenW - FConfig.Width) div 2;
  LPosY := (LScreenH - FConfig.Height) div 2;

  // 3. Create Layered Window
  LExStyle := WS_EX_LAYERED or WS_EX_TOPMOST or WS_EX_APPWINDOW;
  LStyle   := WS_POPUP or WS_MINIMIZEBOX or WS_VISIBLE;

  FHWnd := CreateWindowEx(
    LExStyle,
    cWindowClassName,
    PChar(FConfig.Title),
    LStyle,
    LPosX,
    LPosY,
    FConfig.Width,
    FConfig.Height,
    0,
    0,
    HInstance,
    Self
  );

  if FHWnd = 0 then
    Exit;

  // 4. Create DIB memory DC and initialize Skia direct raster surface
  CreateLayeredBuffer;
  FRenderer.Initialize(FConfig, FMemDC, FBits);

  // 5. Setup frame tick timer for smooth 60fps animations
  FTimerId := SetTimer(FHWnd, cTimerIdRender, 16, nil);

  // 6. Initial Render & Presentation
  RequestRedraw;
  ShowWindow(FHWnd, SW_SHOW);
  UpdateWindow(FHWnd);

  Result := True;
end;

procedure TLayeredWindowManager.UpdateLayeredWindowSurface;
var
  LScreenDC: HDC;
  LWindowPos: TPoint;
  LWindowSize: TSize;
  LSourcePoint: TPoint;
  LNow: UInt64;
begin
  if (FHWnd = 0) or (FMemDC = 0) then
    Exit;

  Inc(FUiState.FrameCount);
  LNow := FStopwatch.ElapsedMilliseconds;
  if LNow - FUiState.LastFpsTime >= 1000 then
  begin
    FUiState.FpsCounter := FUiState.FrameCount;
    FUiState.FrameCount := 0;
    FUiState.LastFpsTime := LNow;
  end;

  // Render using Skia 2D onto FBits
  FRenderer.RenderFrame(FUiState, FStopwatch.ElapsedMilliseconds / 1000.0);

  // Update layered window with alpha blending
  LScreenDC := GetDC(0);
  try
    LWindowPos   := Point(0, 0); // Window position queried via GetWindowRect if needed
    LWindowSize.cx := FConfig.Width;
    LWindowSize.cy := FConfig.Height;
    LSourcePoint := Point(0, 0);

    UpdateLayeredWindow(
      FHWnd,
      LScreenDC,
      nil,
      @LWindowSize,
      FMemDC,
      @LSourcePoint,
      0,
      @FBlendFunc,
      ULW_ALPHA
    );
  finally
    ReleaseDC(0, LScreenDC);
  end;
end;

procedure TLayeredWindowManager.RequestRedraw;
begin
  UpdateLayeredWindowSurface;
end;

procedure TLayeredWindowManager.Close;
begin
  if FTimerId <> 0 then
  begin
    KillTimer(FHWnd, FTimerId);
    FTimerId := 0;
  end;

  if FHWnd <> 0 then
  begin
    DestroyWindow(FHWnd);
    FHWnd := 0;
  end;
end;

function TLayeredWindowManager.RunMessageLoop: Integer;
var
  LMsg: TMsg;
begin
  while GetMessage(LMsg, 0, 0, 0) do
  begin
    TranslateMessage(LMsg);
    DispatchMessage(LMsg);
  end;
  Result := Integer(LMsg.wParam);
end;

function TLayeredWindowManager.WindowProc(aHwnd: HWND; aMsg: UINT; aWParam: WPARAM; aLParam: LPARAM): LRESULT;
var
  LMouseX, LMouseY: Integer;
  LHitCode: Integer;
  LTm: TTrackMouseEvent;
begin
  case aMsg of
    WM_TIMER:
    begin
      if aWParam = cTimerIdRender then
      begin
        RequestRedraw;
        Result := 0;
        Exit;
      end;
    end;

    WM_KEYDOWN:
    begin
      if aWParam = VK_ESCAPE then
      begin
        Writeln('[LayeredWindow] ESC pressed. Terminating...');
        PostQuitMessage(0);
        Result := 0;
        Exit;
      end;
    end;

    WM_LBUTTONDOWN:
    begin
      LMouseX := SmallInt(LOWORD(aLParam));
      LMouseY := SmallInt(HIWORD(aLParam));
      LHitCode := FRenderer.GetHitTestArea(LMouseX, LMouseY);

      SetCapture(aHwnd);
      case LHitCode of
        cHitCloseBtn:
        begin
          FUiState.CloseBtnState := bsPressed;
          FUiState.StatusMessage := 'Close button clicked.';
          RequestRedraw;
        end;

        cHitMinBtn:
        begin
          FUiState.MinBtnState := bsPressed;
          FUiState.StatusMessage := 'Minimize button clicked.';
          RequestRedraw;
        end;

        cHitActionBtn:
        begin
          FUiState.ActionBtnState := bsPressed;
          FUiState.StatusMessage := 'Console ping executed successfully!';
          Writeln(Format('[LayeredWindow Action] Button clicked at T=%.2fs! Skia renderer is healthy.', [FStopwatch.ElapsedMilliseconds / 1000.0]));
          RequestRedraw;
        end;

        cHitTitleBar, cHitClientBody:
        begin
          if FConfig.IsDraggable then
          begin
            FUiState.StatusMessage := 'Dragging layered window...';
            ReleaseCapture;
            // Native smooth Win32 caption dragging
            SendMessage(aHwnd, WM_NCLBUTTONDOWN, HTCAPTION, 0);
          end;
        end;
      end;
      Result := 0;
      Exit;
    end;

    WM_LBUTTONUP:
    begin
      ReleaseCapture;
      LMouseX := SmallInt(LOWORD(aLParam));
      LMouseY := SmallInt(HIWORD(aLParam));
      LHitCode := FRenderer.GetHitTestArea(LMouseX, LMouseY);

      if FUiState.CloseBtnState = bsPressed then
      begin
        FUiState.CloseBtnState := bsNormal;
        if LHitCode = cHitCloseBtn then
        begin
          Writeln('[LayeredWindow] Close button clicked. Exiting...');
          PostQuitMessage(0);
        end;
      end;

      if FUiState.MinBtnState = bsPressed then
      begin
        FUiState.MinBtnState := bsNormal;
        if LHitCode = cHitMinBtn then
          ShowWindow(aHwnd, SW_MINIMIZE);
      end;

      if FUiState.ActionBtnState = bsPressed then
      begin
        if LHitCode = cHitActionBtn then
          FUiState.ActionBtnState := bsHovered
        else
          FUiState.ActionBtnState := bsNormal;
      end;

      RequestRedraw;
      Result := 0;
      Exit;
    end;

    WM_MOUSEMOVE:
    begin
      LMouseX := SmallInt(LOWORD(aLParam));
      LMouseY := SmallInt(HIWORD(aLParam));
      LHitCode := FRenderer.GetHitTestArea(LMouseX, LMouseY);

      // Track mouse leave
      ZeroMemory(@LTm, SizeOf(LTm));
      LTm.cbSize := SizeOf(TTrackMouseEvent);
      LTm.dwFlags := TME_LEAVE;
      LTm.hwndTrack := aHwnd;
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

      RequestRedraw;
      Result := 0;
      Exit;
    end;

    WM_MOUSELEAVE:
    begin
      FUiState.CloseBtnState := bsNormal;
      FUiState.MinBtnState   := bsNormal;
      FUiState.ActionBtnState := bsNormal;
      RequestRedraw;
      Result := 0;
      Exit;
    end;

    WM_DESTROY:
    begin
      PostQuitMessage(0);
      Result := 0;
      Exit;
    end;
  end;

  Result := DefWindowProc(aHwnd, aMsg, aWParam, aLParam);
end;

end.