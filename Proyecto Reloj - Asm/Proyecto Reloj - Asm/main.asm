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

.def DPLY_ENCENDIDO		= R21
.def BANDERA			= R19
.def SEGUNDOS			= R20        // Registro para el contador de 4 bits
.def MODE				= R22
.def INDICE				= R23
.def CONFIGURACION		= R24


.def MOSTRAR_DIPLAY		= R3
.def NumDias			= R4


// definir modo de trabajo del reloj
.equ VELOCIDAD = 200
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
	VAR_ALARMA_HORAS_U:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_HORAS_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_MINUTOS_U:		.byte 1  // Reserva 1 byte para Mes
	VAR_ALARMA_MINUTOS_D:		.byte 1  // Reserva 1 byte para Mes
	VAR_MES:			.byte 1	 // Reserva 1 byte para que numero de mes estamos
	VAR_PINC_PREV:		.byte 1  // Estado anterior de PINC
	VAR_ALARMA_ESTADO:			.byte 1  // Reserva 1 byte para guardar estado de alarma
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
STS VAR_MES, R16

CLR R16
STS VAR_DIAS_D, R16    ; Decena del d?a = 0
STS VAR_MES_D, R16    ; Decena del d?a = 0
STS VAR_ALARMA_HORAS_U, R16
STS VAR_ALARMA_HORAS_D, R16
STS VAR_ALARMA_MINUTOS_U, R16
STS VAR_ALARMA_MINUTOS_D, R16
STS VAR_ALARMA_ESTADO, R16

;========================================
// Configurar entradas y salidas
;========================================

// Input -> PC0, PC1, PC2, PC3, PC4

CBI DDRC, DDC1 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC2 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC3 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC4 // Poniendo en 0, el bit 1 de DDRC -> Input
CBI DDRC, DDC0 // Poniendo en 0, el bit 1 de DDRC -> Input

CBI PORTC, PORTC1 // Deshabilitando pull-up para PC1
CBI PORTC, PORTC2 // Deshabilitando pull-up para PC2
CBI PORTC, PORTC3 // Deshabilitando pull-up para PC3
CBI PORTC, PORTC4 // Deshabilitando pull-up para PC4
CBI PORTC, PORTC0 // Deshabilitando pull-up para PC4

//CONFIGURAR PORTD COMO SALIDA

LDI R16, 0xFF
OUT DDRD, R16
LDI R16, 0x00
OUT PORTD, R16


//SALIDAS  PC5, PB0,PB1, PB2, PB3, PB4, PB5

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


IN R16, PINC
ANDI R16, 0b00011111   ; M?scara: PC1, PC2, PC3, PC4
STS VAR_PINC_PREV, R16

;========================================
; Habilitar el grupo PCIE1 (Puerto C)
;========================================

    LDI R17, (1 << PCIE1)
    STS PCICR, R17

    // Habilitar espec?ficamente los pines PCINT11 (PC3) y PCINT12 (PC4)
    LDI R17, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)|(1<<PCINT12)
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
	
	dispON_OFF: .DB 0x40, 0x48, 0x0E, 0x00
	

	// D?as m?ximos de cada mes (El primer 0 es relleno para el mes 0)
	tabla_meses_u: .DB 0x00, 0x42, 0x39, 0x42, 0x41, 0x42, 0x41, 0x42, 0x42, 0x41, 0x42, 0x41, 0x42, 0x00
	
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

	RCALL ACTUALIZAR_MES
	
	CPI MODE, 0b000
	BREQ MODO_HORA
	
	CPI MODE, 0b001
	BREQ MODE_FECHA
	
	CPI MODE, 0b010
	BREQ CONFIGURAR_HORA
	
	CPI MODE, 0b011
	BREQ CONFIGURAR_FECHA1
	
	CPI MODE, 0b100
	BREQ CONFIGURAR_ALARMA1
	RJMP MAIN_LOOP
	
	CONFIGURAR_FECHA1:
		JMP CONFIGURAR_FECHA
	CONFIGURAR_ALARMA1:
		JMP CONFIGURAR_ALARMA
MODO_HORA:
    CBI PORTB, PORTB5    ; apaga LED fecha
    SBI PORTB, PORTB4    ; enciende LED hora
    RJMP MAIN_LOOP

MODE_FECHA:
    CBI PORTB, PORTB4    ; apaga LED hora
    SBI PORTB, PORTB5    ; enciende LED fecha
    RJMP MAIN_LOOP


