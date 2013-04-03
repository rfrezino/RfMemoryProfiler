unit uRfMemoryProfiler;

interface
{$Include RfMemoryProfilerOptions.inc}

uses
  Classes, SyncObjs {$IFDEF UNITTEST}, uUnitTestHeader {$ENDIF};

  {It's a simple output to save the report of memory usage on the disk. It'll create a file called test.txt in the executable directory}
  procedure SaveMemoryProfileToFile;

  {Get the current list of instances (TClassVars)}
  function RfGetInstanceList: TList;

  {$IFDEF UNITTEST}
  procedure InitializeRfMemoryProfiler;
  {$ENDIF}

{$IFDEF UNITTEST}
var
  SDefaultGetMem: function(Size: Integer): Pointer;
  SDefaultFreeMem: function(P: Pointer): Integer;
  SDefaultReallocMem: function(P: Pointer; Size: Integer): Pointer;
  SDefaultAllocMem: function(Size: Cardinal): Pointer;
{$ENDIF}

const
  SIZE_OF_MAP = 65365;

type
  TArrayOfMap = array [0..SIZE_OF_MAP] of Integer;

  PCallerAllocator = ^TCallerAllocator;
  TCallerAllocator = record
    MemAddress: Integer;
    NumAllocations: Integer;
  end;

  TCriticalSectionIgnore = class(TCriticalSection);

  TAllocationMap = class
  strict private
    FCriticalSection: TCriticalSectionIgnore;
    FItems: array of TCallerAllocator;

    function BinarySearch(const ACallerAddr: Cardinal): Integer;
    function FindOrAdd(const ACallerAddr: Integer): Integer;

    procedure QuickSortInternal(ALow, AHigh: Integer);
    procedure QuickSort;
  private
    function GetItems(Index: Integer): TCallerAllocator;
  public
    constructor Create;
    destructor Destroy; override;

    procedure IncCounter(ACallerAddr: Integer);
    procedure DecCounter(ACallerAddr: Integer);

    function GetAllocationCounterByCallerAddr(ACallerAddr: Cardinal): TCallerAllocator;

    function Count: Integer;

    property Items[Index: Integer]: TCallerAllocator read GetItems;
  end;

  PRfClassController = ^TRfClassController;
  TRfClassController = class(TObject)
  private
    OldVMTFreeInstance: Pointer;
  public
    BaseInstanceCount: Integer;
    BaseClassName: string;
    BaseParentClassName: string;
    BaseInstanceSize: Integer;

    AllocationMap: TAllocationMap;

    constructor Create;
    destructor Destroy; override;
  end;

  TRfObjectHack = class(TObject)
  private
    class procedure SetRfClassController(ARfClassController: TRfClassController); //inline;

    procedure IncCounter; inline;
    procedure DecCounter; inline;
    procedure CallOldFunction;

    function GetAllocationAddress: Integer;
    procedure SetAllocationAddress(const Value: Integer);

    class function NNewInstance: TObject;
    class function NNewInstanceTrace: TObject;
    procedure NFreeInstance;
  public
    class function GetRfClassController: TRfClassController; inline;

    {$IFDEF INSTANCES_TRACKER}
    property AllocationAddress: Integer read GetAllocationAddress write SetAllocationAddress;
    {$ENDIF}
  end;

  procedure RegisterRfClassController(const Classes: array of TRfObjectHack);

var
  RfMapOfBufferAllocation: TArrayOfMap;
  RfIsMemoryProfilerActive: Boolean;

implementation

uses
   Windows, SysUtils, TypInfo;

const
  SIZE_OF_INT = SizeOf(Integer);
  PARITY_BYTE = 7777777;
  GAP_SIZE = SizeOf(PARITY_BYTE) + SIZE_OF_INT {$IFDEF BUFFER_TRACKER} + SIZE_OF_INT {$ENDIF};
  /// Delphi linker starts the code section at this fixed offset
  CODE_SECTION = $1000;

type
  TMemoryAddressBuffer = class
    AllocationAddr: Integer;
    NumAllocations: Integer;
    Next: TMemoryAddressBuffer;
  end;

  TArrayOfMapAddress = array [0..SIZE_OF_MAP] of TMemoryAddressBuffer;

