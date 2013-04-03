unit uUnitTestHeader;

interface
  {$Include RfMemoryProfilerOptions.inc}

uses
  Classes;

const
  AMOUNT_OF_ALLOCATIONS = 2000;
  PERFOMANCE_AMOUNT_OF_ALLOCATIONS = AMOUNT_OF_ALLOCATIONS * 100;
  BUFFER_TEST_SIZE = 777;
  BUFFER_TEST_REALOC_SIZE = 787;

  SIZE_OF_INT = SizeOf(Integer);
  PARITY_BYTE = 7777777;
  GAP_SIZE = SizeOf(PARITY_BYTE) + SIZE_OF_INT {$IFDEF INSTANCES_TRACKER} + SIZE_OF_INT {$ENDIF};

type
  Address = integer;

  procedure RfInitilializeAllocDeallocArrays;
  function IsSameValuesInAllocAndDeallocArray: Boolean;
  procedure SetAllocationAddress(APointer: Pointer);
  procedure SetDeallocationAddress(APointer: Pointer);
  function ComparePointerListToAllocationAddress(AList: TList): Boolean;

implementation

type
  ArrayOfAddress = array [0..AMOUNT_OF_ALLOCATIONS] of Address;

var
  UAllocation_Addresses: ArrayOfAddress;
  UDeallocation_Addresses: ArrayOfAddress;

  UCurrentAllocationArrayPos: Integer;
  UCurrentDeallocationArrayPos: Integer;

procedure RfInitilializeAllocDeallocArrays;
begin
  UCurrentAllocationArrayPos := 0;
  UCurrentDeallocationArrayPos := 0;
end;

function ComparePointerListToAllocationAddress(AList: TList): Boolean;
var
  I: Integer;
  LPointer: Pointer;
begin
  for I := 0 to AList.Count -1 do
  begin
    LPointer := AList.Items[I];
    Result := Integer((Integer(LPointer) - GAP_SIZE))  = UAllocation_Addresses[I];
    if not Result then
      Exit;
  end;
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

function IsSameValuesInAllocAndDeallocArray: Boolean;
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
