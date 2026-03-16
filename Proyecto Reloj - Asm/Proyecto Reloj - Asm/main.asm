/*
* PROYECTO 1 - RELOJ.asm
*
* Creado: 16/03/2026 - 12:00
* Autor : Abner Quiej
* Descripción: Implementación de un reloj digital de 24 horas con microcontrolador
* ATmega328P. Utiliza displays de 7 segmentos multiplexados.
* Muestra hora, fecha (DD/MM) y cuenta con una alarma configurable
* con un zumbador pasivo. Usa botones con antirrebote por software.
*/
/****************************************/
// Encabezado (Definición de Registros, Variables y Constantes)
.include "M328PDEF.inc"     // Incluye las definiciones específicas del ATmega328P

// --- Nombres amigables para los registros ---
.def DPLY_ENCENDIDO     = R21   // Guarda qué display está encendido actualmente (0 a 3)
.def BANDERA            = R19   // Bandera para saber si se presionó el botón MAS (2) o MENOS (1)
.def SEGUNDOS           = R20   // Contador de los segundos reales (0 a 59)
.def MODE               = R22   // Modo actual del reloj (Hora, Fecha, Configurar, Alarma, etc.)
.def INDICE             = R23   // Índice de uso general
.def CONFIGURACION      = R24   // Indica qué dígito se está configurando (0=Min U, 1=Min D, etc.)

.def MOSTRAR_DIPLAY     = R3    // Registro de apoyo
.def NumDias            = R4    // Registro de apoyo para cálculos de días

// --- Constantes ---
.equ VELOCIDAD = 15625          // Valor para que el Timer1 cuente exactamente 1 segundo (con prescaler 1024)
.equ MAX_MODES = 7              // Límite de modos del sistema (0 a 6)

// --- Memoria RAM (Variables dinámicas) ---
.dseg
.org    SRAM_START
    VAR_MINUTOS_U:          .byte 1  // Unidades de minutos del reloj
    VAR_MINUTOS_D:          .byte 1  // Decenas de minutos del reloj
    VAR_HORAS_U:            .byte 1  // Unidades de horas del reloj
    VAR_HORAS_D:            .byte 1  // Decenas de horas del reloj
    VAR_DIAS_U:             .byte 1  // Unidades del día actual
    VAR_DIAS_D:             .byte 1  // Decenas del día actual
    VAR_MES_U:              .byte 1  // Unidades del mes actual
    VAR_MES_D:              .byte 1  // Decenas del mes actual
    VAR_ALARMA_HORAS_U:     .byte 1  // Unidades de hora de la alarma
    VAR_ALARMA_HORAS_D:     .byte 1  // Decenas de hora de la alarma
    VAR_ALARMA_MINUTOS_U:   .byte 1  // Unidades de minuto de la alarma
    VAR_ALARMA_MINUTOS_D:   .byte 1  // Decenas de minuto de la alarma
    VAR_MES:                .byte 1  // Límite máximo de días del mes actual
    VAR_PINC_PREV:          .byte 1  // Guarda el estado anterior de los botones para detectar el toque
    VAR_ALARMA_ESTADO:      .byte 1  // 0 = Alarma apagada, 1 = Alarma encendida
    VAR_BLINK_CONT:         .byte 1  // Cronómetro interno para medir la velocidad de parpadeo
    VAR_BLINK_ESTADO:       .byte 1  // Estado del parpadeo (0 = Display Apagado, 1 = Display Encendido)

.cseg
.org 0x0000
    RJMP RESET              // Vector de Reset: Inicia el programa

.org PCI1addr 
    RJMP ISR_PCINT1         // Vector de interrupción para los botones (Puerto C)

.org OC1Aaddr
    RJMP TMIER1_COMPA       // Vector de interrupción del Timer1 (1 segundo)
 
.org OVF0addr
    RJMP TIMER0_OVF         // Vector de interrupción del Timer0 (Multiplexado de displays)

/****************************************/
// Configuración de la pila
RESET:
    LDI     R16, LOW(RAMEND)
    OUT     SPL, R16
    LDI     R16, HIGH(RAMEND)
    OUT     SPH, R16

