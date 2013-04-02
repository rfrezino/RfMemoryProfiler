unit uRfMemoryProfiler;

{Versão 0.2
  - Added: recurso para identificar quantidade de buffers e seus tamanhados alocados no sistema
  - Changed: Adicionado mais informações no relatório (SaveMemoryProfileToFile)
}

{Versão 0.1
  - Added: recurso para contar quantidade de objetos no sistema.
  - Added: Possibilidade de gerar relatório (SaveMemoryProfileToFile)
}

{
- Funcionalidade: Esse recurso foi desenvolvido para para monitorar objetos e buffers alocados em sua aplicação. A intenção com
  a visibilidade dessa informação é o auxilio para encontrar enventuais leaks de memória da maneira menos intrusiva possível em
  tempo real, de forma que a mesma possa estar disponível em versões release sem comprometer a velocidade do sistema.

- Como instalar: Adicione essa unit no projeto e adicione como a primeira uses do sistema (Project - View Source - uses). Se você
 utiliza algum gerenciador de memória de terceiro, coloque o uses do uRfMemoryProfiler logo após a uses deste.

- Como obter o relatório: O visualizardor não ainda não foi desenvolvido, por hora, é possível solicitar a informação de relatório
 através do comando SaveMemoryProfileToFile. Um arquivo de texto chamado RfMemoryReport será criado no caminho do executável.

 ***** PERIGO: Se você usa o espaço da VMT destinado ao vmtAutoTable, não é possível utilizar os recursos dessa unit *****

 Desenvolvido por Rodrigo Farias Rezino
 E-mail: rodrigofrezino@gmail.com
 Stackoverflow: http://stackoverflow.com/users/225010/saci
 Qualquer bug, por favor me informar.
}

{
- Functionality: The feature developed in this unit to watch how the memory are being allocated by your system. The main
    focus of it is help to find memory leak in the most non intrusive way on a real time mode.

- How to Install: Put this unit as the first unit of yout project. If use use a third memory manager put this unit just after the
    unit of your memory manager.

- How to get it's report: It's not the final version of this unit, so the viewer was not developed. By the moment you can call
  the method SaveMemoryProfileToFile. It'll create a text file called RfMemoryReport in the executable path.

 ***** WARNING: If you use the space of the VMT destinated to vmtAutoTable, you should not use the directive TRACEINSTANCES *****

How it works:
The feature work in two different approaches:
1) Map the memory usage by objects
2) Map the memory usage by buffers (Records, strings and so on)
3) Map the memory usage by objects / Identify the method that called the object creation
4) Map the memory usage by buffers (Records, strings and so on) / Identify the method that called the buffer allocation

How are Objects tracked ?
  The TObject.NewInstance was replaced by a new method (TObjectHack.NNewInstanceTrace).
  So when the creation of an object is called it's redirect to the new method. In this new method is increased the counter of the relative class and change the method in the VMT that is responsible to free the object to a new destructor method (vmtFreeInstance). This new destructor call the decrease of the counter and the old destructor.
  This way I can know how much of objects of each class are alive in the system.

  (More details about how it deep work can be found in the comments on the code)

How are Memory Buffer tracked ?
  The GetMem, FreeMem, ReallocMem, AllocMem were replaced by new method that have an special behavior to help track the buffers.

   As the memory allocation use the same method to every kind of memory request, I'm not able to create a single counter to each count of buffer. So, I calculate them base on it size. First I create a array of integer that start on 0 and goes to 65365.
  When the system ask me to give it a buffer of 65 bytes, I increase the position 65 of the array and the buffer is deallocated I call the decrease of the position of the array corresponding to buffer size. If the size requested to the buffer is bigger or equal to 65365, I'll use the position 65365 of the array.

  (More details about how it deep work can be found in the comments on the code)

Develop by  Rodrigo Farias Rezino
    E-mail: rodrigofrezino@gmail.com
    Stackoverflow: http://stackoverflow.com/users/225010/saci
     Please, any bug let me know
}

