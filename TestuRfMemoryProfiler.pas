unit TestuRfMemoryProfiler;

interface

uses
  TestFramework, uRfMemoryProfiler, SyncObjs, Classes, Contnrs, uUnitTestHeader, Diagnostics, Windows;

type
  {$DEFINE BUFFER_TRACKER}
  {$DEFINE INSTANCES_TRACKER}

  {$Include RfMemoryProfilerOptions.inc}
  // Test methods for class TAllocationMap

  TObjectTest = class(TObject);

  TestRfMemoryProfiller = class(TTestCase)
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestObjectCounter;
    {$IFDEF INSTANCES_TRACKER}
    procedure TestTraceObjectAllocation;
    {$ENDIF}

  end;

  TestBufferAllocation = class(TTestCase)
  private
    FBufferList: TList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  public
    procedure TestBufferAllocMemCounter;
    procedure TestBufferFreeMemToAllocMemCounter;
    procedure TestBufferPointerAddrToAllocFree;

    procedure TestBufferGetMemCounter;
    procedure TestBufferFreeMemToGetMemCounter;
    procedure TestBufferPointerAddrToGetFree;

    procedure TestBufferReallocMemCounter;
  published
    procedure TestCheckPerfomance;

    procedure TestBasicFunctionsAllocFree;
    procedure TestBasicFunctionsGetMemFree;
    procedure TestRealloc;
    {$IFDEF BUFFER_TRACKER}
    procedure TestTracker;
    {$ENDIF}
  end;

implementation

uses
  SysUtils;

var
  UGetModuleHandle: Cardinal;

const
  CODE_SECTION = $1000;

procedure GetCodeOffset;
var
  LMapFile: string;
begin
  LMapFile := GetModuleName(hInstance);
  UGetModuleHandle := GetModuleHandle(Pointer(ExtractFileName(LMapFile))) + CODE_SECTION;
end;

procedure TestRfMemoryProfiller.SetUp;
begin
  InitializeRfMemoryProfiler;
end;

procedure TestRfMemoryProfiller.TearDown;
begin
end;

procedure TestRfMemoryProfiller.TestObjectCounter;
var
  LObjectList: TObjectList;
  I: Integer;
  LList: TList;
  LClassVars: TRfClassController;
  LFound: Boolean;
begin
  LObjectList := TObjectList.Create;
  for I := 0 to AMOUNT_OF_ALLOCATIONS -1 do
    LObjectList.Add(TObjectTest.Create);

  LFound := False;
  LList := RfGetInstanceList;
  for I := 0 to LList.Count -1 do
    if TRfClassController(LList.Items[I]).BaseClassName = 'TObjectTest' then
    begin
      CheckTrue(TRfClassController(LList.Items[I]).BaseInstanceCount = AMOUNT_OF_ALLOCATIONS, 'The object counter is not working as it should. The value in counter is different from the excepted.');
      LFound := True;
      Break;
    end;

  CheckTrue(LFound, 'The object registration is not working');
  LObjectList.Free;
end;

{$IFDEF INSTANCES_TRACKER}
procedure TestRfMemoryProfiller.TestTraceObjectAllocation;
var
  LStack: Integer;
  LObjectTest: TRfObjectHack;
  LAllocationMap: TAllocationMap;
  I: Integer;
  LObjectList: TObjectList;
  II: Integer;
begin
  {Get the addr of this procedure}
  asm
    mov LStack, ebp
  end;
  LStack := PInteger(Integer(LStack) + 4)^;
  Dec(LStack, UGetModuleHandle);

  for II := 0 to 50 do
  begin
    LObjectList := TObjectList.Create;
    for I := 0 to AMOUNT_OF_ALLOCATIONS -1 do
    begin
      LObjectTest := TRfObjectHack(TPersistent.Create);
      LAllocationMap := LObjectTest.GetRfClassController.AllocationMap;

      LObjectList.Add(LObjectTest);
      CheckTrue(LObjectTest.AllocationAddress = LStack, 'Allocation address do not correspond to actual caller.');
      CheckTrue(LAllocationMap.GetAllocationCounterByCallerAddr(LStack).NumAllocations = LObjectList.Count, 'Object allocation counter is not working.');
    end;
    LObjectList.Free;
  end;
  CheckTrue(LAllocationMap.GetAllocationCounterByCallerAddr(LStack).NumAllocations = 0, 'Object deallocation counter is not working.');
end;
{$ENDIF}

{ TestBufferAllocation }

procedure TestBufferAllocation.SetUp;
begin
  InitializeRfMemoryProfiler;
  RfInitilializeAllocDeallocArrays;
  FBufferList := TList.Create;
end;