CONFIGURAR_HORA:
    CBI PORTB, PORTB5    ; apaga LED fecha
    SBI PORTB, PORTB4    ; enciende LED hora
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

	JMP CONFIGURAR_VAR_HORAS_D

	CONFIGURAR_VAR_MINUTOS_U:
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
		CPI BANDERA, 2
		BREQ INC_VAR_HORAS_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_HORAS_UNI

		RJMP SALIR_CONFIGURAR_HORA

			INC_VAR_HORAS_UNI:
			CLR BANDERA
			LDS R16, VAR_HORAS_U
			LDS R17, VAR_HORAS_D
			CPI R17, 2
			BREQ INC_VAR_HORAS_UNI_2
			INC R16 
			CPI R16, 10
			BRNE STS_HORAS_U      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			RJMP STS_HORAS_U

			INC_VAR_HORAS_UNI_2:
			INC R16 
			CPI R16, 4
			BRNE STS_HORAS_U      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			RJMP STS_HORAS_U

			STS_HORAS_U:
				STS VAR_HORAS_U, R16  
			RJMP SALIR_CONFIGURAR_HORA

			DEC_VAR_HORAS_UNI:
			    CLR BANDERA
			    LDS R16, VAR_HORAS_U
			    DEC R16
			    CPI R16, 0xFF              
			    BRNE SALIR_DEC_VAR_HORAS_UNI
			
			    ; underflow → valor depende de la decena
			    LDS R17, VAR_HORAS_D
			    CPI R17, 2
			    BREQ DEC_HORAS_UNI_ES2
			    LDI R16, 9              ; decena 0 o 1 → unidad máx es 9
			    RJMP SALIR_DEC_VAR_HORAS_UNI
			    DEC_HORAS_UNI_ES2:
			    LDI R16, 3              ; decena 2 → unidad máx es 3
			
			    SALIR_DEC_VAR_HORAS_UNI:
			    STS VAR_HORAS_U, R16
			RJMP SALIR_CONFIGURAR_HORA


	CONFIGURAR_VAR_HORAS_D:

			CPI BANDERA, 2
			BREQ INC_VAR_HORAS_DEC
			CPI BANDERA, 1
			BREQ DEC_VAR_HORAS_DEC
			RJMP SALIR_CONFIGURAR_HORA
	
			INC_VAR_HORAS_DEC:
				CLR BANDERA
				LDS R16, VAR_HORAS_D
				INC R16 
				CPI R16, 3
				BRNE STS_HORAS_D      ; si NO es 6 → salta directo a guardar
				CLR R16                 ; si ES 6 → limpia
				STS_HORAS_D:
					STS VAR_HORAS_D, R16 

				CPI R16, 2	
				BRNE SALIR_DEC_CHECK
				LDS R16, VAR_HORAS_U
				CPI R16, 4
				BRLO SALIR_DEC_CHECK
				LDI R16, 3
				STS VAR_HORAS_U, R16
				SALIR_DEC_CHECK:					 
			RJMP SALIR_CONFIGURAR_HORA
		 
			DEC_VAR_HORAS_DEC:
			    CLR BANDERA
			    LDS R16, VAR_HORAS_D
			    DEC R16
			    CPI R16, 0xFF              
			    BRNE STS_HORAS_D_DEC
			    LDI R16, 2              ; underflow → regresa a 2
			
			    STS_HORAS_D_DEC:
			        STS VAR_HORAS_D, R16
			
			    ; Si decena quedó en 2, verificar que unidad no sea > 3
			    CPI R16, 2
			    BRNE SALIR_DEC_HORAS_D
			    LDS R16, VAR_HORAS_U
			    CPI R16, 4
			    BRLO SALIR_DEC_HORAS_D  ; si unidad < 4 está bien
			    LDI R16, 3              ; si unidad >= 4 → forzar a 3
			    STS VAR_HORAS_U, R16

			SALIR_DEC_HORAS_D:
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


	//******************************************************************

CONFIGURAR_FECHA: 
    CBI PORTB, PORTB4
    SBI PORTB, PORTB5

	RCALL VALIDAR_DIA_MES 
    LDS R16, TCCR0B
    ANDI R16, 0xF8
    ORI R16, (1<<CS02)
    STS TCCR0B, R16

    SELECCION_DISP_CONFIGURAR_FECHA:
		RCALL VALIDAR_DIA_MES
        CPI CONFIGURACION, 0
        BREQ CONFIGURAR_VAR_MES_U
        CPI CONFIGURACION, 1
        BREQ CONFIGURAR_VAR_MES_D1
		
        CPI CONFIGURACION, 2
        BREQ CONFIGURAR_VAR_DIA_U1
        RJMP CONFIGURAR_VAR_DIA_D

        CONFIGURAR_VAR_DIA_U1:
            JMP CONFIGURAR_VAR_DIA_U

		CONFIGURAR_VAR_MES_D1:
			JMP CONFIGURAR_VAR_MES_D

    ;========================================
    ; DISPLAY PB0 = Unidades Mes (CONFIGURACION=0)
    ;========================================
    CONFIGURAR_VAR_MES_U:
    CPI BANDERA, 2
    BREQ INC_VAR_MES_UNI
    CPI BANDERA, 1
    BREQ DEC_VAR_MES_UNI
    RJMP SALIR_CONFIGURAR_FECHA

