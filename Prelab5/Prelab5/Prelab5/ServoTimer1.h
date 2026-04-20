/*
 * ServoTimer1.h
 *
 * Librería para control de servo mediante Timer1 PWM (OC1A - PB1)

 */

#ifndef SERVO_TIMER1_H_
#define SERVO_TIMER1_H_

#include <avr/io.h>
#include <stdint.h>


#define SERVO_MIN_TICKS   1000U   /* 0.5ms = 0°   */
#define SERVO_MAX_TICKS   5000U   /* 2.5ms = 180° */
#define SERVO_RANGE_TICKS 4000U

#ifdef __cplusplus
extern "C" {
#endif


void Servo_Init(void);


void Servo_SetPosition(uint8_t adc_val);


void Servo_SetTicks(uint16_t ticks);

#ifdef __cplusplus
}
#endif

#endif /* SERVO_TIMER1_H_ */
