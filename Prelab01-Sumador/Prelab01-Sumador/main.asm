/*
* Prelab01-Sumador
*
* Creado: 01/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Es el primer prelab del curso, en este se tiene que tener dos botones uno para decremento y otro para incremento, estos accionaran unas
salidas (leds) que encenderan y/o apagaran en numeros binarios, son dos fases o dos numeros de 4 bits; estos despues se sumaran y se interpretaran
en otras 4 salidas de led.

*/
/****************************************/
// Encabezado (Definici n de Registros, Variables y Constantes)?
.include "M328PDEF.inc" // Include definitions specific to ATMega328P
.dseg
.org SRAM_START
//variable_name: .byte 1 // Memory alocation for variable_name: .byte (byte size)
.cseg
.org 0x0000
/****************************************/
// Configuracion de la pila
LDI R16, LOW(RAMEND)
OUT SPL, R16
LDI R16, HIGH(RAMEND)
OUT SPH, R16
/****************************************/
// Configuracion MCU
SETUP:
// Configurar entradas y salidas
// Input -> PD5
CBI DDRB, DDB4 // Poniendo en 0, el bit 4 de DDRB -> Input
CBI DDRB, DDB5 // Poniendo en 0, el bit 5 de DDRB -> Input

CBI PORTD, PORTD5 // Deshabilitando pull-up para PD5
// Output -> PB0
SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
CBI PORTB, PORTB0 // Initialmente apagado el PB0
CLR R16
CLR R17
CLR R18
CLR R19
IN R16, PIND
/****************************************/
// Loop Infinito
MAIN_LOOP:
IN R17, PIND // Leer PIND R17 = 0b11111111
CP R17, R16
BREQ MAIN_LOOP
CALL DELAY
IN R18, PIND
CP R18, R17
BRNE MAIN_LOOP
MOV R16, R17
ANDI R17, 0b00100000
BRNE MAIN_LOOP
SBI PINB, PINB0 // Toggle
RJMP MAIN_LOOP
/****************************************/
// NON-Interrupt subroutines
DELAY:
LDI R19, 255
LOOP_DELAY:
DEC R19
BRNE LOOP_DELAY
RET
/****************************************/
// Interrupt routines
/****************************************/