/****************************************/
// Configuracion MCU
SETUP:
    // --- 1. Inicializar todas las variables en cero o valores por defecto ---
    LDI R16, 0
    STS VAR_MINUTOS_U, R16
    STS VAR_MINUTOS_D, R16
    STS VAR_HORAS_U, R16
    STS VAR_HORAS_D, R16
    CLR SEGUNDOS

    LDI R16, 1
    STS VAR_MES_U, R16          ; El mes inicia en 01
    STS VAR_DIAS_U, R16         ; El día inicia en 01
    STS VAR_MES, R16

    CLR R16
    STS VAR_DIAS_D, R16         ; Decena del día inicia en 0
    STS VAR_MES_D, R16          ; Decena del mes inicia en 0
    STS VAR_ALARMA_HORAS_U, R16
    STS VAR_ALARMA_HORAS_D, R16
    STS VAR_ALARMA_MINUTOS_U, R16
    STS VAR_ALARMA_MINUTOS_D, R16
    STS VAR_ALARMA_ESTADO, R16  ; Alarma apagada por defecto
    STS VAR_BLINK_CONT, R16     ; Limpiar basuras de la SRAM
    STS VAR_BLINK_ESTADO, R16

    // --- 2. Configurar Entradas (Botones) ---
    CBI DDRC, DDC1      ; PC1 como entrada
    CBI DDRC, DDC2      ; PC2 como entrada
    CBI DDRC, DDC3      ; PC3 como entrada
    CBI DDRC, DDC4      ; PC4 como entrada
    CBI DDRC, DDC0      ; PC0 como entrada

    CBI PORTC, PORTC1   ; Deshabilitar resistencias pull-up (usaremos externas)
    CBI PORTC, PORTC2   
    CBI PORTC, PORTC3   
    CBI PORTC, PORTC4   
    CBI PORTC, PORTC0   

    // --- 3. Configurar Salidas (Displays y LEDs) ---
    LDI R16, 0xFF
    OUT DDRD, R16       ; Todo el Puerto D como salida (Segmentos del Display)
    LDI R16, 0x00
    OUT PORTD, R16      ; Iniciar apagados

    SBI DDRC, DDC5      ; PC5 como salida (Zumbador)
    SBI DDRB, DDB0      ; PB0 a PB3 como salidas (Transistores de cada display)
    SBI DDRB, DDB1      
    SBI DDRB, DDB2      
    SBI DDRB, DDB3      
    SBI DDRB, DDB4      ; PB4 salida (LED indicador de Hora)
    SBI DDRB, DDB5      ; PB5 salida (LED indicador de Fecha)

    CBI PORTC, PORTC5   ; Iniciar salidas en estado bajo (apagadas)
    CBI PORTB, PORTB0   
    CBI PORTB, PORTB1   
    CBI PORTB, PORTB2   
    CBI PORTB, PORTB3   
    CBI PORTB, PORTB4   
    CBI PORTB, PORTB5   

    // Guardar el estado inicial de los botones para la interrupción
    IN R16, PINC
    ANDI R16, 0b00011111   
    STS VAR_PINC_PREV, R16

    // --- 4. Habilitar interrupciones de cambio de pin (PCINT) ---
    LDI R17, (1 << PCIE1)
    STS PCICR, R17
    ; Habilitar los pines PC0 a PC4 para que generen interrupción al presionarlos
    LDI R17, (1<<PCINT8)|(1<<PCINT9)|(1<<PCINT10)|(1<<PCINT11)|(1<<PCINT12)
    STS PCMSK1, R17

    // --- 5. Configurar Timer0 (Barrido Rápido / Multiplexado) ---
    LDI R16, 0x00
    OUT TCCR0A, R16             ; Modo Normal
    LDI R16, 99
    OUT TCNT0, R16              ; Iniciar contador en 99
    CLR R16
    LDI R16, (1<<CS01)|(1<<CS00); Prescaler a 64 (velocidad rápida para que el ojo no note el parpadeo)
    OUT TCCR0B, R16
    LDI R16, (1<<TOIE0)
    STS TIMSK0, R16             ; Habilitar interrupción de desbordamiento

    // --- 6. Configurar Timer1 (Reloj real, 1 segundo exacto) ---
    LDI R16, 0x00
    STS TCCR1A, R16             ; Modo CTC
    LDI R16, (1<<WGM12)
    STS TCCR1B, R16             
    LDI R16, HIGH(VELOCIDAD)    ; Límite superior del contador (15625)
    STS OCR1AH, R16
    LDI R16, LOW(VELOCIDAD)     ; Límite inferior del contador
    STS OCR1AL, R16
    LDI R16, (1<<OCIE1A)        ; Habilitar interrupción cuando alcance el límite
    STS TIMSK1, R16
    LDS R16, TCCR1B
    ORI R16, (1<<CS12)|(1<<CS10); Prescaler a 1024
    STS TCCR1B, R16

    SEI                         ; Habilitar interrupciones globales

    // Desactivar UART para poder usar los pines PD0 y PD1 libremente
    LDI R18, 0x00
    STS UCSR0B, R18

    // --- Tablas de Datos ---
    RJMP FIN_TABLAS             ; Saltar las tablas para no ejecutarlas como código
    disp7seg: .DB 0x40, 0x79, 0x24, 0x30, 0x19, 0x12, 0x02, 0x78, 0x00, 0x10, 0x08, 0x03, 0x46, 0x21, 0x06, 0x0E
    multDisp: .DB 0b1110, 0b1101, 0b1011, 0b0111
    dispON_OFF: .DB 0x40, 0x48, 0x0E, 0x00  ; Letras: O, N, F, (Vacío)
    tabla_meses_u: .DB 0x00, 0x42, 0x39, 0x42, 0x41, 0x42, 0x41, 0x42, 0x42, 0x41, 0x42, 0x41, 0x42, 0x00
