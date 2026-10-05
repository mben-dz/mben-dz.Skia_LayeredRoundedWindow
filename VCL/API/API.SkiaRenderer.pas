unit API.SkiaRenderer;

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Types,
  System.UITypes,
  System.Math,
  System.Math.Vectors,
  Skia,
  API.Types;

type
  /// <summary>
  /// High-performance Skia 2D rendering engine.
  /// Draws anti-aliased round-corner surfaces with drop-shadows, gradients,
  /// glow effects, glassmorphism cards, and interactive controls directly
  /// into a shared 32-bit ARGB DIBSection buffer for UpdateLayeredWindow.
  /// </summary>
  TSkiaLayeredRenderer = class(TInterfacedObject, ISkiaLayeredRenderer)
  private
    FConfig: TWindowConfig;
    FSurface: ISkSurface;
    FCanvas: ISkCanvas;
    FWidth: Integer;
    FHeight: Integer;
    FBits: Pointer;
    FCloseBtnRect: TRectF;
    FMinBtnRect: TRectF;
    FActionBtnRect: TRectF;
    FShadowMargin: Single;

    procedure DrawBackgroundAndShadow(const aTimeSec: Double);
    procedure DrawHeader(const aUiState: TWindowUiState);
    procedure DrawInteractiveBody(const aUiState: TWindowUiState; const aTimeSec: Double);
    procedure DrawWindowControls(const aUiState: TWindowUiState);
    procedure DrawFooter(const aUiState: TWindowUiState);
  public
    constructor Create;
    destructor Destroy; override;

    procedure Initialize(const aConfig: TWindowConfig; const aHdcTarget: HDC; const aBits: Pointer);
    procedure Resize(const aWidth, aHeight: Integer; const aBits: Pointer);
    procedure RenderFrame(const aUiState: TWindowUiState; const aTimeSec: Double);
    function GetHitTestArea(const aX, aY: Integer): Integer;
  end;

implementation

{ TSkiaLayeredRenderer }

constructor TSkiaLayeredRenderer.Create;
begin
  inherited Create;
  FShadowMargin := 24.0;
end;

destructor TSkiaLayeredRenderer.Destroy;
begin
  FCanvas := nil;
  FSurface := nil;
  inherited Destroy;
end;

procedure TSkiaLayeredRenderer.Initialize(const aConfig: TWindowConfig; const aHdcTarget: HDC; const aBits: Pointer);
begin
  FConfig := aConfig;
  if not FConfig.EnableShadow then
    FShadowMargin := 0.0
  else
    FShadowMargin := 24.0;

  Resize(FConfig.Width, FConfig.Height, aBits);
end;

procedure TSkiaLayeredRenderer.Resize(const aWidth, aHeight: Integer; const aBits: Pointer);
var
  LImageInfo: TSkImageInfo;
  LRowBytes: NativeInt;
begin
  FWidth := aWidth;
  FHeight := aHeight;
  FBits := aBits;

  if (FWidth <= 0) or (FHeight <= 0) or (FBits = nil) then
    Exit;

  // 32-bit Premultiplied BGRA matches Windows DIBSection ARGB format exactly
  LImageInfo := TSkImageInfo.Create(FWidth, FHeight, TSkColorType.BGRA8888, TSkAlphaType.Premul);
  LRowBytes := FWidth * 4;

  // Zero-copy raster surface directly pointing to DIBSection memory
  FSurface := TSkSurface.MakeRasterDirect(LImageInfo, FBits, LRowBytes);
  if FSurface <> nil then
    FCanvas := FSurface.Canvas
  else
    FCanvas := nil;
end;

procedure TSkiaLayeredRenderer.RenderFrame(const aUiState: TWindowUiState; const aTimeSec: Double);
begin
  if FCanvas = nil then
    Exit;

  // Clear surface with total transparency (alpha = 0)
  FCanvas.Clear(TAlphaColors.Null);

  DrawBackgroundAndShadow(aTimeSec);
  DrawHeader(aUiState);
  DrawInteractiveBody(aUiState, aTimeSec);
  DrawWindowControls(aUiState);
  DrawFooter(aUiState);

  // Flush pending Skia GPU/CPU instructions into the underlying buffer
