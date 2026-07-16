/*
 * cinematica.h
 *
 * Motor de marcha CARTESIANO (creep gait) para el robot cuadrupedo.
 *
 * Modelo: cada pata tiene 2 servos -> CADERA (rotacion horizontal, mueve el
 * pie adelante/atras en Y) y RODILLA (sube/baja el pie). La posicion del pie
 * se expresa en milimetros sobre el eje Y (adelante/atras) y se convierte a
 * angulos con una IK LINEAL calibrable (ver GRADOS_POR_MM en cinematica.c).
 *
 * Reproduce el ciclo del diagrama:  STEP D, STEP C, SHIFT, STEP A, STEP B, SHIFT
 *
 * La maquina de marcha es NO BLOQUEANTE: se avanza llamando Gait_Tick() una vez
 * por cada tick de 10 ms. No usa _delay_ms, para no romper la reactividad LoRa.
 */

#ifndef CINEMATICA_H_
#define CINEMATICA_H_

#include <stdint.h>

#define N_LEGS 4

/* Indices logicos de pata (coinciden con los del main / soft_servo).
 * 0 = FL (S1)   1 = FR (S2)   2 = RR (S3)   3 = RL (S4)                    */

/* Coloca las 4 patas en la postura neutra (pies en Y=0, rodillas en stance).
 * knee_stand[] = angulo de rodilla plantada por pata (incluye offset de altura). */
void Gait_Init(const uint8_t knee_stand[N_LEGS]);

/* Fija la orden de marcha para el proximo tick:
 *   dir      : +1 adelante, -1 atras, 0 detenerse (vuelve a stance)
 *   knee_stand: angulo de rodilla plantada por pata (con altura ya aplicada)   */
void Gait_SetCommand(int8_t dir, const uint8_t knee_stand[N_LEGS]);

/* Avanza la maquina de marcha un paso de tiempo (llamar cada 10 ms).
 * Internamente recalcula coordenadas de pie -> angulos -> servos.
 * Devuelve 1 si en este tick el robot esta a mitad de un ciclo de marcha.     */
uint8_t Gait_Tick(void);

/* Convierte una coordenada de pie (y_mm) al angulo de cadera de esa pata.
 * Expuesta por si quieres usar la IK directamente o depurar la calibracion.   */
uint8_t IK_HipDeg(uint8_t leg, int16_t y_mm);

#endif /* CINEMATICA_H_ */
