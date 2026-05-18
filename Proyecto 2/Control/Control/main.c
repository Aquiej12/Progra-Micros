/*
 * Control.c
 *
 * Created: Guatemala 17/05/2026
 * Author: Abner Quiej (Terricola)
 * Description: Mando inalambrico (cerebro del sistema) 
 *      - Lee 4 joysticks (ADC)
 *      - Lee 2 botones (debounce)
 *      - Maneja 3 LEDs indicadores
 *      - Lee/escribe la EEPROM para grabar y reproducir macros
 *      - Recibe comandos UART desde la PC (puente Adafruit IO)
 *      - En todos los modos arma un Payload_t y lo envia por LoRa
 */


/****************************************/
// Encabezado (Libraries)
/****************************************/

#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/eeprom.h>
#include <util/delay.h>
#include "spi.h"
#include "lora.h"
#include "uart.h"

// Payload — 10 bytes 

typedef struct {
    int16_t fwd_bwd;
    int16_t left_right;
    int16_t yaw;
    int16_t height;
    uint8_t mode;        /* 0=Manual, 1=EEPROM, 2=UART */
    uint8_t action_btn;  /* LATCH: 1=REC activo, 0=detenido */
} Payload_t;

// EEPROM Macro-Grabadora (5 bytes por evento)

typedef struct {
    int8_t   j_fb;
    int8_t   j_lr;
    int8_t   j_yaw;
    uint16_t duration_ticks;     
} EEPROM_Macro_t;

#define EEPROM_TOTAL       1000
#define EEPROM_EVT_SIZE    sizeof(EEPROM_Macro_t)            /* 5 bytes */
#define EEPROM_DATA_MAX    (EEPROM_TOTAL - EEPROM_EVT_SIZE)  /* 995 */
#define EOF_MARK           0xFFFF

//  Configuracion general

#define LORA_FREQ         915000000UL
#define DEADZONE          35
#define JOY_SAMPLES       16
#define TX_PERIOD_MS      20        /* cada cuanto se transmite por LoRa */
#define DEBOUNCE_TICKS    2
#define MODE_COUNT        3
#define BLINK_TICKS       12        /* 12 × 20 ms = 240 ms (≈ 250 ms)    */


/****************************************/
// Function prototypes
/****************************************/

// ADC + Joysticks

static uint16_t joy_center[4];

static void ADC_Init(void) {
    ADMUX  = (1 << REFS0);
    ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);
}

static uint16_t ADC_Read(uint8_t ch) {
    ADMUX = (ADMUX & 0xF0) | (ch & 0x0F);
    _delay_us(10);
    ADCSRA |= (1 << ADSC);
    while (ADCSRA & (1 << ADSC)) { }
    return ADC;
}

static void joy_calibrate(void) {
    uint8_t  i, ch;
    uint32_t s[4] = { 0, 0, 0, 0 };

    for (i = 0; i < JOY_SAMPLES; i++)
        for (ch = 0; ch < 4; ch++)
            s[ch] += ADC_Read(ch);

    for (ch = 0; ch < 4; ch++)
        joy_center[ch] = (uint16_t)(s[ch] / JOY_SAMPLES);
}

static int16_t dz(int16_t v) {
    return (v > -DEADZONE && v < DEADZONE) ? 0 : v;
}

// Simplifica un valor a -1/0/+1 para grabar en EEPROM

static int8_t simplify(int16_t v) {
    if (v >  DEADZONE) return  1;
    if (v < -DEADZONE) return -1;
    return 0;
}

// GRABADORA EEPROM

static int8_t   rec_prev_fb = 0, rec_prev_lr = 0, rec_prev_yw = 0;
static uint16_t rec_duration = 0;
static uint16_t rec_addr     = 0;

static void rec_write_event(int8_t fb, int8_t lr, int8_t yw, uint16_t dur) {
    EEPROM_Macro_t ev;
    ev.j_fb           = fb;
    ev.j_lr           = lr;
    ev.j_yaw          = yw;
    ev.duration_ticks = dur;
    eeprom_write_block(&ev, (void *)(uintptr_t)rec_addr, EEPROM_EVT_SIZE);
    rec_addr = (uint16_t)(rec_addr + EEPROM_EVT_SIZE);
    UART_PrintString("EEPROM Grabado!\r\n");
}

