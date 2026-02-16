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
	RJMP RESET

 .org OVF0addr
	RJMP TIMER0_OVF:



/****************************************/


// Configuracion de la pila
LDI R16, LOW(RAMEND)
OUT SPL, R16
LDI R16, HIGH(RAMEND)
OUT SPH, R16
/****************************************/

disp7seg: .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78, 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E
// Configuracion MCU
SETUP:
// Configurar entradas y salidas

//Habilitar cambio del prescaler (ventana de 4 ciclos)
LDI R16, (1<<CLKPCE)
STS CLKPR, R16

//Configurar división entre 8
LDI R16, 0b00000011    ; CLKPS = 0011 ? divide entre 8
STS CLKPR, R16

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
		//	- Fclk=2000000 Hz
		//	- PreScaler=1024
		//	- Overflow==0.09984 s

//Configuracion del TIMER0
LDI R16, 0x00
OUT TCCR0A, R16			//Modo normal (cuenta de 0 a 255).

LDI R16, 0b00000101		//prescaler de 1024
OUT TCCR0B, R16

LDI R16, 59			//el contador empieza en 59
OUT TCNT0, R16

LDI R16, 0b0000001		//Habilitar interrupciones del timer0
STS TIMSK0, R16

SEI
//
//PARA USAR EL PORTD COMPLETO (DESACTIVAR RX Y TX
LDI R18, 0x00
STS UCSR0B, R18

CLR R18




/****************************************/
// Loop Infinito

MAIN_LOOP:
    RJMP MAIN_LOOP

CONTAR1up:
	IN R18, PORTB				//Guardar lo que haya en el PORTB
	ANDI R18, 0b11110000		//Guardar solo los 4 mas significativos
	CPI R19, 0b00001111			//comparar si r19 ya es 15
	BRSH regresar1				// si es 15, regresar a 0
	INC R19						// si no era 15, le sumamos 1 al registro
	OR R18, R19					// fusionamos los 4 mas significativos de R18 y los 4 menos significativos del r19
	OUT PORTB, R18				//presentamos la fusion en PORTB
	RJMP REGRESAR
	regresar1:				
	ANDI R19, 0b00000000
	OR R18, R19					// fusionamos los 4 mas significativos de R18 y los 4 menos significativos del r19
	OUT PORTB, R18				//presentamos la fusion en PORTB
	REGRESAR:
	RET							// se termina la funcion

///****************************************/
//// Interrupt routines
///****************************************/
TIMER0_OVF:
	PUSH R16
	IN R16, SREG
	PUSH R16
    PUSH R17

	//recargamos para volver a contar 100ms
	LDI R16, 61
	OUT TCNT0, R16

	//CONTAMOS 1S
	INC R17
	CPI R17, 10		//Ya es 10?
	BRNE SALIR		// nop, entonces salir
	//si es, modificamos los registros 
	CLR R17			// limpiamos la cuenta
	INC R18
	ANDI R18, 0b00001111
	OUT PORTB, R18

	SALIR:
	POP R17
	POP R16
	OUT SREG, R16
	POP R16
	RETI