var
  {Flag to say if the memory watcher is on or off}
  SIsNamedBufferMapActive: Boolean;
  SIsObjectAllocantionTraceOn: Boolean;
  SIsBufferAllocationTraceOn: Boolean;
  SMapofBufferAddressAllocation: TArrayOfMapAddress;

type
  TThreadMemory = array [0..SIZE_OF_MAP] of Integer;

  PJump = ^TJump;
  TJump = packed record
    OpCode: Byte;
    Distance: Pointer;
  end;

  PMappedRecord = ^MappedRecord;
  MappedRecord = packed record
    Parity: Integer;
    SizeCounterAddr: Integer;

    {$IFDEF BUFFER_TRACKER}
    AllocationAddr: Integer;
    {$ENDIF}

    procedure SetParityByte; inline;
    procedure IncMapSizeCounter; inline;
    {$IFDEF BUFFER_TRACKER}
    procedure IncAllocationMap; inline;
    {$ENDIF}

    procedure ClearParityByte; inline;
    procedure DecMapSizeCounter; inline;

    function Size: Integer; inline;
    {$IFDEF BUFFER_TRACKER}
    procedure DecAllocationMap; inline;
    {$ENDIF}
  end;

var
  {$IFNDEF UNITTEST}
  SDefaultGetMem: function(Size: Integer): Pointer;
  SDefaultFreeMem: function(P: Pointer): Integer;
  SDefaultReallocMem: function(P: Pointer; Size: Integer): Pointer;
  SDefaultAllocMem: function(Size: Cardinal): Pointer;
  {$ENDIF}

  SThreadMemory: TThreadMemory;
  SListClassVars: TList;
  SGetModuleHandle: Cardinal;

  SInitialSection: Cardinal;
  SFinalSection: Cardinal;

  SRCBufferCounter: TCriticalSection;

{$REGION 'Util'}
procedure GetCodeOffset;
var
  LMapFile: string;
begin
  LMapFile := GetModuleName(hInstance);
  SGetModuleHandle := GetModuleHandle(Pointer(ExtractFileName(LMapFile))) + CODE_SECTION;
end;

function GetMethodAddress(AStub: Pointer): Pointer;
const
  CALL_OPCODE = $E8;
begin
  if PBYTE(AStub)^ = CALL_OPCODE then
  begin
    Inc(Integer(AStub));
    Result := Pointer(Integer(AStub) + SizeOf(Pointer) + PInteger(AStub)^);
  end
  else
    Result := nil;
end;

procedure AddressPatch(const ASource, ADestination: Pointer);
const
  JMP_OPCODE = $E9;
  SIZE = SizeOf(TJump);
var
  NewJump: PJump;
  OldProtect: Cardinal;
begin
  if VirtualProtect(ASource, SIZE, PAGE_EXECUTE_READWRITE, OldProtect) then
  begin
    NewJump := PJump(ASource);
    NewJump.OpCode := JMP_OPCODE;
    NewJump.Distance := Pointer(Integer(ADestination) - Integer(ASource) - 5);

    FlushInstructionCache(GetCurrentProcess, ASource, SizeOf(TJump));
    VirtualProtect(ASource, SIZE, OldProtect, @OldProtect);
  end;
end;

function PatchCodeDWORD(ACode: PDWORD; AValue: DWORD): Boolean;
var
  LRestoreProtection, LIgnore: DWORD;
begin
  Result := False;
  if VirtualProtect(ACode, SizeOf(ACode^), PAGE_EXECUTE_READWRITE, LRestoreProtection) then
  begin
    Result := True;
    ACode^ := AValue;
    Result := VirtualProtect(ACode, SizeOf(ACode^), LRestoreProtection, LIgnore);

    if not Result then
      Exit;

    Result := FlushInstructionCache(GetCurrentProcess, ACode, SizeOf(ACode^));
  end;
end;

procedure SaveMemoryProfileToFile;
var
  LStringList: TStringList;
  i: Integer;
  LClassVar: TRfClassController;
