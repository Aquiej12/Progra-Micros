#include "soft_servo.h"
#include <avr/interrupt.h>

static volatile uint8_t *s_puertos[MAX_SOFT_SERVOS];
static uint8_t s_pines_mask[MAX_SOFT_SERVOS];
static uint16_t s_ticks[MAX_SOFT_SERVOS];

// ¡NUEVOS! Arreglos para los límites físicos individuales
static uint16_t s_min_tick[MAX_SOFT_SERVOS];
static uint16_t s_max_tick[MAX_SOFT_SERVOS];
static uint16_t s_min_adc[MAX_SOFT_SERVOS];
static uint16_t s_max_adc[MAX_SOFT_SERVOS];

volatile uint16_t global_tick_counter = 0;

void SoftServo_Init(void)
{
	for(uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
		s_puertos[i] = 0;
		s_ticks[i] = 150; // Centro por defecto
	}

	TCCR1A = 0;
	TCCR1B = (1 << WGM12) | (1 << CS11); // Prescaler de 8 global
	OCR1A = 19; // 10 us por tick a 16MHz
	TIMSK1 |= (1 << OCIE1A);
}

void SoftServo_Attach(uint8_t canal, volatile uint8_t *puerto, volatile uint8_t *ddr, uint8_t pin, uint16_t min_tick, uint16_t max_tick, uint16_t min_adc, uint16_t max_adc)
{
	if(canal >= MAX_SOFT_SERVOS) return;

	*ddr |= (1 << pin); // Pin como salida

	// Guardamos el perfil único de este motor
	s_puertos[canal] = puerto;
	s_pines_mask[canal] = (1 << pin);
	s_min_tick[canal] = min_tick;
	s_max_tick[canal] = max_tick;
	s_min_adc[canal] = min_adc;
	s_max_adc[canal] = max_adc;
}

void SoftServo_SetFromADC(uint8_t canal, uint16_t adc_val)
{
	if(canal >= MAX_SOFT_SERVOS || s_puertos[canal] == 0) return;

	// Extraemos los topes específicos de ESTE canal
	uint16_t min_a = s_min_adc[canal];
	uint16_t max_a = s_max_adc[canal];
	uint16_t min_t = s_min_tick[canal];
	uint16_t max_t = s_max_tick[canal];

	if (adc_val < min_a) adc_val = min_a;
	if (adc_val > max_a) adc_val = max_a;

	uint32_t rango_adc = max_a - min_a;
	uint16_t rango_servo = max_t - min_t;

	// Calculamos usando los topes individuales
	s_ticks[canal] = min_t + ((uint32_t)(adc_val - min_a) * rango_servo) / rango_adc;
}

ISR(TIMER1_COMPA_vect)
{
	global_tick_counter++;

	if (global_tick_counter >= 2000) {
		global_tick_counter = 0;
		for(uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
			if(s_puertos[i] != 0) *(s_puertos[i]) |= s_pines_mask[i];
		}
	}

	for(uint8_t i = 0; i < MAX_SOFT_SERVOS; i++) {
		if(s_puertos[i] != 0 && global_tick_counter == s_ticks[i]) {
			*(s_puertos[i]) &= ~(s_pines_mask[i]);
		}
	}
}