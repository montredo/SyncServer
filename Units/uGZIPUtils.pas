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

unit uGZIPUtils;

{$IFDEF FPC}
  {$MODE OBJFPC}
{$ENDIF}
{$H+}

interface

uses
  Classes, SysUtils, PasZLib, zbase;

type
  TZCompressionLevel = (zcNone, zcFastest, zcDefault, zcMax);

  TZStreamType = (
    zsZLib,  //standard zlib stream
    zsGZip,  //gzip stream
    zsRaw,   //raw stream (without any header)
    zsNo     //no compression
  );

const
  Z_BUFSIZE = 16384; //32768, 65536;

  ZLevels: array[TZCompressionLevel] of Shortint = (
    Z_NO_COMPRESSION,
    Z_BEST_SPEED,
    Z_DEFAULT_COMPRESSION,
    Z_BEST_COMPRESSION
  );

function zipStream(inStream, outStream: TMemoryStream; level: TZCompressionLevel = zcDefault; streamType: TZStreamType = zsZLib): boolean;
function unzipStream(inStream, outStream: TMemoryStream): boolean;

implementation

var ZipLock: TRTLCriticalSection;

function zipStream(inStream, outStream: TMemoryStream; level: TZCompressionLevel = zcDefault; streamType: TZStreamType = zsZLib): boolean;
  function ZCompressStream(inStream, outStream: TMemoryStream; level: TZCompressionLevel = zcDefault): boolean;
  var
    zstream: z_stream;
    zresult: integer;
    input_buffer: array[0..Z_BUFSIZE-1] of byte;
    output_buffer: array[0..Z_BUFSIZE-1] of byte;
    FlushType: LongInt;
  begin
    result := false;
    FillChar(input_buffer, SizeOf(input_buffer), 0);
    if deflateInit(zstream, ZLevels[level]) < 0 then Exit;
    while inStream.Position < inStream.Size do
    begin
      zstream.next_in := @input_buffer;
      zstream.avail_in := inStream.Read(input_buffer, Z_BUFSIZE);
      if inStream.Position = inStream.Size then
        FlushType := Z_FINISH
      else
        FlushType := Z_NO_FLUSH;
      repeat
        zstream.next_out := @output_buffer;
        zstream.avail_out := Z_BUFSIZE;
        zresult := deflate(zstream, FlushType);
        if zresult < 0 then Exit;
        outStream.Write(output_buffer, Z_BUFSIZE - zstream.avail_out);
      until zstream.avail_out > 0;
      if (zresult <> Z_OK) and (zresult <> Z_BUF_ERROR) then break;
    end;
    result := not (deflateEnd(zstream) < 0);
  end;

var
  copyStream: TMemoryStream;
  crc, size: longword;
begin
  inStream.Seek(0, soFromBeginning);
  result := ZCompressStream(inStream, outStream, level);
  if result then
  try
    if StreamType in [zsGZip, zsRaw] then
    begin
      result := false;
      copyStream := TMemoryStream.Create; // create help stream
      try
        if StreamType = zsGZip then //add GZip Header
        begin
          inStream.Seek(0, soFromBeginning); // goto start of input stream
          crc := 0;
          size := inStream.Size;
          crc := crc32(crc, Pointer(inStream.Memory), size);
          copyStream.WriteByte($1f); //IDentification 1
          copyStream.WriteByte($8b); //IDentification 2
          copyStream.WriteByte($08); //Compression Method = deflate
          copyStream.WriteByte($00); //FLaGs
          // bit 0   FTEXT - indicates file is ASCII text (can be safely ignored)
          // bit 1   FHCRC - there is a CRC16 for the header immediately following the header
          // bit 2   FEXTRA - extra fields are present
          // bit 3   FNAME - the zero-terminated filename is present. encoding; ISO-8859-1.
          // bit 4   FCOMMENT  - a zero-terminated file comment is present. encoding: ISO-8859-1
          // bit 5   reserved
          // bit 6   reserved
          // bit 7   reserved
          copyStream.WriteDWord($00000000); //Modification TIME = no time stamp is available (UNIX time format only make problems)
          copyStream.WriteByte($00); //eXtra FLags
          // 00 - default compression
          // 02 - compressor used maximum compression, slowest algorithm
          // 04 - compressor used fastest algorithm
          copyStream.WriteByte({$ifdef win32}$0b{$else}$03{$endif}); //Operating System = NTFS filesystem (NT)
          // 00 - FAT filesystem (MS-DOS, OS/2, NT/Win32)
          // 01 - Amiga
          // 02 - VMS (or OpenVMS)
          // 03 - Unix
          // 04 - VM/CMS
          // 05 - Atari TOS
          // 06 - HPFS filesystem (OS/2, NT)
          // 07 - Macintosh
          // 08 - Z-System
          // 09 - CP/M
          // 0A - TOPS-20
          // 0B - NTFS filesystem (NT)
          // 0C - QDOS
          // 0D - Acorn RISCOS
          // FF - unknown
        end;
        outStream.Seek(2, soFromBeginning); //cut off first 2 bytes deflate header
        copyStream.CopyFrom(outStream, outStream.Size-6); //cut off last 4 bytes adler32 checksum
        if StreamType = zsGZip then // add checksum and size
        begin
          copyStream.WriteDWord(crc); // CRC32 (CRC-32)
          copyStream.WriteDWord(size); // ISIZE (Input SIZE)
        end;
        copyStream.Seek(0, soFromBeginning); // goto start of stream
        outStream.Size := 0;
        outStream.CopyFrom(copyStream, copyStream.Size); // copy stream to result stream
        result := true;
      finally
        copyStream.Free; // free the help stream
      end;
    end;
    outStream.Seek(0, soFromBeginning); // goto start of result stream
  except
    result := false;
  end;