procedure TestBufferAllocation.TearDown;
begin
  FBufferList.Free;
end;

procedure TestBufferAllocation.TestBasicFunctionsAllocFree;
begin
  Status('Testing TestBufferAllocMemCounter');
  TestBufferAllocMemCounter;

  Status('Testing TestBufferFreeMemToAllocMemCounter');
  TestBufferFreeMemToAllocMemCounter;

  Status('Testing TestBufferPointerAddrToAllocFree');
  TestBufferPointerAddrToAllocFree;
end;

procedure TestBufferAllocation.TestBasicFunctionsGetMemFree;
begin
  Status('Testing TestBufferGetMemCounter');
  TestBufferGetMemCounter;

  Status('Testing TestBufferFreeMemToGetMemCounter');
  TestBufferFreeMemToGetMemCounter;

  Status('Testing TestBufferPointerAddrToGetFree');
  TestBufferPointerAddrToGetFree;
end;

procedure TestBufferAllocation.TestBufferAllocMemCounter;
var
  I: Integer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
    FBufferList.Add(AllocMem(BUFFER_TEST_SIZE));
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = AMOUNT_OF_ALLOCATIONS, 'Wrong counter of buffer allocation for AllocMem.');

  CheckTrue(ComparePointerListToAllocationAddress(FBufferList), 'The comparision btw the addresses pointer of allocmem result are not correct.');
end;

procedure TestBufferAllocation.TestBufferFreeMemToAllocMemCounter;
var
  I: Integer;
  LPointer: Pointer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
  begin
    LPointer := FBufferList.Items[I];
    Dispose(LPointer);
  end;
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong count of buffer deallocation to AllocMem.');
end;

procedure TestBufferAllocation.TestBufferFreeMemToGetMemCounter;
var
  I: Integer;
  LPointer: Pointer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
  begin
    LPointer := FBufferList.Items[I];
    Dispose(LPointer);
  end;
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong count of buffer deallocation GetMem.');
end;

procedure TestBufferAllocation.TestBufferGetMemCounter;
var
  I: Integer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
    FBufferList.Add(GetMemory(BUFFER_TEST_SIZE));
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = AMOUNT_OF_ALLOCATIONS, 'Wrong counter of buffer allocation GetMem.');

  CheckTrue(ComparePointerListToAllocationAddress(FBufferList), 'The comparision btw the addresses pointer of GetMem result are not correct.');
end;

procedure TestBufferAllocation.TestBufferPointerAddrToAllocFree;
begin
  CheckTrue(IsSameValuesInAllocAndDeallocArray, 'Wrong allocation and deallocations address to AllocMem and FreeMem.');
end;

procedure TestBufferAllocation.TestBufferPointerAddrToGetFree;
begin
  CheckTrue(IsSameValuesInAllocAndDeallocArray, 'Wrong allocation and deallocations address GetMem and FreeMem.');
end;

procedure TestBufferAllocation.TestBufferReallocMemCounter;
var
  I: Integer;
  LPointer: Pointer;
begin
  for I := 0 to FBufferList.Count -1 do
  begin
    LPointer := FBufferList.Items[I];
    ReallocMem(LPointer, BUFFER_TEST_REALOC_SIZE);
    FBufferList.Items[I] := LPointer;
  end;

  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong counter of buffer on base pointer on reallocation.');
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_REALOC_SIZE] = AMOUNT_OF_ALLOCATIONS, 'Wrong counter of buffer on new pointer on reallocation.');

  for I := 0 to FBufferList.Count -1 do
  begin
    LPointer := FBufferList.Items[I];
    FreeMem(LPointer);
  end;

  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_REALOC_SIZE] = 0, 'Wrong counter of buffer on new pointer on deallocation.');
end;

procedure TestBufferAllocation.TestCheckPerfomance;
const
  LOOP_AMOUNT = 200;
var
  LStopWatcher: TStopwatch;
  I: Integer;
  LDefaultAllocMemTime: Int64;
  LDefaultFreeMemTime: Int64;
  LNewAllocMemTime: Int64;
  LNewFreeMemTime: Int64;
  LPointer: Pointer;
  II: Integer;
  LDeltaAllocMem: Extended;
  LDeltaFreeMem: Extended;
