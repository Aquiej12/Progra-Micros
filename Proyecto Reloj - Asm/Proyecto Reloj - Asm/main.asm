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

.def DPLY_ENCENDIDO		= R18
.def BANDERA			= R19
.def SEGUNDOS			= R20        // Registro para el contador de 4 bits
.def MODE				= R22
.def INDICE				= R23
.def MES_ACTUAL			= R24


.def MOSTRAR_DIPLAY		= R3
.def NumDias			= R4


// definir modo de trabajo del reloj
.equ VELOCIDAD = 1953 
; 15625  = EXACTO
; 1953 = RAPIDO

// Numero Maximo de Modos
.equ MAX_MODES = 7

.dseg
.org SRAM_START
//variable_name:	.byte 1  // Memory alocation for variable_name: .byte (byte size)
	VAR_MINUTOS_U:		.byte 1  // Reserva 1 byte para Unidades de Hora
	VAR_MINUTOS_D:		.byte 1  // Reserva 1 byte para Horas
	VAR_HORAS_U:		.byte 1  // Reserva 1 byte para Unidades de Hora
	VAR_HORAS_D:		.byte 1  // Reserva 1 byte para Horas
    VAR_DIAS_U:		.byte 1  // Reserva 1 byte para Días
    VAR_DIAS_D:		.byte 1  // Reserva 1 byte para Días
    VAR_MES_U:		.byte 1  // Reserva 1 byte para Mes
    VAR_MES_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_U:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_MES:			.byte 1	 // Reserva 1 byte para que numero de mes estamos
.cseg


;========================================
// VECTORES
;========================================


.org 0x0000
	RJMP RESET

.org PCI1addr 
    RJMP ISR_PCINT1

.org OC1Aaddr
	RJMP TMIER1_COMPA
 
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
/****************************************/
// --- INICIALIZAR VARIABLES EN SRAM ---
LDI R16, 0
STS VAR_MINUTOS_U, R16
STS VAR_MINUTOS_D, R16
STS VAR_HORAS_U, R16
STS VAR_HORAS_D, R16
CLR SEGUNDOS
LDI R16, 1
STS VAR_MES_U, R16
STS VAR_DIAS_U, R16    ; Unidad del día = 1
CLR R16
STS VAR_DIAS_D, R16    ; Decena del día = 0
STS VAR_MES_D, R16    ; Decena del día = 0
;========================================
// Configurar entradas y salidas
;========================================

// Input -> PC1, PC2, PC3, PC4, PC5

CBI DDRC, DDC1 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC2 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC3 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC4 // Poniendo en 0, el bit 1 de DDRC -> Input


CBI PORTC, PORTC1 // Deshabilitando pull-up para PC1
CBI PORTC, PORTC2 // Deshabilitando pull-up para PC2
CBI PORTC, PORTC3 // Deshabilitando pull-up para PC3
CBI PORTC, PORTC4 // Deshabilitando pull-up para PC4


//CONFIGURAR PORTD COMO SALIDA

LDI R16, 0xFF
OUT DDRD, R16
LDI R16, 0x00
OUT PORTD, R16


//SALIDAS  PC0, PB0,PB1, PB2, PB3, PB4, PB5

SBI DDRC, DDC5 // Poniendo en 0, el bit 5 de DDRC -> Output
SBI DDRB, DDB0 // Poniendo en 1, el bit 0 de DDRB -> Output
SBI DDRB, DDB1 // Poniendo en 1, el bit 1 de DDRB -> Output
SBI DDRB, DDB2 // Poniendo en 1, el bit 2 de DDRB -> Output
SBI DDRB, DDB3 // Poniendo en 1, el bit 3 de DDRB -> Output
SBI DDRB, DDB4 // Poniendo en 1, el bit 4 de DDRB -> Output
SBI DDRB, DDB5 // Poniendo en 1, el bit 5 de DDRB -> Output

CBI PORTC, PORTC5   // Inicialmente apagado el PC5
CBI PORTB, PORTB0   // Inicialmente apagado el PB0
CBI PORTB, PORTB1   // Inicialmente apagado el PB1
CBI PORTB, PORTB2   // Inicialmente apagado el PB2
CBI PORTB, PORTB3   // Inicialmente apagado el PB3
CBI PORTB, PORTB4   // Inicialmente apagado el PB4
CBI PORTB, PORTB5   // Inicialmente apagado el PB5


