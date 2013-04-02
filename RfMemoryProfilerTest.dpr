program RfMemoryProfilerTest;
{

  Add UNITTEST to your project directives.

}

{$IFDEF CONSOLE_TESTRUNNER}
{$APPTYPE CONSOLE}
{$ENDIF}

uses
  uRfMemoryProfiler in 'uRfMemoryProfiler.pas',
  Forms,
  SysUtils,
  TestFramework,
  GUITestRunner,
  TextTestRunner,
  TestuRfMemoryProfiler in 'TestuRfMemoryProfiler.pas',
  uUnitTestHeader in 'uUnitTestHeader.pas';

{$R *.RES}
begin
  Application.Initialize;

  try
    if IsConsole then
      with TextTestRunner.RunRegisteredTests do
        Free
    else
      GUITestRunner.RunRegisteredTests;
  except
    on E: exception do
      ShowException(Application, E);
  end;
end.