begin
  LDefaultAllocMemTime := 0;
  LDefaultFreeMemTime := 0;
  LNewAllocMemTime := 0;
  LNewFreeMemTime := 0;
  //Old callers
  LStopWatcher := TStopwatch.Create;
  for II := 0 to LOOP_AMOUNT do
  begin
    LStopWatcher.Reset;
    LStopWatcher.Start;
    for I := 0 to PERFOMANCE_AMOUNT_OF_ALLOCATIONS do
      FBufferList.Add(SDefaultAllocMem(SIZE_OF_INT));
    LStopWatcher.Stop;

    LDefaultAllocMemTime := LStopWatcher.ElapsedMilliseconds + LDefaultAllocMemTime;

    LStopWatcher.Reset;
    LStopWatcher.Start;
    for I := 0 to PERFOMANCE_AMOUNT_OF_ALLOCATIONS do
    begin
      LPointer := FBufferList.Items[I];
      SDefaultFreeMem(LPointer);
    end;
    LStopWatcher.Stop;
    LDefaultFreeMemTime := LStopWatcher.ElapsedMilliseconds + LDefaultFreeMemTime;

    FBufferList.Clear;
    //New callers
    LStopWatcher.Reset;
    LStopWatcher.Start;
    for I := 0 to PERFOMANCE_AMOUNT_OF_ALLOCATIONS do
      FBufferList.Add(SDefaultAllocMem(SIZE_OF_INT));
    LStopWatcher.Stop;

    LNewAllocMemTime := LStopWatcher.ElapsedMilliseconds + LNewAllocMemTime;

    LStopWatcher.Reset;
    LStopWatcher.Start;
    for I := 0 to PERFOMANCE_AMOUNT_OF_ALLOCATIONS do
    begin
      LPointer := FBufferList.Items[I];
      FreeMem(LPointer);
    end;
    LStopWatcher.Stop;
    LNewFreeMemTime := LStopWatcher.ElapsedMilliseconds + LNewFreeMemTime;

    FBufferList.Clear;
  end;

  LDeltaAllocMem := (LDefaultAllocMemTime / LNewAllocMemTime);
  LDeltaFreeMem := (LDefaultFreeMemTime / LNewFreeMemTime);

  Status('------------------ Perfomance Test ------------------');
  Status(Format('Amount of items allocated/deallocated: %d', [LOOP_AMOUNT * PERFOMANCE_AMOUNT_OF_ALLOCATIONS]));

  Status('-- AllocMem: ');
  Status(Format('  Default: Spent %d ms', [LDefaultAllocMemTime]));
  Status(Format('  New: Spent %d ms', [LNewAllocMemTime]));
  Status(Format('  Speed delta: %2.2f %%',[(LDeltaAllocMem * 100) - 100]));

  Status('-- FreeMem: ');
  Status(Format('  Default: Spent %d ms', [LDefaultFreeMemTime]));
  Status(Format('  New: Spent %d ms', [LNewFreeMemTime]));
  Status(Format('  Speed delta: %2.2f %%',[(LDeltaFreeMem * 100) - 100]));

  CheckTrue(LDeltaAllocMem > 0.5, 'The new memory allocator is more than 50% slower the default method.');
  CheckTrue(LDeltaFreeMem > 0.5, 'The new free memory is more than 50% slower than the default methos');
end;

procedure TestBufferAllocation.TestRealloc;
begin
  TestBufferAllocMemCounter;
  TestBufferReallocMemCounter;
end;

procedure TestBufferAllocation.TestTracker;
var
  I: Integer;
  LStack: Cardinal;
  LPointer: Pointer;
  LMemoryItem: TMappedRecord;
begin
  {Get the addr of this procedure}
  asm
    mov LStack, ebp
  end;
  LStack := PInteger(Integer(LStack) + 4)^;
  Dec(LStack, UGetModuleHandle);

  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong buffer trace test initialization. The buffer counter allocation must start in 0.');
  CheckTrue(GetAmountOfBufferAllocations(LStack, BUFFER_TEST_SIZE) = 0, 'Wrong buffer trace test initialization. The buffer addr allocation counter allocation must start in 0.');

  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
    FBufferList.Add(GetMemory(BUFFER_TEST_SIZE));

  LMemoryItem := TMappedRecord(Pointer(Integer(FBufferList.Items[0]) - GAP_SIZE)^);
  CheckTrue(LMemoryItem.AllocationAddr = LStack, 'Wrong caller addr for buffer allocation');

  CheckTrue(GetAmountOfBufferAllocations(LStack, BUFFER_TEST_SIZE) = AMOUNT_OF_ALLOCATIONS, 'The number of buffer allocations for addr is wrong');

  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
  begin
    LPointer := FBufferList.Items[I];
    Dispose(LPointer);
  end;
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong count of buffer deallocation to AllocMem.');
  CheckTrue(GetAmountOfBufferAllocations(LStack, BUFFER_TEST_SIZE) = 0, 'The number of buffer deallocations for addr is wrong');
end;

initialization
  GetCodeOffset;
  RegisterTest(TestRfMemoryProfiller.Suite);
  RegisterTest(TestBufferAllocation.Suite);
end.