//  FCanvas.Flush; // undeclared identifier!!
end;

procedure TSkiaLayeredRenderer.DrawBackgroundAndShadow(const aTimeSec: Double);
var
  LBodyRect: TRectF;
  LRRect: ISkRoundRect;
  LPaint: ISkPaint;
  LShadowPaint: ISkPaint;
  LGradientShader: ISkShader;
  LBorderPaint: ISkPaint;
  LColors: TArray<TAlphaColor>;
  LPositions: TArray<Single>;
begin
  LBodyRect := TRectF.Create(
    FShadowMargin,
    FShadowMargin,
    FWidth - FShadowMargin,
    FHeight - FShadowMargin
  );

  LRRect := TSkRoundRect.Create;
  LRRect.SetRect(LBodyRect, FConfig.CornerRadius, FConfig.CornerRadius);

  // 1. Drop shadow rendering
  if FConfig.EnableShadow then
  begin
    LShadowPaint := TSkPaint.Create;
    LShadowPaint.AntiAlias := True;
    LShadowPaint.Style := TSkPaintStyle.Fill;
    LShadowPaint.Color := $55000000;
    LShadowPaint.MaskFilter := TSkMaskFilter.MakeBlur(TSkBlurStyle.Normal, FConfig.ShadowBlur);

    FCanvas.Save;
    FCanvas.Translate(0, FConfig.ShadowOffset * 0.5);
    FCanvas.DrawRoundRect(LRRect, LShadowPaint);
    FCanvas.Restore;
  end;

  // 2. Window Body Background with smooth multi-stop gradient
  LPaint := TSkPaint.Create;
  LPaint.AntiAlias := True;
  LPaint.Style := TSkPaintStyle.Fill;

  SetLength(LColors, 3);
  LColors[0] := FConfig.PrimaryColor;
  LColors[1] := FConfig.SecondaryColor;
  LColors[2] := $FF12141A;

  SetLength(LPositions, 3);
  LPositions[0] := 0.0;
  LPositions[1] := 0.65;
  LPositions[2] := 1.0;

  LGradientShader := TSkShader.MakeGradientLinear(
    PointF(LBodyRect.Left, LBodyRect.Top),
    PointF(LBodyRect.Right, LBodyRect.Bottom),
    LColors,
    LPositions,
    TSkTileMode.Clamp
  );
  LPaint.Shader := LGradientShader;
  FCanvas.DrawRoundRect(LRRect, LPaint);

  // 3. Subtle Outer Glow / Border for high-DPI crispness
  LBorderPaint := TSkPaint.Create;
  LBorderPaint.AntiAlias := True;
  LBorderPaint.Style := TSkPaintStyle.Stroke;
  LBorderPaint.StrokeWidth := 1.2;
  LBorderPaint.Color := $33FFFFFF; // Crisp semi-transparent white outline
  FCanvas.DrawRoundRect(LRRect, LBorderPaint);
end;

procedure TSkiaLayeredRenderer.DrawHeader(const aUiState: TWindowUiState);
var
  LFont: ISkFont;
  LPaint: ISkPaint;
  LTextX, LTextY: Single;
begin
  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Bold), 20);
  LPaint := TSkPaint.Create;
  LPaint.AntiAlias := True;
  LPaint.Color := $FFFFFFFF;

  LTextX := FShadowMargin + 28;
  LTextY := FShadowMargin + 42;

  // App Title
  FCanvas.DrawSimpleText(FConfig.Title, LTextX, LTextY, LFont, LPaint);

  // Subtitle
  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Normal), 12);
  LPaint.Color := $88A0AEC0;
  FCanvas.DrawSimpleText(FConfig.Subtitle, LTextX, LTextY + 20, LFont, LPaint);
end;

procedure TSkiaLayeredRenderer.DrawInteractiveBody(const aUiState: TWindowUiState; const aTimeSec: Double);
var
  LCardRect: TRectF;
  LCardRRect: ISkRoundRect;
  LCardPaint: ISkPaint;
  LCardBorder: ISkPaint;
  LFont: ISkFont;
  LPaint: ISkPaint;
  LStatusText: string;
  LPulseAlpha: Byte;
  LGlowRadius: Single;
