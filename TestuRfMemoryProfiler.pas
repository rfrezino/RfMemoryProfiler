unit TestuRfMemoryProfiler;

interface

uses
  TestFramework, uRfMemoryProfiler, SyncObjs, Classes, Contnrs;

type
  // Test methods for class TAllocationMap

  TObjectTest = class(TObject);

  TestRfMemoryProfiller = class(TTestCase)
  const
    AMOUNT_ITEMS = 999;
  public
    procedure SetUp; override;
    procedure TearDown; override;
  published
    procedure TestObjectCounter;
    procedure TestBufferCounter;
  end;

implementation

procedure TestRfMemoryProfiller.SetUp;
begin
end;

procedure TestRfMemoryProfiller.TearDown;
begin
end;

procedure TestRfMemoryProfiller.TestBufferCounter;
const
  BUFFER_SIZE = 7777;
var
  LList: TList;
  I, II: Integer;
  LPointer: Pointer;
begin
  LList := TList.Create;

  for II := 0 to 9 do
  begin
    for I := 0 to AMOUNT_ITEMS -1 do
      LList.Add(AllocMem(BUFFER_SIZE));

     CheckTrue(RfMapOfBufferAllocation[BUFFER_SIZE] = AMOUNT_ITEMS, 'Quantidade de buffers esta errada');

     for I := LList.Count -1 downto 0 do
     begin
      LPointer := LList.Items[I];
      Dispose(LPointer);
     end;

     CheckTrue(RfMapOfBufferAllocation[BUFFER_SIZE] = 0, 'Quantidade de buffers esta errada');
     LList.Clear;
  end;
  LList.Free;
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
  for I := 0 to AMOUNT_ITEMS -1 do
    LObjectList.Add(TObjectTest.Create);

  LFound := False;
  LList := RfGetInstanceList;
  for I := 0 to LList.Count -1 do
    if TClassVars(LList.Items[I]).BaseClassName = 'TObjectTest' then
    begin
      CheckTrue(TClassVars(LList.Items[I]).BaseInstanceCount = AMOUNT_ITEMS, 'Não foi contado todos os itens.');
      LFound := True;
    end;

  CheckTrue(LFound, 'Não foi cadastrado corretamente o objeto TObjectTest');
  SaveMemoryProfileToFile;
  LObjectList.Free;
end;

initialization
  RegisterTest(TestRfMemoryProfiller.Suite);
end.

