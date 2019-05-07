@for /F "delims=" %%I in ("%~dp0") do @set root=%%~dI
@for /F "delims=" %%I in ("%~dp0") do @set folder=%%~fI

@set PATH=%root%\devel\flex_sdk_4.6\bin;%folder%\..\..\..\..\..\devel\flex_sdk_4.6\bin;%PATH%

mxmlc Connector.as -static-link-runtime-shared-libraries -o ../../../app/assets/other/connector.swf
pause