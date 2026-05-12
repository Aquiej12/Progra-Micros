#ifndef FLEXI_TIMER_H_
#define FLEXI_TIMER_H_

/*  flexi_timer — reimplementación en C puro de FlexiTimer2
 *
 *  Usa Timer2 en modo overflow (Normal) con prescaler 64.
 *  A 16 MHz: tick = 1 ms exacto (recarga TCNT2 = 6 → 250 cuentas).
 *
 *  API:
 *    FlexiTimer_Set(ms, callback)  — configura período e ISR
 *    FlexiTimer_Start()            — arranca el timer
 *    FlexiTimer_Stop()             — detiene el timer
 *
 *  El callback se ejecuta dentro de ISR(TIMER2_OVF_vect).
 *  Mantenerlo CORTO (ej. solo levantar una bandera).
 */

#include <stdint.h>

void FlexiTimer_Set(uint16_t ms, void (*callback)(void));
void FlexiTimer_Start(void);
void FlexiTimer_Stop(void);

#endif /* FLEXI_TIMER_H_ */