;========================================
; Habilitar el grupo PCIE1 (Puerto C)
;========================================

    LDI R17, (1 << PCIE1)
    STS PCICR, R17

    // Habilitar específicamente los pines PCINT11 (PC3) y PCINT12 (PC4)
    LDI R17, (1 << PCINT8) | (1 << PCINT9) |(1 << PCINT10) 
    STS PCMSK1, R17



;========================================
; CONFIGURACIÓN TIMER0
;========================================

    // Modo Normal (WGM01=0, WGM00=0)
    LDI R16, 0x00
    OUT TCCR0A, R16

	LDI R16, 99
	OUT TCNT0, R16
	CLR R16

   ; Prescaler
	LDI R16, (1<<CS01)|(1<<CS00)
	OUT TCCR0B, R16

    ; Habilitar interrupción por overflow
    LDI R16, (1<<TOIE0)
    STS TIMSK0, R16



;========================================
; CONFIGURACIÓN TIMER1
;========================================
// TIMER1 CTC configurado a 1 segundo

; Modo CTC (WGM12 = 1)
LDI R16, 0x00
STS TCCR1A, R16          ; WGM11=0, WGM10=0

LDI R16, (1<<WGM12)
STS TCCR1B, R16          ; WGM12=1

; Cargar valor MODO
LDI R16, HIGH(VELOCIDAD)
STS OCR1AH, R16

LDI R16, LOW(VELOCIDAD)
STS OCR1AL, R16

; Habilitar interrupción por comparación A
LDI R16, (1<<OCIE1A)
STS TIMSK1, R16

; Prescaler 1024 (CS12=1, CS10=1)
LDS R16, TCCR1B
ORI R16, (1<<CS12)|(1<<CS10)
STS TCCR1B, R16




    ; Habilitar interrupciones globales
    SEI

//
//PARA USAR EL PORTD COMPLETO (DESACTIVAR RX Y TX
LDI R18, 0x00
STS UCSR0B, R18


;========================================
// TABLAS DE DATOS
;========================================

// Tabla de DISPLAYS

	// Numeros del 0 al 9 en display Anodo Comun
	disp7seg: .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78, 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E

	// Multiplexacion de 4 Displays Anodo Comun
	multDisp: .DB 0b1110, 0b1101, 0b1011, 0b0111
	
	// Palabra "ON" en Display 7 segmentos Anodo Común
	
	dispON:	  .DB 0b00000001, 0b00010011
	
	// Palabra "OF" en Display 7 segmentos Anodo Común
	dispOFF:  .DB 0b00000001, 0b01110001

	// Días máximos de cada mes (El primer 0 es relleno para el mes 0)
	tabla_meses: .DB 0x00, 0x32, 0x29, 0x32, 0x31, 0x32, 0x31, 0x32, 0x32, 0x31, 0x32, 0x31, 0x32, 0x00
;========================================
// LIMPIAR REGISTROS
;========================================

CLR R19
CLR R18
CLR R1
CLR R21
CLR MODE

;========================================
// LOOP INFINITO
;========================================

MAIN_LOOP:

	RJMP MAIN_LOOP

// NOINTERRUPTER ROUTINES



///****************************************/
//// Interrupt routines
///****************************************/

// Interrupcion por PINC
ISR_PCINT1:
    // Guardar contexto
	PUSH R16
	PUSH R17
	IN R16, SREG
	PUSH R16
	// INTERRUPCION
	SBIS PINC, PINC1	
	RJMP PRESSMODO
	SBIS PINC, PINC2
	RJMP PRESSALARMA
	SBIS PINC, PINC3
	RJMP PRESSMENOS
	SBIS PINC, PINC4
	RJMP PRESSMAS
	RJMP SALIR_ISR_PINC

PRESSMODO:
	INC MODE
	CPI MODE, MAX_MODES
	BRNE CONTINUE
	CLR MODE
	CONTINUE:
	RJMP SALIR_ISR_PINC

PRESSALARMA:
	//CPI ALARMA, 0
	//BREQ SALIR_ISR_PINC
	//CBI PORTB, PB5
	//RJMP SALIR_ISR_PINC