INC_VAR_MES_UNI:
    CLR BANDERA
	RCALL VALIDAR_DIA_MES
    ; Verificar si ya es mes 12 (decena=1, unidad=2)
    LDS R16, VAR_MES_U
    LDS R17, VAR_MES_D
    CPI R17, 1

    BRNE INC_MES_NORMAL

    INC R16
	CPI R16, 3
	BRNE STS_VAR_MES_U
	CLR R16
	RJMP STS_VAR_MES_U

INC_MES_NORMAL:
    INC R16
    CPI R16, 10
    BRNE STS_VAR_MES_U



    LDI R16, 1
	                
	RJMP STS_VAR_MES_U

STS_VAR_MES_U:
    STS VAR_MES_U, R16
	RCALL ACTUALIZAR_MES
	RCALL VALIDAR_DIA_MES
    RJMP SALIR_CONFIGURAR_FECHA


DEC_VAR_MES_UNI:
    CLR BANDERA
	RCALL VALIDAR_DIA_MES
    LDS R16, VAR_MES_U
    LDS R17, VAR_MES_D

    CPI R17, 1
    BRNE DEC_MES_NORMAL
	
	DEC R16
	CPI R16, 0xFF
	BRNE DEC_MES_GUARDAR
	LDI R16, 2
	RJMP DEC_MES_GUARDAR


DEC_MES_NORMAL:
    DEC R16
    CPI R16, 0
    BRNE DEC_MES_GUARDAR
    LDI R16, 9


DEC_MES_GUARDAR:
    STS VAR_MES_U, R16
	RCALL ACTUALIZAR_MES
	RCALL VALIDAR_DIA_MES
    RJMP SALIR_CONFIGURAR_FECHA



    ;========================================
    ; DISPLAY PB1 = Decenas Mes (CONFIGURACION=1)
    ;========================================
    CONFIGURAR_VAR_MES_D:
	RCALL VALIDAR_DIA_MES 

        CPI BANDERA, 2
        BREQ INC_VAR_MES_DEC
        CPI BANDERA, 1
        BREQ DEC_VAR_MES_DEC
        RJMP SALIR_CONFIGURAR_FECHA

        INC_VAR_MES_DEC:
            CLR BANDERA
			RCALL VALIDAR_DIA_MES

            LDS R16, VAR_MES_D
			LDS R17, VAR_MES_U
            INC R16

			CPI R16, 1
			BREQ INC_VAR_MES_DECENAS
            CPI R16,2
			BRNE STS_VAR_MES_D
            CLR R16  
			RJMP STS_VAR_MES_D

			INC_VAR_MES_DECENAS:
				CPI R17, 3

			    BRLO STS_VAR_MES_D
				LDI R17, 2
				STS VAR_MES_U, R17
				RJMP STS_VAR_MES_D

				STS_VAR_MES_D:
				STS VAR_MES_D, R16
				RCALL ACTUALIZAR_MES
				RCALL VALIDAR_DIA_MES
              RJMP SALIR_CONFIGURAR_FECHA

        DEC_VAR_MES_DEC:
            CLR BANDERA
			RCALL VALIDAR_DIA_MES
            LDS R16, VAR_MES_D
            DEC R16
            CPI R16, 0xFF
            BRNE STS_VAR_MES_DEC

            LDI R16, 1              ; underflow → wrap a 1
			LDS R17, VAR_MES_U
			CPI R17, 3
			BRLO STS_VAR_MES_DEC

			LDI R17, 2
			STS VAR_MES_U, R17
			RJMP STS_VAR_MES_DEC

			STS_VAR_MES_DEC:
            STS VAR_MES_D, R16
			RCALL ACTUALIZAR_MES
        RJMP SALIR_CONFIGURAR_FECHA

    ;========================================
    ; DISPLAY PB2 = Unidades Día (CONFIGURACION=2)
    ;========================================
    CONFIGURAR_VAR_DIA_U:
	RCALL VALIDAR_DIA_MES 
        CPI BANDERA, 2
        BREQ INC_VAR_DIA_UNI
        CPI BANDERA, 1
        BREQ DEC_VAR_DIA_UNI
        RJMP SALIR_CONFIGURAR_FECHA