FIN_TABLAS:

    // Limpiar registros de uso general antes de entrar al loop
    CLR R19
    CLR R18
    CLR R1
    CLR R21
    CLR MODE

/****************************************/
// Loop Infinito
MAIN_LOOP:
    // 1. Recalcular el límite de días según el mes actual
    RCALL ACTUALIZAR_MES

    // 2. Verificar si la alarma debe activarse
    LDS R16, VAR_ALARMA_ESTADO
    CPI R16, 1
    BRNE CONTINUAR_MODOS       ; Si está apagada (0), ignorar comprobación

    CPI MODE, 6                ; Si ya está sonando, no volver a verificar
    BREQ CONTINUAR_MODOS

    // Comprobar si Hora y Minuto coinciden con la alarma
    LDS R16, VAR_HORAS_D
    LDS R17, VAR_ALARMA_HORAS_D
    CP R16, R17
    BRNE CONTINUAR_MODOS

    LDS R16, VAR_HORAS_U
    LDS R17, VAR_ALARMA_HORAS_U
    CP R16, R17
    BRNE CONTINUAR_MODOS

    LDS R16, VAR_MINUTOS_D
    LDS R17, VAR_ALARMA_MINUTOS_D
    CP R16, R17
    BRNE CONTINUAR_MODOS

    LDS R16, VAR_MINUTOS_U
    LDS R17, VAR_ALARMA_MINUTOS_U
    CP R16, R17
    BRNE CONTINUAR_MODOS

    // Si todo coincide, forzar al modo 6 (Alarma Sonando)
    LDI R16, 6
    MOV MODE, R16

CONTINUAR_MODOS:
    // Máquina de estados principal: decide qué hacer según el modo actual
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

    CPI MODE, 0b110
    BREQ MODO_ALARMA_SONANDO

    CPI MODE, 0b101              
    BREQ MODO_LETRAS_ESTADO
    
    RJMP MAIN_LOOP
    
    // Saltos intermedios para modos largos
    CONFIGURAR_FECHA1:
        JMP CONFIGURAR_FECHA
    CONFIGURAR_ALARMA1:
        JMP CONFIGURAR_ALARMA

// --- Estados del Menú ---
MODO_LETRAS_ESTADO:              
    SBI PORTB, PORTB4          ; Enciende LED de Hora
    SBI PORTB, PORTB5          ; Enciende LED de Fecha (Ambos indican que configuramos estado alarma)
    RJMP MAIN_LOOP

MODO_ALARMA_SONANDO:
    ; Se queda atrapado aquí. El zumbador y displays se manejan en Timer0
    RJMP MAIN_LOOP

MODO_HORA:
    CBI PORTB, PORTB5          ; Apaga LED fecha
    SBI PORTB, PORTB4          ; Enciende LED hora
    RJMP MAIN_LOOP

MODE_FECHA:
    CBI PORTB, PORTB4          ; Apaga LED hora
    SBI PORTB, PORTB5          ; Enciende LED fecha
    RJMP MAIN_LOOP

