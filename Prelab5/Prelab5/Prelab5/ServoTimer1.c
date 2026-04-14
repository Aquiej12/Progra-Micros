/*
 * ServoTimer1.c
 *
 */

#include "ServoTimer1.h"

/* ---------------------------------------------------------------
 * Servo_Init
 * --------------------------------------------------------------- */
void Servo_Init(void)
{
    /* PB1 (OC1A) como salida */
    DDRB |= (1 << PB1);

    /* Modo Fast PWM, TOP = ICR1, salida no invertida */
    TCCR1A = (1 << COM1A1) | (1 << WGM11);
    TCCR1B = (1 << WGM13)  | (1 << WGM12) | (1 << CS11);

    ICR1  = 39999;           /* TOP: periodo exacto de 20ms a 16MHz/8 */
    OCR1A = SERVO_MIN_TICKS; /* Posición inicial: 0°                  */
}


void Servo_SetPosition(uint8_t adc_val)
{
    uint16_t ticks = SERVO_MIN_TICKS
                   + (uint16_t)(((uint32_t)adc_val * SERVO_RANGE_TICKS) / 255U);
    Servo_SetTicks(ticks);
}

void Servo_SetTicks(uint16_t ticks)
{
    if (ticks < SERVO_MIN_TICKS) ticks = SERVO_MIN_TICKS;
    if (ticks > SERVO_MAX_TICKS) ticks = SERVO_MAX_TICKS;
    OCR1A = ticks;
}
