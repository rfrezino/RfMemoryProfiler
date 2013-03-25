unit uRfMemoryDiagnosis;

interface

uses
  uRfDiagnosis;

type
  TRfMemoryDiagnosis = class(TRfDiagnosis)
  private
    function GetApplicationMemoryUsage: Cardinal;
  public
    procedure Execute; override;
  end;

implementation

uses
  PsApi, Windows, SysUtils;

{ TRfMemoryDiagnosis }

procedure TRfMemoryDiagnosis.Execute;
begin
  inherited;

end;

function TRfMemoryDiagnosis.GetApplicationMemoryUsage: Cardinal;
var
   LProcessMemoryCounters: TProcessMemoryCounters;
begin
  LProcessMemoryCounters.cb := SizeOf(LProcessMemoryCounters) ;
  if GetProcessMemoryInfo(GetCurrentProcess, @LProcessMemoryCounters, SizeOf(LProcessMemoryCounters)) then
    Result := LProcessMemoryCounters.WorkingSetSize
  else
     RaiseLastOSError;
end;

end.
