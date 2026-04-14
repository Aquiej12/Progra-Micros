/*
 * ServoTimer1.h
 *
 * Librería para control de servo mediante Timer1 PWM (OC1A - PB1)

 */

#ifndef SERVO_TIMER1_H_
#define SERVO_TIMER1_H_

#include <avr/io.h>
#include <stdint.h>

/* ---------------------------------------------------------------
 * Límites de pulso en ticks
 * Prescaler 8 → 1 tick = 0.5µs
 * Servo estándar: 1ms (0°) a 2ms (180°)
 *   1ms = 2000 ticks
 *   2ms = 4000 ticks
 * --------------------------------------------------------------- */
#define SERVO_MIN_TICKS   1000U   /* 0.5ms = 0°   */
#define SERVO_MAX_TICKS   5000U   /* 2.5ms = 180° */
#define SERVO_RANGE_TICKS 4000U

#ifdef __cplusplus
extern "C" {
#endif

/*
 * Servo_Init
 * Configura PB1 como salida y Timer1 en modo Fast PWM
 * con TOP = ICR1 para generar 50Hz.
 * Posición inicial: 0° (pulso de 1ms).
 */
void Servo_Init(void);

/*
 * Servo_SetPosition
 * Recibe un valor ADC de 8 bits (0–255) y lo mapea
 * linealmente al rango completo de movimiento del servo (0°–180°).
 */
void Servo_SetPosition(uint8_t adc_val);

/*
 * Servo_SetTicks
 * Escribe directamente en OCR1A con saturación en los límites.
 * Útil para control fino o conversión desde microsegundos.
 */
void Servo_SetTicks(uint16_t ticks);

#ifdef __cplusplus
}
#endif

#endif /* SERVO_TIMER1_H_ */