begin
  LStringList := TStringList.Create;
  try
    LStringList.Add('CLASS | INSTANCE SIZE | NUMBER OF INSTANCES | TOTAL');
    {$IFDEF INSTANCES_COUNTER}
    for i := 0 to SListClassVars.Count -1 do
    begin
      LClassVar := TRfClassController(SListClassVars.Items[I]);
      if LClassVar.BaseInstanceCount > 0 then
      begin
        LStringList.Add(Format('%s | %d bytes | %d | %d bytes',
          [LClassVar.BaseClassName, LClassVar.BaseInstanceSize, LClassVar.BaseInstanceCount, LClassVar.BaseInstanceSize * LClassVar.BaseInstanceCount]));
      end;
    end;
    {$ENDIF}

    {$IFDEF BUFFER_COUNTER}
    for I := 0 to SIZE_OF_MAP do
      if RfMapOfBufferAllocation[I] > 0 then
        LStringList.Add(Format('Buffer | %d bytes | %d | %d bytes', [I, RfMapOfBufferAllocation[I], RfMapOfBufferAllocation[I] * I]));
    {$ENDIF}

    LStringList.SaveToFile(ExtractFilePath(ParamStr(0)) + 'RfMemoryReport.txt');
  finally
    FreeAndNil(LStringList);
  end;
end;

type
  PStackFrame = ^TStackFrame;
  TStackFrame = record
    CallerFrame: Cardinal;
    CallerAddr: Cardinal;
  end;

function GetSectorIdentificator: Integer;
var
  LStack: PStackFrame;
begin
  asm
    mov eax, ebp
    mov LStack, eax
  end;
  Result := 0;
  LStack := PStackFrame(LStack^.CallerFrame);
  LStack := PStackFrame(LStack^.CallerFrame);
  Result := LStack^.CallerAddr;
  Dec(Result, SGetModuleHandle);
end;

function GetMemAllocIdentificator: Integer;
const
  MIN_FRAME = 66000;
var
  LStack: PStackFrame;
begin
  asm
    mov eax, ebp
    mov LStack, eax
  end;
  Result := 0;
  if LStack^.CallerFrame > MIN_FRAME then
    LStack := PStackFrame(LStack^.CallerFrame);
  if LStack^.CallerFrame > MIN_FRAME then
    LStack := PStackFrame(LStack^.CallerFrame);
  Result := LStack^.CallerAddr;
  Dec(Result, SGetModuleHandle);
end;

function RfGetInstanceList: TList;
begin
  Result := SListClassVars;
end;

function _InitializeHook(AClass: TClass; AOffset: Integer; HookAddress: Pointer): Boolean;
var
  lAddress: Pointer;
  lProtect: DWord;
begin
  lAddress := Pointer(Integer(AClass) + AOffset);
  Result := VirtualProtect(lAddress, SIZE_OF_INT, PAGE_READWRITE, @lProtect);
  if not Result then
    Exit;

  CopyMemory(lAddress, @HookAddress, SIZE_OF_INT);
  Result := VirtualProtect(lAddress, SIZE_OF_INT, lProtect, @lProtect);
end;

procedure RegisterRfClassController(const Classes: array of TRfObjectHack);
var
  LClass: TRfObjectHack;
begin
  for LClass in Classes do
    if LClass.GetRfClassController = nil then
      LClass.SetRfClassController(TRfClassController.Create)
    else
      raise Exception.CreateFmt('Class %s has automated section or duplicated registration.', [LClass.ClassName]);
end;

{$ENDREGION}

{$REGION 'Override Methods'}
procedure OldNewInstance;
asm
  call TObject.NewInstance;
end;

procedure OldInstanceSize;
asm
  call TObject.InstanceSize
end;
{$ENDREGION}

{$REGION 'Instances Control'}
{ TObjectHack }
type
  TExecute = procedure of object;

procedure TRfObjectHack.CallOldFunction;
var
  Routine: TMethod;
  Execute: TExecute;
begin
  Routine.Data := Pointer(Self);
  Routine.Code := GetRfClassController.OldVMTFreeInstance;
  Execute := TExecute(Routine);
  Execute;
end;

procedure TRfObjectHack.DecCounter;
begin
  {$IFDEF INSTANCES_TRACKER}
  GetRfClassController.AllocationMap.DecCounter(AllocationAddress);
  {$ENDIF}

  GetRfClassController.BaseInstanceCount := GetRfClassController.BaseInstanceCount - 1;
  CallOldFunction;
end;

function TRfObjectHack.GetAllocationAddress: Integer;
begin
  Result := PInteger(Integer(Self) + Self.InstanceSize)^;
end;

class function TRfObjectHack.GetRfClassController: TRfClassController;
begin
  Result := PRfClassController(Integer(Self) + vmtAutoTable)^;
end;

