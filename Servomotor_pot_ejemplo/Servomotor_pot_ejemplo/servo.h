#ifndef SERVO_H_
#define SERVO_H_

#include <avr/io.h>
#include <stdint.h>

/* ?? Nombres de Canales (0 a 3) ?? */
#define CANAL_T0_A  0  // Usa Timer0, Pin PD6 (D6)
#define CANAL_T0_B  1  // Usa Timer0, Pin PD5 (D5)
#define CANAL_T2_A  2  // Usa Timer2, Pin PB3 (D11)
#define CANAL_T2_B  3  // Usa Timer2, Pin PD3 (D3)

/* ?? Funciones ?? */
// Inicializa un canal con su prescaler y límites únicos
void Servo_Init(uint8_t canal, uint16_t prescaler, uint8_t min_ocr, uint8_t max_ocr, uint16_t min_adc, uint16_t max_adc);

// Mueve el servo en un canal específico
void Servo_SetFromADC(uint8_t canal, uint16_t adc_val);

#endif /* SERVO_H_ */