interface
{$DEFINE TRACEINSTANCES}            {Directive used to track objects allocation}
{$DEFINE TRACEBUFFER}               {Directive used to track buffer}

{$DEFINE TRACEINSTACESALLOCATION} {Must have the TRACEINSTANCES directive ON to work}

//This itens above are not all tested
{$IFDEF NONCONCLUDEDITEMS}
  {$DEFINE TRACEBUFFERALLOCATION}     {Must have the TRACEBUFFERALLOCATION directive ON to work}
{$ENDIF}

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

  PMemoryAddress = ^TMemoryAddress;
  TMemoryAddress = record
    MemAddress: Integer;
    NumAllocations: Integer;
  end;

  TCriticalSectionIgnore = class(TCriticalSection);

  TAllocationMap = class
  strict private
    FCriticalSection: TCriticalSectionIgnore;
    FItems: array of TMemoryAddress;

    function BinarySearch(const LMemoryAddress: Cardinal): Integer;
    function FindOrAdd(const LMemoryAddress: Integer): Integer;

    procedure QuickSortInternal(ALow, AHigh: Integer);
    procedure QuickSort;
  private
    function GetItems(Index: Integer): TMemoryAddress;
  public
    constructor Create;
    destructor Destroy; override;

    procedure IncCounter(LMemoryAddress: Integer);
    procedure DecCounter(LMemoryAddress: Integer);

    function GetAllocationCounterByCallerAddr(ACallerAddr: Cardinal): TMemoryAddress;

    function Count: Integer;

    property Items[Index: Integer]: TMemoryAddress read GetItems;
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
    class procedure SetRfClassController(AClassVars: TRfClassController); //inline;

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

    {$IFDEF TRACEINSTACESALLOCATION}
    property AllocationAddress: Integer read GetAllocationAddress write SetAllocationAddress;
    {$ENDIF}
  end;

  procedure RegisterClassVarsSupport(const Classes: array of TRfObjectHack);

var
  RfMapOfBufferAllocation: TArrayOfMap;
  RfIsMemoryProfilerActive: Boolean;

implementation

uses
   Windows, SysUtils, TypInfo;

const
  SIZE_OF_INT = SizeOf(Integer);
  PARITY_BYTE = 7777777;
  GAP_SIZE = SizeOf(PARITY_BYTE) + SIZE_OF_INT {$IFDEF TRACEBUFFERALLOCATION} + SIZE_OF_INT {$ENDIF};
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

    {$IFDEF TRACEBUFFERALLOCATION}
    AllocationAddr: Integer;
    {$ENDIF}

    procedure SetParityByte; inline;
    procedure IncMapSizeCounter; inline;
    {$IFDEF TRACEBUFFERALLOCATION}
    procedure IncAllocationMap; inline;
    {$ENDIF}

    procedure ClearParityByte; inline;
    procedure DecMapSizeCounter; inline;

    function Size: Integer; inline;
    {$IFDEF TRACEBUFFERALLOCATION}
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
    {$IFDEF TRACEINSTANCES}
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

    {$IFDEF TRACEBUFFER}
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

procedure RegisterClassVarsSupport(const Classes: array of TRfObjectHack);
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
  {$IFDEF TRACEINSTACESALLOCATION}
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