end;

function unzipStream(inStream, outStream: TMemoryStream): boolean;
  function ZUnCompressStream(inStream, outStream: TMemoryStream): boolean;
  var
    zstream: z_stream;
    zresult: integer;
    input_buffer : array[0..Z_BUFSIZE-1] of byte;
    output_buffer : array[0..Z_BUFSIZE-1] of byte;
    FlushType: LongInt;
  begin
    result := false;
    FillChar(input_buffer, SizeOf(input_buffer), 0);
    if inflateInit(zstream) < 0 then Exit;
    while inStream.Position < inStream.Size do
    begin
      zstream.next_in := @input_buffer;
      zstream.avail_in := inStream.Read(input_buffer, Z_BUFSIZE);
      if inStream.Position = inStream.Size then
        FlushType := Z_FINISH
      else
        FlushType := Z_SYNC_FLUSH;
      repeat
        zstream.next_out := @output_buffer;
        zstream.avail_out := Z_BUFSIZE;
        zresult := inflate(zstream, FlushType);
        if zresult < 0 then break;
        outStream.Write(output_buffer, Z_BUFSIZE - zstream.avail_out);
        if zresult = Z_STREAM_END then break;
      until zstream.avail_out > 0;
      if (zresult <> Z_OK) and (zresult <> Z_BUF_ERROR) then break;
    end;
    result := not (inflateEnd(zstream) < 0);
  end;

var
  copyStream: TMemoryStream;
  streamType: TZStreamType;
  hdr, crc, crcGZin, sizeGZin: Cardinal;
begin
  result := false;
  copyStream := TMemoryStream.Create; // create help stream
  try
    inStream.Seek(0, soFromBeginning); // jump to start of input stream
    hdr := inStream.ReadDWord;
    if (hdr and $00088B1F) = $00088B1F then // gzip header (deflate method)
    begin
      streamType := zsGZip; // GZIP format
      copyStream.WriteWord($9C78); // deflate header
      inStream.Seek(10, soFromBeginning); // jump over the first ten byte gzip header
      copyStream.CopyFrom(inStream, inStream.Size-18); // and cut the 4 byte crc32 and 4 byte input size
      crcGZin := inStream.ReadDWord; // CRC32 (CRC-32)
      sizeGZin := inStream.ReadDWord; // ISIZE (Input SIZE)
      copyStream.WriteDWord(0); // ok, the stream isn't complete without checksum (but we don't have adler32 checksum from source)
      copyStream.Seek(0, soFromBeginning); // goto start of stream
    end
    else if (hdr and $00009C78) = $00009C78 then // deflate header
    begin
      streamType := zsZLib; // deflate format (with header)
      inStream.Seek(0, soFromBeginning); // first byte is start of deflate header
      copyStream.CopyFrom(inStream, inStream.Size);
    end
    else
    begin
      streamType := zsRaw; // deflate format (is without header)
      copyStream.WriteWord($9C78); // deflate header
      inStream.Seek(0, soFromBeginning); // first byte is start of deflate stream
      copyStream.CopyFrom(inStream, inStream.Size); // and complete size is data (no checksum !)
      copyStream.WriteDWord(0); // ok, the stream isn't complete without checksum (but we don't have adler32 checksum from source)
      copyStream.Seek(0, soFromBeginning); // goto start of stream
    end;
    result := ZUnCompressStream(copyStream, outStream); // uncompress deflated stream
    if streamType = zsGZip then // if format is GZIP we can check the result
    begin
      outStream.Seek(0, soFromBeginning); // goto start of output stream
      crc := 0;
      crc := crc32(crc, Pointer(outStream.Memory), outStream.Size); // get result crc32 checksum
      result := (crc = crcGZin) and (outStream.Size = sizeGZin); // compare with input checksum and size
    end
    else if streamType <> zsRaw then
      result := true; // can't check, get no adler32 checksum
  finally
    copyStream.Free; // free the help stream
  end;
  inStream.Seek(0, soFromBeginning); // goto start of source stream
  outStream.Seek(0, soFromBeginning); // goto start of result stream
end;

end.

