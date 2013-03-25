unit uRfAppDiagnosis;

interface

uses
  uRfMemoryDiagnosis;

type
  TRfAppDiagnosis = class
  private
    FApplicationVersion: string;
    FCategory: string;
    FClientKey: string;

    FRfMemoryDiagnosis: TRfMemoryDiagnosis;
  public
    constructor Create(AClientKey: string);
    destructor Destroy; override;

    procedure SetRfMemoryDiagnosis(ARfMemoryDiagnosis: TRfMemoryDiagnosis);

    property ApplicationVersion: string read FApplicationVersion write FApplicationVersion;
    property Category: string read FCategory write FCategory;
  end;

implementation

{ TRfAppDiagnosis }

constructor TRfAppDiagnosis.Create(AClientKey: string);
begin
  FClientKey := AClientKey;
end;

destructor TRfAppDiagnosis.Destroy;
begin

  inherited;
end;

procedure TRfAppDiagnosis.SetRfMemoryDiagnosis(ARfMemoryDiagnosis: TRfMemoryDiagnosis);
begin

end;

end.
