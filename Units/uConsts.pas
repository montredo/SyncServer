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

unit uConsts;

{$MODE OBJFPC}{$H+}

interface

const
  STitle = 'SyncServer';
  SVersion = '0.0.1';
  SBuild = '11';

  CR = #$0d;
  LF = #$0a;
  CRLF = CR + LF;
  c64k = 65535;

  SGZipBOM = #$1f + #$8b + #$08 + #$00 + #$00 + #$00 + #$00 + #$00;

type
  FSemaphore = record
    Terminated: Boolean;
  end;

var
  Semaphore: FSemaphore;

implementation

end.

