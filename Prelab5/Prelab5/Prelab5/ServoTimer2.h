/*
 * ServoTimer2.h
 *
 * Librería para control de servo mediante Timer2 PWM (OC2B - PD3)
 * Timer2: 8 bits, Phase Correct PWM, prescaler 1024
 * F_CPU = 16MHz ? f_tick = 15625Hz ? 1 tick ? 64µs
 *
 * Pulsos:
 *   1.0ms (0°)   ? ~16 ticks
 *   2.5ms (180°) ? ~39 ticks
 */
#ifndef SERVO_TIMER2_H_
#define SERVO_TIMER2_H_

#include <avr/io.h>
#include <stdint.h>

/* ---------------------------------------------------------------
 * Límites en ticks (1 tick = 64µs con prescaler 1024 a 16MHz)
 * --------------------------------------------------------------- */
#define SERVO2_MIN_TICKS    16U   /* ~1.0ms = 0°   */
#define SERVO2_MAX_TICKS    39U   /* ~2.5ms = 180° */
#define SERVO2_RANGE_TICKS  23U   /* 39 - 16       */

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Servo2_Init
 * Configura PD3 (OC2B) como salida y Timer2 en modo
 * Phase Correct PWM. Posición inicial: 0°.
 */
void Servo2_Init(void);

/*
 * Servo2_SetPosition
 * Mapea un valor ADC de 8 bits (0–255) al rango 0°–180°.
 */
void Servo2_SetPosition(uint8_t adc_val);

/*
 * Servo2_SetTicks
 * Escribe directamente en OCR2B con saturación en los límites.
 */
void Servo2_SetTicks(uint8_t ticks);

#ifdef __cplusplus
}
#endif

#endif /* SERVO_TIMER2_H_ */