begin
  // Inner Glassmorphism Card
  LCardRect := TRectF.Create(
    FShadowMargin + 28,
    FShadowMargin + 85,
    FWidth - FShadowMargin - 28,
    FHeight - FShadowMargin - 65
  );

  LCardRRect := TSkRoundRect.Create;
  LCardRRect.SetRect(LCardRect, 16.0, 16.0);

  // Card Background
  LCardPaint := TSkPaint.Create;
  LCardPaint.AntiAlias := True;
  LCardPaint.Color := $18FFFFFF; // 10% translucent white
  FCanvas.DrawRoundRect(LCardRRect, LCardPaint);

  // Card Border
  LCardBorder := TSkPaint.Create;
  LCardBorder.AntiAlias := True;
  LCardBorder.Style := TSkPaintStyle.Stroke;
  LCardBorder.StrokeWidth := 1.0;
  LCardBorder.Color := $22FFFFFF;
  FCanvas.DrawRoundRect(LCardRRect, LCardBorder);

  // Animated Skia Pulse Dot
  LPulseAlpha := Byte(120 + Round(100 * Sin(aTimeSec * 4.0)));
  LGlowRadius := 6.0 + 2.0 * Sin(aTimeSec * 4.0);

  LPaint := TSkPaint.Create;
  LPaint.AntiAlias := True;
  LPaint.Style := TSkPaintStyle.Fill;
  LPaint.Color := (Cardinal(LPulseAlpha) shl 24) or (FConfig.AccentColor and $00FFFFFF);
  FCanvas.DrawCircle(LCardRect.Left + 25, LCardRect.Top + 32, LGlowRadius + 3, LPaint);

  LPaint.Color := FConfig.AccentColor;
  FCanvas.DrawCircle(LCardRect.Left + 25, LCardRect.Top + 32, 5.0, LPaint);

  // Engine Active Text
  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Bold), 13);
  LPaint.Color := $FFE2E8F0;
  FCanvas.DrawSimpleText('Skia Native Vector Canvas Active', LCardRect.Left + 42, LCardRect.Top + 37, LFont, LPaint);

  // Status and Diagnostic Info
  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Consolas', TSkFontStyle.Normal), 12);
  LPaint.Color := $FFCBD5E1;

  LStatusText := Format('Render Resolution: %d x %d  |  FPS: %d', [FWidth, FHeight, aUiState.FpsCounter]);
  FCanvas.DrawSimpleText(LStatusText, LCardRect.Left + 25, LCardRect.Top + 75, LFont, LPaint);

  LStatusText := Format('Corner Radius: %.1f px  |  Per-pixel Alpha: %d', [FConfig.CornerRadius, FConfig.WindowAlpha]);
  FCanvas.DrawSimpleText(LStatusText, LCardRect.Left + 25, LCardRect.Top + 100, LFont, LPaint);

  LStatusText := Format('User Event Status: %s', [aUiState.StatusMessage]);
  FCanvas.DrawSimpleText(LStatusText, LCardRect.Left + 25, LCardRect.Top + 125, LFont, LPaint);

  // Action Button inside Card
  FActionBtnRect := TRectF.Create(
    LCardRect.Left + 25,
    LCardRect.Bottom - 52,
    LCardRect.Left + 215,
    LCardRect.Bottom - 16
  );

  LCardRRect.SetRect(FActionBtnRect, 10.0, 10.0);
  LPaint.Style := TSkPaintStyle.Fill;
  case aUiState.ActionBtnState of
    bsHovered: LPaint.Color := $FF2563EB;
    bsPressed: LPaint.Color := $FF1D4ED8;
  else
    LPaint.Color := FConfig.AccentColor;
  end;
  FCanvas.DrawRoundRect(LCardRRect, LPaint);

  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Bold), 12);
  LPaint.Color := $FFFFFFFF;
  FCanvas.DrawSimpleText('Dispatch Console Ping', FActionBtnRect.Left + 24, FActionBtnRect.Top + 23, LFont, LPaint);
end;