// ==========================================
// MODO CONFIGURACIÓN DE HORA (MODE 2)
// ==========================================
CONFIGURAR_HORA:
    CBI PORTB, PORTB5          ; Apaga LED fecha
    SBI PORTB, PORTB4          ; Enciende LED hora
    
    ; Congelar el reloj real mientras se configura (apaga Timer1 temporamente)
    LDS R16, TIMSK1
    ANDI R16, ~(1<<OCIE1A)
    STS TIMSK1, R16
    CLR SEGUNDOS
    
    SELECCION_DISP_CONFIGURAR:
    ; Determinar qué dígito modificamos según el botón de Config
    CPI CONFIGURACION, 0
    BREQ CONFIGURAR_VAR_MINUTOS_U
    CPI CONFIGURACION, 1
    BREQ CONFIGURAR_VAR_MINUTOS_D   
    CPI CONFIGURACION, 2
    BREQ CONFIGURAR_VAR_HORAS_U
    JMP CONFIGURAR_VAR_HORAS_D

    // -- Modificar Unidades de Minuto --
    CONFIGURAR_VAR_MINUTOS_U:
        CPI BANDERA, 2          ; Botón MAS
        BREQ INC_VAR_MINUTOS_UNI
        CPI BANDERA, 1          ; Botón MENOS
        BREQ DEC_VAR_MINUTOS_UNI
        RJMP SALIR_CONFIGURAR_HORA

        INC_VAR_MINUTOS_UNI:
            CLR BANDERA
            LDS R16, VAR_MINUTOS_U
            INC R16 
            CPI R16, 10
            BRNE STS_MINUTOS_U      ; Envuelve de 9 a 0
            CLR R16                 
            STS_MINUTOS_U:
                STS VAR_MINUTOS_U, R16  
        RJMP SALIR_CONFIGURAR_HORA

        DEC_VAR_MINUTOS_UNI:
            CLR BANDERA
            LDS R16, VAR_MINUTOS_U
            DEC R16 
            CPI R16, 0xFF           ; Si baja de 0 (Underflow)
            BRNE SALIR_DEC_VAR_MINUTOS_UNI    
            LDI R16, 9              ; Envuelve a 9
            SALIR_DEC_VAR_MINUTOS_UNI:
                STS VAR_MINUTOS_U, R16  
        RJMP SALIR_CONFIGURAR_HORA

    // -- Modificar Decenas de Minuto --
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
            BRNE STS_MINUTOS_D      ; Envuelve de 5 a 0
            CLR R16                 
            STS_MINUTOS_D:
                STS VAR_MINUTOS_D, R16  
        RJMP SALIR_CONFIGURAR_HORA
    
        DEC_VAR_MINUTOS_DEC:
            CLR BANDERA
            LDS R16, VAR_MINUTOS_D
            DEC R16 
            CPI R16, 0xFF             
            BRNE SALIR_DEC_VAR_MINUTOS_DEC   
            LDI R16, 5              ; Envuelve de 0 a 5
            SALIR_DEC_VAR_MINUTOS_DEC:
                STS VAR_MINUTOS_D, R16  
        RJMP SALIR_CONFIGURAR_HORA
    
    // -- Modificar Unidades de Hora --
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
            BREQ INC_VAR_HORAS_UNI_2 ; Si la decena es 2, el límite de la unidad es 3
            INC R16 
            CPI R16, 10              ; Si la decena es 0 o 1, el límite es 9
            BRNE STS_HORAS_U      
            CLR R16                 
            RJMP STS_HORAS_U

            INC_VAR_HORAS_UNI_2:
            INC R16 
            CPI R16, 4
            BRNE STS_HORAS_U      
            CLR R16                 
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
            
            LDS R17, VAR_HORAS_D
            CPI R17, 2
            BREQ DEC_HORAS_UNI_ES2  ; Si decena es 2, baja a 3
            LDI R16, 9              ; Si es 0 o 1, baja a 9
            RJMP SALIR_DEC_VAR_HORAS_UNI
            DEC_HORAS_UNI_ES2:
            LDI R16, 3              
            
            SALIR_DEC_VAR_HORAS_UNI:
            STS VAR_HORAS_U, R16
            RJMP SALIR_CONFIGURAR_HORA

    // -- Modificar Decenas de Hora --
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
            BRNE STS_HORAS_D      ; Limite máximo de decena es 2
            CLR R16                 
            STS_HORAS_D:
                STS VAR_HORAS_D, R16 

            ; Controlar que si subimos la decena a 2, la unidad no se quede en >3 (ej: 19 a 29)
            CPI R16, 2  
            BRNE SALIR_DEC_CHECK
            LDS R16, VAR_HORAS_U
            CPI R16, 4
            BRLO SALIR_DEC_CHECK  ; Si la unidad es menor a 4, está bien
            LDI R16, 3            ; Forzar unidad a 3 si se pasó
            STS VAR_HORAS_U, R16
            SALIR_DEC_CHECK:                     
        RJMP SALIR_CONFIGURAR_HORA
        
        DEC_VAR_HORAS_DEC:
            CLR BANDERA
            LDS R16, VAR_HORAS_D
            DEC R16
            CPI R16, 0xFF              
            BRNE STS_HORAS_D_DEC
            LDI R16, 2              ; Envuelve a 2
            
            STS_HORAS_D_DEC:
                STS VAR_HORAS_D, R16
            
            ; Mismo control de unidades pero al bajar (de 09 a 29 -> forzar a 23)
            CPI R16, 2
            BRNE SALIR_DEC_HORAS_D
            LDS R16, VAR_HORAS_U
            CPI R16, 4
            BRLO SALIR_DEC_HORAS_D  
            LDI R16, 3              
            STS VAR_HORAS_U, R16

            SALIR_DEC_HORAS_D:
        RJMP SALIR_CONFIGURAR_HORA

    SALIR_CONFIGURAR_HORA:
    CPI MODE, 0b010
    BRNE SALIR_MODE_S2
    JMP SELECCION_DISP_CONFIGURAR

    SALIR_MODE_S2:  
    ; Rehabilitar el Timer1 para que el reloj avance
    LDS R16, TIMSK1
    ORI R16, (1<<OCIE1A)
    STS TIMSK1, R16
    RJMP MAIN_LOOP

