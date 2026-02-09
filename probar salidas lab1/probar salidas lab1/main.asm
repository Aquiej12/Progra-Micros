;
; probar salidas lab1.asm
;
; Created: 8/02/2026 13:50:55
; Author : abner
;


; Replace with your application code
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
// Input -> PB4, PB5, PC5
CBI DDRB, DDB4 // Poniendo en 0, el bit 4 de DDRB -> Input
CBI DDRB, DDB5 // Poniendo en 0, el bit 5 de DDRB -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Input
CBI DDRD, DDD2 // Poniendo en 0, el bit 2 de DDRC -> Input
CBI DDRD, DDD3 // Poniendo en 0, el bit 3 de DDRC -> Input

SBI PORTB, PORTB4 // Habilitando pull-up para PB4
SBI PORTB, PORTB5 // Habilitando pull-up para PB5
SBI PORTC, PORTC5 // Habilitando pull-up para PC5
SBI PORTD, PORTD2 // Habilitando pull-up para PD2
SBI PORTD, PORTD3 // Habilitando pull-up para PD3


// Output -> PD7, PD6, PD5, PD4; PB0, PB1, PB2, PB3; PC0, PC1, PC2, PC3, PC4
SBI DDRD, DDD4 // Poniendo en 1, el bit 4 de DDRD -> Output
SBI DDRD, DDD5 // Poniendo en 1, el bit 5 de DDRD -> Output
SBI DDRD, DDD6 // Poniendo en 1, el bit 6 de DDRD -> Output
SBI DDRD, DDD7 // Poniendo en 1, el bit 7 de DDRD -> Output

SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
SBI DDRB, DDB1 // Poniendo en 1, el bit 1 de DDRB -> Output
SBI DDRB, DDB2 // Poniendo en 1, el bit 2 de DDRB -> Output
SBI DDRB, DDB3 // Poniendo en 1, el bit 3 de DDRB -> Output

SBI DDRC, DDC0 // Poniendo en 1, el bit 0 de DDRC -> Output
SBI DDRC, DDC1 // Poniendo en 1, el bit 1 de DDRC -> Output
SBI DDRC, DDC2 // Poniendo en 1, el bit 2 de DDRC -> Output
SBI DDRC, DDC3 // Poniendo en 1, el bit 3 de DDRC -> Output
SBI DDRC, DDC4 // Poniendo en 1, el bit 4 de DDRC -> Output

// Puerto D -> PD4, PD5, PD6, PD7
SBI PORTD, PORTD4   // Inicialmente apagado el PD4
SBI PORTD, PORTD5   // Inicialmente apagado el PD5
SBI PORTD, PORTD6   // Inicialmente apagado el PD6
SBI PORTD, PORTD7   // Inicialmente apagado el PD7

// Puerto B -> PB0, PB1, PB2, PB3
SBI PORTB, PORTB0   // Inicialmente apagado el PB0
SBI PORTB, PORTB1   // Inicialmente apagado el PB1
SBI PORTB, PORTB2   // Inicialmente apagado el PB2
SBI PORTB, PORTB3   // Inicialmente apagado el PB3

// Puerto C -> PC0, PC1, PC2, PC3, PC4
SBI PORTC, PORTC0   // Inicialmente apagado el PC0
SBI PORTC, PORTC1   // Inicialmente apagado el PC1
SBI PORTC, PORTC2   // Inicialmente apagado el PC2
SBI PORTC, PORTC3   // Inicialmente apagado el PC3
SBI PORTC, PORTC4   // Inicialmente apagado el PC4 (CARRY-BORROW)

start:
SBI PORTC, PORTC0   // Inicialmente apagado el PC0
SBI PORTC, PORTC1   // Inicialmente apagado el PC1
SBI PORTC, PORTC2   // Inicialmente apagado el PC2
SBI PORTC, PORTC3   // Inicialmente apagado el PC3
SBI PORTC, PORTC4   // Inicialmente apagado el PC4 (CARRY-BORROW)    
    rjmp start