INC_VAR_DIA_UNI:
    CLR BANDERA
	RCALL VALIDAR_DIA_MES
   
	LDS R16, VAR_DIAS_U
	LDS R17, VAR_DIAS_D
	LDS R18, VAR_MES
	SWAP R18
	ANDI R18, 0b00001111
	SUBI R18, 0x010
	
	CP R17, R18
	BREQ REVISAR_ULTIMO_DIA_MES

	INC R16
	CPI R16, 10
	BRNE STS_VAR_DIAS_UNIDAD
	LDI R16, 0
	RJMP STS_VAR_DIAS_UNIDAD


	REVISAR_ULTIMO_DIA_MES:
	INC R16
	LDS R18, VAR_MES
	ANDI R18, 0b00001111

	CP R16, R18
	BREQ ES_ULTIMO_DIA

	RJMP STS_VAR_DIAS_UNIDAD

	ES_ULTIMO_DIA:
	LDI R16, 0
	RJMP STS_VAR_DIAS_UNIDAD



	STS_VAR_DIAS_UNIDAD:
	STS VAR_DIAS_U, R16
	RCALL VALIDAR_DIA_MES
    RJMP SALIR_CONFIGURAR_FECHA

DEC_VAR_DIA_UNI:
	
            CLR BANDERA
            
			LDS R16, VAR_DIAS_U
			LDS R17, VAR_DIAS_D
			LDS R18, VAR_MES

			DEC R16

			CPI R16, 0xFF
			BREQ DEC_VAR_DIAS_U_ESMENOR0

			RJMP DEC_STS_VAR_DIAS_UNIDADES

			
			DEC_VAR_DIAS_U_ESMENOR0:
			ANDI R18, 0b11110000
			SWAP R18
			SUBI R18, 0x01
			CP R17, R18
			BREQ DECENAS_ESTA_EN_LIMITE
			LDI R16, 9
			RJMP DEC_STS_VAR_DIAS_UNIDADES


			


			DECENAS_ESTA_EN_LIMITE:
			LDS R18, VAR_MES
			ANDI R18, 0b00001111
			SUBI R18, 0x01
			MOV R16, R18
			
			RJMP DEC_STS_VAR_DIAS_UNIDADES

	DEC_STS_VAR_DIAS_UNIDADES:
	STS VAR_DIAS_U, R16
	RCALL VALIDAR_DIA_MES
    RJMP SALIR_CONFIGURAR_FECHA

    ;========================================
    ; DISPLAY PB3 = Decenas Día (CONFIGURACION=3)
    ;========================================
    CONFIGURAR_VAR_DIA_D:
	RCALL VALIDAR_DIA_MES 
        CPI BANDERA, 2
        BREQ INC_VAR_DIA_DEC
        CPI BANDERA, 1
        BREQ DEC_VAR_DIA_DEC
        RJMP SALIR_CONFIGURAR_FECHA

        INC_VAR_DIA_DEC:
            CLR BANDERA

			LDS R16, VAR_DIAS_D
			LDS R17, VAR_DIAS_U
			LDS R18, VAR_MES
			ANDI R18, 0b11110000
			SWAP R18

			INC R16


			CP R16, R18
			BREQ ES_ULTIMO_DIA_DECENA

			SUBI R18, 0x01
			CP R16, R18
			BREQ ES_LIMITE_MES

			RJMP STS_VAR_DIAS_DECENAS

			ES_LIMITE_MES:
			LDS R18, VAR_MES
			ANDI R18, 0b00001111
			CP R17, R18
			BRLO STS_VAR_DIAS_DECENAS
			SUBI R18, 0x01
			MOV R17, R18
			RJMP STS_VAR_DIAS_DECENAS
			
			ES_ULTIMO_DIA_DECENA:
			CLR R16
			RJMP STS_VAR_DIAS_DECENAS



			STS_VAR_DIAS_DECENAS:
			STS VAR_DIAS_D, R16
			RCALL VALIDAR_DIA_MES

        RJMP SALIR_CONFIGURAR_FECHA

        DEC_VAR_DIA_DEC:
            CLR BANDERA
            
			LDS R16, VAR_DIAS_D
			LDS R17, VAR_DIAS_U
			LDS R18, VAR_MES

			DEC R16

			CPI R16, 0xFF
			BREQ DEC_VAR_DIAS_ESMENOR0

			RJMP DEC_STS_VAR_DIAS_DECENAS

			
			DEC_VAR_DIAS_ESMENOR0:
			ANDI R18, 0b11110000
			SWAP R18
			SUBI R18, 0x01
			MOV R16, R18
			LDS R18, VAR_MES
			ANDI R18, 0b00001111
			CP R17, R18
			BRLO DEC_STS_VAR_DIAS_DECENAS
			SUBI R18, 0x01
			MOV R17, R18
			STS VAR_DIAS_U, R17
			RJMP DEC_STS_VAR_DIAS_DECENAS


			DEC_STS_VAR_DIAS_DECENAS:
			STS VAR_DIAS_D, R16
			RCALL VALIDAR_DIA_MES

        RJMP SALIR_CONFIGURAR_FECHA


    ;========================================
   SALIR_CONFIGURAR_FECHA:
		RCALL VALIDAR_DIA_MES
        CPI MODE, 0b011
        BRNE SALIR_MODE_S3
        JMP SELECCION_DISP_CONFIGURAR_FECHA

        SALIR_MODE_S3:
        LDS R16, TCCR0B
        ANDI R16, 0xF8
        ORI R16, (1<<CS01)|(1<<CS00)
        STS TCCR0B, R16

        JMP MAIN_LOOP


