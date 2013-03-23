unit uUnitTestHeader;

interface

const
  AMOUNT_OF_ALLOCATIONS = 2000;
  PERFOMANCE_AMOUNT_OF_ALLOCATIONS = AMOUNT_OF_ALLOCATIONS * 100;
  BUFFER_TEST_SIZE = 777;
  SIZE_OF_WORD = SizeOf(Integer);

type
  Address = integer;

  procedure InitilializeArrays;
  function IsSameValuesInAllocationAndDeallocationArray: Boolean;
  procedure SetAllocationAddress(APointer: Pointer);
  procedure SetDeallocationAddress(APointer: Pointer);

implementation

type
  ArrayOfAddress = array [0..AMOUNT_OF_ALLOCATIONS] of Address;

var
  UAllocation_Addresses: ArrayOfAddress;
  UDeallocation_Addresses: ArrayOfAddress;

  UCurrentAllocationArrayPos: Integer;
  UCurrentDeallocationArrayPos: Integer;

procedure InitilializeArrays;
begin
  UCurrentAllocationArrayPos := 0;
  UCurrentDeallocationArrayPos := 0;
end;

function IsSameValuesInArray(AArray1, AArray2: ArrayOfAddress): Boolean;
var
  I: Integer;
begin
  for I := 0 to AMOUNT_OF_ALLOCATIONS - 1 do
  begin
    Result := AArray1[I] = AArray2[I];
    if not Result then
      Exit;
  end;
end;

function IsSameValuesInAllocationAndDeallocationArray: Boolean;
begin
  Result := IsSameValuesInArray(UAllocation_Addresses, UDeallocation_Addresses);
end;

procedure SetAllocationAddress(APointer: Pointer);
begin
  UAllocation_Addresses[UCurrentAllocationArrayPos] := Integer(APointer);
  Inc(UCurrentAllocationArrayPos);
end;

procedure SetDeallocationAddress(APointer: Pointer);
begin
  UDeallocation_Addresses[UCurrentDeallocationArrayPos] := Integer(APointer);
  Inc(UCurrentDeallocationArrayPos);
end;

end.
