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
// Input -> PB4, PB5, PC5
CBI DDRB, DDB4 // Poniendo en 0, el bit 4 de DDRB -> Input
CBI DDRB, DDB5 // Poniendo en 0, el bit 5 de DDRB -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Input

SBI PORTB, PORTB4 // Habilitando pull-up para PB4
SBI PORTB, PORTB5 // Habilitando pull-up para PB5
SBI PORTC, PORTC5 // Habilitando pull-up para PC5


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
CBI PORTD, PORTD4   // Inicialmente apagado el PD4
CBI PORTD, PORTD5   // Inicialmente apagado el PD5
CBI PORTD, PORTD6   // Inicialmente apagado el PD6
CBI PORTD, PORTD7   // Inicialmente apagado el PD7

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

CLR R16
CLR R17
CLR R18
CLR R19
IN R18, PINB    ; Guardar estado inicial de PORTB
IN R19, PIND    ; Guardar estado inicial de PORTD

/****************************************/
// Loop Infinito
MAIN_LOOP:
    // Primera lectura
    IN R20, PINB    ; Leer PORTB actual
    IN R21, PIND    ; Leer PORTD actual

    // Comparar con estado base
    CP R20, R18
    BRNE ANTIREBOTE
    CP R21, R19
    BRNE ANTIREBOTE

    RJMP MAIN_LOOP  // Sin cambios ? volver al loop
/****************************************/
// NON-Interrupt subroutines

ANTIREBOTE:
    CALL DELAY

    ; Segunda lectura
    IN R20, PINB
    IN R21, PIND

    ; ¿El cambio se mantuvo?
    CP R20, R18
    BREQ MAIN_LOOP
    CP R21, R19
    BREQ MAIN_LOOP
	
	//Si hubo cambio, ver cual fue:
    // PB4 (NC) ? sumar 1 a R16
    SBIS PINB, PINB4	//skip si es 1, leer la siguiente si es 0
    RJMP CHECK_PB5		//chequear PINB5
    INC R16				//incrementar 1 a R16
	CALL DISPLAY
	RJMP UPDATE_STATE

CHECK_PB5:
    // PB5 (NC) ? restar 1 a R16
    SBIS PINB, PINB5	//Skip si es 1, leer la siguiente si es 0
    RJMP CHECK_PD2		//chequear el siguiente boton
    DEC R16				//restar 1 a r16
	CALL DISPLAY
	RJMP UPDATE_STATE

CHECK_PD2:
    // PD2 ? restar 1 a R17
    SBIS PIND, PIND2	//Skip si es 1, leer la siguiente si es 0
    RJMP CHECK_PD3		//chequear siguiente boton
    DEC R17				//restar 1 a r17
	CALL DISPLAY
	RJMP UPDATE_STATE

CHECK_PD3:
    // PD3 ? sumar 1 a R17
    SBIS PIND, PIND3	// skip si es1, leer la siguiente si es 0
    RJMP UPDATE_STATE	// actualizar estado
    INC R17				// Sumar 1 al r17
	CALL DISPLAY
	RJMP UPDATE_STATE


DELAY:
LDI R24, 255
LOOP_DELAY:
DEC R24
BRNE LOOP_DELAY
RET

UPDATE_STATE:
    MOV R18, R20        // Nuevo estado base PORTB
    MOV R19, R21        // Nuevo estado base PORTD
    RJMP MAIN_LOOP

DISPLAY:
    // Actualizar el primer numero binario
    MOV  R22, R16		//guardamos el r16 en r22
    ANDI R22, 0x0F		//Aislamos solo las entradas PB0 - PB3

    IN   R23, PORTB		//Guardamos la configuracion actual del PROTB
    ANDI R23, 0xF0		//Aislamos los pullups
    OR   R22, R23		//combinamos ambas configuraciones
    OUT  PORTB, R22		//Actualizamos las salidas del PORTB con la combinacion de ambas configuraiones

    // Actualizar el segundo numero binario
    MOV  R22, R17		//Guardamos el r17 en r22 
    ANDI R22, 0x0F		//Aislamos solo los primeros bit de entrada
    LSL  R22			//Corrimiento de 1 bit
    LSL  R22			//Corrimiento de 1 bit	
    LSL  R22			//Corrimiento de 1 bit
    LSL  R22			//Corrimiento de 1 bit

    IN   R23, PORTD		//leer PORTD Actual
    ANDI R23, 0x0F		//Aislar primeros 4 BITS
    OR   R22, R23		//Combinar R22 y R23
    OUT  PORTD, R22		//Actualizar PORTD

    RET

/****************************************/
// Interrupt routines
/****************************************/
