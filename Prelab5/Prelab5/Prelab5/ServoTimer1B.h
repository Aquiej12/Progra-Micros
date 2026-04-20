/*
 * ServoTimer1B.h
 */
#ifndef SERVO_TIMER1B_H_
#define SERVO_TIMER1B_H_

#include <avr/io.h>
#include <stdint.h>

/* Mismos límites que ServoTimer1 */
#define SERVO_B_MIN_TICKS    1000U
#define SERVO_B_MAX_TICKS    5000U
#define SERVO_B_RANGE_TICKS  4000U

#ifdef __cplusplus
extern "C" {
#endif

void Servo_B_Init(void);
void Servo_B_SetPosition(uint8_t adc_val);
void Servo_B_SetTicks(uint16_t ticks);

#ifdef __cplusplus
}
#endif

#endif /* SERVO_TIMER1B_H_ */