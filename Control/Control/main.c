/*
 * Control.c — Transmisor LoRa (4 ejes + botones latch + LEDs)
 *
 * ATmega328P @ 16 MHz, C puro, Microchip Studio.
 *
 * Pinout:
 *   LoRa SX1276:
 *     MOSI = PB3 (D11)    NSS  = PB2 (D10)
 *     MISO = PB4 (D12)    RST  = PB1 (D9)
 *     SCK  = PB5 (D13)    DIO0 = PB0 (D8)
 *
 *   Entradas (pull-up):
 *     PD2 (D2) = Boton MODO    (cicla 0→1→2→0, fuerza action_btn=0)
 *     PD3 (D3) = Boton ACCION  (LATCH: cada press toggle de action_btn)
 *
 *   Salidas (LEDs):
 *     PD5 (D5) = LED_MANUAL  — solido en mode 0, PARPADEA en mode 0 + REC
 *     PD6 (D6) = LED_EEPROM  — solido en mode 1
 *     PD7 (D7) = LED_UART    — solido en mode 2
 *
 *   Joysticks:
 *     A0=fwd_bwd  A1=left_right  A2=yaw  A3=height
 */

#define F_CPU 16000000UL
#include <avr/io.h>
#include <util/delay.h>
#include "spi.h"
#include "lora.h"
#include "uart.h"

/* ════════════════════════════════════════════════════════════════════
 *  Payload — 10 bytes (igual al del robot)
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    int16_t fwd_bwd;
    int16_t left_right;
    int16_t yaw;
    int16_t height;
    uint8_t mode;        /* 0=Manual, 1=EEPROM, 2=UART */
    uint8_t action_btn;  /* LATCH: toggle por cada press */
} Payload_t;

/* ════════════════════════════════════════════════════════════════════
 *  Configuracion
 * ═══════════════════════════════════════════════════════════════════ */
#define LORA_FREQ         915000000UL
#define DEADZONE          35
#define JOY_SAMPLES       16
#define TX_PERIOD_MS      20
#define DEBOUNCE_TICKS    2
#define MODE_COUNT        3
#define BLINK_TICKS       12      /* 12 × 20 ms = 240 ms (≈250 ms) */

/* ════════════════════════════════════════════════════════════════════
 *  ADC
 * ═══════════════════════════════════════════════════════════════════ */
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

/* ════════════════════════════════════════════════════════════════════
 *  GPIO
 * ═══════════════════════════════════════════════════════════════════ */
static void io_init(void) {
    /* LEDs */
    DDRD |=  (1 << PD5) | (1 << PD6) | (1 << PD7);
    PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7));

    /* Botones con pull-up */
    DDRD  &= ~((1 << PD2) | (1 << PD3));
    PORTD |=  (1 << PD2) | (1 << PD3);
}

/* ════════════════════════════════════════════════════════════════════
 *  LEDs — solido por modo + parpadeo en modo 0 si REC activo
 * ═══════════════════════════════════════════════════════════════════ */