procedure TRfObjectHack.SetAllocationAddress(const Value: Integer);
begin
  PInteger(Integer(Self) + Self.InstanceSize)^ := Value;
end;

class procedure TRfObjectHack.SetRfClassController(ARfClassController: TRfClassController);
begin
  ARfClassController.BaseClassName := Self.ClassName;
  ARfClassController.BaseInstanceSize := Self.InstanceSize;
  ARfClassController.OldVMTFreeInstance := PPointer(Integer(TClass(Self)) + vmtFreeInstance)^;

  if Self.ClassParent <> nil then
    ARfClassController.BaseParentClassName := Self.ClassParent.ClassName;

  PatchCodeDWORD(PDWORD(Integer(Self) + vmtAutoTable), DWORD(ARfClassController));
  _InitializeHook(Self, vmtFreeInstance, @TRfObjectHack.DecCounter);
end;

procedure TRfObjectHack.NFreeInstance;
begin
  CleanupInstance;
  SDefaultFreeMem(Self);
end;

class function TRfObjectHack.NNewInstance: TObject;
begin
  Result := InitInstance(SDefaultGetMem(Self.InstanceSize));
end;

class function TRfObjectHack.NNewInstanceTrace: TObject;
begin
  Result := InitInstance(SDefaultGetMem(Self.InstanceSize {$IFDEF INSTANCES_TRACKER} + SIZE_OF_INT {$ENDIF}));
  if (Result.ClassType = TObject)
      or (Result.ClassType = TRfClassController)
      or (Result.ClassType = TAllocationMap)
      or (Result.ClassType = TMemoryAddressBuffer)
      or (Result.ClassType = TCriticalSectionIgnore)
      or (Result is EExternal) then
  begin
    Exit;
  end;

  {$IFDEF INSTANCES_TRACKER}
  TRfObjectHack(Result).AllocationAddress := GetSectorIdentificator;
  {$ENDIF}
  TRfObjectHack(Result).IncCounter;
end;

procedure TRfObjectHack.IncCounter;
begin
  if GetRfClassController = nil then
    RegisterRfClassController(Self);

  GetRfClassController.BaseInstanceCount := GetRfClassController.BaseInstanceCount + 1;
  {$IFDEF INSTANCES_TRACKER}
  GetRfClassController.AllocationMap.IncCounter(AllocationAddress);
  {$ENDIF}
end;

{ TClassVars }
constructor TRfClassController.Create;
begin
  SListClassVars.Add(Self);
  {$IFDEF INSTANCES_TRACKER}
  AllocationMap := TAllocationMap.Create;
  {$ENDIF}
end;

{ TAllocationMap }
procedure TAllocationMap.QuickSort;
begin
  QuickSortInternal(Low(FItems), High(FItems));
end;

procedure TAllocationMap.QuickSortInternal(ALow, AHigh: Integer);
var
  LLow, LHigh, LPivot, LValue: Integer;
begin
  LLow := ALow;
  LHigh := AHigh;
  LPivot := FItems[(LLow + LHigh) div 2].MemAddress;
  repeat
    while FItems[LLow].MemAddress < LPivot do
      Inc(LLow);
    while FItems[LHigh].MemAddress > LPivot do
      Dec(LHigh);
    if LLow <= LHigh then
    begin
      LValue := FItems[LLow].MemAddress;
      FItems[LLow].MemAddress := FItems[LHigh].MemAddress;
      FItems[LHigh].MemAddress := LValue;
      Inc(LLow);
      Dec(LHigh);
    end;
  until LLow > LHigh;
  if LHigh > ALow then
    QuickSortInternal(ALow, LHigh);
  if LLow < AHigh then
    QuickSortInternal(LLow, AHigh);
end;

function TAllocationMap.BinarySearch(const ACallerAddr: Cardinal): Integer;
var
  LMinIndex, LMaxIndex: Cardinal;
  LMedianIndex, LMedianValue: Cardinal;
begin
  LMinIndex := Low(FItems);
  LMaxIndex := Length(FItems);
  while LMinIndex <= LMaxIndex do
  begin
    LMedianIndex := (LMinIndex + LMaxIndex) div 2;
    LMedianValue := FItems[LMedianIndex].MemAddress;
    if ACallerAddr < LMedianValue then
      LMaxIndex := Pred(LMedianIndex)
    else if ACallerAddr = LMedianValue then
    begin
      Result := LMedianIndex;
      Exit;
    end
    else
      LMinIndex := Succ(LMedianIndex);
  end;
  Result := -1;