CONFIGURAR_ALARMA:
	    CBI PORTB, PORTB5    ; apaga LED fecha
		SBI PORTB, PORTB4    ; enciende LED hora

	; Prescaler 256 ? m�s lento ? parpadeo visible
	LDS R16, TCCR0B
	ANDI R16, 0xF8          ; limpiar bits CS02, CS01, CS00
	ORI R16, (1<<CS02)      ; prescaler 256
	STS TCCR0B, R16
	
	SELECCION_DISP_CONFIGURAR_ALARMA:
	CPI CONFIGURACION, 0
	BREQ CONFIGURAR_VAR_ALARMA_MINUTOS_U

	CPI CONFIGURACION, 1
	BREQ CONFIGURAR_VAR_ALARMA_MINUTOS_D	

	CPI CONFIGURACION, 2
	BREQ CONFIGURAR_VAR_ALARMA_HORAS_U

	JMP CONFIGURAR_VAR_ALARMA_HORAS_D

	CONFIGURAR_VAR_ALARMA_MINUTOS_U:
		CPI BANDERA, 2
		BREQ INC_VAR_ALARMA_MINUTOS_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_ALARMA_MINUTOS_UNI

		RJMP SALIR_CONFIGURAR_ALARMA

		INC_VAR_ALARMA_MINUTOS_UNI:
			CLR BANDERA
			LDS R16, VAR_ALARMA_MINUTOS_U
			INC R16 
			CPI R16, 10
			BRNE STS_MINUTOS_U_ALARMA      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			STS_MINUTOS_U_ALARMA:
				STS VAR_ALARMA_MINUTOS_U, R16  
		RJMP SALIR_CONFIGURAR_ALARMA

		DEC_VAR_ALARMA_MINUTOS_UNI:
			CLR BANDERA
			LDS R16, VAR_ALARMA_MINUTOS_U
			DEC R16 
			CPI R16, 0xFF             
			BRNE SALIR_DEC_VAR_ALARMA_MINUTOS_UNI    
			LDI R16, 9
			SALIR_DEC_VAR_ALARMA_MINUTOS_UNI:
				STS VAR_ALARMA_MINUTOS_U, R16  
		RJMP SALIR_CONFIGURAR_ALARMA


	CONFIGURAR_VAR_ALARMA_MINUTOS_D:

		CPI BANDERA, 2
		BREQ INC_VAR_ALARMA_MINUTOS_DEC
		CPI BANDERA, 1
		BREQ DEC_VAR_ALARMA_MINUTOS_DEC
		RJMP SALIR_CONFIGURAR_ALARMA
	
		INC_VAR_ALARMA_MINUTOS_DEC:
			CLR BANDERA

			LDS R16, VAR_ALARMA_MINUTOS_D
			INC R16             
			CPI R16, 6
			BRNE STS_MINUTOS_D_ALARMA     ; si NO es 6 → salta directo a guardar
			CLR R16                 ; si ES 6 → limpia
			STS_MINUTOS_D_ALARMA:
				STS VAR_ALARMA_MINUTOS_D, R16  ; guarda en ambos casos
				 
		RJMP SALIR_CONFIGURAR_ALARMA
	

		DEC_VAR_ALARMA_MINUTOS_DEC:
			CLR BANDERA

			LDS R16, VAR_ALARMA_MINUTOS_D
			DEC R16 
			CPI R16, 0xFF             
			BRNE SALIR_DEC_VAR_ALARMA_MINUTOS_DEC   
			LDI R16, 5
			SALIR_DEC_VAR_ALARMA_MINUTOS_DEC:
				STS VAR_ALARMA_MINUTOS_D, R16  
	
		RJMP SALIR_CONFIGURAR_ALARMA
	
	

	CONFIGURAR_VAR_ALARMA_HORAS_U:
		CPI BANDERA, 2
		BREQ INC_VAR_ALARMA_HORAS_UNI

		CPI BANDERA, 1
		BREQ DEC_VAR_ALARMA_HORAS_UNI

		RJMP SALIR_CONFIGURAR_ALARMA

			INC_VAR_ALARMA_HORAS_UNI:
			CLR BANDERA
			LDS R16, VAR_ALARMA_HORAS_U
			LDS R17, VAR_ALARMA_HORAS_D
			CPI R17, 2
			BREQ INC_VAR_ALARMA_HORAS_UNI_2
			INC R16 
			CPI R16, 10
			BRNE STS_HORAS_U_ALARMA      ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			RJMP STS_HORAS_U_ALARMA

			INC_VAR_ALARMA_HORAS_UNI_2:
			INC R16 
			CPI R16, 4
			BRNE STS_HORAS_U_ALARMA     ; si NO es 10 → salta directo a guardar
			CLR R16                 ; si ES 10 → limpia
			RJMP STS_HORAS_U_ALARMA

			STS_HORAS_U_ALARMA:
				STS VAR_ALARMA_HORAS_U, R16  
			RJMP SALIR_CONFIGURAR_ALARMA

			DEC_VAR_ALARMA_HORAS_UNI:
			    CLR BANDERA
			    LDS R16, VAR_ALARMA_HORAS_U
			    DEC R16
			    CPI R16, 0xFF              
			    BRNE SALIR_DEC_VAR_ALARMA_HORAS_UNI
			
			    ; underflow → valor depende de la decena
			    LDS R17, VAR_ALARMA_HORAS_D
			    CPI R17, 2
			    BREQ DEC_HORAS_UNI_ES2_ALARMA
			    LDI R16, 9              ; decena 0 o 1 → unidad máx es 9
			    RJMP SALIR_DEC_VAR_ALARMA_HORAS_UNI
			    DEC_HORAS_UNI_ES2_ALARMA:
			    LDI R16, 3              ; decena 2 → unidad máx es 3
			
			    SALIR_DEC_VAR_ALARMA_HORAS_UNI:
			    STS VAR_ALARMA_HORAS_U, R16
			RJMP SALIR_CONFIGURAR_ALARMA


	CONFIGURAR_VAR_ALARMA_HORAS_D:

			CPI BANDERA, 2
			BREQ INC_VAR_ALARMA_HORAS_DEC
			CPI BANDERA, 1
			BREQ DEC_VAR_ALARMA_HORAS_DEC
			RJMP SALIR_CONFIGURAR_ALARMA
	
			INC_VAR_ALARMA_HORAS_DEC:
				CLR BANDERA
				LDS R16, VAR_ALARMA_HORAS_D
				INC R16 
				CPI R16, 3
				BRNE STS_HORAS_D_ALARMA     ; si NO es 6 → salta directo a guardar
				CLR R16                 ; si ES 6 → limpia
				STS_HORAS_D_ALARMA:
					STS VAR_ALARMA_HORAS_D, R16 

				CPI R16, 2	
				BRNE SALIR_DEC_CHECK_ALARMA
				LDS R16, VAR_ALARMA_HORAS_U
				CPI R16, 4
				BRLO SALIR_DEC_CHECK_ALARMA
				LDI R16, 3
				STS VAR_ALARMA_HORAS_U, R16
				SALIR_DEC_CHECK_ALARMA:					 
			RJMP SALIR_CONFIGURAR_ALARMA
		 
			DEC_VAR_ALARMA_HORAS_DEC:
			    CLR BANDERA
			    LDS R16, VAR_ALARMA_HORAS_D
			    DEC R16
			    CPI R16, 0xFF              
			    BRNE STS_HORAS_D_DEC_ALARMA
			    LDI R16, 2              ; underflow → regresa a 2
			
			    STS_HORAS_D_DEC_ALARMA:
			        STS VAR_ALARMA_HORAS_D, R16
			
			    ; Si decena quedó en 2, verificar que unidad no sea > 3
			    CPI R16, 2
			    BRNE SALIR_DEC_HORAS_D_ALARMA
			    LDS R16, VAR_ALARMA_HORAS_U
			    CPI R16, 4
			    BRLO SALIR_DEC_HORAS_D_ALARMA  ; si unidad < 4 está bien
			    LDI R16, 3              ; si unidad >= 4 → forzar a 3
			    STS VAR_ALARMA_HORAS_U, R16

			SALIR_DEC_HORAS_D_ALARMA:
		RJMP SALIR_CONFIGURAR_ALARMA


	SALIR_CONFIGURAR_ALARMA:

	CPI MODE, 0b100
	BRNE SALIR_MODE_S4
	JMP SELECCION_DISP_CONFIGURAR_ALARMA

	SALIR_MODE_S4:

	; Prescaler 64 ? velocidad normal (tu configuraci�n original)
	LDS R16, TCCR0B
	ANDI R16, 0xF8
	ORI R16, (1<<CS01)|(1<<CS00)    ; prescaler 64
	STS TCCR0B, R16
	RJMP MAIN_LOOP