// ==========================================
// MODO CONFIGURACIÓN DE FECHA (MODE 3)
// ==========================================
CONFIGURAR_FECHA: 
    CBI PORTB, PORTB4
    SBI PORTB, PORTB5
    RCALL VALIDAR_DIA_MES       ; Ajustar los días si pasamos de un mes largo a uno corto

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

    // -- Modificar Unidades de Mes --
    CONFIGURAR_VAR_MES_U:
    CPI BANDERA, 2
    BREQ INC_VAR_MES_UNI
    CPI BANDERA, 1
    BREQ DEC_VAR_MES_UNI
    RJMP SALIR_CONFIGURAR_FECHA

    INC_VAR_MES_UNI:
        CLR BANDERA
        RCALL VALIDAR_DIA_MES
        LDS R16, VAR_MES_U
        LDS R17, VAR_MES_D
        CPI R17, 1                  ; Si decena es 1, límite es el mes 12
        BRNE INC_MES_NORMAL

        INC R16
        CPI R16, 3
        BRNE STS_VAR_MES_U
        CLR R16                     ; Mes 12 envuelve a mes 10
        RJMP STS_VAR_MES_U

    INC_MES_NORMAL:
        INC R16
        CPI R16, 10
        BRNE STS_VAR_MES_U
        LDI R16, 1                  ; Evitar el mes "00"
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
        LDI R16, 2                  ; Si bajamos de mes 10, va a 12
        RJMP DEC_MES_GUARDAR

    DEC_MES_NORMAL:
        DEC R16
        CPI R16, 0
        BRNE DEC_MES_GUARDAR
        LDI R16, 9                  ; Límite inferior de unidades

    DEC_MES_GUARDAR:
        STS VAR_MES_U, R16
        RCALL ACTUALIZAR_MES
        RCALL VALIDAR_DIA_MES
        RJMP SALIR_CONFIGURAR_FECHA

    // -- Modificar Decenas de Mes --
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
                LDI R17, 2          ; Si estábamos en 09 y pasamos a 10, forzar a 12 (mes no existe)
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

            LDI R16, 1              ; Underflow de decenas de mes
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

    // -- Modificar Unidades del Día --
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
        ANDI R18, 0b00001111        ; Obtener decena máxima del mes
        SUBI R18, 0x01
        
        CP R17, R18
        BREQ REVISAR_ULTIMO_DIA_MES ; Si estamos en la última decena del mes

        INC R16
        CPI R16, 10
        BRNE STS_VAR_DIAS_UNIDAD
        LDI R16, 0
        RJMP STS_VAR_DIAS_UNIDAD

    REVISAR_ULTIMO_DIA_MES:
        INC R16
        LDS R18, VAR_MES
        ANDI R18, 0b00001111
        CP R16, R18                 ; No sobrepasar la unidad final del mes
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

    // -- Modificar Decenas del Día --
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
        CP R16, R18                 ; Evaluar si alcanzamos la decena máxima del mes
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
        MOV R17, R18                ; Cortar unidades si la decena superó el límite real
        RJMP STS_VAR_DIAS_DECENAS
        
        ES_ULTIMO_DIA_DECENA:
        CLR R16                     ; Reiniciar de 3 a 0
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
        MOV R16, R18                ; Enviar al límite superior
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

    SALIR_CONFIGURAR_FECHA:
        RCALL VALIDAR_DIA_MES
        CPI MODE, 0b011
        BRNE SALIR_MODE_S3
        JMP SELECCION_DISP_CONFIGURAR_FECHA

    SALIR_MODE_S3:
        JMP MAIN_LOOP

