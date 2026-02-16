;=========================================
; TIMER0 Overflow - ATmega328P
; Fclk = 2 MHz
; Prescaler = 1024
; Overflow ? 131 ms
; Salidas: PB0–PB3
;=========================================

.INCLUDE "m328pdef.inc"

.ORG 0x0000
    RJMP RESET

.ORG 0x0020          ; Vector TIMER0 OVF
    RJMP TIMER0_OVF

;=========================================
RESET:
    ; Configurar Stack Pointer
    LDI R16, HIGH(RAMEND)
    OUT SPH, R16
    LDI R16, LOW(RAMEND)
    OUT SPL, R16

    ; Configurar PB0-PB3 como salida
    LDI R16, 0x0F        ; 00001111
    OUT DDRB, R16
	LDI R16, (1<<CLKPCE)
	STS CLKPR, R16
	LDI R16, 0b00000011    ; CLKPS = 0011 ? divide entre 8
	STS CLKPR, R16
    ;=============================
    ; CONFIGURAR TIMER0
    ;=============================

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
	CLR R18
MAIN:
	
    RJMP MAIN

;=========================================
; INTERRUPCIÓN TIMER0 OVERFLOW
;=========================================

TIMER0_OVF:
    ; Guardar contexto
    PUSH R16
    IN   R16, SREG
    PUSH R16
	; Recargar 60 para mantener 100 ms
    LDI  R16, 60
    OUT  TCNT0, R16

    ; Toggle PB0-PB3
	DEC  R17          ; Decrementar contador
    BRNE REGRESAR		   ; Si no es 0, salir
    LDI  R17, 10
	INC R18
	OUT PORTB, R18
	CLR R16
    ; Restaurar contexto
	REGRESAR:
    POP  R16
    OUT  SREG, R16
    POP  R16

    RETI
