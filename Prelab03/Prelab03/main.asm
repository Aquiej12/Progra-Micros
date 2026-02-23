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
.def counterdisp2 = R21		// Registro para el contador hex, decenas



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
SBI DDRB, DDB5 // Poniendo en 1, el bit 5 de DDRB -> Output


// Puerto B -> PB0, PB1, PB2, PB3
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3


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
ISR_PCINT1:
    ; Guardar contexto
    PUSH R16
    IN   R16, SREG
    PUSH R16
	PUSH R24
	PUSH R25
	PUSH R22

    ; Leer el estado de los pines (Activos en BAJO por pull-up)
    IN R17, PINC
    
		// Ignorar cambios en PC3 y PC4 momentáneamente
    LDI  R22, 0x00
    STS  PCMSK1, R22

    ANDI R17, 0b00011000 ; Aislamos PC3 y PC4
    
    CPI  R17, 0x10       ; Solo PC3 presionado (Incrementar)
    BREQ DO_INC
    
    CPI  R17, 0x08       ; Solo PC4 presionado (Decrementar)
    BREQ DO_DEC

	RJMP EXIT_ISR

DO_INC:
    INC  counter
    RJMP EXIT_ISR

DO_DEC:
    DEC  counter

EXIT_ISR:
	//Borramos cualquier interrupción "encolada"
	LDI  R22, (1<<PCIF1)
    OUT  PCIFR, R22     

    // Habilitar nuevamente PC3 y PC4 ---
    LDI  R22, (1 << PCINT11) | (1 << PCINT12)
    STS  PCMSK1, R22
	//restaurar registros
	POP R22
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
	PUSH R22
	; Recargar 99 para mantener 100 ms
    LDI  R16, 99
    OUT  TCNT0, R16
	DEC  R18
	BRNE REGRESAR		   // Si no es 0, salir
    LDI  R18, 100			//nuevamente contar 0.01s 100 veces = 1segundo
	INC counterdisp1
	CPI counterdisp1, 10
	BREQ DECENAS
	RJMP REGRESAR

	DECENAS:
	CLR counterdisp1
	INC counterdisp2
	CPI counterdisp2, 6
	BRNE REGRESAR
	CLR counterdisp2

	REGRESAR:
	POP	 R22
	POP  R25
	POP	 R24
    POP  R16
    OUT  SREG, R16
    POP  R16

    RETI
