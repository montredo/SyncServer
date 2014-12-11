{*******************************************************************************
  Copyright (с) 2014 MontDigital Software <montredo@mail.ru>

  This program is free software; you can redistribute it and/or modify
  it under the terms of the GNU General Public License as published by
  the Free Software Foundation; either version 2 of the License, or
  (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.
*******************************************************************************}

unit uClient;

{$MODE OBJFPC}{$H+}
//{$R-}

interface

uses
  {$IFDEF MSWINDOWS}Windows, WinSock2,{$ENDIF} Classes, SysUtils, FileUtil,
  LCLProc, Dialogs;

type

  { TClientThread }

  TClientThread = class(TThread)
  private
    FClientSocket: TSocket;
    FRequestList: TStringList;
    FResponseList: TStringList;

    FBuffer: string;

    FResponseBuffer: string;

    FResultCode: Integer;
    FResultStatus: string;

    FMethod: string;
    FDocument: string;
    FURLDocument: string;
    FFileDocument: string;

    FFileIndexDocument: Int64;

    FAcceptRanges: Int64;
    FContentType: string;
    FContentLength: Int64;

    FLastError: Integer;

    FRequestLength: Int64;
    FResponseLength: Int64;

    FScanPath: string;

    function WaitingRequest(): Int64;
    function RequestBuffer(): string;
    function RequestString(): string;
    function RequestData(): string;

    procedure SendString(AValue: string);
    procedure SendFile(const AFileName: string; AOffset: Int64 = -1);
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: boolean);
    destructor Destroy; override;

    property Socket: TSocket read FClientSocket write FClientSocket;
    property ScanPath: string read FScanPath write FScanPath;
  end;

implementation

uses
  uAccept, uGZIPUtils, uConsts, zstream, fpjson, jsonparser;

function EncodeURLElement(AValue: string): string;
var
  I: Integer;
begin
  Result := '';
  for I := 1 to Length(AValue) do
    if not (AValue[I] in ['A'..'Z', 'a'..'z', '0', '1'..'9', '-', '_', '~', '.']) then
      Result := Result + '%' + IntToHex(Ord(AValue[I]), 2)
    else
      Result := Result + AValue[I];
end;

function DecodeTriplet(const Value: string; Delimiter: AnsiChar): string;
var
  x, l, lv: Integer;
  c: AnsiChar;
  b: byte;
  bad: boolean;