PRESSMENOS:
	LDI BANDERA, 1
	RJMP SALIR_ISR_PINC

PRESSMAS:
	LDI BANDERA, 2
	RJMP SALIR_ISR_PINC


SALIR_ISR_PINC:
	// Retornar Contexto

	POP R16
	OUT SREG, R16
	POP R17
	POP R16
	// Salir de Interrupcion
    RETI



//Interrupcion por Timer1

TMIER1_COMPA:
    // Guardar contexto
	PUSH R16
	PUSH R17
	IN R16, SREG
	PUSH R16

	// Operaciones

	SBI PIND, PIND7
	 
	INC SEGUNDOS
	CPI SEGUNDOS, 60
	BREQ INC_VAR_MINUTOS_U
	RJMP SALIR_ISR_TMR0
	
	INC_VAR_MINUTOS_U:
	CLR SEGUNDOS
	LDS R16, VAR_MINUTOS_U
	INC R16 
	CPI R16, 10             
    BREQ INC_VAR_MINUTOS_D            
    STS VAR_MINUTOS_U, R16      
    RJMP SALIR_ISR_TMR0

	INC_VAR_MINUTOS_D:
	CLR R16
	STS VAR_MINUTOS_U, R16
    LDS R16, VAR_MINUTOS_D      
    INC R16
    CPI R16, 6					
    BREQ INC_VAR_HORAS_U
    STS VAR_MINUTOS_D, R16      
    RJMP SALIR_ISR_TMR0

	INC_VAR_HORAS_U:
	CLR R16
	STS VAR_MINUTOS_D, R16
    LDS R16, VAR_HORAS_U 
	LDS R17, VAR_HORAS_D 
	SWAP R17
	INC R16
	OR R17, R16
	CPI R17, 0x24			
    BREQ INC_VAR_DIAS_U
	CPI R16, 10
	BREQ INC_VAR_HORAS_D
    STS VAR_HORAS_U, R16
	CLR R17 
	CLR R16     
    RJMP SALIR_ISR_TMR0


	INC_VAR_HORAS_D:
	CLR R16
	STS VAR_HORAS_U, R16
    LDS R16, VAR_HORAS_D 
	INC R16
	STS VAR_HORAS_D, R16
	CLR R16     
	RJMP SALIR_ISR_TMR0

	INC_VAR_DIAS_U:
	CLR R16
	STS VAR_HORAS_U, R16
	STS VAR_HORAS_D, R16

    LDS R16, VAR_DIAS_U 
	LDS R17, VAR_DIAS_D 
	SWAP R17
	INC R16
	OR R17, R16
	CP R17, MES_ACTUAL			
    BREQ INC_VAR_MES_U

	CPI R16, 10
	BREQ INC_VAR_DIAS_D

    STS VAR_DIAS_U, R16
	CLR R17      
    RJMP SALIR_ISR_TMR0


	INC_VAR_DIAS_D:
	CLR R16
	STS VAR_DIAS_U, R16

    LDS R16, VAR_DIAS_D 
	INC R16
	STS VAR_DIAS_D, R16

	CLR R16     
	RJMP SALIR_ISR_TMR0


	INC_VAR_MES_U:
	LDI R16, 1
	STS VAR_DIAS_U, R16
	CLR R16
	STS VAR_DIAS_D, R16

    LDS R16, VAR_MES_U 
	LDS R17, VAR_MES_D 
	SWAP R17
	INC R16
	OR R17, R16
	CPI R17, 0x13			
    BREQ RST_MES

	CPI R16, 10
	BREQ INC_VAR_MES_D

    STS VAR_MES_U, R16
	CLR R17      
    RJMP SALIR_ISR_TMR0


	INC_VAR_MES_D:
	CLR R16
	STS VAR_MES_U, R16

    LDS R16, VAR_MES_D 
	INC R16
	STS VAR_MES_D, R16

	CLR R16     
	RJMP SALIR_ISR_TMR0

	RST_MES:
	CLR R16
	STS VAR_MES_D, R16
	LDI R16, 1
	STS VAR_MES_U, R16
	

	SALIR_ISR_TMR0:
	// Retornar Contexto
	POP R16
	OUT SREG, R16
	POP R17
	POP R16
	// Salir de Interrupcion
    RETI


//Interrupcion por Timer0