static void update_leds(uint8_t mode, uint8_t action_btn, uint8_t blink_on) {
    PORTD &= ~((1 << PD5) | (1 << PD6) | (1 << PD7));

    switch (mode) {
        case 0:
            /* MANUAL: parpadea si grabando, solido si no */
            if (action_btn == 0 || blink_on) {
                PORTD |= (1 << PD5);
            }
            break;
        case 1:
            PORTD |= (1 << PD6);
            break;
        case 2:
            PORTD |= (1 << PD7);
            break;
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  MAIN
 * ═══════════════════════════════════════════════════════════════════ */
int main(void) {
    /* ── Declaraciones al inicio (C89) ─────────────────────────── */
    Payload_t datos_lora;
    int16_t   raw0, raw1, raw2, raw3;
    uint8_t   mode = 0;

    /* Debounce */
    uint8_t mode_stable   = 1, mode_count   = 0;
    uint8_t action_stable = 1, action_count = 0;
    uint8_t raw_mode, raw_action;

    /* Parpadeo del LED_MANUAL en REC */
    uint8_t blink_count = 0;
    uint8_t blink_on    = 1;

    /* LoRa status + tracking de cambios para imprimir */
    uint8_t lora_status;
    uint8_t tx_result;
    uint8_t prev_mode_print   = 0xFF;     /* fuerza imprimir en 1ra iter */
    uint8_t prev_action_print = 0xFF;

    /* Inicializar payload */
    datos_lora.fwd_bwd    = 0;
    datos_lora.left_right = 0;
    datos_lora.yaw        = 0;
    datos_lora.height     = 0;
    datos_lora.mode       = mode;
    datos_lora.action_btn = 0;     /* LATCH arranca apagado */

    /* ── Init ──────────────────────────────────────────────────── */
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

        /* ════════════════════════════════════════════════════════
         *  BOTON MODO (PD2) — debounce + ciclo + reset action_btn
         * ══════════════════════════════════════════════════════ */
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
                    datos_lora.action_btn = 0;     /* fuerza off en cambio de modo */
                }
            }
        }

        /* ════════════════════════════════════════════════════════
         *  BOTON ACCION (PD3) — debounce + LATCH (toggle)
         * ══════════════════════════════════════════════════════ */
        raw_action = (PIND & (1 << PD3)) ? 1 : 0;
        if (raw_action == action_stable) {
            action_count = 0;
        } else {
            action_count++;
            if (action_count >= DEBOUNCE_TICKS) {
                action_stable = raw_action;
                action_count  = 0;
                if (raw_action == 0) {
                    /* Flanco de bajada → toggle */
                    datos_lora.action_btn = (uint8_t)(!datos_lora.action_btn);
                }
            }
        }

        /* ════════════════════════════════════════════════════════
         *  DEBUG UART — imprimir cuando cambien modo o action_btn
         * ══════════════════════════════════════════════════════ */
        if (datos_lora.mode != prev_mode_print) {
            UART_PrintString("Modo: ");
            UART_PrintInt((int16_t)datos_lora.mode);
            UART_PrintString("\r\n");
            prev_mode_print = datos_lora.mode;
        }
        if (datos_lora.action_btn != prev_action_print) {
            UART_PrintString("Action: ");
            UART_PrintInt((int16_t)datos_lora.action_btn);
            UART_PrintString("\r\n");
            prev_action_print = datos_lora.action_btn;
        }

        /* ════════════════════════════════════════════════════════
         *  PARPADEO LED_MANUAL (no bloqueante)
         * ══════════════════════════════════════════════════════ */
        blink_count++;
        if (blink_count >= BLINK_TICKS) {
            blink_count = 0;
            blink_on   ^= 1;
        }
        update_leds(mode, datos_lora.action_btn, blink_on);

        /* ════════════════════════════════════════════════════════
         *  ENVIO LoRa — solo en mode 0 (Manual) y 1 (EEPROM)
         * ══════════════════════════════════════════════════════ */
        if (mode == 0 || mode == 1) {
            raw0 = (int16_t)ADC_Read(0) - (int16_t)joy_center[0];
            raw1 = (int16_t)ADC_Read(1) - (int16_t)joy_center[1];
            raw2 = (int16_t)ADC_Read(2) - (int16_t)joy_center[2];
            raw3 = (int16_t)ADC_Read(3) - (int16_t)joy_center[3];

            datos_lora.fwd_bwd    = dz(raw0);
            datos_lora.left_right = dz(raw1);
            datos_lora.yaw        = dz(raw2);
            datos_lora.height     =    raw3;
            /* mode y action_btn ya estan actualizados arriba */

            tx_result = LoRa_Transmit((uint8_t *)&datos_lora,
                                      sizeof(Payload_t));
            if (tx_result == 0) {
                UART_PrintString("Error: Tx Timeout\r\n");
            }
        }

        _delay_ms(TX_PERIOD_MS);
    }

    return 0;
}
