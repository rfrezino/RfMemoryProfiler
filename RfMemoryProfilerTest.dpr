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
  TestFramework,
  GUITestRunner,
  TextTestRunner,
  TestuRfMemoryProfiler in 'TestuRfMemoryProfiler.pas',
  uUnitTestHeader in 'uUnitTestHeader.pas';

{$R *.RES}

begin
  Application.Initialize;
  if IsConsole then
    with TextTestRunner.RunRegisteredTests do
      Free
  else
    GUITestRunner.RunRegisteredTests;
end.

