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

unit uMain;

{$MODE OBJFPC}{$H+}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Dialogs, StdCtrls;

type

  { TMainForm }

  TMainForm = class(TForm)
    PathEdit: TEdit;
    StopServerButton: TButton;
    StartServerButton: TButton;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure StartServerButtonClick(Sender: TObject);
    procedure StopServerButtonClick(Sender: TObject);
  private

  public

  end;

var
  MainForm: TMainForm;

implementation

uses
  uAccept, uConsts;

{$R *.lfm}

{ TMainForm }

procedure TMainForm.FormCreate(Sender: TObject);
begin
  CriticalSectionCreate();

  Position := poScreenCenter;

  Caption := Format('%s %s Build %s', [STitle, SVersion, SBuild]);
end;

procedure TMainForm.FormDestroy(Sender: TObject);
begin
  CriticalSectionFree();
end;

procedure TMainForm.StartServerButtonClick(Sender: TObject);
var
  AcceptThread: TAcceptThread;
begin
  CS.Enter;
  Semaphore.Terminated := False;
  CS.Leave;

  AcceptThread := TAcceptThread.Create(True);
  AcceptThread.FreeOnTerminate := True;
  AcceptThread.Priority := tpNormal;

  AcceptThread.ScanPath := Trim(PathEdit.Text);

  AcceptThread.Start;
end;

procedure TMainForm.StopServerButtonClick(Sender: TObject);
begin
  CS.Enter;
  Semaphore.Terminated := True;
  CS.Leave;
end;

end.

