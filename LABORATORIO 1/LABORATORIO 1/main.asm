/*
* Prelab01-Sumador
*
* Creado: 01/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Es el primer prelab del curso, en este se tiene que tener dos botones uno para decremento
 y otro para incremento, estos accionaran unas salidas (leds) que encenderan y/o apagaran en numeros binarios,
 xson dos fases o dos numeros de 4 bits; estos despues se sumaran y se interpretaran
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
// Input -> PB4, PB5, PC5

CBI DDRB, DDB4 // Poniendo en 0, el bit 4 de DDRB -> Input
CBI DDRB, DDB5 // Poniendo en 0, el bit 5 de DDRB -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Input
CBI DDRD, DDD7 // Poniendo en 0, el bit 2 de DDRC -> Input
CBI DDRD, DDD6 // Poniendo en 0, el bit 3 de DDRC -> Input

SBI PORTB, PORTB4 // Habilitando pull-up para PB4
SBI PORTB, PORTB5 // Habilitando pull-up para PB5
SBI PORTC, PORTC5 // Habilitando pull-up para PC5
SBI PORTD, PORTD7 // Habilitando pull-up para PD6
SBI PORTD, PORTD6 // Habilitando pull-up para PD7


// Output -> PD5, PD4, PD3, PD2; PB0, PB1, PB2, PB3; PC0, PC1, PC2, PC3, PC4
SBI DDRD, DDD2 // Poniendo en 1, el bit 2 de DDRD -> Output
SBI DDRD, DDD3 // Poniendo en 1, el bit 3 de DDRD -> Output
SBI DDRD, DDD4 // Poniendo en 1, el bit 4 de DDRD -> Output
SBI DDRD, DDD5 // Poniendo en 1, el bit 6 de DDRD -> Output

SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
SBI DDRB, DDB1 // Poniendo en 1, el bit 1 de DDRB -> Output
SBI DDRB, DDB2 // Poniendo en 1, el bit 2 de DDRB -> Output
SBI DDRB, DDB3 // Poniendo en 1, el bit 3 de DDRB -> Output

SBI DDRC, DDC0 // Poniendo en 1, el bit 0 de DDRC -> Output
SBI DDRC, DDC1 // Poniendo en 1, el bit 1 de DDRC -> Output
SBI DDRC, DDC2 // Poniendo en 1, el bit 2 de DDRC -> Output
SBI DDRC, DDC3 // Poniendo en 1, el bit 3 de DDRC -> Output
SBI DDRC, DDC4 // Poniendo en 1, el bit 4 de DDRC -> Output

// Puerto D -> PD5, PD4, PD3, PD2
CBI PORTD, PORTD5   // Inicialmente apagado el PD4
CBI PORTD, PORTD4   // Inicialmente apagado el PD5
CBI PORTD, PORTD3   // Inicialmente apagado el PD6
CBI PORTD, PORTD2   // Inicialmente apagado el PD7

// Puerto B -> PB0, PB1, PB2, PB3
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3

// Puerto C -> PC0, PC1, PC2, PC3, PC4
CBI PORTC, PORTC0   // Inicialmente apagado el PC0
CBI PORTC, PORTC1   // Inicialmente apagado el PC1
CBI PORTC, PORTC2   // Inicialmente apagado el PC2
CBI PORTC, PORTC3   // Inicialmente apagado el PC3
CBI PORTC, PORTC4   // Inicialmente apagado el PC4 (CARRY-BORROW)


IN R16, PIND
IN R17, PORTD
ANDI R17, 0b11000011
IN R18, PINB
IN R19, PORTB
ANDI R19, 0b11110000
IN R20, PINC
IN R21, PORTC
ANDI R21, 0b11100000
CLR R23
CLR R25
CLR R27

/****************************************/
// Loop Infinito
MAIN_LOOP:
	IN R22, PIND
	CP R22, R16
	BRNE btB
	CALL DELAY
	IN R22, PIND
	CP R22, R16
	BRNE btB
	CALL CONTADOR1

	btB:
	IN R24, PINB
	CP R24, R18
	BRNE btC
	CALL DELAY
	IN R24, PINB
	CP R24, R18
	BRNE btC
	CALL CONTADOR2

	btC:
	IN R26, PINC
	CP R26, R20
	BRNE FIN
	CALL DELAY
	IN R26, PINC
	CP R26, R20
	BRNE FIN
	CALL SUMAR

	FIN:
	RJMP MAIN_LOOP
		

	
/****************************************/
// NON-Interrupt subroutines	

CONTADOR1:
	ANDI R22, 0x40
	BREQ resta1
	LSR R23
	LSR R23
	CPI R23, 0b00001111
	BREQ REGRESAR1
	INC R23
	LSL R23
	LSL R23
	OR R17, R23
	MOV R16, R17
	OUT PORTD, R16
	RJMP REGRESAR1

	resta1:
	LSR R23
	LSR R23
	CPI R23, 0b00000000
	BREQ REGRESAR1
	DEC R23
	LSL R23
	LSL R23
	OR R17, R23
	MOV R16, R17
	OUT PORTD, R16
	
	REGRESAR1:
	RET

CONTADOR2:
	ANDI R24, 0b0001000
	BRNE resta2
	CPI R25, 0b00001111
	BREQ REGRESAR2
	INC R25
	OR R19, R25
	MOV R18, R19
	OUT PORTB, R18
	RJMP REGRESAR2

	resta2:
	CPI R25, 0b00000000
	BREQ REGRESAR2
	DEC R25
	OR R19, R25
	MOV R18, R19
	OUT PORTB, R18

	REGRESAR2:
	RET

SUMAR:
	MOV R27, R23
	LSR R27
	LSR R27
	ADD R27, R25
	CPI R27, 0b00001111
	BRSH carry
	CBI PORTC, PORTC4
	OR R21,R27
	MOV R20, R21
	OUT PORTC, R20
	RJMP REGRESAR3
	carry:
	SBI PORTC, PORTC4
	ANDI R27, 0b00001111
	OR R21,R27
	MOV R20, R21
	OUT PORTC, R20

	REGRESAR3:
	RET

DELAY:
    LDI  R29, 10
L1:
    LDI  R30, 200
L2:
    LDI  R31, 200
L3:
    DEC  R31
    BRNE L3
    DEC  R30
    BRNE L2
    DEC  R29
    BRNE L1
    RET
             // 4 ciclos



/****************************************/
// Interrupt routines
/****************************************/