class procedure TRfObjectHack.SetRfClassController(AClassVars: TRfClassController);
begin
  AClassVars.BaseClassName := Self.ClassName;
  AClassVars.BaseInstanceSize := Self.InstanceSize;
  AClassVars.OldVMTFreeInstance := PPointer(Integer(TClass(Self)) + vmtFreeInstance)^;

  if Self.ClassParent <> nil then
    AClassVars.BaseParentClassName := Self.ClassParent.ClassName;

  PatchCodeDWORD(PDWORD(Integer(Self) + vmtAutoTable), DWORD(AClassVars));
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
  try
    Result := InitInstance(SDefaultGetMem(Self.InstanceSize {$IFDEF TRACEINSTACESALLOCATION} + SIZE_OF_INT {$ENDIF}));
    if (Result.ClassType = TRfClassController)
        or (Result.ClassType = TAllocationMap)
        or (Result.ClassType = TMemoryAddressBuffer)
        or (Result.ClassType = TCriticalSectionIgnore) or (Result is EExternal) then
      Exit;

    {$IFDEF TRACEINSTACESALLOCATION}
    TRfObjectHack(Result).AllocationAddress := GetSectorIdentificator;
    {$ENDIF}
    TRfObjectHack(Result).IncCounter;
  except
    raise Exception.Create(Result.ClassName);
  end;
end;

procedure TRfObjectHack.IncCounter;
begin
  if GetRfClassController = nil then
    RegisterClassVarsSupport(Self);

  GetRfClassController.BaseInstanceCount := GetRfClassController.BaseInstanceCount + 1;
  {$IFDEF TRACEINSTACESALLOCATION}
  GetRfClassController.AllocationMap.IncCounter(AllocationAddress);
  {$ENDIF}
end;

{ TClassVars }
constructor TRfClassController.Create;
begin
  SListClassVars.Add(Self);
  {$IFDEF TRACEINSTACESALLOCATION}
  AllocationMap := TAllocationMap.Create;
  {$ENDIF}
end;

{$ENDREGION}

{$REGION 'Buffer Control'}
{$REGION 'Description'}
//////////////////////////////////////////////////////////////////////////////////////
{
------  Memory Allocation Control
Objective: Count how much memory buffer with determined size is all allocated by the system, exemple:

Buffer Size | Amount of Allocs | Total Memory Used
----------------------------------------------------
	325		|		35265	   | 	11461125
	23 		|    32		   |     736
	...		|		...		   |	...


How I control the memory allocation and deallocation:

	I created an array of integer that goes from 0 to 65365. This array will be used to keep the amount of allocs of the corresponding size.
	For example, If I call GetMem for a buffer of 523, the Array[523] will increase + 1.

	The GetMem, ReallocMem, AllocMem, the problem is easy to resolve 'cause one of it's parameters is the size of the buffer. So I can use this to increase the position of the array.

	The problem cames with the FreeMem, 'cause the only parameter is the pointer of the buffer. I don't know it's size.
		- I can't create a list to keep the Pointer and it's size. 'Cause there is SO much allocations, it will be so much expensive to the application keep searching/adding/removing items from this list. And this list must to be protected with critical section etc etc. So no way.

	How I'm trying to solve this problem:
		Just to remeber I created the array to keep the number off allocations.

		Items:     0							                65365
		           |................................|
		Addess:   $X						      	$(65365x SizeOf(Integer))

		When allocators methos are called, for example: GetMem(52);
		I changed the behavior of it, I will alloc the requested size (52), but I'll add here a size of an integer;
		So I will have:

		$0 $3  $7  $11                  $64
		...|...|...|....................|

    In 0..3 bits =  filled with the parity value, used to know what was created or not by the buffer controller
    In 4..7 bits =  filled with the address of the corresponding space of the array.
    In 8..11 bits =  filled with the frame code address of the memory requester.


    In this case the address position $array(52).
                    And I add + (SizeOf(Integer)) to the address result of the GetMem, so it will have access just the 52 bytes that
                    were asked for.

		When the FreeMem are called. What I do is:
			- Get the pointer asked for deallocation.
			- Decrease the pointer by the size of the integer
			- Check if the address of the current pointer is relative to the Array of control address.
			- If it is, I use the the address and decrease 1 from the Array position
			- And ask for the FreeMem
}
{$ENDREGION}

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
    {$IFDEF TRACEBUFFERALLOCATION}
    SMapofBufferAddressAllocation[ABufSize].AllocationAddr := AInitialPointer.AllocationAddr;
    {$ENDIF}
    Exit;
  end;

  LLastMemoryBufferAddress := SMapofBufferAddressAllocation[ABufSize];
  LMemoryBufferAddress := LLastMemoryBufferAddress;

  while (LMemoryBufferAddress <> nil) do
  begin
    {$IFDEF TRACEBUFFERALLOCATION}
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
    {$IFDEF TRACEBUFFERALLOCATION}
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

  {$IFDEF TRACEBUFFERALLOCATION}
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

  {$IFDEF TRACEBUFFERALLOCATION}
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
    {$IFDEF TRACEBUFFERALLOCATION}
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
  {$IFNDEF TRACEBUFFER}
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
  {$IFDEF TRACEINSTACESALLOCATION}
  AllocationMap.Free;
  {$ENDIF}
  inherited;
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

