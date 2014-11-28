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

unit uAccept;

{$MODE OBJFPC}{$H+}
{$R-}

interface

uses
  {$IFDEF MSWINDOWS}Windows, WinSock2,{$ENDIF} Classes, SysUtils, FileUtil,
  LCLProc, SyncObjs;

type
  TFileArray = record
    FileName: AnsiString;
    FilePath: AnsiString;
    FileLength: Int64;
  end;

type

  { TAcceptThread }

  TAcceptThread = class(TThread)
  private
    FServerSocket: TSocket;

    FScanPath: string;

    procedure ScanFiles(APathName: AnsiString);
  protected
    procedure Execute; override;
  public
    constructor Create(CreateSuspended: Boolean);
    destructor Destroy; override;

    property ScanPath: string read FScanPath write FScanPath;
  end;

procedure CriticalSectionCreate;
procedure CriticalSectionFree;

var
  CS: TCriticalSection;
  Event: TEvent;

  FileArray: array of TFileArray;

implementation

uses
  uClient, uConsts;

{$REGION '*** Critical section ***'}

procedure CriticalSectionCreate;
begin
  CS := TCriticalSection.Create;
  Event := TEvent.Create(nil, False, True, '');
end;

procedure CriticalSectionFree;
begin
  CS.Free;
  Event.Free;
end;

{$ENDREGION}

{ TAcceptThread }

constructor TAcceptThread.Create(CreateSuspended: Boolean);
begin
  inherited Create(CreateSuspended);

  SetLength(FileArray, 0);
end;

destructor TAcceptThread.Destroy;
begin
  SetLength(FileArray, 0);

  inherited Destroy;
end;

procedure TAcceptThread.ScanFiles(APathName: AnsiString);
var
  SearchRec: TSearchRec;
  Name, Extension: string;
  ItemIndex: Cardinal;

  FACount: Integer;
begin
  APathName := IncludeTrailingBackslash(APathName);

  if FindFirstUTF8(APathName + '*.*', faAnyFile, SearchRec) = 0 then
  begin
    try
      repeat
        Sleep(0);

        Name := SearchRec.Name;

        if (SearchRec.Attr and faDirectory = faDirectory) and
          (Name <> '..') and (Name <> '.') then
        begin
          //ShowMessage(APathName + Name + '\');
          ScanFiles(APathName + Name);
        end;

        if SearchRec.Attr and faDirectory <> faDirectory then
        begin
          Extension := UTF8LowerCase(ExtractFileExt(APathName + Name));

          CS.Enter;

          // запись в массив
          FACount := Length(FileArray);
          SetLength(FileArray, FACount + 1);

          FileArray[FACount].FileName := ExtractFileName(Name);
          FileArray[FACount].FilePath := Copy(APathName, Length(FScanPath) + 1, MaxInt);
          FileArray[FACount].FileLength := SearchRec.Size;

          CS.Leave;
        end;

      until FindNextUTF8(SearchRec) <> 0;
    finally
      FindCloseUTF8(SearchRec);
    end;
  end;
end;

procedure TAcceptThread.Execute;
var
  ClientThread: TClientThread;
  WSAData: TWSAData;
  ClientSocket: TSocket;
  InAddr, FromAddr: sockaddr_in;
  NonBlockingArg: u_long;
  LenghtSock: Integer;
begin
  FScanPath := IncludeTrailingBackslash(FScanPath);

  ScanFiles(FScanPath);

  if WSAStartup($202, WSAData) <> 0 then
    Exit;

  FServerSocket := Socket(AF_INET, SOCK_STREAM, IPPROTO_TCP);
  if FServerSocket = SOCKET_ERROR then
    Exit;

  // перевод сокета в неблокирующий режим
  NonBlockingArg := 1;
  if ioctlsocket(FServerSocket, FIONBIO, NonBlockingArg) = SOCKET_ERROR then
  begin
    closesocket(FServerSocket);
    Exit;
  end;

  InAddr.sin_family := AF_INET;
  InAddr.sin_port := htons(80);
  //InAddr.sin_port := htons(8080);
  //InAddr.sin_port := htons(443);
  InAddr.sin_addr.S_addr := INADDR_ANY;

  if bind(FServerSocket, InAddr, SizeOf(InAddr)) <> 0 then
  begin
    Exit;
  end;

  if listen(FServerSocket, SOMAXCONN) <> 0 then
    Exit;

  while True do
  begin
    case Semaphore.Terminated of
      True: Break;
    end;

    LenghtSock := SizeOf(FromAddr);
    ClientSocket := accept(FServerSocket, @FromAddr, @LenghtSock);

    if ClientSocket <> INVALID_SOCKET then
    begin
      // перевод сокета в блокирующий режим
      NonBlockingArg := 0;
      if ioctlsocket(ClientSocket, FIONBIO, NonBlockingArg) = SOCKET_ERROR then
      begin
        closesocket(FServerSocket);
        Exit;
      end;

      if WSAGetLastError = WSAEWOULDBLOCK then
        Continue;

      ClientThread := TClientThread.Create(True);
      ClientThread.FreeOnTerminate := True;
      ClientThread.Priority := tpNormal;

      ClientThread.Socket := ClientSocket;
      ClientThread.ScanPath := FScanPath;

      ClientThread.Start;
    end;

    Sleep(1);
  end;

  //shutdown(FServerSocket, SD_BOTH);
  closesocket(FServerSocket);

  WSACleanUp;
end;

end.

