/*
* laboratorio3-Interrupciones
*
* Creado: 16/02/2026 - 12:00
* Autor : Abner Quiej
* Descripcion: Implementacion un contador de ?decenas?. Cada vez que el contador con el TMR0 llegue a
10 deber? de resetearlo e incrementar el contador de decenas en un segundo display de
7 segmentos, de manera que se muestren las decenas de segundos.
Consideraciones
- Cuando ?ste llegue a 60s deber? de reiniciar ambos contadores.
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
.def CONFIGURACION		= R24


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
    VAR_DIAS_U:		.byte 1  // Reserva 1 byte para D?as
    VAR_DIAS_D:		.byte 1  // Reserva 1 byte para D?as
    VAR_MES_U:		.byte 1  // Reserva 1 byte para Mes
    VAR_MES_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_U:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_MES:			.byte 1	 // Reserva 1 byte para que numero de mes estamos
	VAR_PINC_PREV:		.byte 1  // Estado anterior de PINC
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
STS VAR_DIAS_U, R16    ; Unidad del d?a = 1
CLR R16
STS VAR_DIAS_D, R16    ; Decena del d?a = 0
STS VAR_MES_D, R16    ; Decena del d?a = 0

;========================================
// Configurar entradas y salidas
;========================================

// Input -> PC1, PC2, PC3, PC4, PC5

CBI DDRC, DDC1 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC2 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC3 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC4 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC5 // Poniendo en 0, el bit 1 de DDRC -> Input

CBI PORTC, PORTC1 // Deshabilitando pull-up para PC1
CBI PORTC, PORTC2 // Deshabilitando pull-up para PC2
CBI PORTC, PORTC3 // Deshabilitando pull-up para PC3
CBI PORTC, PORTC4 // Deshabilitando pull-up para PC4
CBI PORTC, PORTC5 // Deshabilitando pull-up para PC4

//CONFIGURAR PORTD COMO SALIDA

LDI R16, 0xFF
OUT DDRD, R16
LDI R16, 0x00
OUT PORTD, R16


//SALIDAS  PC0, PB0,PB1, PB2, PB3, PB4, PB5

SBI DDRC, DDC0 // Poniendo en 0, el bit 5 de DDRC -> Output
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


IN R16, PINC
ANDI R16, 0b00011110   ; M?scara: PC1, PC2, PC3, PC4
STS VAR_PINC_PREV, R16

;========================================
; Habilitar el grupo PCIE1 (Puerto C)
;========================================

    LDI R17, (1 << PCIE1)
    STS PCICR, R17

    // Habilitar espec?ficamente los pines PCINT11 (PC3) y PCINT12 (PC4)
    LDI R17, (1 << PCINT8) | (1 << PCINT9) |(1 << PCINT10) 
    STS PCMSK1, R17



;========================================
; CONFIGURACI?N TIMER0
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

    ; Habilitar interrupci?n por overflow
    LDI R16, (1<<TOIE0)
    STS TIMSK0, R16



;========================================
; CONFIGURACI?N TIMER1
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

; Habilitar interrupci?n por comparaci?n A
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
	
	// Palabra "ON" en Display 7 segmentos Anodo Com?n
	
	dispON_OFF: .DB 0b00000001, 0b00010011, 0b01110001, 0x00
	

	// D?as m?ximos de cada mes (El primer 0 es relleno para el mes 0)
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
	
	CPI MODE, 0b000
	BREQ MODO_HORA
	
	CPI MODE, 0b001
	BREQ MODO_FECHA
	
	CPI MODE, 0b010
	BREQ CONFIGURAR_HORA

	CPI MODE, 0b011
	BREQ CONFIGURAR_FECHA

MODO_HORA:
	CBI DDRB, DDB5
	SBI DDRB, DDB4
	RJMP MAIN_LOOP

MODO_FECHA:
	CBI DDRB, DDB4
	SBI DDRB, DDB5
	RJMP MAIN_LOOP


CONFIGURAR_HORA:
	CBI DDRB, DDB5
	SBI DDRB, DDB4
	; Deshabilitar interrupci�n por comparaci�n A de Timer1
	LDS R16, TIMSK1
	ANDI R16, ~(1<<OCIE1A)
	STS TIMSK1, R16
	CLR SEGUNDOS

	; Prescaler 256 ? m�s lento ? parpadeo visible
	LDS R16, TCCR0B
	ANDI R16, 0xF8          ; limpiar bits CS02, CS01, CS00
	ORI R16, (1<<CS02)      ; prescaler 256
	STS TCCR0B, R16
	
	SELECCION_DISP_CONFIGURAR:
	CPI CONFIGURACION, 0
	BREQ CONFIGURAR_VAR_MINUTOS_U

	CPI CONFIGURACION, 1
	BREQ CONFIGURAR_VAR_MINUTOS_D	

	CPI CONFIGURACION, 2
	BREQ CONFIGURAR_VAR_HORAS_U

	RJMP CONFIGURAR_VAR_HORAS_D

	CONFIGURAR_VAR_MINUTOS_U:
		// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB0
		
		CPI BANDERA, 2
		BREQ INC_VAR_MINUTOS_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_MINUTOS_UNI

		RJMP SALIR_CONFIGURAR_HORA

		INC_VAR_MINUTOS_UNI:
			CLR BANDERA
			LDS R16, VAR_MINUTOS_U
			INC R16 
			CPI R16, 10
			BRNE STS_MINUTOS_U      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			STS_MINUTOS_U:
				STS VAR_MINUTOS_U, R16  
		RJMP SALIR_CONFIGURAR_HORA

		DEC_VAR_MINUTOS_UNI:
			CLR BANDERA
			LDS R16, VAR_MINUTOS_U
			DEC R16 
			CPI R16, 0xFF             
			BRNE SALIR_DEC_VAR_MINUTOS_UNI    
			LDI R16, 9
			SALIR_DEC_VAR_MINUTOS_UNI:
				STS VAR_MINUTOS_U, R16  
		RJMP SALIR_CONFIGURAR_HORA


	CONFIGURAR_VAR_MINUTOS_D:
		CBI PORTB, PORTB1
	
		CPI BANDERA, 2
		BREQ INC_VAR_MINUTOS_DEC
		CPI BANDERA, 1
		BREQ DEC_VAR_MINUTOS_DEC
		RJMP SALIR_CONFIGURAR_HORA
	
		INC_VAR_MINUTOS_DEC:
			CLR BANDERA

			LDS R16, VAR_MINUTOS_D
			INC R16             
			CPI R16, 6
			BRNE STS_MINUTOS_D      ; si NO es 6 → salta directo a guardar
			CLR R16                 ; si ES 6 → limpia
			STS_MINUTOS_D:
				STS VAR_MINUTOS_D, R16  ; guarda en ambos casos
				 
		RJMP SALIR_CONFIGURAR_HORA
	

		DEC_VAR_MINUTOS_DEC:
			CLR BANDERA

			LDS R16, VAR_MINUTOS_D
			DEC R16 
			CPI R16, 0xFF             
			BRNE SALIR_DEC_VAR_MINUTOS_DEC   
			LDI R16, 5
			SALIR_DEC_VAR_MINUTOS_DEC:
				STS VAR_MINUTOS_D, R16  
	
		RJMP SALIR_CONFIGURAR_HORA
	
	

	CONFIGURAR_VAR_HORAS_U:
		// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB2
		
		CPI BANDERA, 2
		BREQ INC_VAR_HORAS_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_HORAS_UNI

		RJMP SALIR_CONFIGURAR_HORA

			INC_VAR_HORAS_UNI:
			CLR BANDERA
			LDS R16, VAR_HORAS_U
			INC R16 
			CPI R16, 10
			BRNE STS_HORAS_U      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			STS_HORAS_U:
				STS VAR_HORAS_U, R16  
			RJMP SALIR_CONFIGURAR_HORA

			DEC_VAR_HORAS_UNI:
				CLR BANDERA

				LDS R16, VAR_HORAS_U
				DEC R16 
				CPI R16, 00xFF              
				BRNE SALIR_DEC_VAR_HORAS_UNI  
				LDI R16, 9

				SALIR_DEC_VAR_HORAS_UNI:
				STS VAR_HORAS_U, R16  

			RJMP SALIR_CONFIGURAR_HORA


	CONFIGURAR_VAR_HORAS_D:
	
			CBI PORTB, PORTB3
	
			CPI BANDERA, 2
			BREQ INC_VAR_HORAS_DEC
			CPI BANDERA, 1
			BREQ DEC_VAR_HORAS_DEC
			RJMP SALIR_CONFIGURAR_HORA
	
			INC_VAR_HORAS_DEC:
				CLR BANDERA
				LDS R16, VAR_HORAS_D
				INC R16 
				CPI R16, 6
				BRNE STS_HORAS_D      ; si NO es 6 → salta directo a guardar
				CLR R16                 ; si ES 6 → limpia
				STS_HORAS_D:
					STS VAR_HORAS_D, R16  
			RJMP SALIR_CONFIGURAR_HORA
		 
			DEC_VAR_HORAS_DEC:
				CLR BANDERA
				LDS R16, VAR_HORAS_D
				DEC R16 
				CPI R16, 0xFF              
				BRNE SALIR_DEC_VAR_HORAS_DEC   
				LDI R16, 5
				SALIR_DEC_VAR_HORAS_DEC:
					STS VAR_HORAS_D, R16  
	
			RJMP SALIR_CONFIGURAR_HORA


	SALIR_CONFIGURAR_HORA:

	CPI MODE, 0b010
	BRNE SALIR_MODE_S2
	JMP SELECCION_DISP_CONFIGURAR

	SALIR_MODE_S2:	
	; Habilitar interrupci�n por comparaci�n A de Timer1
	LDS R16, TIMSK1
	ORI R16, (1<<OCIE1A)
	STS TIMSK1, R16

	; Prescaler 64 ? velocidad normal (tu configuraci�n original)
	LDS R16, TCCR0B
	ANDI R16, 0xF8
	ORI R16, (1<<CS01)|(1<<CS00)    ; prescaler 64
	STS TCCR0B, R16

	RJMP MAIN_LOOP


CONFIGURAR_FECHA: 
	CBI DDRB, DDB4
	SBI DDRB, DDB5

	; Prescaler 256 ? m�s lento ? parpadeo visible
	LDS R16, TCCR0B
	ANDI R16, 0xF8          ; limpiar bits CS02, CS01, CS00
	ORI R16, (1<<CS02)      ; prescaler 256
	STS TCCR0B, R16

	SELECCION_DISP_CONFIGURAR_FECHA:
		CPI CONFIGURACION, 0
		BREQ CONFIGURAR_VAR_MES_U

		CPI CONFIGURACION, 1
		BREQ CONFIGURAR_VAR_MES_D	

		CPI CONFIGURACION, 2
		BREQ CONFIGURAR_VAR_DIA_U

		RJMP CONFIGURAR_VAR_DIA_D

	CONFIGURAR_VAR_MES_U:
		// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB0
		
		CPI BANDERA, 2
		BREQ INC_VAR_MES_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_MES_UNI

		RJMP SALIR_CONFIGURAR_FECHA

		INC_VAR_MES_UNI:
			CLR BANDERA

			LDS R16, VAR_MES_U 
			LDS R17, VAR_MES_D 
			SWAP R17
			INC R16
			OR R17, R16

			CPI R17, 0x13			
    		BREQ RST_VAR_MES_UNI:

			CPI R16, 10
			BRNE STS_INC_VAR_MES_UNI
			CLR R16
			RJMP STS_INC_VAR_MES_UNI

			RST_VAR_MES_UNI:
				CLR R16
				STS VAR_MES_D, R16
				LDI R16, 1
				STS VAR_MES_U, R16
				CLR R17
			RJMP SALIR_ISR_TMR0

			STS_INC_VAR_MES_UNI:
    			STS VAR_DIAS_U, R16
				CLR R17      
    		RJMP SALIR_ISR_TMR0

		DEC_VAR_MES_UNI:
			CLR BANDERA
			LDS R17, VAR_MES_D
			CPI R17, 1
			BRNE DEC_VAR_MES_UNI_0
			RJMP DEC_VAR_MES_UNI_1

			DEC_VAR_MES_UNI_0:
				LDS R16, VAR_MES_U
				DEC R16
				CPI R16, 0 
				BRNE STS_DEC_VAR_MES_UNI
				LDI R16, 9
			RJMP STS_DEC_VAR_MES_UNI

			DEC_VAR_MES_UNI_1:
				LDS R16, VAR_MES_U
				DEC R16
				CPI R16, 0xFF 
				BRNE STS_DEC_VAR_MES_UNI
				LDI R16, 12

			STS_DEC_VAR_MES_UNI:
				STS VAR_MES_UNI, R16
		RJMP SALIR_CONFIGURAR_FECHA

		
	CONFIGURAR_VAR_MES_D:
		// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB1
		
		CPI BANDERA, 2
		BREQ INC_VAR_MES_DEC

		CPI BANDERA, 1
		BREQ DEC_VAR_MES_DEC

		RJMP SALIR_CONFIGURAR_FECHA

		INC_VAR_MES_DEC:
			CLR BANDERA

			LDS R16, VAR_MES_D
			INC R16 
			CPI R16, 2
			BRNE STS_MES_D      ; si NO es 2 → salta directo a guardar
			CLR R16                 ; si ES 2 → limpia
			STS_MES_D:
				STS VAR_MES_D, R16  
		RJMP SALIR_CONFIGURAR_FECHA

		DEC_VAR_MES_DEC:
			CLR BANDERA
			LDS R16, VAR_MES_D
			DEC R16 
			CPI R16, 0xFF             
			BRNE SALIR_DEC_VAR_MES_UNI    
			LDI R16, 1	
			SALIR_DEC_VAR_MES_UNI:
				STS VAR_MES_U, R16  
		RJMP SALIR_CONFIGURAR_FECHA


	CONFIGURAR_VAR_DIA_U:
		
	// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB2
		
		CPI BANDERA, 2
		BREQ INC_VAR_DIA_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_DIA_UNI

		RJMP SALIR_CONFIGURAR_FECHA

		INC_VAR_DIA_UNI:
			CLR BANDERA

			LDS R16, VAR_DIA_U 
			LDS R17, VAR_DIA_D 
			SWAP R17
			INC R16
			OR R17, R16

			// Si la decena es igual a el limite
			LDS R16, VAR_MES
			CP R17, R16			
    		BREQ RST_VAR_DIA_UNI:

			// Si el Incremento es mayor a 9
			LDS R16, VAR_DIA_U
			INC R16
			CPI R16, 10
			BRNE STS_INC_VAR_DIA_UNI
			CLR R16
			RJMP STS_INC_VAR_DIA_UNI

			RST_VAR_DIA_UNI:
				CLR R16
				STS VAR_DIA_D, R16
				LDI R16, 1
				STS VAR_DIA_U, R16
				CLR R17
			RJMP SALIR_CONFIGURAR_FECHA

			STS_INC_VAR_DIA_UNI:
    			STS VAR_DIAS_U, R16
				CLR R17
				CLR R16      
    		RJMP SALIR_CONFIGURAR_FECHA

		DEC_VAR_DIA_UNI:
			CLR BANDERA
			LDS R17, VAR_DIA_D

			// Si la decena es cero
			CPI R17, 0
			BREQ DEC_VAR_DIA_UNI_0
			
			// Si la decena esta en el limite
			LDS R16, VAR_MES
			ANDI R16, 0b11110000
			SWAP R16

			CP R17, R16
			BREQ DEC_VAR_DIA_UNI_1
			
			// Si la decena esta en cualquier otro lado
			RJMP DEC_VAR_MES_UNI_2

			DEC_VAR_DIA_UNI_0:
				LDS R16, VAR_MES_U
				DEC R16
				CPI R16, 0 
				BRNE STS_DEC_VAR_MES_UNI
				LDI R16, 9
				RJMP STS_DEC_VAR_MES_UNI

			DEC_VAR_MES_UNI_1:
				LDS R16, VAR_MES_U
				DEC R16
				CPI R16, 0xFF 
				BRNE STS_DEC_VAR_MES_UNI
				LDS R16, VAR_MES
				ANDI R16, 0b00001111
				DEC R16
			RJMP STS_DEC_VAR_MES_UNI

			DEC_VAR_MES_UNI_2:
				LDS R16, VAR_MES_U
				DEC R16
				CPI R16, 0xFF
				BRNE STS_DEC_VAR_MES_UNI
				LDI R16, 9


			STS_DEC_VAR_MES_UNI:
				STS VAR_MES_UNI, R16
		RJMP SALIR_CONFIGURAR_FECHA

	CONFIGURAR_VAR_DIA_D:
		
	// ENCENDER EL DISPLAY A CONFIGURAR
		CBI PORTB, PORTB3
		
		CPI BANDERA, 2
		BREQ INC_VAR_DIA_DEC

		CPI BANDERA, 1
		BREQ DEC_VAR_DIA_DEC

		RJMP SALIR_CONFIGURAR_FECHA

		INC_VAR_DIA_DEC:
			CLR BANDERA
			LDS R17, VAR_DIAS_D 
			INC R17
			
			// Si la decena es igual a el limite
			LDS R16, VAR_MES
			SWAP R16
			ANDI R16, 0b00001111
			CP R17, R16			
    		BREQ RST_VAR_DIA_DEC

			LDS R16, VAR_DIAS_D
			INC R16
			CLR R16
			RJMP STS_INC_VAR_DIA_UNI

			RST_VAR_DIA_DEC:
				CLR R16
				STS VAR_DIA_D, R16
				CLR R17
			RJMP SALIR_CONFIGURAR_FECHA

			STS_INC_VAR_DIA_UNI:
    			STS VAR_DIAS_U, R16
				CLR R17
				CLR R16      
    		RJMP SALIR_CONFIGURAR_FECHA

		DEC_VAR_DIA_DEC:
			CLR BANDERA
			LDS R17, VAR_DIA_D
			DEC R17

			// Si la decena baja de cero
			CPI R17, 0xFF
			BREQ DEC_VAR_DIA_DEC_0
			
			MOV R16, R17
			RJMP STS_DEC_VAR_MES_DEC

			DEC_VAR_DIA_DEC_0:
				LDS R16, VAR_MES
				SWAP R16
				ANDI R16, 0b00001111
				RJMP STS_DEC_VAR_MES_DEC
				

			STS_DEC_VAR_MES_DEC:
				STS VAR_MES_UNI, R16
		RJMP SALIR_CONFIGURAR_FECHA
			


	SALIR_CONFIGURAR_FECHA:

	CPI MODE, 0b011
	BRNE SALIR_MODE_S3
	JMP SELECCION_DISP_CONFIGURAR_FECHA

	SALIR_MODE_S3:	

	; Prescaler 64 ? velocidad normal (tu configuraci�n original)
	LDS R16, TCCR0B
	ANDI R16, 0xF8
	ORI R16, (1<<CS01)|(1<<CS00)    ; prescaler 64
	STS TCCR0B, R16

	JMP MAIN_LOOP



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

	//Leer estado actual de PINC (solo pines de inter?s)
    IN R16, PINC
    ANDI R16, 0b00011110        ; M?scara PC1, PC2, PC3, PC4

    // Cargar estado anterior
    LDS R17, VAR_PINC_PREV

    // Detectar flancos de subida: bits que eran 0 y ahora son 1
    // flanco_subida = (~prev) & actual
    COM R17                     ; NOT del estado anterior
    AND R17, R16                ; AND con estado actual ? solo flancos de subida

    ; Guardar nuevo estado como "anterior" para la pr?xima vez
    IN R16, PINC
    ANDI R16, 0b00011110
    STS VAR_PINC_PREV, R16
	
	; Verificar qu? pin tuvo flanco de subida
	SBRC R17, PC0
	RJMP PRESSCONFIGURACION
	
	SBRC R17, PC1
	RJMP PRESSMODO
	
	SBRC R17, PC2
	RJMP PRESSALARMA
	
	SBRC R17, PC3
	RJMP PRESSMENOS
	
	SBRC R17, PC4
	RJMP PRESSMAS
	
	RJMP SALIR_ISR_PINC


	PRESSCONFIGURACION:
		INC CONFIGURACION
		CPI CONFIGURACION, 3
		BRNE SALIR_ISR_PINC
		CLR CONFIGURACION

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
		LDS R16, VAR_MES
		CP R17, R16			
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

	  ; --- elegir datos seg?n modo ---

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
		; Elegir variable seg?n el display
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

	MODO_letras:
		
		CPI DPLY_ENCENDIDO, 0
		BREQ Cargar_O
		CPI DPLY_ENCENDIDO, 1
		BREQ Cargar_N
		CPI DPLY_ENCENDIDO, 2
		BREQ Cargar_O
		
		Cargar_F:
			LDI R16,2
			LDI ZH, HIGH(dispON_OFF<<1)
			LDI ZL, LOW(dispON_OFF<<1)
			ADD ZL, R16
			ADC ZH, R1              ; R1 es 0
			LPM R17, Z
			IN R16, PORTD          
			ANDI R16, 0x80         
			ANDI R17, 0x7F          
			OR R17, R16             
			OUT PORTD, R17
			RJMP Activar_Transistor          

		Cargar_O:
			LDI ZH, HIGH(dispON_OFF<<1)
			LDI ZL, LOW(dispON_OFF<<1)
			LPM R17, Z
			IN R16, PORTD          
			ANDI R16, 0x80         
			ANDI R17, 0x7F          
			OR R17, R16             
			OUT PORTD, R17 
			RJMP Activar_Transistor

		Cargar_N:
			LDI R16,1
			LDI ZH, HIGH(dispON_OFF<<1)
			LDI ZL, LOW(dispON_OFF<<1)
			ADD ZL, R16
			ADC ZH, R1              ; R1 es 0
			LPM R17, Z
			IN R16, PORTD          
			ANDI R16, 0x80         
			ANDI R17, 0x7F          
			OR R17, R16             
			OUT PORTD, R17
			RJMP Activar_Transistor 

	Dibujar_Numero:
	
		LDI ZH, HIGH(disp7seg<<1)
		LDI ZL, LOW(disp7seg<<1)
		ADD ZL, R16
		ADC ZH, R1              ; R1 es 0
		LPM R17, Z
		IN R16, PORTD           ; Lee c?mo est? el puerto D actualmente (con el LED)
		ANDI R16, 0x80          ; Conserva SOLO el bit 7 (PD7) y borra el resto
		ANDI R17, 0x7F          ; Asegura que el n?mero del display no toque el bit 7
		OR R17, R16             ; Combina el LED encendido/apagado con el n?mero
		OUT PORTD, R17          ; Mandar a los segmentos



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
