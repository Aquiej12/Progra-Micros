#ifndef FLEXI_TIMER_H_
#define FLEXI_TIMER_H_


#include <stdint.h>

void FlexiTimer_Set(uint16_t ms, void (*callback)(void));
void FlexiTimer_Start(void);
void FlexiTimer_Stop(void);

#endif /* FLEXI_TIMER_H_ */