end;

function TAllocationMap.Count: Integer;
begin
  Result := Length(FItems);
end;

constructor TAllocationMap.Create;
begin
  inherited;
  SetLength(FItems, 1);
  FItems[0].MemAddress := 0;
  FItems[0].NumAllocations := 0;
  FCriticalSection := TCriticalSectionIgnore.Create;
end;

procedure TAllocationMap.DecCounter(ACallerAddr: Integer);
var
  LItem: PCallerAllocator;
begin
  LItem := @FItems[FindOrAdd(ACallerAddr)];
  LItem^.NumAllocations := LItem^.NumAllocations - 1;
end;

destructor TAllocationMap.Destroy;
begin
  FCriticalSection.Free;
  inherited;
end;

function TAllocationMap.FindOrAdd(const ACallerAddr: Integer): Integer;
begin
  Result := BinarySearch(ACallerAddr);
  if Result = -1 then
  begin
    FCriticalSection.Acquire;
    SetLength(FItems, Length(FItems) + 1);
    FItems[Length(FItems) - 1].MemAddress := ACallerAddr;
    FItems[Length(FItems) - 1].NumAllocations := 0;
    QuickSort;
    FCriticalSection.Release;
  end;
  Result := BinarySearch(ACallerAddr);
end;

function TAllocationMap.GetAllocationCounterByCallerAddr(ACallerAddr: Cardinal): TCallerAllocator;
begin
  Result := Items[BinarySearch(ACallerAddr)];
end;

function TAllocationMap.GetItems(Index: Integer): TCallerAllocator;
begin
  Result := FItems[Index];
end;

procedure TAllocationMap.IncCounter(ACallerAddr: Integer);
var
  LItem: PCallerAllocator;
begin
  LItem := @FItems[FindOrAdd(ACallerAddr)];
  LItem^.NumAllocations := LItem^.NumAllocations + 1;
end;

{$ENDREGION}

{$REGION 'Buffer Control'}
function IsInMap(AValue: Integer): Boolean; inline;
begin
  try
    Result := (AValue = PARITY_BYTE);
  except
    Result := False;
  end;
end;

function MemorySizeOfPos(APos: Integer): Integer; inline;
begin
  Result := (APos - Integer(@RfMapOfBufferAllocation)) div SIZE_OF_INT;
end;

procedure MemoryBufferCounter(ABufSize: Integer; AInitialPointer: PMappedRecord; AValue: Integer);
var
  LMemoryBufferAddress: TMemoryAddressBuffer;
  LLastMemoryBufferAddress: TMemoryAddressBuffer;
begin
  if SMapofBufferAddressAllocation[ABufSize] = nil then
  begin
    SMapofBufferAddressAllocation[ABufSize] := TMemoryAddressBuffer.Create;
    SMapofBufferAddressAllocation[ABufSize].NumAllocations := AValue;
    {$IFDEF BUFFER_TRACKER}
    SMapofBufferAddressAllocation[ABufSize].AllocationAddr := AInitialPointer.AllocationAddr;
    {$ENDIF}
    Exit;
  end;

  LLastMemoryBufferAddress := SMapofBufferAddressAllocation[ABufSize];
  LMemoryBufferAddress := LLastMemoryBufferAddress;

  while (LMemoryBufferAddress <> nil) do
  begin
    {$IFDEF BUFFER_TRACKER}
    if LMemoryBufferAddress.AllocationAddr <> AInitialPointer.AllocationAddr then
    begin
      LLastMemoryBufferAddress := LMemoryBufferAddress;
      LMemoryBufferAddress := LMemoryBufferAddress.Next;
      Continue;
    end;
    {$ENDIF}

    SRCBufferCounter.Acquire;
    try
      LMemoryBufferAddress.NumAllocations := LMemoryBufferAddress.NumAllocations + AValue;
    finally
      SRCBufferCounter.Release;
    end;
    Exit;
  end;

  SRCBufferCounter.Acquire;
  try
    LMemoryBufferAddress := TMemoryAddressBuffer.Create;
    {$IFDEF BUFFER_TRACKER}
    LMemoryBufferAddress.AllocationAddr := AInitialPointer.AllocationAddr;
    {$ENDIF}
    LMemoryBufferAddress.NumAllocations := AValue;

    LLastMemoryBufferAddress.Next := LMemoryBufferAddress;
  finally
    SRCBufferCounter.Release;
  end;
