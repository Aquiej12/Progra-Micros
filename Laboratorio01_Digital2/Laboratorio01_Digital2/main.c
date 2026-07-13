/*
 * Laboratorio01_Digital2.c
 *
 * Created: 9/07/2026 17:28:22
 * Author: Abner Quiej
 * Description: Juego de carreras con ATmega328P (Arduino Nano). Dos jugadores
 *              compiten presionando un boton para avanzar hacia la meta,
 *              representada mediante un contador de decadas de 4 bits (LEDs).
 *              Antes de la carrera hay un conteo regresivo en display de 7 seg.
 */
/****************************************/
// Encabezado (Libraries)
#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <stdint.h>

/****************************************/
// Constantes de configuracion
#define TIMER1_OCR    249   // CTC + prescaler 64 -> interrupcion cada 1 ms


// Estados del juego
#define ST_IDLE       0     // esperando boton de inicio
#define ST_COUNTDOWN  1     // conteo regresivo, botones de jugadores deshabilitados
#define ST_RACE       2     // carrera activa
#define ST_END        3     // hay ganador, entradas deshabilitadas

/****************************************/
// Variables globales
volatile uint8_t counterp1 = 0;   // LEDs del Player 1
volatile uint8_t counterp2 = 0;   // LEDs del Player 2

volatile uint8_t flag_p1   = 0;   // Bandera: pulsacion de P1
volatile uint8_t flag_p2   = 0;   // Bandera: pulsacion de P2
volatile uint8_t flag_star = 0;   // Bandera: pulsacion de inicio

volatile uint8_t race_active = 0; // 1 = los botones de jugadores estan habilitados
volatile uint16_t ms = 0;         // contador de milisegundos (base de tiempo)

/****************************************/
// Function prototypes
void initPins(void);
void initTimer1(void);
void showLEDs(void);
void endGame(void);


/****************************************/
// Main Function
int main(void)
{
	initPins();
	initTimer1();
	sei();

	uint8_t  state       = ST_IDLE;
	uint8_t  countdown    = 0;
	uint16_t ms_last      = 0;


	while (1)
	{
		switch (state)
		{
			// --- Esperando el boton de inicio ---
			case ST_IDLE:
				if (flag_star)
				{
					flag_star  = 0;
					counterp1  = 0;
					counterp2  = 0;
					showLEDs();           // limpiar LEDs de la partida anterior
					countdown  = 5;
					ms_last    = ms;
					state = ST_COUNTDOWN;
				}
				break;

			// --- Conteo regresivo (botones de jugadores deshabilitados) ---
			case ST_COUNTDOWN:
				if ((uint16_t)(ms - ms_last) >= 1000)   // paso de 1 segundo
				{
					ms_last += 1000;
					if (countdown == 0)
					{
						flag_p1 = 0;          // descartar cualquier pulsacion previa
						flag_p2 = 0;
						race_active = 1;      // habilitar botones de jugadores
						showLEDs();           // posicion inicial de los "autos"
						state = ST_RACE;
					}
					else
					{
						countdown--;
					}
				}
				break;

			// --- Carrera: rutinas independientes de cada jugador ---
			case ST_RACE:
				// Rutina Player 1: cuenta una vez por pulsacion (anti-rebote en el ISR)
				if (flag_p1)
				{
					flag_p1 = 0;
					counterp1++;
					showLEDs();
				}

				// Rutina Player 2: independiente, no la bloquea la de P1
				if (flag_p2)
				{
					flag_p2 = 0;
					counterp2++;
					showLEDs();
				}

				// Revisar si alguien llego a la meta
				if (counterp1 >= 4 || counterp2 >= 4)
				{
					race_active = 0;   // deshabilitar botones de jugadores
					state = ST_END;
				}
				break;

			// --- Fin del juego: permitir reinicio con el boton de inicio ---
			case ST_END:
				if (flag_star)
				{
					flag_star = 0;
					state = ST_IDLE;
				}
				break;
		}
	}
}

/****************************************/
// NON-Interrupt subroutines
void initTimer1(void)
{
	TCCR1A = 0;
	TCCR1B = (1<<WGM12) | (1<<CS11) | (1<<CS10);  // CTC, prescaler 64
	OCR1A  = TIMER1_OCR;                          // interrupcion cada 1 ms
	TIMSK1 |= (1<<OCIE1A);
	TCNT1  = 0;
}

void initPins(void)
{
	// --- PORTD: segmentos del display (salida) ---
	DDRD   = 0xFF;
	PORTD  = 0x00;
	UCSR0B = 0x00;   // deshabilitar UART para liberar PD0 y PD1

	// --- PORTB: PB0-PB3 salidas (LEDs Player 1) ---
	DDRB  |=  (1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3);
	PORTB &= ~((1<<PB0)|(1<<PB1)|(1<<PB2)|(1<<PB3));

	// --- PORTB: PB4 entrada (boton Player 2) con pull-up ---
	// (PB5 = D13 tiene el LED integrado y no sirve como entrada)
	DDRB  &= ~(1<<PB4);
	PORTB |=  (1<<PB4);

	// --- PORTC: PC0-PC3 salidas (LEDs Player 2) ---
	DDRC  |=  (1<<PC0)|(1<<PC1)|(1<<PC2)|(1<<PC3);
	PORTC &= ~((1<<PC0)|(1<<PC1)|(1<<PC2)|(1<<PC3));

	// --- PORTC: PC4 (inicio) y PC5 (Player 1) entradas con pull-up ---
	DDRC  &= ~((1<<PC4)|(1<<PC5));
	PORTC |=  (1<<PC4)|(1<<PC5);
}

void showLEDs(void)
{
	// botones que estan en los bits altos (PB5, PC4, PC5).
	PORTB = (PORTB & 0xF0) | ((counterp1 >= 1 && counterp1 <= 4) ? (1 << (counterp1 - 1)) : 0);
	PORTC = (PORTC & 0xF0) | ((counterp2 >= 1 && counterp2 <= 4) ? (1 << (counterp2 - 1)) : 0);
}



/****************************************/
// Interrupt routines

// Anti-rebote por muestreo cada 1 ms: se detecta el flanco de bajada
// (boton activo en bajo). Como se lee una sola vez por transicion 1->0,
// cada pulsacion cuenta una unica vez y un boton no bloquea al otro.
ISR(TIMER1_COMPA_vect)
{
	static uint8_t prev_p1   = 1;
	static uint8_t prev_p2   = 1;
	static uint8_t prev_star = 1;

	ms++;   // base de tiempo de 1 ms

	// --- Boton de inicio (siempre habilitado, para iniciar/reiniciar) ---
	uint8_t curr_star = (PINC & (1<<PC4)) ? 1 : 0;
	if (prev_star == 1 && curr_star == 0) flag_star = 1;
	prev_star = curr_star;

	// --- Botones de jugadores: solo durante la carrera ---
	if (race_active)
	{
		uint8_t curr_p1 = (PINC & (1<<PC5)) ? 1 : 0;
		uint8_t curr_p2 = (PINB & (1<<PB4)) ? 1 : 0;

		if (prev_p1 == 1 && curr_p1 == 0) flag_p1 = 1;   // Player 1
		if (prev_p2 == 1 && curr_p2 == 0) flag_p2 = 1;   // Player 2

		prev_p1 = curr_p1;
		prev_p2 = curr_p2;
	}
	else
	{
		prev_p1 = 1;   // dejar listo el flanco para la siguiente carrera
		prev_p2 = 1;
	}
}
