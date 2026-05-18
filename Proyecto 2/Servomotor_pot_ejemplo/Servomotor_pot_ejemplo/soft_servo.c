/*
 * soft_servo.c
 *
 * Created: 17/05/2026
 * Author: Abner Quiej (Mecatronico)
 * Description: Servomotor por medio de Timer 1
 */
/****************************************/
// Encabezado (Libraries)

#include "soft_servo.h"
#include <avr/interrupt.h>

static volatile uint8_t  *s_puertos[MAX_SOFT_SERVOS];
static uint8_t            s_pines_mask[MAX_SOFT_SERVOS];
static volatile uint16_t  s_ticks[MAX_SOFT_SERVOS];
static uint16_t           s_min_tick[MAX_SOFT_SERVOS];
static uint16_t           s_max_tick[MAX_SOFT_SERVOS];
static uint16_t           s_min_adc[MAX_SOFT_SERVOS];
static uint16_t           s_max_adc[MAX_SOFT_SERVOS];


/****************************************/
// Function prototypes
/****************************************/

void SoftServo_Init(void) {
    for (uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
        s_puertos[i] = 0;
        s_ticks[i]   = 75;
    }
    TCCR1A = 0;
    TCCR1B = (1 << WGM12) | (1 << CS11); // CTC, prescaler 8
    OCR1A  = 39;                           // 20us/tick @ 16MHz/8 = 2MHz → 2e6/100k = 20us
    TIMSK1 |= (1 << OCIE1A);
}

void SoftServo_Attach(uint8_t canal, volatile uint8_t *puerto, volatile uint8_t *ddr,
                      uint8_t pin, uint16_t min_tick, uint16_t max_tick,
                      uint16_t min_adc, uint16_t max_adc) {
    if (canal >= MAX_SOFT_SERVOS) return;
    *ddr             |= (1 << pin);
    s_puertos[canal]  = puerto;
    s_pines_mask[canal] = (1 << pin);
    s_min_tick[canal] = min_tick;
    s_max_tick[canal] = max_tick;
    s_min_adc[canal]  = min_adc;
    s_max_adc[canal]  = max_adc;
}

void SoftServo_SetFromADC(uint8_t canal, uint16_t adc_val) {
    if (canal >= MAX_SOFT_SERVOS || !s_puertos[canal]) return;
    if (adc_val < s_min_adc[canal]) adc_val = s_min_adc[canal];
    if (adc_val > s_max_adc[canal]) adc_val = s_max_adc[canal];
    uint32_t num = (uint32_t)(adc_val - s_min_adc[canal]) * (s_max_tick[canal] - s_min_tick[canal]);
    s_ticks[canal] = s_min_tick[canal] + (uint16_t)(num / (s_max_adc[canal] - s_min_adc[canal]));
}

void SoftServo_SetAngle(uint8_t canal, uint8_t deg) {
    if (canal >= MAX_SOFT_SERVOS || !s_puertos[canal]) return;
    s_ticks[canal] = s_min_tick[canal] +
        (uint16_t)((uint32_t)deg * (s_max_tick[canal] - s_min_tick[canal]) / 180);
}

void SoftServo_SetTicks(uint8_t canal, uint16_t ticks) {
    if (canal >= MAX_SOFT_SERVOS || !s_puertos[canal]) return;
    if (ticks < s_min_tick[canal]) ticks = s_min_tick[canal];
    if (ticks > s_max_tick[canal]) ticks = s_max_tick[canal];
    s_ticks[canal] = ticks;
}

/****************************************/
// Interrupt routines
/****************************************/

ISR(TIMER1_COMPA_vect) {
    static uint16_t count = 0;

    if (count == 0) {
        for (uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
            volatile uint8_t *p = s_puertos[i];
            if (p) *p |= s_pines_mask[i];
        }
    } else {
        for (uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
            volatile uint8_t *p = s_puertos[i];
            if (p && count == s_ticks[i]) *p &= ~s_pines_mask[i];
        }
    }

    if (++count >= 1000) count = 0;
}