end;

function NGetMem(Size: Integer): Pointer;
var
  MapSize: Integer;
  LMappedRecord: PMappedRecord;
begin
  if (Size = SIZE_OF_INT) then
  begin
    Result := SDefaultAllocMem(Size);
    Exit;
  end;

  if Size >= SIZE_OF_MAP then
    MapSize := SIZE_OF_MAP
  else
    MapSize := Size;

  Result := SDefaultGetMem(Size + GAP_SIZE);
  LMappedRecord := Result;

  LMappedRecord^.SetParityByte;

  LMappedRecord^.SizeCounterAddr := Integer(@RfMapOfBufferAllocation[MapSize]);
  LMappedRecord^.IncMapSizeCounter;

  {$IFDEF BUFFER_TRACKER}
  LMappedRecord^.AllocationAddr := GetMemAllocIdentificator;
  LMappedRecord^.IncAllocationMap;
  {$ENDIF}

  {$IFDEF UNITTEST}
  if LMappedRecord.Size = BUFFER_TEST_SIZE then
    SetAllocationAddress(LMappedRecord);
  {$ENDIF}
  Result := Pointer(Integer(Result) + GAP_SIZE);
end;

function NAllocMem(Size: Cardinal): Pointer;
var
  MapSize: Integer;
  LMappedRecord: PMappedRecord;
begin
  if (Size = SIZE_OF_INT) then
  begin
    Result := SDefaultAllocMem(Size);
    Exit;
  end;

  if Size > SIZE_OF_MAP then
    MapSize := SIZE_OF_MAP
  else
    MapSize := Size;

  Result := SDefaultAllocMem(Size + GAP_SIZE);
  LMappedRecord := Result;

  LMappedRecord^.SetParityByte;

  LMappedRecord^.SizeCounterAddr := Integer(@RfMapOfBufferAllocation[MapSize]);
  LMappedRecord^.IncMapSizeCounter;

  {$IFDEF BUFFER_TRACKER}
  LMappedRecord^.AllocationAddr := GetMemAllocIdentificator;
  LMappedRecord^.IncAllocationMap;
  {$ENDIF}

  {$IFDEF UNITTEST}
    if Size = BUFFER_TEST_SIZE then
      SetAllocationAddress(Result);
  {$ENDIF}
  Result := Pointer(Integer(Result) + GAP_SIZE);
end;

function NFreeMem(P: Pointer): Integer;
var
  LMappedRecord: PMappedRecord;
begin
  LMappedRecord := Pointer(Integer(P) - GAP_SIZE);
  if IsInMap(LMappedRecord^.Parity) then
  begin
    LMappedRecord^.ClearParityByte;
    LMappedRecord^.DecMapSizeCounter;
    {$IFDEF BUFFER_TRACKER}
    LMappedRecord^.DecAllocationMap;
    {$ENDIF}

    {$IFDEF UNITTEST}
    if LMappedRecord.Size = BUFFER_TEST_SIZE then
      SetDeallocationAddress(LMappedRecord);
    {$ENDIF}
    Result := SDefaultFreeMem(LMappedRecord);
  end
  else
    Result := SDefaultFreeMem(P);
end;

function NReallocMem(P: Pointer; Size: Integer): Pointer;
var
  LMappedRecord: PMappedRecord;
  LSizeMap: Integer;
begin
  LMappedRecord := Pointer(Integer(P) - GAP_SIZE);
  if not IsInMap(LMappedRecord^.Parity) then
  begin
    Result := SDefaultReallocMem(P, Size);
    Exit;
  end;

  if Size > SIZE_OF_MAP then
    LSizeMap := SIZE_OF_MAP
  else
    LSizeMap := Size;

  LMappedRecord^.ClearParityByte;
  LMappedRecord^.DecMapSizeCounter;

  Result := SDefaultReallocMem(LMappedRecord, Size + GAP_SIZE);

  LMappedRecord := Result;
  LMappedRecord^.SetParityByte;

  LMappedRecord^.SizeCounterAddr := Integer(@RfMapOfBufferAllocation[LSizeMap]);
  LMappedRecord^.IncMapSizeCounter;

  Result := Pointer(Integer(LMappedRecord) + GAP_SIZE);
end;

procedure InitializeArray;
var
  I: Integer;