// ==========================================
// MODO CONFIGURACIÓN ALARMA (MODE 4)
// ==========================================
CONFIGURAR_ALARMA:
    SBI PORTB, PORTB5          ; Enciende LED de Fecha
    SBI PORTB, PORTB4          ; Enciende LED de Hora (Indica modo de configurar alarma)
    
    SELECCION_DISP_CONFIGURAR_ALARMA:
    ; Similar a la hora, evalúa qué dígito cambiar
    CPI CONFIGURACION, 0
    BREQ CONFIGURAR_VAR_ALARMA_MINUTOS_U
    CPI CONFIGURACION, 1
    BREQ CONFIGURAR_VAR_ALARMA_MINUTOS_D    
    CPI CONFIGURACION, 2
    BREQ CONFIGURAR_VAR_ALARMA_HORAS_U
    JMP CONFIGURAR_VAR_ALARMA_HORAS_D

    // (La lógica interna de incrementar/decrementar la alarma es 
    // idéntica a la configuración del reloj regular pero usando variables de alarma)
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
            BRNE STS_MINUTOS_U_ALARMA      
            CLR R16                 
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
            BRNE STS_MINUTOS_D_ALARMA     
            CLR R16                 
            STS_MINUTOS_D_ALARMA:
                STS VAR_ALARMA_MINUTOS_D, R16  
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
            BRNE STS_HORAS_U_ALARMA      
            CLR R16                 
            RJMP STS_HORAS_U_ALARMA

            INC_VAR_ALARMA_HORAS_UNI_2:
            INC R16 
            CPI R16, 4
            BRNE STS_HORAS_U_ALARMA     
            CLR R16                 
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
            LDS R17, VAR_ALARMA_HORAS_D
            CPI R17, 2
            BREQ DEC_HORAS_UNI_ES2_ALARMA
            LDI R16, 9              
            RJMP SALIR_DEC_VAR_ALARMA_HORAS_UNI
            DEC_HORAS_UNI_ES2_ALARMA:
            LDI R16, 3              
            
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
            BRNE STS_HORAS_D_ALARMA     
            CLR R16                 
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
            LDI R16, 2              
            
            STS_HORAS_D_DEC_ALARMA:
                STS VAR_ALARMA_HORAS_D, R16
            
            CPI R16, 2
            BRNE SALIR_DEC_HORAS_D_ALARMA
            LDS R16, VAR_ALARMA_HORAS_U
            CPI R16, 4
            BRLO SALIR_DEC_HORAS_D_ALARMA  
            LDI R16, 3              
            STS VAR_ALARMA_HORAS_U, R16

            SALIR_DEC_HORAS_D_ALARMA:
        RJMP SALIR_CONFIGURAR_ALARMA

    SALIR_CONFIGURAR_ALARMA:
    CPI MODE, 0b100
    BRNE SALIR_MODE_S4
    JMP SELECCION_DISP_CONFIGURAR_ALARMA

    SALIR_MODE_S4:
    RJMP MAIN_LOOP

/****************************************/
// NON-Interrupt subroutines
/****************************************/

// --- Rutina: Recalcula y actualiza la cantidad de días del mes actual ---
ACTUALIZAR_MES:
    PUSH R0          ; Guardar registros de uso interno
    PUSH R1          
    PUSH R16
    PUSH R17
    PUSH R18
    LDS R17, VAR_MES_D
    LDS R16, VAR_MES_U
    LDI R18, 10

    MUL R17, R18                ; Calcula el valor del mes actual (Decenas * 10 + Unidades)
    ADD R0, R16

    MOV R16, R0
    CLR R1

    LDI ZH, HIGH(tabla_meses_u<<1)
    LDI ZL, LOW(tabla_meses_u<<1)
    ADD ZL, R16                 ; Busca en la tabla el límite de días según el mes
    ADC ZH, R1              
    LPM R17, Z
    
    STS VAR_MES, R17            ; Guarda el nuevo límite
    
    POP R18
    POP R17
    POP R16
    POP R1           
    POP R0 
    RET

// --- Rutina: Evita que el día exceda el límite mensual (ej: 31 de Febrero) o se vuelva 00 ---
VALIDAR_DIA_MES:  
    LDS R17, VAR_MES
    LDS R18, VAR_DIAS_D
    LDS R16, VAR_DIAS_U
    SWAP R18
    OR R18, R16                 ; Empaqueta unidades y decenas
    CP R18, R17                 ; Compara contra el máximo permitido
    BRLO SALIR_VALIDAR_DIA_MES  ; Si es menor, todo bien

    // Si es mayor, lo fuerza al día máximo del mes
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

/****************************************/
// Interrupt routines
/****************************************/