procedure TSkiaLayeredRenderer.DrawWindowControls(const aUiState: TWindowUiState);
var
  LTop, LRight: Single;
  LPaint: ISkPaint;
  LFont: ISkFont;
  LBtnSize: Single;
  LRRect: ISkRoundRect;
begin
  LBtnSize := 32.0;
  LRight := FWidth - FShadowMargin - 20;
  LTop := FShadowMargin + 18;

  // 1. Close Button [X]
  if FConfig.ShowCloseButton then
  begin
    FCloseBtnRect := TRectF.Create(LRight - LBtnSize, LTop, LRight, LTop + LBtnSize);
    LRRect := TSkRoundRect.Create;
    LRRect.SetRect(FCloseBtnRect, 8.0, 8.0);

    LPaint := TSkPaint.Create;
    LPaint.AntiAlias := True;

    case aUiState.CloseBtnState of
      bsHovered: LPaint.Color := $FFE81123;
      bsPressed: LPaint.Color := $FFBF0F1D;
    else
      LPaint.Color := $18FFFFFF;
    end;
    FCanvas.DrawRoundRect(LRRect, LPaint);

    LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Normal), 13);
    LPaint.Color := $FFFFFFFF;
    FCanvas.DrawSimpleText('X', FCloseBtnRect.Left + 11.5, FCloseBtnRect.Top + 21, LFont, LPaint);

    LRight := LRight - LBtnSize - 8;
  end;

  // 2. Minimize Button [-]
  if FConfig.ShowMinimizeButton then
  begin
    FMinBtnRect := TRectF.Create(LRight - LBtnSize, LTop, LRight, LTop + LBtnSize);
    LRRect := TSkRoundRect.Create;
    LRRect.SetRect(FMinBtnRect, 8.0, 8.0);

    LPaint := TSkPaint.Create;
    LPaint.AntiAlias := True;

    case aUiState.MinBtnState of
      bsHovered: LPaint.Color := $35FFFFFF;
      bsPressed: LPaint.Color := $45FFFFFF;
    else
      LPaint.Color := $18FFFFFF;
    end;
    FCanvas.DrawRoundRect(LRRect, LPaint);

    LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Bold), 14);
    LPaint.Color := $FFFFFFFF;
    FCanvas.DrawSimpleText('-', FMinBtnRect.Left + 12.0, FMinBtnRect.Top + 21, LFont, LPaint);
  end;
end;

procedure TSkiaLayeredRenderer.DrawFooter(const aUiState: TWindowUiState);
var
  LFont: ISkFont;
  LPaint: ISkPaint;
  LText: string;
begin
  LFont := TSkFont.Create(TSkTypeface.MakeFromName('Segoe UI', TSkFontStyle.Normal), 11);
  LPaint := TSkPaint.Create;
  LPaint.AntiAlias := True;
  LPaint.Color := $66A0AEC0;

  LText := 'Drag anywhere on window to move  *  Press ESC or [X] to exit';
  FCanvas.DrawSimpleText(LText, FShadowMargin + 30, FHeight - FShadowMargin - 20, LFont, LPaint);
end;

function TSkiaLayeredRenderer.GetHitTestArea(const aX, aY: Integer): Integer;
var
  LPt: TPointF;
begin
  LPt := PointF(aX, aY);

  if FConfig.ShowCloseButton and FCloseBtnRect.Contains(LPt) then
    Exit(cHitCloseBtn);

  if FConfig.ShowMinimizeButton and FMinBtnRect.Contains(LPt) then
    Exit(cHitMinBtn);

  if FActionBtnRect.Contains(LPt) then
    Exit(cHitActionBtn);

  // Check if inside title bar area
  if (aY >= FShadowMargin) and (aY <= FShadowMargin + 65) and
     (aX >= FShadowMargin) and (aX <= FWidth - FShadowMargin) then
    Exit(cHitTitleBar);

  // Check if within round body
  if (aX >= FShadowMargin) and (aX <= FWidth - FShadowMargin) and
     (aY >= FShadowMargin) and (aY <= FHeight - FShadowMargin) then
    Exit(cHitClientBody);

  Result := cHitNowhere;
end;

end.