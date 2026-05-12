#ifndef SOFT_SERVO_H_
#define SOFT_SERVO_H_

#include <avr/io.h>
#include <stdint.h>

#define MAX_SOFT_SERVOS 5

void SoftServo_Init(void);
void SoftServo_Attach(uint8_t canal, volatile uint8_t *puerto, volatile uint8_t *ddr,
                      uint8_t pin, uint16_t min_tick, uint16_t max_tick,
                      uint16_t min_adc, uint16_t max_adc);
void SoftServo_SetFromADC(uint8_t canal, uint16_t adc_val);
void SoftServo_SetAngle(uint8_t canal, uint8_t deg);
void SoftServo_SetTicks(uint8_t canal, uint16_t ticks);

#endif /* SOFT_SERVO_H_ */