begin
  lv := Length(Value);
  SetLength(Result, lv);
  x := 1;
  l := 1;
  while x <= lv do
  begin
    c := Value[x];
    Inc(x);
    if c <> Delimiter then
    begin
      Result[l] := c;
      Inc(l);
    end
    else
    if x < lv then
    begin
      case Value[x] of
        #13:
          if (Value[x + 1] = #10) then
            Inc(x, 2)
          else
            Inc(x);
        #10:
          if (Value[x + 1] = #13) then
            Inc(x, 2)
          else
            Inc(x);
        else
        begin
          bad := False;
          case Value[x] of
            '0'..'9': b := (byte(Value[x]) - 48) shl 4;
            'a'..'f', 'A'..'F': b := ((byte(Value[x]) and 7) + 9) shl 4;
            else
            begin
              b := 0;
              bad := True;
            end;
          end;
          case Value[x + 1] of
            '0'..'9': b := b or (byte(Value[x + 1]) - 48);
            'a'..'f', 'A'..'F': b := b or ((byte(Value[x + 1]) and 7) + 9);
            else
              bad := True;
          end;
          if bad then
          begin
            Result[l] := c;
            Inc(l);
          end
          else
          begin
            Inc(x, 2);
            Result[l] := AnsiChar(b);
            Inc(l);
          end;
        end;
      end;
    end
    else
      break;
  end;
  Dec(l);
  SetLength(Result, l);
end;

function DecodeURLElement(AValue: string): string;
begin
  Result := DecodeTriplet(AValue, '%');
end;

function DateTimeRFCEncode(DateTime: TDateTime): string;
const
  DayNames: array[1..7] of string = (
    'Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat');

  MonthNames: array[1..12] of string = (
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec');
var
  Year, Month, Day: word;
begin
  DecodeDate(DateTime, Year, Month, Day);

  Result := Format('%s, %d %s %s GMT', [DayNames[DayOfWeek(DateTime)],
    Day, MonthNames[Month], FormatDateTime('yyyy hh":"nn":"ss', DateTime)]);
end;

function DateTimeRFC: string;
var
  SystemTime: TSystemTime;
  DateTime: TDateTime;
begin
  {$IFDEF MSWINDOWS}
  GetSystemTime(SystemTime);
  DateTime := SystemTimeToDateTime(SystemTime);

  Result := DateTimeRFCEncode(DateTime);
  {$ENDIF}
end;

function GetContentType(AFileName: string): string;
type
  MIMEName = record
    mime_ext: string;
    mime_type: string;
  end;

const
  MIMENames: array [0..15] of MIMEName = (
    (mime_ext: '.ico'; mime_type: 'image/x-icon'),
    (mime_ext: '.htm'; mime_type: 'text/html'),
    (mime_ext: '.html'; mime_type: 'text/html'),
    (mime_ext: '.css'; mime_type: 'text/css'),
    (mime_ext: '.js'; mime_type: 'application/javascript'),
    (mime_ext: '.gif'; mime_type: 'image/gif'),
    (mime_ext: '.jpg'; mime_type: 'image/jpg'),
    (mime_ext: '.png'; mime_type: 'image/png'),
    (mime_ext: '.txt'; mime_type: 'text/plain'),
    (mime_ext: '.mp3'; mime_type: 'audio/mpeg'),
    (mime_ext: '.ts'; mime_type: 'video/mp2t'),
    (mime_ext: '.mp4'; mime_type: 'video/mp4'),
    (mime_ext: '.mkv'; mime_type: 'video/x-matroska'),
    (mime_ext: '.mpeg'; mime_type: 'video/mpeg'),
    (mime_ext: '.mpg'; mime_type: 'video/mpeg'),
    (mime_ext: '.avi'; mime_type: 'video/x-msvideo')
    );

var
  FileExt: string;
  I: Integer;
begin
  Result := 'application/octet-stream';

  FileExt := AnsiLowerCase(ExtractFileExt(AFileName));

  for I := Low(MIMENames) to High(MIMENames) do
  begin
    if MIMENames[I].mime_ext = FileExt then
    begin
      Result := MIMENames[I].mime_type;
      Break;
    end;
  end;
end;

{ TClientThread }

constructor TClientThread.Create(CreateSuspended: boolean);
begin
  inherited Create(CreateSuspended);

  FRequestList := TStringList.Create;
  FResponseList := TStringList.Create;

  FResultCode := 500;
  FResultStatus := 'Internal Server Error';

  FAcceptRanges := -1;
  FContentType := 'text/html; charset=utf-8';
  FContentLength := 0;

  FRequestLength := 0;
  FResponseLength := 0;

  FLastError := 0;
end;

destructor TClientThread.Destroy;
begin
  FRequestList.Free;
  FResponseList.Free;

  inherited Destroy;
end;

function TClientThread.WaitingRequest(): Int64;
var
  RequestLength: cardinal;
begin
  Result := 0;

  RequestLength := 0;

  if ioctlsocket(FClientSocket, FIONREAD, RequestLength) = 0 then
    Result := RequestLength;
  if Result > c64k then
    Result := c64k;
end;

function TClientThread.RequestBuffer(): string;
var
  RequestLength: Int64;
begin
  Result := '';

  {$IFDEF MSWINDOWS}
  //not drain CPU on large downloads...
  Sleep(1);
  {$ENDIF}

  RequestLength := WaitingRequest;
  if RequestLength > 0 then
  begin
    SetLength(FBuffer, RequestLength);
    if recv(FClientSocket, PAnsiChar(FBuffer)^, RequestLength, 0) > 0 then
    begin
      Result := FBuffer;
    end;
  end
  else
  begin
    FLastError := WSAECONNRESET;
  end;

  FLastError := WSAGetLastError;
end;

function TClientThread.RequestString(): string;
begin
  Result := '';

  Result := UTF8Copy(FBuffer, 1, UTF8Pos(CRLF, FBuffer) - 1);
  Delete(FBuffer, 1, Length(Result + CRLF));

  FBuffer := FBuffer;
end;

function TClientThread.RequestData: string;
var
  S, M: string;
begin
  S := Trim(RequestString());

  FMethod := UTF8Copy(S, 1, UTF8Pos(' ', S) - 1);
  Delete(S, 1, Length(FMethod) + 1);

  FDocument := UTF8Copy(S, 1, UTF8Pos(' ', S) - 1);
  Delete(S, 1, Length(FDocument) + 1);

  while True do
  begin
    S := Trim(RequestString());
    FRequestList.Add(S);

    if UTF8Pos('range:', UTF8LowerCase(S)) > 0 then
    begin
      //Delete(S, 1, UTF8Pos('=', S));
      //FAcceptRanges := StrToInt64Def(UTF8Copy(S, 1, UTF8Pos('-', S) - 1), -1);

      Delete(S, 1, Pos('=', S));
      FAcceptRanges := StrToInt64Def(Copy(S, 1, Pos('-', S) - 1), -1);
      FAcceptRanges := FAcceptRanges;
    end;

    if S = '' then
      Break;
  end;
end;

procedure TClientThread.SendString(AValue: string);
var
  ResponseLength: Int64;
begin
  ResponseLength := send(FClientSocket, PAnsiChar(AValue)^, Length(AValue), 0);
  FLastError := WSAGetLastError;

  if ResponseLength > 0 then
    Inc(FResponseLength, ResponseLength);
end;

procedure TClientThread.SendFile(const AFileName: string; AOffset: Int64);
var
  FileHandle: THandle;

  FileOffset: Int64;
  FileLength: Int64;

  FileReadln: Int64;

  Range: ansistring;
begin
  FileOffset := 0;
  FileLength := 0;

  FileHandle := FileOpenUTF8(AFileName, fmOpenRead or fmShareDenyNone);

  if FileHandle = feInvalidHandle then
  begin
    FResultCode := 404;
    FResultStatus := 'Not Found';

    SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
    SendString('Date: ' + DateTimeRFC + CRLF);
    SendString('Server: ' + STitle + '/' + SVersion + CRLF);
    SendString('Connection: close' + CRLF + CRLF);

    Exit;
  end;

  try
    FileLength := FileSeek(FileHandle, FileOffset, soFromEnd);

    FContentType := GetContentType(AFileName);

    if (FileLength = 0) or (AOffset > FileLength) then
    begin
      FResultCode := 400;
      FResultStatus := 'Bad Request';

      SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
      SendString('Date: ' + DateTimeRFC + CRLF);
      SendString('Server: ' + STitle + '/' + SVersion + CRLF);
      SendString('Connection: close' + CRLF + CRLF);

      Exit;
    end;

    if AOffset >= 0 then
    begin
      FResultCode := 206;
      FResultStatus := 'Partial Content';

      FContentLength := FileLength - AOffset;

      Range := Format('Content-Range: bytes %d-%d/%d',
        [AOffset, FileLength - 1, FileLength]);

      FileSeek(FileHandle, AOffset, soFromBeginning);
    end
    else
    begin
      FResultCode := 200;
      FResultStatus := 'OK';

      FContentLength := FileLength;

      Range := 'Accept-Ranges: bytes';

      FileSeek(FileHandle, FileOffset, soFromBeginning);
    end;

    SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
    SendString('Date: ' + DateTimeRFC + CRLF);
    SendString('Server: ' + STitle + '/' + SVersion + CRLF);
    SendString('Content-Type: ' + FContentType + CRLF);
    SendString('Content-Length: ' + IntToStr(FContentLength) + CRLF);
    SendString('Content-Disposition: attachment; filename="' +
      ExtractFileName(AFileName) + '"' + CRLF);
    SendString(Range + CRLF);
    SendString('Connection: close' + CRLF + CRLF);

    while True do
    begin
      SetLength(FBuffer, c64k);
      FileReadln := FileRead(FileHandle, PAnsiChar(FBuffer)^, c64k);
      SetLength(FBuffer, FileReadln);

      if FileReadln > 0 then
        SendString(FBuffer)
      else
        Break;

      if FLastError <> 0 then
        Break;
    end;

  finally
    FileClose(FileHandle);
  end;
end;

procedure TClientThread.Execute;
var
  JSONObject: TJSONObject;
  JSONArray: TJSONArray;

  I: Integer;
begin
  try
    RequestBuffer();
    RequestData();

    FURLDocument := DecodeURLElement(FDocument);

    if FMethod = 'GET' then
    begin
      if FURLDocument = '/favicon.ico' then
      begin
        FResultCode := 404;
        FResultStatus := 'Not Found';

        SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
        SendString('Date: ' + DateTimeRFC + CRLF);
        SendString('Server: ' + STitle + '/' + SVersion + CRLF);
        SendString('Connection: close' + CRLF + CRLF);
      end;

      if FURLDocument = '/' then
      begin
        FResultCode := 200;
        FResultStatus := 'OK';

        JSONObject := TJSONObject.Create;
        try
          JSONArray := TJSONArray.Create;

          for I := Low(FileArray) to High(FileArray) do
          begin
            JSONArray.Add(TJSONObject.Create(['file_id', I + 1,
              'file_name', FileArray[I].FileName, 'file_path',
              FileArray[I].FilePath, 'file_length', FileArray[I].FileLength,
              'file_url', '/getFile/' + IntToStr(I + 1) + '/' +
              EncodeURLElement(FileArray[I].FileName)]));
          end;

          JSONObject.Add('path', FScanPath);
          JSONObject.Add('count', Length(FileArray));
          JSONObject.Add('items', JSONArray);

          FResponseBuffer := JSONObject.FormatJSON(DefaultFormat, 4);
        finally
          JSONObject.Free;
        end;

        FContentType := 'application/json; charset=utf-8';
        FContentLength := Length(FResponseBuffer);

        SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
        SendString('Date: ' + DateTimeRFC + CRLF);
        SendString('Server: ' + STitle + '/' + SVersion + CRLF);
        SendString('Content-Type: ' + FContentType + CRLF);
        SendString('Content-Length: ' + IntToStr(FContentLength) + CRLF);
        SendString('Connection: close' + CRLF + CRLF);

        SendString(FResponseBuffer);
      end;

      if FURLDocument = '/html' then
      begin
        FResultCode := 200;
        FResultStatus := 'OK';

        FResponseBuffer := '';

        for I := Low(FileArray) to High(FileArray) do
        begin
          FResponseBuffer :=
            FResponseBuffer + Format('<p>%s - <a href="/getFile/%d/%s">%s</a></p>',
            [FileArray[I].FilePath, I + 1,
            EncodeURLElement(FileArray[I].FileName), FileArray[I].FileName]) + #13#10;
        end;

        FContentType := 'text/html; charset=utf-8';
        FContentLength := Length(FResponseBuffer);

        SendString('HTTP/1.1 ' + IntToStr(FResultCode) + ' ' + FResultStatus + CRLF);
        SendString('Date: ' + DateTimeRFC + CRLF);
        SendString('Server: ' + STitle + '/' + SVersion + CRLF);
        SendString('Content-Type: ' + FContentType + CRLF);
        SendString('Content-Length: ' + IntToStr(FContentLength) + CRLF);
        SendString('Connection: close' + CRLF + CRLF);

        SendString(FResponseBuffer);
      end;

      if FURLDocument = '/getClient/' then
      begin
        SendFile(ExtractFilePath(ParamStrUTF8(0)) + 'SyncClient.exe', FAcceptRanges);
      end;

      if UTF8Pos('/getFile/', FURLDocument) > 0 then
      begin
        FFileDocument := FURLDocument;
        Delete(FFileDocument, 1, Length('/getFile/'));
        FFileDocument := UTF8Copy(FFileDocument, 1, UTF8Pos('/', FFileDocument) - 1);

        FFileDocument := FFileDocument;
        FFileIndexDocument := StrToInt64Def(FFileDocument, -1);

        if (FFileIndexDocument > 0) and (FFileIndexDocument <= Length(FileArray)) then
        begin
          SendFile(FScanPath + FileArray[FFileIndexDocument - 1].FilePath +
            FileArray[FFileIndexDocument - 1].FileName, FAcceptRanges);
        end;
      end;

    end
    else
    begin
      Exit;
    end;

  finally
    //shutdown(FClientSocket, SD_SEND);
    closesocket(FClientSocket);
  end;
end;

end.