function TAllocationMap.BinarySearch(const LMemoryAddress: Cardinal): Integer;
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
    if LMemoryAddress < LMedianValue then
      LMaxIndex := Pred(LMedianIndex)
    else if LMemoryAddress = LMedianValue then
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

procedure TAllocationMap.DecCounter(LMemoryAddress: Integer);
var
  LItem: PMemoryAddress;
begin
  LItem := @FItems[FindOrAdd(LMemoryAddress)];
  LItem.NumAllocations := LItem.NumAllocations - 1;
end;

destructor TAllocationMap.Destroy;
begin
  FCriticalSection.Free;
  inherited;
end;

function TAllocationMap.FindOrAdd(const LMemoryAddress: Integer): Integer;
begin
  Result := BinarySearch(LMemoryAddress);
  if Result = -1 then
  begin
    FCriticalSection.Acquire;
    SetLength(FItems, Length(FItems) + 1);
    FItems[Length(FItems) - 1].MemAddress := LMemoryAddress;
    FItems[Length(FItems) - 1].NumAllocations := 0;
    QuickSort;
    FCriticalSection.Release;
  end;
  Result := BinarySearch(LMemoryAddress);
end;

function TAllocationMap.GetAllocationCounterByCallerAddr(ACallerAddr: Cardinal): TMemoryAddress;
begin
  Result := Items[BinarySearch(ACallerAddr)];
end;

function TAllocationMap.GetItems(Index: Integer): TMemoryAddress;
begin
  Result := FItems[Index];
end;

procedure TAllocationMap.IncCounter(LMemoryAddress: Integer);
var
  LItem: PMemoryAddress;
begin
  LItem := @FItems[FindOrAdd(LMemoryAddress)];
  LItem.NumAllocations := LItem.NumAllocations + 1;
end;

{ MappedRecord }

{$IFDEF TRACEBUFFERALLOCATION}
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

{$IFDEF TRACEBUFFERALLOCATION}
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
  {$IFDEF TRACEINSTACESALLOCATION}
  SIsObjectAllocantionTraceOn := True;
  {$ENDIF}

  SIsBufferAllocationTraceOn := False;
  {$IFDEF TRACEBUFFERALLOCATION}
  SIsBufferAllocationTraceOn := True;
  {$ENDIF}

  {$IFDEF TRACEINSTANCES}
  SListClassVars := TList.Create;
  {$ENDIF}

  {$IFDEF TRACEBUFFER}
  InitializeArray;
  {$ENDIF}

  ApplyMemoryManager;
  ///  Buffer wrapper
  {$IFDEF TRACEBUFFER}
    {$IFNDEF TRACEINSTANCES}
    AddressPatch(GetMethodAddress(@OldNewInstance), @TObjectHack.NNewInstance);
    {$ENDIF}
  {$ENDIF}

  ///Class wrapper
  {$IFDEF TRACEINSTANCES}
  AddressPatch(GetMethodAddress(@OldNewInstance), @TRfObjectHack.NNewInstanceTrace);
  {$ENDIF}
end;

initialization
  RfIsMemoryProfilerActive := False;
  {$IFNDEF UNITTEST}
  InitializeRfMemoryProfiler;
  {$ENDIF}

end.
