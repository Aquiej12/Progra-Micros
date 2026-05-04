#include "servo.h"

// Memoria independiente para 4 canales posibles
static uint8_t s_min_ocr[4];
static uint8_t s_max_ocr[4];
static uint16_t s_min_adc[4];
static uint16_t s_max_adc[4];

void Servo_Init(uint8_t canal, uint16_t prescaler, uint8_t min_ocr, uint8_t max_ocr, uint16_t min_adc, uint16_t max_adc)
{
	// 1. Guardamos el perfil en el casillero correspondiente al canal
	s_min_ocr[canal] = min_ocr;
	s_max_ocr[canal] = max_ocr;
	s_min_adc[canal] = min_adc;
	s_max_adc[canal] = max_adc;

	// 2. Lógica de Hardware (Seleccionar Timer y Prescaler)
	if (canal == CANAL_T0_A || canal == CANAL_T0_B)
	{
		// Configurar Timer0 para Fast PWM
		TCCR0A |= (1 << WGM01) | (1 << WGM00);
		
		if (canal == CANAL_T0_A) {
			DDRD |= (1 << PD6);             // Pin como salida
			TCCR0A |= (1 << COM0A1);        // Activar PWM en OC0A
			OCR0A = min_ocr;                // Posición inicial
			} else {
			DDRD |= (1 << PD5);
			TCCR0A |= (1 << COM0B1);
			OCR0B = min_ocr;
		}

		// Configurar Prescaler Timer0
		if (prescaler == 64)        TCCR0B |= (1 << CS01) | (1 << CS00);
		else if (prescaler == 256)  TCCR0B |= (1 << CS02);
		else if (prescaler == 1024) TCCR0B |= (1 << CS02) | (1 << CS00);
	}
	else if (canal == CANAL_T2_A || canal == CANAL_T2_B)
	{
		// Configurar Timer2 para Fast PWM
		TCCR2A |= (1 << WGM21) | (1 << WGM20);
		
		if (canal == CANAL_T2_A) {
			DDRB |= (1 << PB3);
			TCCR2A |= (1 << COM2A1);
			OCR2A = min_ocr;
			} else {
			DDRD |= (1 << PD3);
			TCCR2A |= (1 << COM2B1);
			OCR2B = min_ocr;
		}

		// Configurar Prescaler Timer2 (¡Nota que los bits de T2 son diferentes a los de T0!)
		if (prescaler == 64)        TCCR2B |= (1 << CS22);
		else if (prescaler == 256)  TCCR2B |= (1 << CS22) | (1 << CS21);
		else if (prescaler == 1024) TCCR2B |= (1 << CS22) | (1 << CS21) | (1 << CS20);
	}
}

void Servo_SetFromADC(uint8_t canal, uint16_t adc_val)
{
	// Extraemos los límites guardados para este canal en específico
	uint8_t min_ocr_actual = s_min_ocr[canal];
	uint8_t max_ocr_actual = s_max_ocr[canal];
	uint16_t min_adc_actual = s_min_adc[canal];
	uint16_t max_adc_actual = s_max_adc[canal];

	if (adc_val < min_adc_actual) adc_val = min_adc_actual;
	if (adc_val > max_adc_actual) adc_val = max_adc_actual;

	uint32_t rango_adc = max_adc_actual - min_adc_actual;
	uint8_t rango_servo = max_ocr_actual - min_ocr_actual;

	// Calculamos la posición
	uint8_t ocr_calc = (uint8_t)(min_ocr_actual + ((uint32_t)(adc_val - min_adc_actual) * rango_servo) / rango_adc);

	// Asignamos el valor al registro físico correcto
	if (canal == CANAL_T0_A) OCR0A = ocr_calc;
	else if (canal == CANAL_T0_B) OCR0B = ocr_calc;
	else if (canal == CANAL_T2_A) OCR2A = ocr_calc;
	else if (canal == CANAL_T2_B) OCR2B = ocr_calc;
}