ACTUALIZAR_MES:
   ; Guardar registros que modificamos
    PUSH R0          ; ← AGREGAR
    PUSH R1          ; ← AGREGAR
    PUSH R16
    PUSH R17
    PUSH R18
	LDS R17, VAR_MES_D
	LDS R16, VAR_MES_U
	LDI R18, 10

	MUL R17, R18
	ADD R0, R16

	MOV R16, R0
	CLR R1

	LDI ZH, HIGH(tabla_meses_u<<1)
	LDI ZL, LOW(tabla_meses_u<<1)
	ADD ZL, R16
	ADC ZH, R1              ; R1 es 0
	LPM R17, Z
	
	STS VAR_MES, R17
	
	POP R18
    POP R17
    POP R16
    POP R1           ; ← AGREGAR
    POP R0 
	RET

VALIDAR_DIA_MES:  
	LDS R17, VAR_MES
	LDS R18, VAR_DIAS_D
	LDS R16, VAR_DIAS_U
	SWAP R18
	OR R18, R16
	CP R18, R17
	BRLO SALIR_VALIDAR_DIA_MES

	LDS R16, VAR_MES
	ANDI R16, 0b00001111
	SUBI R16, 0x01
	STS  VAR_DIAS_U, R16

	ANDI R17, 0b11110000
	SUBI R17, 0x10
	SWAP R17
	STS VAR_DIAS_D, R17

	SALIR_VALIDAR_DIA_MES:
	   RET


