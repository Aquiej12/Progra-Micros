/*
 * SoftPWM.h
 *
 * PWM manual por software usando Timer2 (interrupción por overflow)
 * LED en PD5, potenciómetro en ADC2 (PC2)
 *
 * Principio:
 *   - Timer2 desborda cada ~32µs (prescaler 8, 16MHz)
 *   - Contador interno de 0 a 255 (periodo PWM completo)
 *   - Cuando contador == 0      ? LED encendido (HIGH)
 *   - Cuando contador == umbral ? LED apagado  (LOW)
 *   - umbral = 0   ? 0% duty (siempre apagado)
 *   - umbral = 255 ? 100% duty (siempre encendido)
 */
#ifndef SOFT_PWM_H_
#define SOFT_PWM_H_

#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdint.h>

/* Pin de salida del LED */
#define SPWM_DDR   DDRD
#define SPWM_PORT  PORTD
#define SPWM_PIN   PD5

#ifdef __cplusplus
extern "C" {
#endif

/*
 * SoftPWM_Init
 * Configura PD5 como salida y Timer2 en modo CTC
 * con interrupción por comparación. NO inicia sei().
 */
void SoftPWM_Init(void);

/*
 * SoftPWM_SetDuty
 * Actualiza el umbral de duty cycle (0–255).
 * 0 = apagado, 255 = encendido total.
 */
void SoftPWM_SetDuty(uint8_t duty);

#ifdef __cplusplus
}
#endif

#endif /* SOFT_PWM_H_ */