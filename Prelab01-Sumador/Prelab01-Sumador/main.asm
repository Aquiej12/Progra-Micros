/*
* laboratorio1-Sumador
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
// Prescaler de CPU a /16
// 16 MHz / 16 = 1 MHz

LDI R16, (1<<CLKPCE)
STS CLKPR, R16

LDI R16, (1<<CLKPS2)    ; divisor /16
STS CLKPR, R16

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
CBI DDRC, DDC4 // Poniendo en 0, el bit 4 de DDRC -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Input
CBI DDRD, DDD7 // Poniendo en 0, el bit 2 de DDRC -> Input
CBI DDRD, DDD6 // Poniendo en 0, el bit 3 de DDRC -> Input

SBI PORTB, PORTB4 // Habilitando pull-up para PB4
SBI PORTC, PORTC4 // Habilitando pull-up para PC4
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
SBI DDRB, DDB5

SBI DDRC, DDC0 // Poniendo en 1, el bit 0 de DDRC -> Output
SBI DDRC, DDC1 // Poniendo en 1, el bit 1 de DDRC -> Output
SBI DDRC, DDC2 // Poniendo en 1, el bit 2 de DDRC -> Output
SBI DDRC, DDC3 // Poniendo en 1, el bit 3 de DDRC -> Output


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
CBI PORTB, PORTB5   // Inicialmente apagado el PB3


// Puerto C -> PC0, PC1, PC2, PC3, PC4
CBI PORTC, PORTC0   // Inicialmente apagado el PC0
CBI PORTC, PORTC1   // Inicialmente apagado el PC1
CBI PORTC, PORTC2   // Inicialmente apagado el PC2
CBI PORTC, PORTC3   // Inicialmente apagado el PC3


CLR R17
CLR R16
CLR R20
CLR R21

/****************************************/
// Loop Infinito
MAIN_LOOP:
// ---- PB4 (NO) ----
	IN   R16, PINB
	ANDI R16, 0b00010000
	BRNE VPB5
	CALL DELAY
	IN   R16, PINB
	ANDI R16, 0b00010000
	BRNE VPB5
	CALL CONTAR1up

	VPB5:
	; ---- PC4 (NO) ----
	IN   R16, PINC
	ANDI R16, 0b00010000
	BRNE VPC5
	CALL DELAY
	IN   R16, PINC
	ANDI R16, 0b00010000
	BRNE VPC5
	CALL CONTAR1dn

	VPC5:
	; ---- PC5 (NO) ----
	IN   R16, PINC
	ANDI R16, 0b00100000
	BRNE VPD6
	CALL DELAY
	IN   R16, PINC
	ANDI R16, 0b00100000
	BRNE VPD6
	CALL SUMAR

	VPD6:
	; ---- PD6 (NC) ----
	IN   R16, PIND
	ANDI R16, 0b01000000
	BREQ VPD7
	CALL DELAY
	IN   R16, PIND
	ANDI R16, 0b01000000
	BREQ VPD7
	CALL CONTAR2up

	VPD7:
	; ---- PD7 (NC) ----
	IN   R16, PIND
	ANDI R16, 0b10000000
	BREQ FIN_LECTURA
	CALL DELAY
	IN   R16, PIND
	ANDI R16, 0b10000000
	BREQ FIN_LECTURA
	CALL CONTAR2dn

	FIN_LECTURA:
	RJMP MAIN_LOOP



CONTAR1up:
	IN R18, PORTB
	ANDI R18, 0b11110000
	CPI R17, 0b00001111
	BRSH regresar1
	INC R17
	OR R18, R17
	OUT PORTB, R18
	regresar1: 
	RET

CONTAR1dn:
	IN R18, PORTB
	ANDI R18, 0b11110000
	TST R17
	BREQ regresar2
	DEC R17
	OR R18, R17
	OUT PORTB, R18

	regresar2: 
	RET

CONTAR2up:
	IN R19, PORTD
	ANDI R19, 0b11000011
	CPI R20, 0b00111100
	BRSH regresar3
	LSR R20
	LSR R20
	INC R20
	LSL R20
	LSL R20
	OR R19, R20
	OUT PORTD, R19

	regresar3: 
	RET

CONTAR2dn:
	IN R19, PORTD
	ANDI R19, 0b11000011
	LSR R20
	LSR R20
	TST R20
	BREQ regresar4
	DEC R20
	LSL R20
	LSL R20
	OR R19, R20
	OUT PORTD, R19
	regresar4: 
	RET

SUMAR:
	MOV R21, R17
	LSR R20
	LSR R20
	ADD R21, R20
	LSL R20
	LSL R20
	CPI R21, 0b00010000
	BRSH CARRY
	IN R22, PORTC
	ANDI R22, 0b11110000
	OR R22, R21
	OUT PORTC, R22
	CBI PORTB, PORTB5
	RJMP regresar5

	CARRY:
	IN R22, PORTC
	ANDI R22, 0b11110000
	ANDI R21, 0b00001111
	OR R22, R21
	OUT PORTC, R22
	SBI PORTB, PORTB5

	regresar5:
	RET

DELAY:
    LDI  R29, 255
L1:
    LDI  R30, 255
L2:
    DEC  R30
    BRNE L2
    DEC  R29
    BRNE L1
    RET
             // 4 ciclos



/****************************************/
// Interrupt routines
/****************************************/
