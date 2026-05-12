/*  flexi_timer.c — Timer2 overflow, 1 ms de resolución (16 MHz / 64)
 *
 *  Equivalente funcional de FlexiTimer2 pero en C puro.
 *  NO toca Timer0 ni Timer1; solo usa Timer2.
 */

#include "flexi_timer.h"
#include <avr/io.h>
#include <avr/interrupt.h>

/* ── Estado interno ──────────────────────────────────────────────── */
static void (*user_callback)(void) = 0;
static uint16_t target_ms  = 1;         /* período en ms              */
static volatile uint16_t tick_count = 0;
static volatile uint8_t  running    = 0;

/*  Valor de recarga para 1 ms exacto:
 *    F_CPU = 16 MHz, prescaler = 64 → f_timer = 250 kHz
 *    250 cuentas = 1.000 ms  →  recarga = 256 − 250 = 6            */
#define TCNT2_RELOAD  6

/* ── API pública ─────────────────────────────────────────────────── */

void FlexiTimer_Set(uint16_t ms, void (*callback)(void)) {
    user_callback = callback;
    target_ms     = (ms == 0) ? 1 : ms;

    /* Timer2: modo Normal (sin WGM), sin salidas OC2x              */
    TCCR2A = 0;
    TCCR2B = 0;
    ASSR  &= ~(1 << AS2);               /* reloj síncrono            */
    TIMSK2 &= ~(1 << OCIE2A);           /* sin compare-match         */
}

void FlexiTimer_Start(void) {
    tick_count = 0;
    running    = 1;
    TCNT2  = TCNT2_RELOAD;
    TCCR2B = (1 << CS22);               /* prescaler 64 → arrancar   */
    TIMSK2 |= (1 << TOIE2);             /* habilitar overflow IRQ    */
}

void FlexiTimer_Stop(void) {
    TIMSK2 &= ~(1 << TOIE2);            /* deshabilitar overflow IRQ */
    TCCR2B  = 0;                         /* detener reloj             */
    running = 0;
}

/* ── ISR ─────────────────────────────────────────────────────────── */
ISR(TIMER2_OVF_vect) {
    TCNT2 = TCNT2_RELOAD;               /* recarga inmediata         */

    if (++tick_count >= target_ms) {
        tick_count = 0;
        if (user_callback) user_callback();
    }
}