// ==========================================
// INTERRUPCIÓN DE BOTONES (PCINT1)
// ==========================================
ISR_PCINT1:
    PUSH R16
    PUSH R17
    IN R16, SREG
    PUSH R16

    // ---- DELAY ANTIRREBOTE SOFTWARE (~15ms) ----
    // Retardo bloqueante básico para evitar que un solo click cuente múltiples veces
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
    // -------------------------------------------

    // Leer el estado de los pines donde están los botones
    IN R16, PINC
    ANDI R16, 0b00011111        ; Solo nos interesan PC0 a PC4

    // Evaluar si fue un flanco de subida (pasó de soltado a presionado)
    LDS R17, VAR_PINC_PREV
    COM R17                     ; Invertir el estado anterior
    AND R17, R16                ; Si antes era 0 (1 invertido) y ahora 1, entonces se presionó

    // Guardar este nuevo estado para la próxima
    IN R16, PINC
    ANDI R16, 0b00011111 
    STS VAR_PINC_PREV, R16
    
    // --- BLOQUEO: Si la alarma suena, ignorar botones regulares ---
    CPI MODE, 6
    BREQ EVALUAR_APAGAR_ALARMA
    
    // Identificar qué botón se presionó (salta a su rutina)
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

EVALUAR_APAGAR_ALARMA:
    SBRC R17, PC2       ; Botón de alarma apaga el zumbador
    RJMP APAGAR_ALARMA
    RJMP SALIR_ISR_PINC

APAGAR_ALARMA:
    CBI PORTC, PORTC5           ; Apagar zumbador
    LDI R16, 0
    STS VAR_ALARMA_ESTADO, R16  ; Desactivar alarma temporalmente
    CLR MODE                    ; Regresar al reloj
    RJMP SALIR_ISR_PINC

PRESSCONFIGURACION:
    CPI MODE, 0b101             ; Si estamos en modo letras, este botón invierte la alarma
    BREQ TOGGLE_ALARMA_ESTADO

    INC CONFIGURACION           ; Navegar entre los 4 dígitos del display
    CPI CONFIGURACION, 4
    BRNE SALIR_ISR_PINC
    CLR CONFIGURACION
    RJMP SALIR_ISR_PINC

TOGGLE_ALARMA_ESTADO:
    LDS R16, VAR_ALARMA_ESTADO
    LDI R17, 1
    EOR R16, R17                ; XOR mágico para cambiar 0 a 1, o 1 a 0
    STS VAR_ALARMA_ESTADO, R16
    RJMP SALIR_ISR_PINC

PRESSMODO:
    INC MODE
    CPI MODE, 6                 ; Cambiar de vista, envolver antes de llegar al 6
    BRNE CONTINUE
    CLR MODE
    CONTINUE:
        RJMP SALIR_ISR_PINC

PRESSALARMA:
    RJMP SALIR_ISR_PINC

PRESSMENOS:
    LDI BANDERA, 1              ; Bandera de decremento
    RJMP SALIR_ISR_PINC

PRESSMAS:
    LDI BANDERA, 2              ; Bandera de incremento
    RJMP SALIR_ISR_PINC

SALIR_ISR_PINC:
    POP R16
    OUT SREG, R16
    POP R17
    POP R16
    RETI

// ==========================================
// TIMER 1 (Mantiene el tiempo real - 1 seg)
// ==========================================
TMIER1_COMPA:
    PUSH R0          
    PUSH R1          
    PUSH R16
    PUSH R17
    IN R16, SREG
    PUSH R16
    PUSH R18

    // Hacer parpadear el LED en PD7 cada segundo (los 2 puntos)
    SBI PIND, PIND7
     
    // Conteo de tiempo principal en cascada
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
        CPI R17, 0x24           ; Si es hora 24, resetear a 00 y aumentar día
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
        CP R17, R16             ; Ver si el día superó el máximo de su mes actual
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
        CPI R17, 0x13           ; Ver si llegamos al mes 13 (Año nuevo)
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
    POP R18
    POP R16
    OUT SREG, R16
    POP R17
    POP R16
    POP R1           
    POP R0           
    RETI

// ==========================================
// TIMER 0 (Multiplexado rápido y animaciones)
// ==========================================
TIMER0_OVF:
    PUSH R16
    PUSH R17
    IN R16, SREG
    PUSH R16
    PUSH R18

    // Recargar Timer0
    LDI R16, 99
    OUT TCNT0, R16
    CLR R16

    // --- Cronómetro de Parpadeo de Display ---
    LDS R16, VAR_BLINK_CONT
    INC R16
    CPI R16, 150              ; Ajusta la velocidad de parpadeo (alcanzado 150 veces)
    BRNE SALVAR_CONTADOR_BLINK
    CLR R16                   
    LDS R17, VAR_BLINK_ESTADO
    LDI R18, 1
    EOR R17, R18              ; Invierte la fase (On a Off)
    ANDI R17, 1               ; Asegura que sea 0 o 1
    STS VAR_BLINK_ESTADO, R17