TIMER0_OVF:
    // Guardar contexto
	PUSH R16
	PUSH R17
	IN R16, SREG
	PUSH R16

	// Recargar Timer0
    LDI R16, 99
	OUT TCNT0, R16
	CLR R16


// Operacion
INC DPLY_ENCENDIDO
CPI DPLY_ENCENDIDO, 4
BRLO Apagar_Displays    ; si < 4, sigue normal
CLR DPLY_ENCENDIDO      ; si >= 4, resetea


	Apagar_Displays:
    IN R16, PORTB
    ORI R16, 0x0F       ; apaga transistores (PB0-PB3)
    OUT PORTB, R16

    IN R16, PORTD
    ORI R16, 0x7F
    OUT PORTD, R16

    ; --- delay de blanking ---
    PUSH R17
    LDI R17, 50
blank_loop:
    DEC R17
    BRNE blank_loop
    POP R17

	  ; --- elegir datos según modo ---

	CPI MODE, 0b000
	BREQ MODO_horario

	CPI MODE, 0b001
	BREQ MODO_fecha

	CPI MODE, 0b010
	BREQ MODO_horario

	CPI MODE, 0b011
	BREQ MODO_fecha

	CPI MODE, 0b100
	BREQ MODO_horario

	CPI MODE, 0b101
	BREQ MODO_letras

	CPI MODE, 0b110
	BREQ MODO_horario



	MODO_horario:

	CPI DPLY_ENCENDIDO, 0
    BREQ Cargar_Min_U
    CPI DPLY_ENCENDIDO, 1
    BREQ Cargar_Min_D
    CPI DPLY_ENCENDIDO, 2
    BREQ Cargar_Hora_U
    
		Cargar_Hora_D:
		LDS R16, VAR_HORAS_D
		RJMP Dibujar_Numero
		Cargar_Hora_U:
	    LDS R16, VAR_HORAS_U 
		RJMP Dibujar_Numero
		Cargar_Min_D:
	    LDS R16, VAR_MINUTOS_D 
		RJMP Dibujar_Numero
		Cargar_Min_U:
	    LDS R16, VAR_MINUTOS_U 
		RJMP Dibujar_Numero
			

	MODO_fecha:
	; Elegir variable según el display
    CPI DPLY_ENCENDIDO, 0
    BREQ Cargar_Dia_U
    CPI DPLY_ENCENDIDO, 1
    BREQ Cargar_Dia_D
    CPI DPLY_ENCENDIDO, 2
    BREQ Cargar_Mes_U
    
	Cargar_Mes_D:
	    LDS R16, VAR_MES_D 
		RJMP Dibujar_Numero
	Cargar_Mes_U:
	    LDS R16, VAR_MES_U 
		RJMP Dibujar_Numero
	Cargar_Dia_D:
	    LDS R16, VAR_DIAS_D 
		RJMP Dibujar_Numero
	Cargar_Dia_U:
	    LDS R16, VAR_DIAS_U 
		RJMP Dibujar_Numero
	
Dibujar_Numero:
   
    LDI ZH, HIGH(disp7seg<<1)
    LDI ZL, LOW(disp7seg<<1)
    ADD ZL, R16
    ADC ZH, R1              ; R1 es 0
    LPM R17, Z
	IN R16, PORTD           ; Lee cómo está el puerto D actualmente (con el LED)
    ANDI R16, 0x80          ; Conserva SOLO el bit 7 (PD7) y borra el resto
    ANDI R17, 0x7F          ; Asegura que el número del display no toque el bit 7
    OR R17, R16             ; Combina el LED encendido/apagado con el número
    OUT PORTD, R17          ; Mandar a los segmentos

MODO_letras:

Activar_Transistor:
    LDI ZH, HIGH(multDisp<<1)
    LDI ZL, LOW(multDisp<<1)
    ADD ZL, DPLY_ENCENDIDO
    ADC ZH, R1
    LPM R16, Z             

 IN R17, PORTB
    ANDI R17, 0xF0         ; Limpia bits 0-3, conserva 4-7
    OR R17, R16            ; Combina solo los bits bajos
    OUT PORTB, R17         

Salir_Timer0:
   	// Retornar Contexto
	POP R16
	OUT SREG, R16
	POP R17
	POP R16
	// Salir de Interrupcion
    RETI