// Empezar grabación
static void rec_start(int8_t fb, int8_t lr, int8_t yw) {
    rec_addr     = 0;
    rec_prev_fb  = fb;
    rec_prev_lr  = lr;
    rec_prev_yw  = yw;
    rec_duration = 0;
    UART_PrintString("REC start\r\n");
}

// Duración grabación

static void rec_tick(int8_t fb, int8_t lr, int8_t yw) {
    if (fb != rec_prev_fb || lr != rec_prev_lr || yw != rec_prev_yw) {
        if (rec_addr + EEPROM_EVT_SIZE <= EEPROM_DATA_MAX) {
            rec_write_event(rec_prev_fb, rec_prev_lr, rec_prev_yw, rec_duration);
        }
        rec_prev_fb  = fb;
        rec_prev_lr  = lr;
        rec_prev_yw  = yw;
        rec_duration = 0;
    } else {
        if (rec_duration < 0xFFFE) rec_duration++;
    }
}

// Parar Grabación

static void rec_stop(void) {
    if (rec_addr == 0) return;
    if (rec_addr + EEPROM_EVT_SIZE <= EEPROM_DATA_MAX) {
        rec_write_event(rec_prev_fb, rec_prev_lr, rec_prev_yw, rec_duration);
    }
    if (rec_addr <= EEPROM_TOTAL - EEPROM_EVT_SIZE) {
        rec_write_event(0, 0, 0, EOF_MARK);
    }
    UART_PrintString("REC stop (EOF escrito)\r\n");
}

// REPRODUCTOR EEPROM

static EEPROM_Macro_t pb_event;
static uint16_t       pb_addr      = 0;
static uint16_t       pb_remaining = 0;

static void pb_load(void) {
    eeprom_read_block(&pb_event, (const void *)(uintptr_t)pb_addr,
                      EEPROM_EVT_SIZE);

    if (pb_event.duration_ticks == EOF_MARK) {
        // EOF: rebobinar al inicio
        if (pb_addr != 0) {
            pb_addr = 0;
            eeprom_read_block(&pb_event, (const void *)0, EEPROM_EVT_SIZE);
        }
        // Si la direccion 0 tambien es EOF = EEPROM vacia, idle
        if (pb_event.duration_ticks == EOF_MARK) {
            pb_event.j_fb           = 0;
            pb_event.j_lr           = 0;
            pb_event.j_yaw          = 0;
            pb_event.duration_ticks = 100;
        }
    }
    pb_remaining = pb_event.duration_ticks;
}

static void pb_init(void) {
    pb_addr = 0;
    pb_load();
    UART_PrintString("Playback iniciado\r\n");
}

static void pb_step(void) {
    if (pb_remaining > 0) {
        pb_remaining--;
    } else {
        pb_addr = (uint16_t)(pb_addr + EEPROM_EVT_SIZE);
        if (pb_addr >= EEPROM_TOTAL) pb_addr = 0;
        pb_load();
    }
}

// GPIO (botones + LEDs)

static void io_init(void) {
    DDRD  |=  (1 << PD5) | (1 << PD6) | (1 << PD7);
    PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7));
    DDRD  &= ~((1 << PD2) | (1 << PD3));
    PORTD |=  (1 << PD2) | (1 << PD3);     /* pull-ups */
}

// Enciende solo el LED del modo actual; parpadea LED_MANUAL en REC

static void update_leds(uint8_t mode, uint8_t action_btn, uint8_t blink_on) {
    PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7));
    switch (mode) {
        case 0:
            if (action_btn == 0 || blink_on) PORTD |= (1 << PD5);
            break;
        case 1: PORTD |= (1 << PD6); break;
        case 2: PORTD |= (1 << PD7); break;
    }
}


/****************************************/
// Main Function
/****************************************/

