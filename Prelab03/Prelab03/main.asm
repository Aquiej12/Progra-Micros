/*
* Prelaboratorio3-Interrupciones
*
* Creado: 16/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Contador binario de 4 bits del prelaboratorio
para que el contador se incrementará cada interrupcion

*/
/****************************************/
// Encabezado (Definici n de Registros, Variables y Constantes)?
.include "M328PDEF.inc" // Include definitions specific to ATMega328P
.def counter = R20        // Registro para el contador de 4 bits
.def counterdisp1 = R19		// Registro para el contador hex, unidades



.dseg
.org SRAM_START
//variable_name: .byte 1 // Memory alocation for variable_name: .byte (byte size)
.cseg
.org 0x0000
	RJMP RESET

.org PCI1addr 
    RJMP ISR_PCINT1

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

// Input -> PB4, PB5, PC5
CBI DDRC, DDC4 // Poniendo en 0, el bit 4 de DDRC -> Input
CBI DDRC, DDC3 // Poniendo en 0, el bit 5 de DDRC -> Input

SBI PORTC, PORTC4 // Habilitando pull-up para PC4
SBI PORTC, PORTC3 // Habilitando pull-up para PC3

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
SBI DDRB, DDB4 // Poniendo en 1, el bit 4 de DDRB -> Output


// Puerto B -> PB0, PB1, PB2, PB3
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3
CBI PORTB, PORTB4   // Inicialmente apagado el PB4

; Habilitar el grupo PCIE1 (Puerto C)
    LDI R17, (1 << PCIE1)
    STS PCICR, R17
    // Habilitar específicamente los pines PCINT11 (PC3) y PCINT12 (PC4)
    LDI R17, (1 << PCINT11) | (1 << PCINT12)
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

CLR R19
CLR R18
CLR R1


MAIN_LOOP:
ANDI counterdisp1, 9					// solo queremos cuenta de 0 a 9

	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)
	//Desplazar Z a poscicion
	ADD	ZL, counterdisp1				// apuntar segun el r19
	ADC ZH, R1				// R1 debe ser 0 (registro 0)
	LPM R23, Z				// Guardar lo apuntado en z
	SBI //NPN
	OUT PORTD, R23			// Mostrar lo apuntado en z
	// Nuevamente para el segundo Display	
	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)
	//Dezplasar a segunda poscicion 
	ADD	ZL, counterdisp2				// apuntar segun el 
	ADC ZH, R1				// R1 debe ser 0 (registro 0)
	LPM R23, Z				// Guardar lo apuntado en z
	CBI //NPN


	OUT PORTB, counter
	RJMP MAIN_LOOP
///****************************************/
//// Interrupt routines
///****************************************/
ISR_PCINT1:
    ; Guardar contexto
    PUSH R16
    IN   R16, SREG
    PUSH R16
	PUSH R24
	PUSH R25
	PUSH R21

//ANTIRREBOTE
LDI  R24, 255
DELAY_ISR:
    LDI  R25, 255
DELAY_INNER:
    DEC  R25
    BRNE DELAY_INNER
    DEC  R24
    BRNE DELAY_ISR

    ; Leer el estado de los pines (Activos en BAJO por pull-up)
    IN R17, PINC
    
    ; Debido a que la interrupción ocurre en ambos flancos (0->1 y 1->0),
    ; verificamos si el botón está presionado (es decir, el bit es 0).
    
CHECK_INC:
    SBRC R17, PORTC3     ; Si PC3 es 0, salta la siguiente instrucción
    RJMP CHECK_DEC        ; Si es 1 (suelto), saltar a revisar el otro
    ; Acción Incrementar
    INC counter
    RJMP EXIT_ISR

CHECK_DEC:
    SBRC R17, PORTC4     ; Si PC4 es 0, salta la siguiente instrucción
    RJMP EXIT_ISR         ; Si es 1 (suelto), salir
    ; Acción Decrementar
    DEC counter


EXIT_ISR:
	POP  R21
	POP  R25
	POP	 R24
    POP  R16
    OUT  SREG, R16
    POP  R16
    RETI

//Interrupcion por Timer0

TIMER0_OVF:
    ; Guardar contexto
    PUSH R16
    IN   R16, SREG
    PUSH R16
	PUSH R24
	PUSH R25
	PUSH R21
	; Recargar 99 para mantener 100 ms
    LDI  R16, 99
    OUT  TCNT0, R16
	DEC  R18
	BRNE REGRESAR		   // Si no es 0, salir
    LDI  R18, 100			//nuevamente contar 0.01s 100 veces = 1segundo
	INC counterdisp1
	

	REGRESAR:
	POP  R21
	POP  R25
	POP	 R24
    POP  R16
    OUT  SREG, R16
    POP  R16

    RETI