begin
  for I := 0 to SIZE_OF_MAP do
    RfMapOfBufferAllocation[I] := 0;
end;
{$ENDREGION}


procedure ApplyMemoryManager;
var
  LMemoryManager: TMemoryManagerEx;
begin
  GetMemoryManager(LMemoryManager);
  SDefaultGetMem := LMemoryManager.GetMem;
  SIsNamedBufferMapActive := False;
  {$IFNDEF BUFFER_COUNTER}
  Exit;
  {$ENDIF}
  SIsNamedBufferMapActive := True;
  LMemoryManager.GetMem := NGetMem;

  SDefaultFreeMem := LMemoryManager.FreeMem;
  LMemoryManager.FreeMem := NFreeMem;

  SDefaultReallocMem := LMemoryManager.ReallocMem;
  LMemoryManager.ReallocMem := NReallocMem;

  SDefaultAllocMem := LMemoryManager.AllocMem;
  LMemoryManager.AllocMem := NAllocMem;

  SetMemoryManager(LMemoryManager);
end;

destructor TRfClassController.Destroy;
begin
  {$IFDEF INSTANCES_TRACKER}
  AllocationMap.Free;
  AllocationMap := nil;
  {$ENDIF}
  inherited;
end;

{ MappedRecord }

{$IFDEF BUFFER_TRACKER}
procedure MappedRecord.DecAllocationMap;
begin
  MemoryBufferCounter(MemorySizeOfPos(SizeCounterAddr), PMappedRecord(@Self), -1);
end;
{$ENDIF}

procedure MappedRecord.DecMapSizeCounter;
begin
  SRCBufferCounter.Acquire;
  try
    Integer(Pointer(SizeCounterAddr)^) := Integer(Pointer(SizeCounterAddr)^) - 1;
  finally
    SRCBufferCounter.Release;
  end;
end;

{$IFDEF BUFFER_TRACKER}
procedure MappedRecord.IncAllocationMap;
begin
  MemoryBufferCounter(MemorySizeOfPos(SizeCounterAddr), PMappedRecord(@Self), +1);
end;
{$ENDIF}

procedure MappedRecord.IncMapSizeCounter;
begin
  SRCBufferCounter.Acquire;
  try
    Integer(Pointer(SizeCounterAddr)^) := Integer(Pointer(SizeCounterAddr)^) + 1;
  finally
    SRCBufferCounter.Release;
  end;
end;

procedure MappedRecord.SetParityByte;
begin
  Parity := PARITY_BYTE;
end;

function MappedRecord.Size: Integer;
begin
  Result := (Self.SizeCounterAddr - Integer(@RfMapOfBufferAllocation)) div SIZE_OF_INT;
end;

procedure MappedRecord.ClearParityByte;
begin
  Parity := 0;
end;

procedure InitializeRfMemoryProfiler;
begin
  if RfIsMemoryProfilerActive then
    Exit;

  RfIsMemoryProfilerActive := True;

  SRCBufferCounter := TCriticalSection.Create;
  GetCodeOffset;

  SIsObjectAllocantionTraceOn := False;
  {$IFDEF INSTANCES_TRACKER}
  SIsObjectAllocantionTraceOn := True;
  {$ENDIF}

  SIsBufferAllocationTraceOn := False;
  {$IFDEF BUFFER_TRACKER}
  SIsBufferAllocationTraceOn := True;
  {$ENDIF}

  {$IFDEF INSTANCES_COUNTER}
  SListClassVars := TList.Create;
  {$ENDIF}

  {$IFDEF BUFFER_COUNTER}
  InitializeArray;
  {$ENDIF}

  ApplyMemoryManager;
  ///  Buffer wrapper
  {$IFDEF BUFFER_COUNTER}
    {$IFNDEF INSTANCES_COUNTER}
    AddressPatch(GetMethodAddress(@OldNewInstance), @TObjectHack.NNewInstance);
    {$ENDIF}
  {$ENDIF}

  ///Class wrapper
  {$IFDEF INSTANCES_COUNTER}
  AddressPatch(GetMethodAddress(@OldNewInstance), @TRfObjectHack.NNewInstanceTrace);
  {$ENDIF}
end;

initialization
  RfIsMemoryProfilerActive := False;
  {$IFNDEF UNITTEST}
  InitializeRfMemoryProfiler;
  {$ENDIF}

end.