int main(void) {
    // Declaraciones al inicio 
    Payload_t datos_lora;
    int16_t   raw0, raw1, raw2, raw3;
    uint8_t   mode = 0;
    uint8_t   prev_mode_internal = 0xFF;   /* para detectar cambio de modo */
    uint8_t   prev_action_btn    = 0;
    int8_t    s_fb, s_lr, s_yw;

    // Debounce
    uint8_t mode_stable   = 1, mode_count   = 0;
    uint8_t action_stable = 1, action_count = 0;
    uint8_t raw_mode, raw_action;

    // Parpadeo del LED_MANUAL durante REC 
    uint8_t blink_count = 0;
    uint8_t blink_on    = 1;

    // LoRa + UART debug
    uint8_t lora_status;
    uint8_t tx_result;
    uint8_t prev_mode_print   = 0xFF;
    uint8_t prev_action_print = 0xFF;

    // Modo UART: ultimo comando recibido se mantiene
    int16_t uart_fb = 0, uart_lr = 0, uart_yw = 0;
    uint8_t uart_cmd;

    // Throttle para enviar los ADC al puente Python cada ~200 ms
     * (10 iteraciones × 20 ms = 200 ms). El feed AIO_ADC sube a
     * Adafruit y permite visualizar los joysticks en el dashboard. */
    uint8_t aio_adc_throttle = 0;

    // Inicializa payload
    datos_lora.fwd_bwd    = 0;
    datos_lora.left_right = 0;
    datos_lora.yaw        = 0;
    datos_lora.height     = 0;
    datos_lora.mode       = mode;
    datos_lora.action_btn = 0;

    //  Init
    
    io_init();
    ADC_Init();

    UART_Init(9600);
    UART_PrintString("\r\n--- INICIANDO CONTROL TX ---\r\n");

    lora_status = LoRa_Init(LORA_FREQ);
    if (lora_status != 0) {
        UART_PrintString("ERROR: Fallo comunicacion SPI LoRa\r\n");
    } else {
        UART_PrintString("LoRa OK\r\n");
    }

    _delay_ms(100);
    joy_calibrate();
    UART_PrintString("Joysticks calibrados\r\n");

    update_leds(mode, datos_lora.action_btn, blink_on);

    while (1) {

        // 1) BOTON MODO (PD2) — debounce + ciclo + reset action_btn
        
        raw_mode = (PIND & (1 << PD2)) ? 1 : 0;
        if (raw_mode == mode_stable) {
            mode_count = 0;
        } else {
            mode_count++;
            if (mode_count >= DEBOUNCE_TICKS) {
                mode_stable = raw_mode;
                mode_count  = 0;
                if (raw_mode == 0) {
                    mode = (uint8_t)((mode + 1) % MODE_COUNT);
                    datos_lora.mode       = mode;
                    datos_lora.action_btn = 0;     
                }
            }
        }

        // 2) BOTON ACCION (PD3) — debounce + LATCH (toggle)
        
        raw_action = (PIND & (1 << PD3)) ? 1 : 0;
        if (raw_action == action_stable) {
            action_count = 0;
        } else {
            action_count++;
            if (action_count >= DEBOUNCE_TICKS) {
                action_stable = raw_action;
                action_count  = 0;
                if (raw_action == 0) {
                    datos_lora.action_btn = (uint8_t)(!datos_lora.action_btn);
                }
            }
        }

        // 3) DEBUG UART — imprime al cambiar modo o boton
         
        if (datos_lora.mode != prev_mode_print) {
            if (datos_lora.mode == 2) {
                UART_PrintString("Modo UART\r\n");
            } else {
                UART_PrintString("Modo: ");
                UART_PrintInt((int16_t)datos_lora.mode);
                UART_PrintString("\r\n");
            }
            prev_mode_print = datos_lora.mode;
        }
        if (datos_lora.action_btn != prev_action_print) {
            UART_PrintString("Action: ");
            UART_PrintInt((int16_t)datos_lora.action_btn);
            UART_PrintString("\r\n");
            prev_action_print = datos_lora.action_btn;
        }

        // 4) PARPADEO LED_MANUAL 
        
        blink_count++;
        if (blink_count >= BLINK_TICKS) {
            blink_count = 0;
            blink_on   ^= 1;
        }
        update_leds(mode, datos_lora.action_btn, blink_on);

        // 5) TRANSICION DE MODO — cerrar grabacion / abrir playback
        
        if (mode != prev_mode_internal) {
            /* Si veniamos grabando en cualquier modo no-1, cerrar la macro */
            if (prev_mode_internal != 1 && prev_action_btn == 1) {
                rec_stop();
            }
            if (mode == 1) pb_init();
            if (mode == 2) {
                /* Al entrar a UART, resetear el estado de comandos */
                uart_fb = uart_lr = uart_yw = 0;
            }
            prev_mode_internal = mode;
        }

        // 6) LECTURA SEGUN MODO — arma el Payload_t para LoRa
        
        if (mode == 0) {
            /* ─── MODO 0: MANUAL (joysticks) ─── */
            raw0 = (int16_t)ADC_Read(0) - (int16_t)joy_center[0];
            raw1 = (int16_t)ADC_Read(1) - (int16_t)joy_center[1];
            raw2 = (int16_t)ADC_Read(2) - (int16_t)joy_center[2];
            raw3 = (int16_t)ADC_Read(3) - (int16_t)joy_center[3];

            datos_lora.fwd_bwd    = dz(raw0);
            datos_lora.left_right = dz(raw1);
            datos_lora.yaw        = dz(raw2);
            datos_lora.height     =    raw3;

            // Grabacion: si action_btn esta activo, registrar en EEPROM
            if (datos_lora.action_btn == 1) {
                s_fb = simplify(datos_lora.fwd_bwd);
                s_lr = simplify(datos_lora.left_right);
                s_yw = simplify(datos_lora.yaw);

                if (prev_action_btn == 0) {
                    rec_start(s_fb, s_lr, s_yw);
                }
                rec_tick(s_fb, s_lr, s_yw);
            } else if (prev_action_btn == 1) {
                rec_stop();
            }
        }
        else if (mode == 1) {
            
            //  MODO 1: REPRODUCCION EEPROM

            pb_step();
            // Magnificar los valores simplificados a algo > DEADZONE
             * para que el robot los reconozca como joystick activo.   */
            datos_lora.fwd_bwd    = (int16_t)(pb_event.j_fb  * 100);
            datos_lora.left_right = (int16_t)(pb_event.j_lr  * 100);
            datos_lora.yaw        = (int16_t)(pb_event.j_yaw * 100);
            datos_lora.height     = 0;
        }
        else {

            // ─── MODO 2: UART 
            
            if (UART_Available()) {
                uart_cmd = UART_Read();
                switch (uart_cmd) {
                    case 'F': case 'f':
                        uart_fb = 100; uart_lr = 0; uart_yw = 0; break;
                    case 'B': case 'b':
                        uart_fb = -100; uart_lr = 0; uart_yw = 0; break;
                    case 'L': case 'l':
                        uart_fb = 0; uart_lr = 0; uart_yw = -100; break;
                    case 'R': case 'r':
                        uart_fb = 0; uart_lr = 0; uart_yw =  100; break;
                    case 'I': case 'i':
                        uart_fb = 0; uart_lr = -100; uart_yw = 0; break;
                    case 'D': case 'd':
                        uart_fb = 0; uart_lr =  100; uart_yw = 0; break;
                    case 'S': case 's':
                        uart_fb = uart_lr = uart_yw = 0; break;
                    case 'C': case 'c':
                        /* Toggle del action_btn → detona la grabacion
                         * en EEPROM con la misma logica del boton fisico */
                        datos_lora.action_btn =
                            (uint8_t)(!datos_lora.action_btn);
                        break;
                    default: break;
                }
                // Echo de confirmacion al puente Python
                UART_PrintString("UART OK: ");
                UART_Send(uart_cmd);
                UART_PrintString("\r\n");
            }
            datos_lora.fwd_bwd    = uart_fb;
            datos_lora.left_right = uart_lr;
            datos_lora.yaw        = uart_yw;
            datos_lora.height     = 0;

            // Grabacion EEPROM tambien activa en MODO 2.
             
            if (datos_lora.action_btn == 1) {
                s_fb = simplify(uart_fb);
                s_lr = simplify(uart_lr);
                s_yw = simplify(uart_yw);
                if (prev_action_btn == 0) {
                    rec_start(s_fb, s_lr, s_yw);
                }
                rec_tick(s_fb, s_lr, s_yw);
            } else if (prev_action_btn == 1) {
                rec_stop();
            }
        }

        prev_action_btn = datos_lora.action_btn;

        // 7) ENVIO LoRa — en TODOS los modos
        
        tx_result = LoRa_Transmit((uint8_t *)&datos_lora, sizeof(Payload_t));
        if (tx_result == 0) {
            UART_PrintString("Error: Tx Timeout\r\n");
        }

        // 8) TELEMETRIA ADC → puente Python → Adafruit
        
        aio_adc_throttle++;
        if (aio_adc_throttle >= 10) {
            aio_adc_throttle = 0;
            UART_PrintString("AIO_ADC:");
            UART_PrintInt(datos_lora.fwd_bwd);
            UART_Send(',');
            UART_PrintInt(datos_lora.left_right);
            UART_Send(',');
            UART_PrintInt(datos_lora.yaw);
            UART_Send(',');
            UART_PrintInt(datos_lora.height);
            UART_PrintString("\r\n");
        }

        _delay_ms(TX_PERIOD_MS);
    }

    return 0;
}