///****************************************/
//// Interrupt routines
///****************************************/

// Interrupcion por PINC
ISR_PCINT1:
    PUSH R16
    PUSH R17
    IN R16, SREG
    PUSH R16

	
   ; ---- DELAY ANTIREBOTE SOFTWARE (~15ms) ----
    PUSH R18
    PUSH R19
    LDI R18, 250
_dbnc_outer:
    LDI R19, 100
_dbnc_inner:
    DEC R19
    BRNE _dbnc_inner
    DEC R18 
    BRNE _dbnc_outer
    POP R19
    POP R18
    ; -------------------------------------------

	//Leer estado actual de PINC (solo pines de inter?s)
    IN R16, PINC
    ANDI R16, 0b00011111        ; M?scara PC1, PC2, PC3, PC4

    // Cargar estado anterior
    LDS R17, VAR_PINC_PREV

    // Detectar flancos de subida: bits que eran 0 y ahora son 1
    // flanco_subida = (~prev) & actual
    COM R17                     ; NOT del estado anterior
    AND R17, R16                ; AND con estado actual ? solo flancos de subida

    ; Guardar nuevo estado como "anterior" para la pr?xima vez
    IN R16, PINC
    ANDI R16, 0b00011111 
    STS VAR_PINC_PREV, R16
	
	; Verificar qu? pin tuvo flanco de subida
    SBRC R17, PC1
    RJMP PRESSMODO

    SBRC R17, PC2
    RJMP PRESSALARMA

    SBRC R17, PC3
    RJMP PRESSMENOS

    SBRC R17, PC4
    RJMP PRESSMAS

    SBRC R17, PC0
    RJMP PRESSCONFIGURACION
		
	RJMP SALIR_ISR_PINC


	PRESSCONFIGURACION:
	CPI MODE, 0b101
	BREQ TOGGLE_ALARMA_ESTADO

		INC CONFIGURACION
		CPI CONFIGURACION, 4
		BRNE SALIR_ISR_PINC
		CLR CONFIGURACION
		RJMP SALIR_ISR_PINC

	TOGGLE_ALARMA_ESTADO:
		LDS R16, VAR_ALARMA_ESTADO
		LDI R17, 1
		EOR R16, R17                    ; Hace XOR con 1 (cambia 0 a 1 y 1 a 0)
		STS VAR_ALARMA_ESTADO, R16
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
		RJMP SALIR_ISR_PINC

	PRESSMENOS:
		LDI BANDERA, 1
		RJMP SALIR_ISR_PINC

	PRESSMAS:
		LDI BANDERA, 2
		RJMP SALIR_ISR_PINC


    SALIR_ISR_PINC:
    POP R16
    OUT SREG, R16
    POP R17
    POP R16
    RETI



