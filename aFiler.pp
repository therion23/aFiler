Program aFiler;

{$H+}
{$APPTYPE CONSOLE}
{$MODESWITCH EXCEPTIONS+}

Uses DOS,

{$IFDEF WIN32}
  Windows,
{$ENDIF}
{$IFDEF LINUX}
  Unix,
{$ENDIF}
{$IFDEF DARWIN}
  Unix,
{$ENDIF}

  SQLite3, SysUtils, StrUtils, LazUTF8, FileUtil, Classes, Keyboard, md5;

Const

  Version: Word = 70;
  DBname = 'aFiler.sqlite3';
{$IFDEF WIN32}
  aaptname = 'aapt.exe';
  unzipname = 'unzip.exe';
  shellenv = 'COMSPEC';
{$ENDIF}
{$IFDEF LINUX}
  aaptname = 'aapt';
  unzipname = 'unzip';
  shellenv = 'SHELL';
{$ENDIF}
{$IFDEF DARWIN}
  aaptname = 'aapt';
  unzipname = 'unzip';
  shellenv = 'SHELL';
{$ENDIF}


Type

  DBentries = Record
    packageName,
    packageVersionName,
    applicationLabel: AnsiString;
    packageVersionCode,
    sdkVersion,
    targetsdkVersion: LongWord;
    applicationIcon: AnsiString;
    applicationIconSize: Word;
    applicationIconBlob: Array[0..65535] Of Byte;
    applicationIconBlobString: Array[0..131071] Of Char;
    xmlTime: LongInt;
    MD5xml: String[32];
    CRCxml: String[8];
  End;

  OBBentries = Record
    obbType: Char;
    obbVersion: LongWord;
    obbName: AnsiString;
  End;

  MD5bugger = String[32];

Var

  DB: PSQLite3;
  DBresult: PSQLite3Stmt;

  DBentry: DBentries;
  OBBentry: OBBentries;

  SQLresult: Integer;

  MDDigest: TMDDigest;

  SearchRec: TSearchRec;

  RecurseList: TStringList;

  AAPTfile: Text;
//  ICONfile: File;

  aaptPath,
  unzipPath,
  SourcePath,
  BasePath,
  DestPath,
  OBBPath,
  TempPath,
  DBPath,
  ShellPath: String;

  SQL: AnsiString;

  fnMask: String;

  apkStatus: Boolean;

  dbOpen,
  dbTransaction: Boolean;

  apkVersionCode: LongWord;
  apkTimeStamp: LongInt;

  obbVersionCode: LongWord;

//  IconSize: LongWord;

  dbVersion: Integer;

  S1,
  S2: String;

  FN,
  WS1: UnicodeString;

  W1,
  W2,
  W3: Word;

  FileHandle: LongInt;

  WhiteList: Array[1..512] Of String[64];
  WhiteCount: LongWord;

  optDebug,
  optFakeWrite,
  optJoliet,
  optRecursion,
  optSetPriority,
  optTransactions,
  optVacuum: Boolean;

  optParam: String;
  optFlag: Byte;

Function closeDB: Boolean; Forward;

Procedure Header;
Begin
  Write(#13#10);
  WriteLn(' * aFiler 1.10 - An Android .apk and .obb manager for multiple platforms.');
  WriteLn(' * Copyright (C) 2012-2015 Nocturnal Productions, Copenhagen, Denmark.');
  WriteLn;
End;

Procedure Usage;
Begin
  WriteLn(' * Usage: ' + ParamStr(0) + ' command parameter');
  WriteLn('   - or -');
  WriteLn(' * Usage: ' + ParamStr(0) + ' configoption parameter');
  WriteLn;
  WriteLn('   Where command is exactly one of the following:');
  WriteLn('    a - Add APK files to database and copy files to repository');
  WriteLn('    c - Cleanup OBB repository (USE WITH CAUTION)');
  WriteLn('    d - Delete APK files known to database');
  WriteLn('    k - Keep only latest version of APK file (USE WITH CAUTION)');
  WriteLn('    l - Scan OBB repository and add to database');
  WriteLn('    o - Add OBB files to database and copy files to repository');
  WriteLn('    r - Rename APK files according to metadata');
  WriteLn('    s - Scan APK repository and add to database');
  WriteLn('    t - Timestamp APK files with timestamp of MANIFEST.MF');
  WriteLn('    v - Validate APK files for archive and metadata integrity');
  WriteLn;
  WriteLn('   Or configoption is exactly one of the following:');
  WriteLn('    C - Show configuration and options');
  WriteLn('    F - Set filename pattern');
  WriteLn('    I - Initialize database');
  WriteLn('    O - Set or unset an option');
  WriteLn('    R - Set APK repository folder');
  WriteLn('    S - Set OBB repository folder');
  WriteLn('    U - Remove packagename from Whitelist');
  WriteLn('    V - Show Whitelist');
  WriteLn('    W - Add packagename to Whitelist');
  WriteLn;
  WriteLn(' * For command a, d, k, r, s, t and v, the parameter is a filemask (i.e. *.apk).');
  WriteLn(' * For command l and o, the parameter is a filemask (i.e. *.obb).');
  WriteLn;
  WriteLn(' * For configoption C, the parameter is a dash (-).');
  WriteLn(' * For configoption F, the parameter is the rename pattern.');
  WriteLn(' * For configoption I, the parameter must always be YES.');
  WriteLn(' * For configoptions R and S, the parameter is an existing pathname.');
  WriteLn(' * For configoptions U and W, the parameter is a packagename.');
  WriteLn(' * For configoption V, the parameter is a (partial) packagename.');
  WriteLn;
  WriteLn(' * Please refer to the documentation for more information.');
End;

Procedure Err(errCode: Byte);
Begin
  Case errCode of
      0: WriteLn(' * Done.');
      2: WriteLn(' ! Wrong number of parameters.');
      3: WriteLn(' ! Invalid command.');
      4: WriteLn(' + Database initialized.');
     31: WriteLn(' ! Must approve initialize with the parameter YES.');
     80: WriteLn(' ! Cannot find ' + aaptname);
     81: WriteLn(' ! Cannot find ' + unzipname);
     90: WriteLn(' ! Cannot open database.');
     93: WriteLn(' ! Cannot delete database.');
    101: WriteLn(' ! Cannot create database file.');
    102: WriteLn(' ! Cannot create database table.');
    111: WriteLn(' ! APK path not set.');
    112: WriteLn(' ! APK path invalid.');
    113: WriteLn(' ! OBB path not set.');
    114: WriteLn(' ! OBB path invalid.');
    115: WriteLn(' ! Will not run command in destination folder.');
    116: WriteLn(' ! Absolute path required.');
    121: WriteLn(' + APK path set.');
    122: WriteLn(' + OBB path set.');
    130: WriteLn(' ! Error reading apk file.');
//    131: WriteLn(' ! Error reading icon file.');
//    132: WriteLn(' ! Error reading AndroidManifest.xml file.');
    133: WriteLn(' ! Error setting timestamp.');
    141: WriteLn(' ! Invalid filename pattern.');
    142: WriteLn(' + Filename pattern set.');
    145: WriteLn(' ! Invalid option specifier.');
    146: WriteLn(' + Option set.');
    149: WriteLn(' ! Config file needs updating.');
    151: WriteLn(' ! Cannot copy file.');
    152: WriteLn(' ! Cannot delete source file.');
    153: WriteLn(' ! Cannot rename temp file.');
    154: WriteLn(' ! Cannot change file attributes.');
    160: WriteLn(' ! Nothing to do.');
    171: WriteLn(' ! No contents in filename pattern.');
    181: WriteLn(' ! External I/O error using unzip.');
    191: WriteLn(' ! External I/O error using aapt.');
    200: WriteLn(' ! Fatal SQLite error.');
    201: WriteLn(' ! Cannot INSERT.');
    202: WriteLn(' ! Cannot PREPARE.');
    203: WriteLn(' ! Cannot STEP.');
    204: WriteLn(' ! Cannot FINALIZE.');
    205: WriteLn(' ! Cannot BEGIN.');
    206: WriteLn(' ! Cannot COMMIT.');
    207: WriteLn(' ! Cannot DELETE.');
    208: WriteLn(' ! Cannot VACUUM.');
    213: WriteLn(' ! Interrupted by user.');
  End;
  If errCode > 100 Then closeDB;
{$IFNDEF DARWIN}
  DoneKeyboard;
{$ENDIF}
  Halt(errCode);
End;

Procedure KeyBreak;
Var
  Key: TKeyEvent;
Begin
	Key := TranslateKeyEvent(GetKeyEvent);
	If GetKeyEventChar(Key) = ^C Then Err(213);
End;

Procedure initWhiteList;
Begin
  If optDebug Then WriteLn('Entering initWhiteList');
  SQL := 'CREATE TABLE IF NOT EXISTS [WL] ([WLPattern] CHAR(64), CONSTRAINT [SANITY] UNIQUE ([WLPattern]) ON CONFLICT IGNORE);';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);
  WhiteCount := 0;
  SQL := 'SELECT * FROM [WL];';
  If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
  While (sqlite3_step(DBresult) = SQLITE_ROW) Do Begin
  	Inc(WhiteCount);
    WhiteList[WhiteCount] := sqlite3_column_text(DBresult, 0);
  End;
  If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
  If optDebug Then WriteLn('Leaving initWhiteList');
