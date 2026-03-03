/*
* laboratorio3-Interrupciones
*
* Creado: 16/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Implementacion un contador de “decenas”. Cada vez que el contador con el TMR0 llegue a
10 deberá de resetearlo e incrementar el contador de decenas en un segundo display de
7 segmentos, de manera que se muestren las decenas de segundos.
Consideraciones
- Cuando éste llegue a 60s deberá de reiniciar ambos contadores.
- Los display de 7 segmentos deben estar conectados al mismo puerto

*/
/****************************************/
// Encabezado (Definici n de Registros, Variables y Constantes)?
.include "M328PDEF.inc" // Include definitions specific to ATMega328P
.def counter = R20        // Registro para el contador de 4 bits
.def counterdisp1 = R19		// Registro para el contador hex, unidades
.def counterdisp2 = R21		// Registro para el contador hex, decenas



.dseg
.org SRAM_START
//variable_name: .byte 1 // Memory alocation for variable_name: .byte (byte size)
.cseg


/****************************************/
//             Vectores
/****************************************/


.org 0x0000
	RJMP RESET

.org PCI1addr 
    RJMP ISR_PCINT1

.org OVF1addr
	RJMP TMIER1_OVF 
 
 .org OVF0addr
	RJMP TIMER0_OVF



/****************************************/


RESET:

// Configuracion de la pila
LDI R16, LOW(RAMEND)
OUT SPL, R16
LDI R16, HIGH(RAMEND)
OUT SPH, R16

/****************************************/



// Configurar entradas y salidas

// Input -> PC1, PC2, PC3, PC4, PC5

CBI DDRC, DDC1 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC2 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC3 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC4 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 1 de DDRC -> Input

SBI PORTC, PORTC1 // Habilitando pull-up para PC1
SBI PORTC, PORTC2 // Habilitando pull-up para PC2
SBI PORTC, PORTC3 // Habilitando pull-up para PC3
SBI PORTC, PORTC4 // Habilitando pull-up para PC4
SBI PORTC, PORTC5 // Habilitando pull-up para PC5






//CONFIGURAR PORTD COMO SALIDA

LDI R16, 0xFF
OUT DDRD, R16
LDI R16, 0x00
OUT PORTD, R16


//SALIDAS  PC0, PB0,PB1, PB2, PB3, PB4, PB5

SBI DDRC, DDC0 // Poniendo en 0, el bit 0 de DDRC -> Output
SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
SBI DDRB, DDB1 // Poniendo en 1, el bit 1 de DDRB -> Output
SBI DDRB, DDB2 // Poniendo en 1, el bit 2 de DDRB -> Output
SBI DDRB, DDB3 // Poniendo en 1, el bit 3 de DDRB -> Output
SBI DDRB, DDB4 // Poniendo en 1, el bit 4 de DDRB -> Output
SBI DDRB, DDB5 // Poniendo en 1, el bit 5 de DDRB -> Output

CBI PORTC, PORTC0   // Inicialmente apagado el PC0
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3
CBI PORTB, PORTB4   // Inicialmente apagado el PB4
CBI PORTB, PORTB5   // Inicialmente apagado el PB5



; Habilitar el grupo PCIE1 (Puerto C)
    LDI R17, (1 << PCIE1)
    STS PCICR, R17
    // Habilitar específicamente los pines PCINT11 (PC3) y PCINT12 (PC4)
    LDI R17, (1 << PCINT13)
    STS PCMSK1, R17



//CALCULANDO EL PRESCALER.
//CON:
		//	- TIMER0=8BITS
		//	- Fclk=16000000 Hz
		//	- PreScaler=1024
		//	- Overflow==0.009984 s

//Configuracion del TIMER0
    // Modo Normal (WGM01=0, WGM00=0)
    LDI R16, 0x00
    OUT TCCR0A, R16

	LDI R16, 99
	OUT TCNT0, R16
	CLR R16
	LDI R18, 100      ; 100 interrupciones = 1 segundo

    ; Prescaler = 1024 (CS02=1, CS00=1)
    LDI R16, (1<<CS02)|(1<<CS00)
    OUT TCCR0B, R16

    ; Habilitar interrupción por overflow
    LDI R16, (1<<TOIE0)
    STS TIMSK0, R16

    ; Habilitar interrupciones globales
    SEI

//
//PARA USAR EL PORTD COMPLETO (DESACTIVAR RX Y TX
LDI R18, 0x00
STS UCSR0B, R18

/****************************************/
// Loop Infinito
disp7seg: .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78, 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E

MultDisp: .DB 0b0001, 0b0010, 0b0100, 0b1000

dispON:	  .DB 0b00000001, 0b00010011

dispOFF:  .DB 0b00000001, 0b01110001


CLR R19
CLR R18
CLR R1
CLR R21


MAIN_LOOP:
	
	
	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)
	//Desplazar Z a poscicion
	ADD	ZL, counterdisp1	// apuntar segun la cuenta de  unidades
	ADC ZH, R1				// R1 debe ser 0 (registro 0)
	LPM R23, Z				// Guardar lo apuntado en z
	//Apagamos el display de decenas
	SBI PORTB, PB5
LDI  R27, 20
minidelay:
    DEC  R27
    BRNE minidelay
	//Encendemos el display de unidades
	CBI PORTB, PB4
	// Mostrar lo apuntado en z
	OUT PORTD, R23			
	

	// Nuevamente para el segundo Display	
	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)
	//Dezplasar a segunda poscicion 
	ADD	ZL, counterdisp2	// apuntar segun las decenas
	ADC ZH, R1				// R1 debe ser 0 (registro 0)
	LPM R23, Z				// Guardar lo apuntado en z
	//Apagamos el display de unidades
	SBI PORTB, PB4

	//para evitar numeros fantasma
	LDI  R27, 20
	minidelay2:
    DEC  R27
    BRNE minidelay2
	//Encendemos el display de decenas
	CBI PORTB, PB5
	// Mostrar lo apuntado en z
	OUT PORTD, R23	


	IN R22, PORTB        ; Leemos el estado actual de PORTB (donde están PB4 y PB5)
    ANDI R22, 0b11110000 ; Limpiamos los bits 0-3 (borramos el conteo viejo)
    
    MOV R23, counter     ; Copiamos el contador a un registro temporal (no uses R16 si está ocupado)
    ANDI R23, 0b00001111 ; Nos aseguramos de que solo tenga 4 bits
    
    OR R22, R23          ; Combinamos: bits 4-7 (displays) + bits 0-3 (conteo)
    OUT PORTB, R22       ; Escribimos al puerto sin apagar los displays
	
	RJMP MAIN_LOOP


///****************************************/
//// Interrupt routines
///****************************************/

// Interrupcion por PINC
ISR_PCINT1:
    // Guardar contexto

	// Retornar Contexto

	// Salir de Interrupcion
    RETI

//Interrupcion por Timer1

TMIER1_OVF:
    // Guardar contexto
    
	// Retornar Contexto

	// Salir de Interrupcion
    RETI


//Interrupcion por Timer0

TIMER0_OVF:
    // Guardar contexto
    
	// Retornar Contexto

	// Salir de Interrupcion
    RETI
