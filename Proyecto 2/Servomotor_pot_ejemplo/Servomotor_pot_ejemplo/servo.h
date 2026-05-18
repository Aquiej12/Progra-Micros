#ifndef SERVO_H_
#define SERVO_H_

#include <avr/io.h>
#include <stdint.h>

#define CANAL_T0_A 0  // Timer0 OC0A → PD6 (D6)
#define CANAL_T0_B 1  // Timer0 OC0B → PD5 (D5)
#define CANAL_T2_A 2  // Timer2 OC2A → PB3 (D11)
#define CANAL_T2_B 3  // Timer2 OC2B → PD3 (D3)

void Servo_Init(uint8_t canal, uint16_t prescaler, uint8_t min_ocr, uint8_t max_ocr,
                uint16_t min_adc, uint16_t max_adc);
void Servo_SetFromADC(uint8_t canal, uint16_t adc_val);
void Servo_SetAngle(uint8_t canal, uint8_t deg);

#endif /* SERVO_H_ */
