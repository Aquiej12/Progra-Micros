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
CBI DDRC, DDC3 // Poniendo en 0, el bit 5 de DDRC -> Input

SBI PORTC, PORTC4 // Habilitando pull-up para PC4
SBI PORTC, PORTC3 // Habilitando pull-up para PC5

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



//PARA USAR EL PORTD COMPLETO (DESACTIVAR RX Y TX
LDI R16, 0x00
STS UCSR0B, R16


//Limpiar registros a utilizar
CLR R17
CLR R18
CLR R16
CLR R20
CLR R21

disp7seg: .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x52, 0x02, 0x78, 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E

LDI ZH, HIGH(disp7seg<<1)
LDI ZL, LOW(disp7seg<<1)
/****************************************/
// Loop Infinito
MAIN_LOOP:
//Verificar que boton se presiono
// ---- PC4 (NO) ----
	LPM R20, Z
	OUT PORTD, R20
	SBIS PINC, PC4				//Evualuar si se preciono justamente ese boton
	RJMP VPC4
	SBIS PINC, PC5
	RJMP VPC5
	RJMP MAIN_LOOP
	VPC4:
	CALL DELAY					//ummm parece que si, esperemos a ver si si era
	SBIS PINC, PC4				// revicemos nuevamente							
	CALL CONTAR1up				// :O si era, bueno, ahorita aviso que hay que contar pa arriba
	RJMP MAIN_LOOP
	//Con los botones es basicamente lo mismo, se omite la explicacion
	VPC5:
	CALL DELAY
	SBIS PINC, PC5				// revicemos nuevamente							
	CALL CONTAR1dn
	RJMP MAIN_LOOP
	//contar para arriba del primer grupo de bits
CONTAR1up:

	CPI R18, 0b00001111			//comparar si r18 ya es 15
	BRSH regresar1				// si es 15, no habra incremento
	INC R18						// si no era 15, le sumamos 1 al registro
	ADIW ZL, 1
	
	RET
	regresar1:
	CLR R18
	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)			
	RET							// se termina la funcion

	//la logica es la misma que la anterior 
CONTAR1dn:
	TST R18
	BREQ ESCERO
	DEC R18
	SBIW ZL, 1
	RJMP REGRESAR2
	ESCERO: 
	LDI R18, 0b00001111
	LDI ZL, LOW((disp7seg<<1) + 15)
	LDI ZH, HIGH((disp7seg<<1) + 15)
	REGRESAR2:
	RET


//DELAY de toda la vida
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
