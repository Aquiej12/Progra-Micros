/*
* laboratorio2-Botones y Timer 0
*
* Creado: 16/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Contador binario de 4 bits del prelaboratorio
para que el contador se incrementará cada 1s. Importante, el timer0 seguirá
incrementando cada 100ms.
En el momento que el contador de segundos sea igual al contador de los botones,
deberá reiniciar el contador de segundos y cambiar el estado de una LED (de 0-
>1 o de 1->0 durante un ciclo entero). De manera que pueda variar el periodo del
encendido y apagado del indicador utilizando los botones.

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

//Habilitar cambio del prescaler (ventana de 4 ciclos)
LDI R16, (1<<CLKPCE)
STS CLKPR, R16

//Configurar división entre 8
LDI R16, 0b00000011    ; CLKPS = 0011 ? divide entre 8
STS CLKPR, R16

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


//CALCULANDO EL PRESCALER.
	//CON:
		//	- TIMER0=8BITS
		//	- Fclk=2000000 Hz
		//	- PreScaler=1024
		//	- Overflow==0.09984 s

//Configuracion del TIMER0
    ; Modo Normal (WGM01=0, WGM00=0)
    LDI R16, 0x00
    OUT TCCR0A, R16

	LDI R16, 60
	OUT TCNT0, R16
	CLR R16
	LDI R17, 10      ; 10 interrupciones = 1 segundo

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
	ANDI R19, 0b00001111	// solo queremos cuenta de 0 a 15
	LDI ZH, HIGH(disp7seg<<1)
	LDI ZL, LOW(disp7seg<<1)

	ADD	ZL, R19				// apuntar segun el r19
	ADC ZH, R1				// R1 debe ser 0 (registro 0)

	LPM R23, Z				// Guardar lo apuntado en z
	OUT PORTD, R23			// Mostrar lo apuntado en z

	
	MOV R21, R18
	ANDI R21, 0b00001111
	CP R21, R19
	BRNE LEERBOTONES
	SBI PINB, PB4
	CLR R18



LEERBOTONES:
IN R20, PINC

; PC3 = INC
SBIS PINC, PC3
RJMP ANTRBT_INC

; PC4 = DEC
SBIS PINC, PC4
RJMP ANTRBT_DEC

RJMP MAIN_LOOP




ANTRBT_INC:
    ; Delay ~20ms
    LDI R24, 50
DELAY1I:
    LDI R25, 255
DELAY2I:
    DEC R25
    BRNE DELAY2I
    DEC R24
    BRNE DELAY1I

    ; Confirmar si sigue presionado (debe ser 0 para seguir)
    SBIC PINC, PC3       ; Si se soltó (es 1), salta el incremento
    RJMP MAIN_LOOP       ; Regresa al loop si fue un ruido

    INC R19              ; Incrementa el contador principal

ESPERAR_SUELTE_INC:
    SBIS PINC, PC3       ; Si es 1 (suelto), salta el bucle de espera
    RJMP ESPERAR_SUELTE_INC

    RJMP MAIN_LOOP


ANTRBT_DEC:
    ; Delay ~20ms
    LDI R24, 50
DELAY1D:
    LDI R25, 255
DELAY2D:
    DEC R25
    BRNE DELAY2D
    DEC R24
    BRNE DELAY1D

    ; Confirmar si sigue presionado (debe ser 0)
    SBIC PINC, PC4       ; Si se soltó (es 1), salta el decremento
    RJMP MAIN_LOOP

    DEC R19              ; Decrementa el contador principal

ESPERAR_SUELTE_DEC:
    SBIS PINC, PC4       ; Si es 1 (suelto), salta el bucle de espera
    RJMP ESPERAR_SUELTE_DEC

    RJMP MAIN_LOOP


///****************************************/
//// Interrupt routines
///****************************************/
TIMER0_OVF:
    ; Guardar contexto
    PUSH R16
    IN   R16, SREG
    PUSH R16
	PUSH R24
	PUSH R25
	PUSH R21
	; Recargar 60 para mantener 100 ms
    LDI  R16, 60
    OUT  TCNT0, R16

    ; Toggle PB0-PB3
	DEC  R17          ; Decrementar contador
    BRNE REGRESAR		   ; Si no es 0, salir
    LDI  R17, 10
	INC R18
	IN R16, PORTB     ; Leer estado actual (incluyendo el LED PB4)
    ANDI R16, 0xF0    ; Limpiar bits 0-3 (contador viejo), mantener 4-7
    MOV R21, R18
    ANDI R21, 0x0F    ; Asegurar que R18 solo tenga 4 bits
    OR R16, R21       ; Combinar LED actual con nuevo conteo
    OUT PORTB, R16    ; Sacar al puerto
	CLR R16
    ; Restaurar contexto
	REGRESAR:
	POP  R21
	POP  R25
	POP	 R24
    POP  R16
    OUT  SREG, R16
    POP  R16

    RETI
