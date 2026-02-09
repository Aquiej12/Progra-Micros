/*
* laboratorio1-Sumador
*
* Creado: 01/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Contador binario de 4 bits en el que cada incremento es realizado cada
100ms, utilizando el timer0.

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

CBI DDRC, DDC4 // Poniendo en 0, el bit 4 de DDRC -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Input

SBI PORTC, PORTC4 // Habilitando pull-up para PC4
SBI PORTC, PORTC5 // Habilitando pull-up para PC5

//CONFIGURAR PORTD COMO SALIDA

LDI R16, 0xFF
OUT DDRD, R16
LDI R16, 0x00
OUT PORTD, R16

//SALIDAS DE PORTB (PB0,PB1, PB2, PB3)
SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
SBI DDRB, DDB1 // Poniendo en 1, el bit 1 de DDRB -> Output
SBI DDRB, DDB2 // Poniendo en 1, el bit 2 de DDRB -> Output
SBI DDRB, DDB3 // Poniendo en 1, el bit 3 de DDRB -> Output
SBI DDRB, DDB5


// Puerto B -> PB0, PB1, PB2, PB3
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3
CBI PORTB, PORTB5   // Inicialmente apagado el PB3


//CALCULANDO EL PRESCALER.
	//CON:
		//	- TIMER0=8BITS
		//	- Fclk=16MHz
		//	- PreScaler=64
		//	- Overflow==1.024ms
		// --->100ms/1.024ms==97.6

//Configuracion del TIMER0
LDI R16, 0x00
OUT TCCR0A, R16

LDI R16, 0b00000011
OUT TCCR0B, R16

LDI R16, 0X00
OUT TCNT0, R16

LDI R16, 0b0000001
STS TIMSK0, R16

SEI

//Limpiar registros a utilizar
CLR R17
CLR R16
CLR R20
CLR R21

/****************************************/
// Loop Infinito

MAIN_LOOP:


//Verificar banderas del timer0
	IN R16, TIFR0			//Guardar banderas del Timer0
	SBRS R16, TOV0			//Comparar si hubo Overflow
	RJMP MAIN_LOOP			//si no, regresaral MAINLOOP

	SBI	TIFR0, TOV0			//Si hubo overflow, limpiamos la bandera
	LDI R16, 0
	OUT TCNT0, R16			//recargar timer0 (10ms)
	INC R17					// Contar que ya pasaron n(10ms)
	CPI R17, 98				// n ya es 10??
	BRNE MAIN_LOOP			// si no, volver al mainloop
	CLR R17					// si si es, se limpia el contador


	CALL CONTAR1up				// :O si era, bueno, ahorita aviso que hay que contar pa arriba
	RJMP MAIN_LOOP

CONTAR1up:
	IN R18, PORTB				//Guardar lo que haya en el PORTB
	ANDI R18, 0b11110000		//Guardar solo los 4 mas significativos
	CPI R19, 0b00001111			//comparar si r17 ya es 15
	BRSH regresar1				// si es 15, regresar a 0
	INC R19						// si no era 15, le sumamos 1 al registro
	OR R18, R19					// fusionamos los 4 mas significativos de R18 y los 4 menos significativos del r17
	OUT PORTB, R18				//presentamos la fusion en PORTB
	RJMP REGRESAR
	regresar1:				
	ANDI R19, 0b00000000
	OR R18, R19					// fusionamos los 4 mas significativos de R18 y los 4 menos significativos del r17
	OUT PORTB, R18				//presentamos la fusion en PORTB
	REGRESAR:
	RET							// se termina la funcion

/****************************************/
// Interrupt routines
/****************************************/