End;

Procedure addWhiteList;
Begin
  If optDebug Then WriteLn('Entering addWhiteList');
  SQL := 'INSERT INTO [WL] VALUES(''' + LowerCase(ParamStr(2)) + ''');';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);
  If optDebug Then WriteLn('Leaving addWhiteList');
End;

Procedure delWhiteList;
Begin
  If optDebug Then WriteLn('Entering delWhiteList');
  SQL := 'DELETE FROM [WL] WHERE WLPattern = ''' + LowerCase(ParamStr(2)) + ''';';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(207);
  If optDebug Then WriteLn('Leaving delWhiteList');
End;

Procedure showWhiteList;
Var
  Matched: Boolean;
Begin
  If optDebug Then WriteLn('Entering showWhiteList');
  Matched := False;
  If WhiteCount > 0 Then Begin
  	For W3 := 1 To WhiteCount Do If Pos(LowerCase(ParamStr(2)), WhiteList[W3]) > 0 Then Begin
  		WriteLn(' > ' + WhiteList[W3]);
  		Matched := True;
  	End;
  	If Matched Then WriteLn;
  End;
  If optDebug Then WriteLn('Leaving showWhiteList');
End;

Function checkWhiteList(PN: String): Boolean;
Begin
  If optDebug Then WriteLn('Entering checkWhiteList');
	checkWhiteList := False;
	If WhiteCount > 0 Then Begin
		For W2 := 1 To WhiteCount Do If WhiteList[W2] = LowerCase(PN) Then checkWhiteList := True;
	End;
  If optDebug Then WriteLn('Leaving checkWhiteList');
End;

Function apkExists(seenthisbefore: MD5bugger): Boolean;
Begin
  If optDebug Then WriteLn('Entering apkExists');
  SQL := 'SELECT * FROM [APK] WHERE [md5Manifest] = "' + seenthisbefore + '";';
  If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
  If (sqlite3_step(DBresult) = SQLITE_ROW) Then Begin
  	apkExists := True;
    If Not optFakeWrite Then Begin
      FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
      If DeleteFileUTF8(SourcePath + SearchRec.Name) = False Then WriteLn(' ! Error deleting ' + SearchRec.Name)
      Else WriteLn(' - ' + DBentry.applicationLabel + ' v' + DBentry.packageVersionName + ' Deleted');
    End;
  End
  Else apkExists := False;
  If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
  If optDebug Then WriteLn('Leaving apkExists');
End;

Function initDB: Boolean;
Begin
  If optDebug Then WriteLn('Entering initDB');
  If sqlite3_open(PChar(DBPath), DB) <> SQLITE_OK Then Err(101);

// Config table

  SQL := 'CREATE TABLE IF NOT EXISTS [CONFIG] ([dbVersion] INTEGER(4) DEFAULT 70';
  SQL := SQL + ', [outPath] CHAR(512)';
  SQL := SQL + ', [OBBPath] CHAR(512)';
  SQL := SQL + ', [fnFormat] CHAR(16)';
  SQL := SQL + ', [optDebugInfo] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ', [optFakeWrite] BOOLEAN NOT NULL DEFAULT 1';
  SQL := SQL + ', [optJoliet] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ', [optRecursion] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ', [optSetPriority] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ', [optTransactions] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ', [optVacuum] BOOLEAN NOT NULL DEFAULT 0';
  SQL := SQL + ');';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);
  SQL := 'INSERT INTO CONFIG ([outPath], [fnFormat]) VALUES (NULL, NULL);';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);

// APK table

  SQL := 'CREATE TABLE IF NOT EXISTS [APK] ([md5Manifest] CHAR(32) NOT NULL ON CONFLICT FAIL, ';
  SQL := SQL + '[md5Timestamp] INT(8) NOT NULL, [packageName] CHAR(64) NOT NULL ON CONFLICT FAIL, ';
  SQL := SQL + '[packageVersionCode] INT(8) NOT NULL ON CONFLICT FAIL, [packageVersionName] CHAR(64) NOT NULL ON CONFLICT FAIL, ';
  SQL := SQL + '[applicationLabel] CHAR(64) NOT NULL ON CONFLICT FAIL, [applicationIcon] BLOB(32768), [applicationIconSize] INT(8), ';
  SQL := SQL + 'CONSTRAINT [] PRIMARY KEY ([md5Manifest] COLLATE NOCASE ASC) ON CONFLICT FAIL);';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);
  SQL := 'ALTER TABLE [APK] ADD COLUMN [sdkVersion] INT(8) NOT NULL ON CONFLICT FAIL DEFAULT 0;';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);
  SQL := 'ALTER TABLE [APK] ADD COLUMN [targetsdkVersion] INT(8) DEFAULT 0;';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);

// OBB table

  SQL := 'CREATE TABLE IF NOT EXISTS [OBB] ([OBBType] CHAR(1), [OBBVer] INT(8), [OBBName] CHAR(64), CONSTRAINT [SANITY] UNIQUE([OBBType], [OBBVer], [OBBName]) ON CONFLICT FAIL)';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(102);

  initDB := True;
  If optDebug Then WriteLn('Leaving initDB');
End;

Function openDB: Boolean;
Begin
  If optDebug Then WriteLn('Entering openDB');
  If sqlite3_open(PChar(DBPath), DB) <> SQLITE_OK Then openDB := False Else openDB := True;
  If optDebug Then WriteLn('Leaving openDB');
End;

Function closeDB: Boolean;
Begin
  If optDebug Then WriteLn('Entering closeDB');
  If (optTransactions) And (dbTransaction) Then Begin
    SQL := 'COMMIT TRANSACTION;';
    If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(206);
  End;
  If (ParamStrUTF8(1)[1] = 'k') And (optVacuum) Then Begin
    If optDebug Then WriteLn('Vacuuming database');
    SQL := 'VACUUM;';
    If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(208);
  End;
  Try
    sqlite3_close(DB);
  Except
    On EAccessViolation Do Err(200);
  End;
  closeDB := True;
  If optDebug Then WriteLn('Leaving closeDB');
End;

Procedure reopenDB;
Begin
  If optDebug Then WriteLn('Entering reopenDB');
  Try
    sqlite3_close(DB);
  Except
    On EAccessViolation Do Err(200);
  End;
  If sqlite3_open(PChar(DBPath), DB) <> SQLITE_OK Then Err(90);
  SQL := 'BEGIN EXCLUSIVE TRANSACTION;';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(205);
  dbTransaction := True;
  If optDebug Then WriteLn('Leaving reopenDB');
End;

Procedure getConfig;
Begin
  SQL := 'SELECT * FROM [CONFIG];';
  If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
  If sqlite3_step(DBresult) <> SQLITE_ROW Then Err(203);
  dbVersion := sqlite3_column_int(DBresult, 0);
  If Version <> dbVersion Then Err(149);
  DestPath := sqlite3_column_text(DBresult, 1);
  OBBPath := sqlite3_column_text(DBresult, 2);
  fnMask := sqlite3_column_text(DBresult, 3);
  optDebug := (sqlite3_column_text(DBresult, 4) = '1');
  optFakeWrite := (sqlite3_column_text(DBresult, 5) = '1');
  optJoliet := (sqlite3_column_text(DBresult, 6) = '1');
  optRecursion := (sqlite3_column_text(DBresult, 7) = '1');
  optSetPriority := (sqlite3_column_text(DBresult, 8) = '1');
  optTransactions := (sqlite3_column_text(DBresult, 9) = '1');
  optVacuum := (sqlite3_column_text(DBresult, 10) = '1');
  If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
  If DestPath = '' then Err(111);
  If OBBPath = '' then Err(113);
  If Not DirectoryExistsUTF8(DestPath) Then Err(112);
  If Not DirectoryExistsUTF8(OBBPath) Then Err(114);
  If optTransactions Then reopenDB;
{$IFDEF WIN32}
  if optSetPriority Then SetPriorityClass(GetCurrentProcess(), HIGH_PRIORITY_CLASS);
{$ENDIF}
  If optDebug Then WriteLn('Leaving getConfig');
End;

Procedure writeConfig;
Begin
  If optDebug Then WriteLn('Entering writeConfig');
//   SQL := 'SELECT * FROM [CONFIG];';
//   If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
//   If sqlite3_step(DBresult) <> SQLITE_ROW Then Err(203);
// {$IFDEF DARWIN}
  WriteLn(' * dbVersion = ', dbVersion);
  WriteLn(' * DestPath = ', DestPath);
  WriteLn(' * OBBPath = ', OBBPath);
  WriteLn(' * fnMask = ', fnMask);
  WriteLn(' * optDebug = ', optDebug);
  WriteLn(' * optFakeWrite = ', optFakeWrite);
  WriteLn(' * optJoliet = ', optJoliet);
  WriteLn(' * optRecursion = ', optRecursion);
  WriteLn(' * optSetPriority = ', optSetPriority);
  WriteLn(' * optTransactions = ', optTransactions);
  WriteLn(' * optVacuum = ', optVacuum);
// {$ELSE}
//   For W1 := 0 to sqlite3_column_count(DBresult) - 1 Do WriteLn(' * ' + sqlite3_column_origin_name(DBresult, W1), ' = ', sqlite3_column_text(DBresult, W1));
// {$ENDIF}
  WriteLn;
//   If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
  If optDebug Then WriteLn('Leaving writeConfig');
End;

Procedure parseOutPath;
Begin
  If optDebug Then WriteLn('Entering parseOutPath');
  DestPath := AppendPathDelim(ParamStrUTF8(2));
  If Not DirectoryExistsUTF8(DestPath) Then Err(112);
  If Not FilenameIsAbsolute(DestPath) Then Err(116);
  SQL := 'UPDATE [CONFIG] SET [outPath] = ''' + DestPath + ''';';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);
  If optDebug Then WriteLn('Leaving parseOutPath');
  Err(121);
End;

Procedure parseOBBPath;
Begin
  If optDebug Then WriteLn('Entering parseOBBPath');
  OBBPath := AppendPathDelim(ParamStrUTF8(2));
  If Not DirectoryExistsUTF8(OBBPath) Then Err(114);
  If Not FilenameIsAbsolute(OBBPath) Then Err(116);
  SQL := 'UPDATE [CONFIG] SET [OBBPath] = ''' + OBBPath + ''';';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);
  If optDebug Then WriteLn('Leaving parseOBBPath');
  Err(122);
End;

Procedure parseFnMask;
Var
  nonSpace: Boolean;
Begin
  nonSpace := False;
  fnMask := ParamStrUTF8(2);
  If (Length(fnMask) < 1) Or (Length(fnMask) > 15) Then Err(141);
  For W1 := 1 To Length(fnMask) Do If Pos(fnMask[W1], 'acpv []()') = 0 Then Err(141);
  For W1 := 1 To Length(fnMask) Do If Pos(fnMask[W1], 'acpv') > 0 Then nonSpace := True;
  If nonSpace = False Then Err(171);
  SQL := 'UPDATE [CONFIG] SET [fnFormat] = ''' + fnMask + ''';';
  If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);
  Err(142);
End;

Function validateFnMask: Boolean;
Var
  nonSpace: Boolean;
Begin
  nonSpace := False;
  If (Length(fnMask) < 1) Or (Length(fnMask) > 15) Then Err(141);
  For W1 := 1 To Length(fnMask) Do If Pos(fnMask[W1], 'acpv []()') = 0 Then Err(141);
  For W1 := 1 To Length(fnMask) Do If Pos(fnMask[W1], 'acpv') > 0 Then nonSpace := True;
  validateFnMask := nonSpace;
End;

Procedure clearArray;
Begin
  With DBentry Do Begin
    packageName := '';
    packageVersionName := '';
    applicationLabel := '';
    packageVersionCode := 0;
    sdkVersion := 0;
    targetsdkVersion:= 0;
    applicationIcon := '';
    applicationIconSize := 0;
//    IconSize := 0;
    xmlTime := 0;
    MD5xml := '';
    CRCxml := '';
  End;
End;

Function apkInsert: Boolean;
Begin
  If optDebug Then WriteLn('Entering apkInsert');
  apkInsert := False;
  Try
    With DBentry do Begin
    	For W1 := Length(applicationLabel) DownTo 1 Do If applicationLabel[W1] = '"' Then Insert('"', applicationLabel, W1);
      SQL := 'INSERT INTO APK ([packageName], [packageVersionCode], [packageVersionName], [applicationLabel], [applicationIcon], [applicationIconSize], [sdkVersion], [targetsdkVersion], [md5Manifest], [md5Timestamp]) VALUES (';
      SQL := SQL + '"' + packageName + '","' + IntToStr(packageVersionCode) + '","' + packageVersionName + '","' + applicationLabel + '", "", 0, ' + IntToStr(sdkVersion) + ', ' + IntToStr(targetsdkVersion) + ', "' + MD5xml + '", ' + IntToStr(apkTimeStamp) + ');';
      SQLresult := sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL);
      If SQLresult = 0 Then WriteLn(' + ' + applicationLabel + ' v' + packageVersionName + ' Added');
//      If SQLresult = 19 Then WriteLn(' - ' + applicationLabel + ' v' + packageVersionName + ' Already known');
      If Not(SQLresult In [0, 19]) Then Err(201);
      If SQLresult = 19 Then apkInsert := False Else apkInsert := True;
    End;
  Except
    On EAccessViolation Do Begin
      WriteLn(' ! Invalid metadata in ' + SearchRec.Name);
      apkInsert := False;
    End;
  End;
  If optDebug Then WriteLn('Leaving apkInsert');
End;

(*

Procedure apkGetIcon(PathSpec: String);
Var
  ErrCode: Integer;
Begin
  If optDebug Then WriteLn('Entering apkGetIcon');
// \\  If DBentry.applicationIcon <> '' Then Begin
  If False Then Begin
    Try
      ErrCode := SysUtils.ExecuteProcess(unzipPath, ' -j -qq -o "' + ExtractShortPathNameUTF8(PathSpec + SearchRec.Name) + '" ' + DBentry.applicationIcon, []);
    Except
      On EOSError Do Err(181);
    End;
    DosError := 0;
    Assign(ICONfile, ExtractFileName(DBentry.applicationIcon));
{$I-}
    Reset(ICONfile, 1);
{$I+}
    If IOresult <> 0 Then Err(131);
    BlockRead(ICONfile, DBentry.applicationIconBlob[0], 65520, DBentry.applicationIconSize);
    Close(ICONfile);
    Erase(ICONfile);
    For W2 := 0 To (DBentry.applicationIconSize - 1) Do Begin
      DBentry.applicationIconBlobString[W2 * 2] := Dec2Numb(DBentry.applicationIconBlob[W2] DIV 16, 1, 16)[1];
      DBentry.applicationIconBlobString[(W2 * 2) + 1] := Dec2Numb(DBentry.applicationIconBlob[W2] MOD 16, 1, 16)[1];
    End;
  End
  Else Begin
    DBentry.applicationIconBlobString := '';
    DBentry.applicationIconSize := 0;
  End;
  If optDebug Then WriteLn('Leaving apkGetIcon');
End;

*)

Procedure apkGetIcon(PathSpec: String);
Begin
  If optDebug Then WriteLn('Entering apkGetIcon');
  DBentry.applicationIconBlobString := '';
  DBentry.applicationIconSize := 0;
  If optDebug Then WriteLn('Leaving apkGetIcon');
End;

Procedure apkGetManifest(PathSpec: String);
Var
  ErrCode: Integer;
Begin
  If optDebug Then WriteLn('Entering apkGetManifest');
  apkTimeStamp := 0;
  Try
    ErrCode := SysUtils.ExecuteProcess(unzipPath, '-j -qq -o "' + ExtractShortPathNameUTF8(PathSpec + SearchRec.Name) + '" META-INF/MANIFEST.MF -d ' + TempPath, []);
  Except
    On EOSError Do Err(181);
  End;
  FileHandle := FileOpen(TempPath + 'MANIFEST.MF', fmOpenRead OR fmShareDenyNone);
  If FileHandle > -1 Then Begin
    apkTimeStamp := FileGetDate(FileHandle);
    FileClose(FileHandle);
    MDDigest := MD5File(TempPath + 'MANIFEST.MF', 32768);
    SetLength(S1, 32);
    BinToHex(@MDDigest, @S1[1], 16);
    DBentry.MD5xml := S1;
    FileSetAttrUTF8(TempPath + 'MANIFEST.MF', 0);
    DeleteFileUTF8(TempPath + 'MANIFEST.MF');
  End;
  If optDebug Then WriteLn('Leaving apkGetManifest');
End;

Procedure apkDelete;
Begin
  If optDebug Then WriteLn('Entering apkDelete');
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      DBentry.MD5xml := '';
      apkGetManifest(SourcePath);
      S1 := '';
      SQL := 'SELECT [packageName] FROM [APK] WHERE [md5Manifest] = "' + DBentry.MD5xml + '";';
      If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
      If sqlite3_step(DBresult) = SQLITE_ROW Then Begin
        S1 := sqlite3_column_text(DBresult, 0);
        WriteLn(' - ' + SearchRec.Name + ' (' + S1 + ') is known');
        If Not optFakeWrite Then Begin
          FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
          If DeleteFileUTF8(SourcePath + SearchRec.Name) = False Then WriteLn(' ! Error deleting ' + SearchRec.Name);
        End;
      End;
      If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkDelete');
End;

Procedure apkValidate;
Var
  ErrCode: Integer;
Begin
  If optDebug Then WriteLn('Entering apkValidate');
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      apkStatus := True;
      Try
        ErrCode := SysUtils.ExecuteProcess(unzipPath, '-t -qq "' + ExtractShortPathNameUTF8(SourcePath + SearchRec.Name) + '"', []);
        If ErrCode > 1 Then Begin
          WriteLn(' - ' + SearchRec.Name + ' - Broken archive');
          apkStatus := False;
        End;
      Except
        On EOSError Do Begin
          WriteLn(' - ' + SearchRec.Name + ' - Broken archive');
          apkStatus := False;
        End;
      End;
      If apkStatus = True Then Begin
//      Exec('cmd.exe', '/c ' + aaptpath + ' d badging "' + UTF8ToSys(SearchRec.Name) + '" > NUL 2>&1');
{$IFDEF WIN32}
        Exec(ShellPath, '/c ' + aaptpath + ' d badging "' + ExtractShortPathNameUTF8(SourcePath + SearchRec.Name) + '" > NUL 2>&1');
{$ENDIF}
{$IFDEF LINUX}
        fpSystem('"' + aaptpath + '"' + ' d badging "' + ExtractShortPathNameUTF8(SourcePath + SearchRec.Name) + '" > /dev/null 2>&1');
{$ENDIF}
{$IFDEF DARWIN}
        fpSystem('"' + aaptpath + '"' + ' d badging "' + ExtractShortPathNameUTF8(SourcePath + SearchRec.Name) + '" > /dev/null 2>&1');
{$ENDIF}
        If Lo(DosExitCode) <> 0 Then Begin
          WriteLn(' - ' + SearchRec.Name + ' - Invalid metadata');
          apkStatus := False;
        End;
      End;
      If apkStatus = False Then Begin
        If Not optFakeWrite Then Begin
          FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
          If DeleteFileUTF8(SourcePath + SearchRec.Name) = False Then WriteLn(' ! Error deleting ' + SearchRec.Name);
        End;
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkValidate');
End;

Procedure apkSetTime;
Begin
  If optDebug Then WriteLn('Entering apkSetTime');
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      apkTimeStamp := 0;
      apkGetManifest(SourcePath);
      If apkTimeStamp <> 0 Then Begin
        If FileSetDateUTF8(ExtractShortPathNameUTF8(SourcePath + SearchRec.Name), apkTimeStamp) <> 0 Then WriteLn(' ! Unable to modify timestamp for ' + SearchRec.Name);
      End
      Else WriteLn(' ! No MANIFEST.MF in ' + SearchRec.Name + ' - considering invalid');
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkSetTime');
End;

Function fillArray(PathSpec: String): Boolean;
Begin
  If optDebug Then WriteLn('Entering fillArray');
  With SearchRec Do Begin
{$IFDEF WIN32}
    Exec('cmd.exe', '/c ' + aaptpath + ' d badging "' + ExtractShortPathNameUTF8(PathSpec + Name) + '" > ' + TempPath + 'aFilerAAPT.###');
{$ENDIF}
{$IFDEF LINUX}
    fpSystem('"' + aaptpath + '"' + ' d badging "' + ExtractShortPathNameUTF8(PathSpec + Name) + '" > ' + TempPath + 'aFilerAAPT.###');
{$ENDIF}
{$IFDEF DARWIN}
    fpSystem('"' + aaptpath + '"' + ' d badging "' + ExtractShortPathNameUTF8(PathSpec + Name) + '" > ' + TempPath + 'aFilerAAPT.###');
{$ENDIF}
    DosError := 0;
    Assign(AAPTfile, TempPath + 'aFilerAAPT.###');
{$I-}
    Reset(AAPTfile);
{$I+}
    If IOresult <> 0 Then Err(191);
    fillArray := False;
    If Lo(DosExitCode) <> 0 Then WriteLn(' ! Error parsing metadata in ' + Name) Else Begin
      If IOresult = 0 Then Begin
        While NOT EOF(AAPTfile) Do Begin
          ReadLn(AAPTfile, S1);

// packageName, packageVersionCode, packageVersionName

          If Pos('package:', S1) = 1 Then Begin
            Delete(S1, 1, 9);
            S2 := S1;
            While Length(S2) > 0 Do Begin
              If Pos('name=', S1) = 1 Then Begin
                Delete(S1, 1, 6);
                Delete(S1, Pos('''', S1), Length(S1) - Pos('''', S1) + 1);
                DBentry.packageName := S1;
              End;
              If Pos('versionCode=', S1) = 1 Then Begin
                Delete(S1, 1, 13);
                Delete(S1, Pos('''', S1), Length(S1) - Pos('''', S1) + 1);
                If Length(S1) > 0 Then DBentry.packageVersionCode := StrToInt(S1) Else DBentry.packageVersionCode := 0;
              End;
              If Pos('versionName=', S1) = 1 Then Begin
                Delete(S1, 1, 13);
                Delete(S1, Pos('''', S1), Length(S1) - Pos('''', S1) + 1);
                DBentry.packageVersionName := S1;
              End;
              If Pos(' ', S2) > 0 Then Delete(S2, 1, Pos(' ', S2)) Else S2 := '';
              S1 := S2;
            End;
          End;

// applicationLabel, applicationIcon

          If Pos('application:', S1) = 1 Then Begin
            Delete(S1, 1, 13);
            S2 := S1;
            While Length(S2) > 0 Do Begin
              If Pos('label=', S1) = 1 Then Begin
                Delete(S1, 1, 7);
                Delete(S1, Pos('''', S1), Length(S1) - Pos('''', S1) + 1);
                DBentry.applicationLabel := S1;
              End;
              If Pos('icon=', S1) = 1 Then Begin
                Delete(S1, 1, 6);
                Delete(S1, Pos('''', S1), Length(S1) - Pos('''', S1) + 1);
                DBentry.applicationIcon := S1;
              End;
              If Pos(' ', S2) > 0 Then Delete(S2, 1, Pos(' ', S2)) Else S2 := '';
              S1 := S2;
            End;
          End;

// sdkVersion

          If Pos('sdkVersion:', S1) = 1 Then Begin
            Delete(S1, 1, 12);
            Delete(S1, Length(S1), 1);
            If S1 <> '' Then DBentry.sdkVersion := StrToInt(S1) Else DBentry.sdkVersion := 0;
          End;

// targetSdkVersion

          If Pos('targetSdkVersion:', S1) = 1 Then Begin
            Delete(S1, 1, 18);
            Delete(S1, Length(S1), 1);
            If S1 <> '' Then DBentry.targetsdkVersion := StrToInt(S1) Else DBentry.targetsdkVersion := 0;
          End;
        End;
      End;
      fillArray := True;
    End;
    Close(AAPTfile);
    Erase(AAPTfile);
  End;
  If optDebug Then WriteLn('Leaving fillArray');
End;

Function generateFilename: AnsiString;
Begin
  If optDebug Then WriteLn('Entering generateFilename');
  WS1 := '';
  If DBentry.applicationLabel = '' Then DBentry.applicationLabel := '(Unnamed)';
  For W1 := 1 To Length(fnMask) Do Begin
    Case fnMask[W1] of
      'a': WS1 := WS1 + DBentry.applicationLabel;
      'c': WS1 := WS1 + Copy(DBentry.MD5xml, 29, 4);
      'p': WS1 := WS1 + DBentry.packageName;
      'v': WS1 := WS1 + 'v' + DBentry.packageVersionName;
      ' ', '(', ')', '[', ']': WS1 := WS1 + fnMask[W1];
      Else Err(141);
    End;
  End;
  For W1 := 1 To Length(WS1) Do Begin
    If Pos(WS1[W1], '":\/*?<>|`') > 0 Then WS1[W1] := '-';
  End;
  If (WS1[1] = '.') Or (WS1[1] = ' ') Then WS1[1] := '-';
  generateFilename := WS1 + '.apk';
  If optJoliet Then generateFilename := UTF8Copy(generateFilename, 1, 31) + '..' + UTF8Copy(generateFilename, UTF8Length(generateFilename) - 30, 31);
  If optDebug Then WriteLn('Leaving generateFilename');
End;

Procedure apkRename;
Begin
  If optDebug Then WriteLn('Entering apkRename');
  If Not validateFnMask Then Err(171);
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      clearArray;
      If fillArray(SourcePath) Then Begin
        apkGetManifest(SourcePath);
        FN := generateFilename;
        If SearchRec.Name <> FN Then Begin
          If FileExistsUTF8(SourcePath + FN) Then Begin
            WriteLn(' ! Cannot rename ' + FN + ' - Already exists');
          End
          Else If RenameFileUTF8(SourcePath + SearchRec.Name, SourcePath + FN) = False Then Begin
            WriteLn(' ! Cannot rename ' + FN + ' - Invalid filename?');
          End;
        End;
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkRename');
End;

Procedure apkScan;
Begin
  If optDebug Then WriteLn('Entering apkScan');
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(DestPath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(DestPath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    DestPath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + DestPath);
    If FindFirstUTF8(DestPath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      clearArray;
      If fillArray(DestPath) Then Begin
        apkGetManifest(DestPath);
        apkGetIcon(DestPath);
        If DBentry.MD5xml <> '' Then apkInsert Else Begin
          WriteLn(' ! No MANIFEST.MF in ' + DBentry.MD5xml + ' - considering invalid');
        End;
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkScan');
End;

Procedure apkKill;
Begin
  If optDebug Then WriteLn('Entering apkKill');
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      clearArray;
      If fillArray(SourcePath) Then Begin
        apkGetManifest(SourcePath);
        If (DBentry.MD5xml <> '') And (Not(checkWhiteList(DBentry.packageName))) Then Begin
          DBentry.xmlTime := apkTimeStamp;
          SQL := 'SELECT MAX([packageVersionCode]), MAX([md5Timestamp]) FROM [APK] WHERE [packageName] = ''' + DBentry.packageName + ''';';
          If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
          If (sqlite3_step(DBresult) = SQLITE_ROW) And (sqlite3_column_text(DBresult, 0) <> '') Then Begin

            apkVersionCode := StrToInt(sqlite3_column_text(DBresult, 0));
            apkTimeStamp := StrToInt(sqlite3_column_text(DBresult, 1));
            If (DBentry.packageVersionCode < apkVersionCode) And (DBentry.xmlTime > 1) And (DBentry.xmlTime <= apkTimeStamp) Then Begin
              WriteLn(' - ' + SearchRec.Name + ' deleted - newer exists');
              If Not optFakeWrite Then Begin
                FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
                If DeleteFileUTF8(SourcePath + SearchRec.Name) = False Then WriteLn(' ! Error deleting ' + SearchRec.Name);
                SQL := 'DELETE FROM APK WHERE [packageName] = ''' + DBentry.packageName + ''' AND [md5Manifest] = ''' + DBentry.MD5xml + ''';';
                If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(207);
              End;
            End;

          End;
          If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
        End;
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkKill');
End;

Procedure OBBKill;
Var
  TrimName: AnsiString;
Begin
  If optDebug Then WriteLn('Entering OBBKill');
  SourcePath := OBBPath;
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      OBBentry.obbType := UpCase(SearchRec.Name[1]);
      OBBentry.obbName := SearchRec.Name;
      Delete(OBBentry.obbName, 1, Pos('.', OBBentry.obbName));
      While Pos('.', OBBentry.obbName) > 1 Do Delete(OBBentry.obbName, Length(OBBentry.obbName), 1);
      Try
        OBBentry.obbVersion := StrToInt(OBBentry.obbName);
        OBBentry.obbName := SearchRec.Name;
        Delete(OBBentry.obbName, 1, Pos('.', OBBentry.obbName));
        Delete(OBBentry.obbName, 1, Pos('.', OBBentry.obbName));
        TrimName := Copy(OBBentry.obbName, 1, Length(OBBentry.obbName) - 4);
        If Not(checkWhiteList(TrimName)) Then Begin
          SQL := 'SELECT MAX([OBBVer]) FROM [OBB] WHERE [OBBName] = ''' + OBBentry.obbName + ''' AND [OBBType] = ''M'';';
          If sqlite3_prepare(DB, PChar(SQL), Length(SQL) + 1, DBresult, NIL) <> SQLITE_OK Then Err(202);
          If (sqlite3_step(DBresult) = SQLITE_ROW) And (sqlite3_column_text(DBresult, 0) <> '') Then Begin
            obbVersionCode := StrToInt(sqlite3_column_text(DBresult, 0));
            If (OBBentry.obbVersion < obbVersionCode) Then Begin
              WriteLn(' - ' + SearchRec.Name + ' is older than known in repository.');
              If Not optFakeWrite Then Begin
                FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
                If DeleteFileUTF8(SourcePath + SearchRec.Name) = False Then WriteLn(' ! Error deleting ' + SearchRec.Name);
                SQL := 'DELETE FROM OBB WHERE [OBBName] = ''' + OBBentry.obbName + ''' AND [OBBType] = ''' + OBBentry.obbType + ''' AND [OBBVer] = ''' + IntToStr(OBBentry.obbVersion) + ''';';
                If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(207);
              End;
            End;
          End;
          If sqlite3_finalize(DBresult) <> SQLITE_OK Then Err(204);
        End;
      Except
        On EConvertError Do WriteLn(' ! Not a valid .obb filename, skipping.');
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving OBBKill');
End;

Function apkCopy(PathSpec: String): Boolean;
Var
  tFN: AnsiString;
Begin
  If optDebug Then WriteLn('Entering apkCopy');
  apkCopy := False;
  tFN := generateFilename;
  If Not(FileExistsUTF8(DestPath + tFN)) Then Begin
    If Not CopyFile(PathSpec + SearchRec.Name, DestPath + '##DONUT##.apk', True) Then Err(151);
    If Not RenameFileUTF8(DestPath + '##DONUT##.apk', DestPath + tFN) Then Err(153);
    If Not optFakeWrite Then Begin
      FileSetAttrUTF8(PathSpec + SearchRec.Name, 0);
      If Not DeleteFileUTF8(PathSpec + SearchRec.Name) Then Err(152);
    End;
    apkCopy := True;
  End
  Else Begin
    WriteLn(' ! Destination file already exists, skipping.');
    apkCopy := False;
  End;
  If optDebug Then WriteLn('Leaving apkCopy');
End;

Procedure apkAdd;
Var
  Success: Boolean;
Begin
  If optDebug Then WriteLn('Entering apkAdd');
  If Not validateFnMask Then Err(171);
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      clearArray;
      If fillArray(SourcePath) Then Begin
        apkGetManifest(SourcePath);
        apkGetIcon(SourcePath);
        Success := False;
        If DBentry.MD5xml <> '' Then Success := True Else Success := False;
        If (Success) And Not (apkExists(DBentry.MD5xml)) Then Success := True Else Success := False;
        If (Success) And (apkCopy(SourcePath)) Then Success := True Else Success := False;
        If (Success) And (apkInsert) Then Success := True Else Success := False;
      End;
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving apkAdd');
End;

Procedure OBBAdd(CF: Boolean);
Begin
  If optDebug Then WriteLn('Entering OBBAdd');
  If Not(CF) Then SourcePath := OBBPath;
  If optRecursion Then Begin
    RecurseList := FindAllDirectories(SourcePath);
  End
  Else Begin
    RecurseList := TStringList.Create;
  End;
  RecurseList.Add(SourcePath);
  For W3 := 0 To RecurseList.Count - 1 Do Begin
    SourcePath := AppendPathDelim(RecurseList[W3]);
    If optDebug Then WriteLn('Scanning ' + SourcePath);
    If FindFirstUTF8(SourcePath + ParamStrUTF8(2), $21, SearchRec) = 0 Then Repeat
      With OBBentry Do If (Pos('main.', SearchRec.Name) = 1) Or (Pos('patch.', SearchRec.Name) = 1) Then Begin
        obbType := UpCase(SearchRec.Name[1]);
        obbName := SearchRec.Name;
        Delete(obbName, 1, Pos('.', obbName));
        While Pos('.', obbName) > 1 Do Delete(obbName, Length(obbName), 1);
        Try
          obbVersion := StrToInt(obbName);
          obbName := SearchRec.Name;
          Delete(obbName, 1, Pos('.', obbName));
          Delete(obbName, 1, Pos('.', obbName));
          Case CF of
            True: If Not(FileExistsUTF8(OBBPath + SearchRec.Name)) Then Begin
              If Not CopyFile(SourcePath + SearchRec.Name, OBBPath + SearchRec.Name, True) Then Err(151);
              If Not optFakeWrite Then Begin
                FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
                If Not DeleteFileUTF8(SourcePath + SearchRec.Name) Then Err(152);
              End;
              SQL := 'INSERT INTO OBB ([OBBType], [OBBVer], [OBBName]) VALUES (';
              SQL := SQL + '"' + obbType + '","' + IntToStr(obbVersion) + '","' + obbName + '");';
              SQLresult := sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL);
              If SQLresult = 0 Then WriteLn(' + ' + obbName + ' v' + IntToStr(obbVersion) + ' Added');
              If SQLresult = 19 Then WriteLn(' - ' + obbName + ' v' + IntToStr(obbVersion) + ' Already known');
              If Not(SQLresult In [0, 19]) Then Err(201);
            End
            Else Begin
              WriteLn(' ! ' + obbName + ' already known, skipping.');
              If Not optFakeWrite Then Begin
                FileSetAttrUTF8(SourcePath + SearchRec.Name, 0);
                If Not DeleteFileUTF8(SourcePath + SearchRec.Name) Then Err(152);
              End;
            End;
            False: Begin
              SQL := 'INSERT INTO OBB ([OBBType], [OBBVer], [OBBName]) VALUES (';
              SQL := SQL + '"' + obbType + '","' + IntToStr(obbVersion) + '","' + obbName + '");';
              SQLresult := sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL);
              If SQLresult = 0 Then WriteLn(' + ' + obbName + ' v' + IntToStr(obbVersion) + ' Added');
              If Not(SQLresult In [0, 19]) Then Err(201);
            End;
          End;
        Except
          On EConvertError Do WriteLn(' ! Not a valid .obb filename, skipping.');
        End;
      End
      Else WriteLn(' ! Not a valid .obb filename, skipping.');
      If PollKeyEvent <> 0 Then KeyBreak;
    Until FindNextUTF8(SearchRec) <> 0;
    FindCloseUTF8(SearchRec);
  End;
  RecurseList.Free;
  If optDebug Then WriteLn('Leaving OBBAdd');
End;

Begin
{$IFNDEF DARWIN}
  InitKeyboard;
{$ENDIF}
  Header;

  If (ParamCount <> 2) Then Begin
    Usage;
    Err(2);
  End;

  If (Length(ParamstrUTF8(1)) <> 1) Or (Pos(ParamStrUTF8(1)[1], 'acdklorstvCFIORSUVW') = 0) Then Begin
    Usage;
    Err(3);
  End;

{$IFDEF WIN32}
  SetConsoleOutputCP(CP_UTF8);
{$ENDIF}

  ShellPath := ExtractFileName(GetEnvironmentVariableUTF8(shellenv));
  SourcePath := ExtractShortPathNameUTF8(AppendPathDelim(GetCurrentDirUTF8));
{$IFDEF WIN32}
  BasePath := ExtractShortPathNameUTF8(ParamStrUTF8(0));
  While BasePath[Length(BasePath)] <> DirectorySeparator Do Delete(BasePath, Length(BasePath), 1);
  TempPath := ExtractShortPathNameUTF8(AppendPathDelim(GetEnvironmentVariableUTF8('TEMP')));
{$ENDIF}
{$IFDEF LINUX}
  BasePath := ExtractShortPathNameUTF8(ParamStrUTF8(0));
  While BasePath[Length(BasePath)] <> DirectorySeparator Do Delete(BasePath, Length(BasePath), 1);
  TempPath := '/tmp/';
{$ENDIF}
{$IFDEF DARWIN}
  BasePath := GetEnv('HOME') + DirectorySeparator + 'Library/Application Support/aFiler/';
  TempPath := '/tmp/';
{$ENDIF}
  DBPath := ExtractShortPathNameUTF8(BasePath) + DBName;
  aaptPath := ExtractShortPathNameUTF8(BasePath) + aaptname;
  unzipPath := ExtractShortPathNameUTF8(BasePath) + unzipname;

  If optDebug Then Begin
    WriteLn(' * Shell = ' + ShellPath);
    WriteLn(' * Source = ' + SourcePath);
    WriteLn(' * Base = ' + BasePath);
    WriteLn(' * Temp = ' + TempPath);
    WriteLn(' * DB = ' + dbPath);
    WriteLn(' * aapt = ' + aaptPath);
    WriteLn(' * unzip = ' + unzipPath);
  End;

  If Not FileExistsUTF8(aaptPath) Then Err(80);
  If Not FileExistsUTF8(unzipPath) Then Err(81);

  Case ParamStrUTF8(1)[1] of
    'I': Begin
      If ParamStrUTF8(2) <> 'YES' Then Err(31) Else Begin
        If FileExistsUTF8(DBPath) Then Begin
          FileSetAttrUTF8(DBPath, 0);
          If Not DeleteFileUTF8(DBPath) Then Err(93);
        End;
        initDB;
        Err(4);
      End;
    End;
  End;

  dbTransaction := False;
  dbOpen := openDB;
  If Not dbOpen Then Err(90);
  initWhiteList;

  Case ParamStrUTF8(1)[1] of
    'W': addWhiteList;
    'U': delWhiteList;
    'V': showWhiteList;
    'R': parseOutPath;
    'S': parseOBBPath;
    'F': parseFnMask;
    'O': Begin
      If ParamStrUTF8(2)[Length(ParamStrUTF8(2))] = '+' Then optFlag := 1
      Else If ParamStrUTF8(2)[Length(ParamStrUTF8(2))] = '-' Then optFlag := 0
      Else Err(145);
      optParam := '';
      If Pos('deb', ParamStrUTF8(2)) = 1 Then optParam := 'optDebugInfo';
      If Pos('fak', ParamStrUTF8(2)) = 1 Then optParam := 'optFakeWrite';
      If Pos('jol', ParamStrUTF8(2)) = 1 Then optParam := 'optJoliet';
      If Pos('rec', ParamStrUTF8(2)) = 1 Then optParam := 'optRecursion';
      If Pos('set', ParamStrUTF8(2)) = 1 Then optParam := 'optSetPriority';
      If Pos('tra', ParamStrUTF8(2)) = 1 Then optParam := 'optTransactions';
      If Pos('vac', ParamStrUTF8(2)) = 1 Then optParam := 'optVacuum';
      If optParam <> '' Then Begin
        SQL := 'UPDATE [CONFIG] SET [' + optParam + '] = ' + IntToStr(optFlag) + ';';
        If sqlite3_exec(DB, PChar(SQL), NIL, NIL, NIL) <> SQLITE_OK Then Err(201);
        Err(146);
      End
      Else Err(145);
    End;
    Else getConfig;
  End;

  Case ParamStrUTF8(1)[1] of
    'C': Begin
      writeConfig;
      closeDB;
      Err(0);
    End;
    'c': Begin
      OBBKill;
      closeDB;
      Err(0);
    End;
    'k': Begin
      apkKill;
      closeDB;
      Err(0);
    End;
    'l': Begin
      OBBAdd(False);
      closeDB;
      Err(0);
    End;
    'r': Begin
      apkRename;
      closeDB;
      Err(0);
    End;
    's': Begin
      apkScan;
      closeDB;
      Err(0);
    End;
    'v': Begin
      apkValidate;
      closeDB;
      Err(0);
    End;
    't': Begin
      apkSetTime;
      closeDB;
      Err(0);
    End;
  End;

  If Pos(LowerCase(ExtractShortPathNameUTF8(DestPath)), LowerCase(SourcePath)) = 1 Then Err(115);

  Case ParamStrUTF8(1)[1] of
    'a': Begin
      apkAdd;
      closeDB;
    End;
    'd': Begin
      apkDelete;
      closeDB;
    End;
    'o': Begin
      OBBAdd(True);
      closeDB;
    End;
  End;
  Err(0);
End.
