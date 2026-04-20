/*
 * SoftPWM.c
 */
#include "SoftPWM.h"

/* --------------------------------------------------------------- */
static volatile uint8_t spwm_duty    = 0;   /* umbral de apagado  */
static volatile uint8_t spwm_counter = 0;   /* contador 0–255     */

/* ---------------------------------------------------------------
 * SoftPWM_Init
 *
 * Timer2 modo CTC, TOP = OCR2A = 0 ? interrupción cada tick
 * Prescaler 8 ? f_tick = 2MHz ? 1 tick = 0.5µs
 * Periodo PWM = 256 ticks × 0.5µs = 128µs ? ~7.8kHz
 * Suficiente para que el LED no parpadee visiblemente.
 * --------------------------------------------------------------- */
void SoftPWM_Init(void)
{
    /* PD5 como salida, inicialmente apagada */
    SPWM_DDR  |=  (1 << SPWM_PIN);
    SPWM_PORT &= ~(1 << SPWM_PIN);

    /*
     * Timer2: CTC con OCR2A 
     * WGM21=1 ? modo CTC
     * CS21=1  ? prescaler 8
     * OCR2A=0 ? interrupción en cada tick (máxima resolución)
     */
    TCCR2A = (1 << WGM21);
    TCCR2B = (1 << CS21);
    OCR2A  = 0;

    /* Habilitar interrupción por comparación A de Timer2 */
    TIMSK2 = (1 << OCIE2A);
}


void SoftPWM_SetDuty(uint8_t duty)
{
    spwm_duty = duty;
}


ISR(TIMER2_COMPA_vect)
{
    spwm_counter++;   /* desborda solo de 0 a 255 automáticamente */

    if (spwm_counter == 0)
    {
        /* Inicio de ciclo: encender si duty > 0 */
        if (spwm_duty > 0)
            SPWM_PORT |= (1 << SPWM_PIN);
    }
    else if (spwm_counter == spwm_duty)
    {
        /* Llegamos al umbral: apagar */
        SPWM_PORT &= ~(1 << SPWM_PIN);
    }
}