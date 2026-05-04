#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>

#include "servo.h"
#include "soft_servo.h"

// ?? 1. REGRESAMOS EL ADC A MODO MANUAL ??
void ADC_Init(void)
{
	ADMUX = (1 << REFS0);
	// ¡OJO AQUÍ! Quitamos el (1 << ADIE) para apagar la interrupción del ADC
	ADCSRA = (1 << ADEN) | (1 << ADPS2) | (1 << ADPS1) | (1 << ADPS0);
}

// Función manual y segura para leer cualquier canal
uint16_t ADC_Read(uint8_t canal_adc)
{
	// Cambiamos el canal
	ADMUX = (ADMUX & 0xF0) | (canal_adc & 0x0F);
	// Iniciamos la conversión
	ADCSRA |= (1 << ADSC);
	// Esperamos a que termine (totalmente a prueba de fallos)
	while (ADCSRA & (1 << ADSC));
	return ADC;
}

int main(void)
{
	ADC_Init();

	// ?? 2. MOTORES POR HARDWARE (Límites 7 a 38) ??
	Servo_Init(CANAL_T0_A, 1024, 7, 38, 5, 1000); // D6
	Servo_Init(CANAL_T2_A, 1024, 8, 30, 20, 950); // D11
	
	// ?? 3. MOTORES POR SOFTWARE (Límites 50 a 240) ??
	SoftServo_Init();
	SoftServo_Attach(0, &PORTB, &DDRB, PB0, 20, 220, 5, 1000); // D8
	SoftServo_Attach(1, &PORTB, &DDRB, PB1, 20, 220, 5, 1000); // D9

	// Activamos interrupciones (Ahora SOLO el metrónomo usará interrupciones)
	sei();

	while (1)
	{
		// 4. Leemos los potenciómetros uno por uno tranquilamente
		uint16_t pot0 = ADC_Read(0); // Pin A0
		uint16_t pot1 = ADC_Read(1); // Pin A1
		uint16_t pot2 = ADC_Read(2); // Pin A2
		uint16_t pot3 = ADC_Read(3); // Pin A3
		
		// 5. Movemos los motores
		Servo_SetFromADC(CANAL_T0_A, pot0);
		Servo_SetFromADC(CANAL_T2_A, pot1);
		
		SoftServo_SetFromADC(0, pot2);
		SoftServo_SetFromADC(1, pot3);
		
		// El descanso mecánico de 20ms
		
	}
	
	return 0;
}