SALVAR_CONTADOR_BLINK:
    STS VAR_BLINK_CONT, R16
    // -------------------------------------

    // --- Manejo del Zumbador Pasivo ---
    CPI MODE, 6
    BRNE SILENCIAR_BUZZER
    SBI PINC, PINC5       ; Escribir 1 a PINC invierte PORTC5 rápidamente, creando una onda de sonido
    RJMP CONTINUAR_OVF0

    SILENCIAR_BUZZER:
    CBI PORTC, PORTC5     ; Apaga el zumbador si no estamos en alarma

    CONTINUAR_OVF0:
    // --- Lógica del Multiplexado ---
    // Rotar qué display está encendido
    INC DPLY_ENCENDIDO
    CPI DPLY_ENCENDIDO, 4
    BRLO Apagar_Displays    
    CLR DPLY_ENCENDIDO      ; Resetear al display 0

    Apagar_Displays:
        ; Apagar todos los displays brevemente (evita fantasmas visuales)
        IN R16, PORTB
        ORI R16, 0x0F       
        OUT PORTB, R16

        IN R16, PORTD
        ORI R16, 0x7F
        OUT PORTD, R16

        ; Delay ultracorto para limpieza
        PUSH R17
        LDI R17, 50
        blank_loop:
            DEC R17
            BRNE blank_loop
            POP R17

    // Decidir qué datos mostrar según el modo actual
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
        BREQ Cargar_Mes_U       
        CPI DPLY_ENCENDIDO, 1
        BREQ Cargar_Mes_D       
        CPI DPLY_ENCENDIDO, 2
        BREQ Cargar_Dia_U       
        
        Cargar_Dia_D:           
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
        ; Muestra "ON" u "OFF" según el estado de la alarma
        LDS R16, VAR_ALARMA_ESTADO
        CPI R16, 1
        BREQ MODO_letras_ON

    MODO_letras_OFF:
        CPI DPLY_ENCENDIDO, 3
        BREQ Cargar_O
        CPI DPLY_ENCENDIDO, 2
        BREQ Cargar_F
        RJMP Salir_Timer0      ; Si no es el 3 o 2, dejar apagado

    MODO_letras_ON:
        CPI DPLY_ENCENDIDO, 1
        BREQ Cargar_O
        CPI DPLY_ENCENDIDO, 0
        BREQ Cargar_N
        RJMP Salir_Timer0      

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
            ADC ZH, R1              
            LPM R17, Z
            IN R16, PORTD          
            ANDI R16, 0x80         
            ANDI R17, 0x7F          
            OR R17, R16             
            OUT PORTD, R17
            RJMP Activar_Transistor 

    Dibujar_Numero:
        // Leer la tabla de dígitos del 0 al 9
        LDI ZH, HIGH(disp7seg<<1)
        LDI ZL, LOW(disp7seg<<1)
        ADD ZL, R16
        ADC ZH, R1              
        LPM R17, Z

        IN R16, PORTD           ; Conserva el estado de PD7 (el LED del reloj)
        ANDI R16, 0x80          
        ANDI R17, 0x7F          
        OR R17, R16             
        OUT PORTD, R17          ; Enviar a los segmentos

    Activar_Transistor:
        // --- EVITAR ENCENDER PARA EFECTO DE PARPADEO EN CONFIGURACIÓN ---
        CPI MODE, 2
        BREQ EVALUAR_PARPADEO
        CPI MODE, 3
        BREQ EVALUAR_PARPADEO
        CPI MODE, 4
        BREQ EVALUAR_PARPADEO
        RJMP ENCENDER_NORMAL

    EVALUAR_PARPADEO:
        CP DPLY_ENCENDIDO, CONFIGURACION
        BRNE ENCENDER_NORMAL        ; Si no es el que configuramos, se enciende fijo
        LDS R16, VAR_BLINK_ESTADO
        CPI R16, 0
        BREQ Salir_Timer0           ; Si la fase es 0, omitir su encendido para crear parpadeo

    ENCENDER_NORMAL:
        // Enciende el transistor del dígito correspondiente
        LDI ZH, HIGH(multDisp<<1)
        LDI ZL, LOW(multDisp<<1)
        ADD ZL, DPLY_ENCENDIDO
        ADC ZH, R1
        LPM R16, Z             

        IN R17, PORTB
        ANDI R17, 0xF0         
        OR R17, R16            
        OUT PORTB, R17         

    Salir_Timer0:
        POP R18
        POP R16
        OUT SREG, R16
        POP R17
        POP R16
        RETI