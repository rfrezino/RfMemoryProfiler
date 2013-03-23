unit TestuRfMemoryProfiler;

interface

uses
  TestFramework, uRfMemoryProfiler, SyncObjs, Classes, Contnrs, uUnitTestHeader, Diagnostics;

type
  // Test methods for class TAllocationMap

  TObjectTest = class(TObject);

  TestRfMemoryProfiller = class(TTestCase)
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestObjectCounter;
  end;

  TestBufferAllocation = class(TTestCase)
  private
    FBufferList: TList;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  public
    procedure TestBufferAllocationCounter;
    procedure TestBufferDeallocationCounter;
    procedure TestBufferPointerAddr;
  published
    procedure TestCheckPerfomance;
    procedure TestBasicFunctions;
  end;

implementation

uses
  SysUtils;

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
  LClassVars: TClassVars;
  LFound: Boolean;
begin
  LObjectList := TObjectList.Create;
  for I := 0 to AMOUNT_OF_ALLOCATIONS -1 do
    LObjectList.Add(TObjectTest.Create);

  LFound := False;
  LList := RfGetInstanceList;
  for I := 0 to LList.Count -1 do
    if TClassVars(LList.Items[I]).BaseClassName = 'TObjectTest' then
    begin
      CheckTrue(TClassVars(LList.Items[I]).BaseInstanceCount = AMOUNT_OF_ALLOCATIONS, 'Não foi contado todos os itens.');
      LFound := True;
    end;

  CheckTrue(LFound, 'Não foi cadastrado corretamente o objeto TObjectTest');
  SaveMemoryProfileToFile;
  LObjectList.Free;
end;

{ TestBufferAllocation }

procedure TestBufferAllocation.SetUp;
begin
  InitializeRfMemoryProfiler;
  FBufferList := TList.Create;
end;

procedure TestBufferAllocation.TearDown;
begin
  FBufferList.Free;
end;

procedure TestBufferAllocation.TestBasicFunctions;
begin
  TestBufferAllocationCounter;
  TestBufferDeallocationCounter;
  TestBufferPointerAddr;
end;

procedure TestBufferAllocation.TestBufferAllocationCounter;
var
  I: Integer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
    FBufferList.Add(AllocMem(BUFFER_TEST_SIZE));
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = AMOUNT_OF_ALLOCATIONS, 'Wrong counter of buffer allocation.');
end;

procedure TestBufferAllocation.TestBufferDeallocationCounter;
var
  I: Integer;
  LPointer: Pointer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
  begin
    LPointer := FBufferList.Items[I];
    Dispose(LPointer);
  end;
  CheckTrue(RfMapOfBufferAllocation[BUFFER_TEST_SIZE] = 0, 'Wrong count of buffer deallocation.');
end;

procedure TestBufferAllocation.TestBufferPointerAddr;
begin
  CheckTrue(IsSameValuesInAllocationAndDeallocationArray, 'Wrong allocation and deallocations address.');
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
      FBufferList.Add(SDefaultAllocMem(SIZE_OF_WORD));
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
      FBufferList.Add(SDefaultAllocMem(SIZE_OF_WORD));
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

initialization
  RegisterTest(TestRfMemoryProfiller.Suite);
  RegisterTest(TestBufferAllocation.Suite);
end.