//Interrupcion por Timer1

TMIER1_COMPA:
    // Guardar contexto
	PUSH R0          ; ← AGREGAR
    PUSH R1          ; ← AGREGAR
	PUSH R16
	PUSH R17
	IN R16, SREG
	PUSH R16
	PUSH R18

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

		LDS R16, VAR_DIAS_U
		INC R16
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
	POP R18
	POP R16
	OUT SREG, R16
	POP R17
	POP R16
	POP R1           ; ← AGREGAR
    POP R0           ; ← AGREGAR
	// Salir de Interrupcion
    RETI


//Interrupcion por Timer0

TIMER0_OVF:
    // Guardar contexto
	PUSH R16
	PUSH R17
	IN R16, SREG
	PUSH R16
	PUSH R18

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
	BREQ MODO_alarma

	CPI MODE, 0b101
	BREQ MODO_letras

	CPI MODE, 0b110
	BREQ MODO_alarma

	MODO_alarma:
		
		CPI DPLY_ENCENDIDO, 0
		BREQ Cargar_MinA_U
		CPI DPLY_ENCENDIDO, 1
		BREQ Cargar_MinA_D
		CPI DPLY_ENCENDIDO, 2
		BREQ Cargar_HoraA_U
    
		Cargar_HoraA_D:
			LDS R16, VAR_ALARMA_HORAS_D
			RJMP Dibujar_Numero
		Cargar_HoraA_U:
			LDS R16, VAR_ALARMA_HORAS_U 
			RJMP Dibujar_Numero
		Cargar_MinA_D:
			LDS R16, VAR_ALARMA_MINUTOS_D 
			RJMP Dibujar_Numero
		Cargar_MinA_U:
	    	LDS R16, VAR_ALARMA_MINUTOS_U 
			RJMP Dibujar_Numero
			

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
        CPI DPLY_ENCENDIDO, 0
        BREQ Cargar_Mes_U       ; PB0 = Unidades Mes
        CPI DPLY_ENCENDIDO, 1
        BREQ Cargar_Mes_D       ; PB1 = Decenas Mes
        CPI DPLY_ENCENDIDO, 2
        BREQ Cargar_Dia_U       ; PB2 = Unidades Día
        
        Cargar_Dia_D:           ; PB3 = Decenas Día
            LDS R16, VAR_DIAS_D 
            RJMP Dibujar_Numero
        Cargar_Dia_U:
            LDS R16, VAR_DIAS_U 
            RJMP Dibujar_Numero
        Cargar_Mes_D:
            LDS R16, VAR_MES_D 
            RJMP Dibujar_Numero
        Cargar_Mes_U:
            LDS R16, VAR_MES_U 
            RJMP Dibujar_Numero

	MODO_letras:
		LDS R16, VAR_ALARMA_ESTADO
		CPI R16, 1
		BREQ MODO_letras_ON

	MODO_letras_OFF:
		; Alarma apagada: Solo encender DPLY 3 (letra O) y DPLY 2 (letra F)
		CPI DPLY_ENCENDIDO, 3
		BREQ Cargar_O
		CPI DPLY_ENCENDIDO, 2
		BREQ Cargar_F
		RJMP Salir_Timer0      ; Si el barrido va en 0 o 1, salir dejando apagado

	MODO_letras_ON:
		; Alarma encendida: Solo encender DPLY 1 (letra O) y DPLY 0 (letra N)
		CPI DPLY_ENCENDIDO, 1
		BREQ Cargar_O
		CPI DPLY_ENCENDIDO, 0
		BREQ Cargar_N
		RJMP Salir_Timer0      ; Si el barrido va en 2 o 3, salir dejando apagado

		Cargar_F:
			LDI R16, 2
			RJMP Ejecutar_Letra

		Cargar_O:
			LDI R16, 0
			RJMP Ejecutar_Letra

		Cargar_N:
			LDI R16, 1
			RJMP Ejecutar_Letra

		Ejecutar_Letra:
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
		POP R18
		POP R16
		OUT SREG, R16
		POP R17
		POP R16

		// Salir de Interrupcion
		RETI
