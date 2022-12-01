@ECHO OFF

set program="main.asm"

set avrboi="F:\Programs\AVRDude\avrdude.exe"
set avrboiargs=-c avr109 -p m32u4 -P usb:03EB:204B -U flash:w:
set port="usb:03EB:204B"

set atmel="..\..\..\..\..\..\..\Programs\Microchip Studio\7.0\AtmelStudio.exe"

set build="debug"
set project="Lab7.asmproj"
set hex="./Debug/Lab7.hex"


%atmel% %project% /build %build%
%avrboi% %avrboiargs%%hex%:i
