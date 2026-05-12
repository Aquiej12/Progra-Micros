#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include "servo.h"
#include "soft_servo.h"
#include "flexi_timer.h"

/* ── Pin map ────────────────────────────────────────────────────────
   Pata  Función    Pin   Puerto  Tipo
   ────  ─────────  ────  ──────  ──────────────
   S1.1  knee RF    D11   PB3     Soft ch0
   S1    hip  RF    D10   PB2     Soft ch1
   S2    hip  RB    D9    PB1     Soft ch2
   S2.1  knee RB    D8    PB0     Soft ch3
   S3    hip  LB    D7    PD7     Soft ch4
   S3.1  knee LB    D6    PD6     HW Timer0 OC0A
   S4    hip  LF    D5    PD5     HW Timer0 OC0B
   S4.1  knee LF    D4    PD4     Soft ch5

   Timer0 -> HW PWM:  KNEE_S3 (D6) + HIP_S4 (D5)
   Timer1 -> Soft PWM: 6 canales
   Timer2 -> FlexiTimer (frame_flag cada 10 ms)

   Lados:  DERECHA = S1, S2  |  IZQUIERDA = S3, S4

   Layout fisico:
            FRENTE
     S4(LF)       S1(RF)
     [  cuerpo  ]
     S3(LB)       S2(RB)
            ATRAS
   ─────────────────────────────────────────────────────────────── */

/* HW PWM (Timer0) */
#define HW_KNEE_S3  CANAL_T0_A
#define HW_HIP_S4   CANAL_T0_B

/* Soft servo channel indices */
#define SW_KNEE_S1  0
#define SW_HIP_S1   1
#define SW_HIP_S2   2
#define SW_KNEE_S2  3
#define SW_HIP_S3   4
#define SW_KNEE_S4  5

/* ════════════════════════════════════════════════════════════════════
 *  POSTURA Y SECUENCIA  (Crawl Gait)
 * ═══════════════════════════════════════════════════════════════════ */
#define HIP_CTR         90

#define KB_S1           25
#define KB_S2           35
#define KB_S3           25
#define KB_S4           35
static const uint8_t KB[4] = { KB_S1, KB_S2, KB_S3, KB_S4 };

#define KNEE_LIFT       40
#define KNEE_STAB       10
#define HIP_SWING       40
#define YAW_SWING       40
#define HIP_PUSH        15
#define STEP_TICKS      5
#define KNEE_MAX        90
#define KNEE_OFF_MAX    35
#define DEADZONE        35
#define JOY_SAMPLES     16

/* ════════════════════════════════════════════════════════════════════
 *  TABLAS
 * ═══════════════════════════════════════════════════════════════════ */

/* Crawl: RF(0) -> LB(2) -> RB(1) -> LF(3) */
static const uint8_t SEQ[4] = { 0, 2, 1, 3 };

/* Diagonal opuesta: S1(RF)<->S3(LB), S2(RB)<->S4(LF) */
static const uint8_t OPP[4] = { 2, 3, 0, 1 };

/* ════════════════════════════════════════════════════════════════════
 *  ESPEJO POR LADO
 *  S1,S2 = DERECHA  -> -1
 *  S3,S4 = IZQUIERDA -> +1
 *  Si avanza al reves, cambiar: return (leg <= 1) ? 1 : -1;
 * ═══════════════════════════════════════════════════════════════════ */
static int8_t side_mirror(uint8_t leg) {
    return (leg <= 1) ? -1 : 1;
}

/* ════════════════════════════════════════════════════════════════════
 *  ESTADO GLOBAL
 * ═══════════════════════════════════════════════════════════════════ */
static uint8_t  hip_pos[4]  = { HIP_CTR, HIP_CTR, HIP_CTR, HIP_CTR };
static uint16_t joy_center[4];
static int16_t  smooth_knee_off = 0;

typedef enum { IDLE, SEQ_WAIT } GaitState;

static GaitState state      = IDLE;
static uint8_t   seq_leg    = 0;
static uint8_t   seq_step   = 0;
static uint16_t  wait_ticks = 0;
static int8_t    direction  = 0;

/* Frame flag — levantada por FlexiTimer cada 10 ms */
static volatile uint8_t frame_flag = 0;

static void frame_tick(void) {
    frame_flag = 1;
}

/* ════════════════════════════════════════════════════════════════════
 *  ADC
 * ═══════════════════════════════════════════════════════════════════ */
static void ADC_Init(void) {
    ADMUX  = (1 << REFS0);
    ADCSRA = (1 << ADEN)|(1 << ADPS2)|(1 << ADPS1)|(1 << ADPS0);
}

static uint16_t ADC_Read(uint8_t ch) {
    ADMUX = (ADMUX & 0xF0) | (ch & 0x0F);
    _delay_us(10);
    ADCSRA |= (1 << ADSC);
    while (ADCSRA & (1 << ADSC));
    return ADC;
}

static void joy_calibrate(void) {
    uint8_t  i, ch;                          /* declarar al inicio del bloque */
    uint32_t s[4] = {0, 0, 0, 0};
    for (i = 0; i < JOY_SAMPLES; i++)
        for (ch = 0; ch < 4; ch++) s[ch] += ADC_Read(ch);
    for (ch = 0; ch < 4; ch++)
        joy_center[ch] = (uint16_t)(s[ch] / JOY_SAMPLES);
}

/* ════════════════════════════════════════════════════════════════════
 *  HELPERS
 * ═══════════════════════════════════════════════════════════════════ */
static int16_t clamp16(int16_t v, int16_t lo, int16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static int16_t dz(int16_t v) {
    return (v > -DEADZONE && v < DEADZONE) ? 0 : v;
}

/* Dispatch: idx 0..3 = caderas, idx 4..7 = rodillas */
static void set_servo(uint8_t idx, uint8_t deg) {
    switch (idx) {
        case 0: SoftServo_SetAngle(SW_HIP_S1,  deg); break;
        case 1: SoftServo_SetAngle(SW_HIP_S2,  deg); break;
        case 2: SoftServo_SetAngle(SW_HIP_S3,  deg); break;
        case 3: Servo_SetAngle(HW_HIP_S4,      deg); break;
        case 4: SoftServo_SetAngle(SW_KNEE_S1, deg); break;
        case 5: SoftServo_SetAngle(SW_KNEE_S2, deg); break;
        case 6: Servo_SetAngle(HW_KNEE_S3,     deg); break;
        case 7: SoftServo_SetAngle(SW_KNEE_S4, deg); break;
    }
}

static void go_stance(const uint8_t *kb) {
    uint8_t i;
    for (i = 0; i < 4; i++) {
        hip_pos[i] = HIP_CTR;
        set_servo(i,     HIP_CTR);
        set_servo(i + 4, kb[i]);
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SECUENCIADOR
 *  Paso 0 - LIFT:  rodilla sube + opuesta diagonal ancla
 *  Paso 1 - SWING: cadera avanza/gira
 *  Paso 2 - PLANT: rodilla baja al piso
 *  Paso 3 - PUSH:  TODAS las caderas empujan el cuerpo
 * ═══════════════════════════════════════════════════════════════════ */
static void execute_step(uint8_t leg, uint8_t step, int8_t dir,
                         uint8_t turning, const uint8_t *kb)
{
    uint8_t opp = OPP[leg];
    uint8_t i;                               /* para el bucle del PUSH */

    switch (step) {

    case 0: /* LIFT */
        set_servo(leg + 4, (uint8_t)clamp16(
            (int16_t)kb[leg] + KNEE_LIFT, 0, KNEE_MAX));
        set_servo(opp + 4, (uint8_t)clamp16(
            (int16_t)kb[opp] - KNEE_STAB, 0, KNEE_MAX));
        break;

    case 1: /* SWING */
        if (turning) {
            hip_pos[leg] = (uint8_t)clamp16(
                (int16_t)HIP_CTR + dir * YAW_SWING, 10, 170);
        } else {
            hip_pos[leg] = (uint8_t)clamp16(
                (int16_t)HIP_CTR + dir * HIP_SWING * side_mirror(leg),
                10, 170);
        }
        set_servo(leg, hip_pos[leg]);
        break;

    case 2: /* PLANT */
        set_servo(leg + 4, kb[leg]);
        set_servo(opp + 4, kb[opp]);
        break;

    case 3: /* PUSH */
        for (i = 0; i < 4; i++) {
            if (turning) {
                hip_pos[i] = (uint8_t)clamp16(
                    (int16_t)hip_pos[i] - dir * HIP_PUSH, 10, 170);
            } else {
                hip_pos[i] = (uint8_t)clamp16(
                    (int16_t)hip_pos[i] - dir * HIP_PUSH * side_mirror(i),
                    10, 170);
            }
            set_servo(i, hip_pos[i]);
        }
        break;
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  MAIN
 * ═══════════════════════════════════════════════════════════════════ */
int main(void) {
    /* ── Declarar TODAS las variables al inicio (C89) ─────────── */
    uint8_t  i;
    int16_t  j1y, j2y, j3;
    int8_t   new_dir;
    uint8_t  is_turning;
    int16_t  target_knee_off;
    uint8_t  kb[4];

    ADC_Init();

    /* HW PWM: Timer0 */
    Servo_Init(HW_KNEE_S3, 1024, 7, 38, 4, 962);
    Servo_Init(HW_HIP_S4,  1024, 7, 38, 4, 962);

    /* Soft PWM: Timer1 ISR, 6 canales */
    SoftServo_Init();
    SoftServo_Attach(SW_KNEE_S1, &PORTB, &DDRB, PB3, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S1,  &PORTB, &DDRB, PB2, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S2,  &PORTB, &DDRB, PB1, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S2, &PORTB, &DDRB, PB0, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S3,  &PORTD, &DDRD, PD7, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S4, &PORTD, &DDRD, PD4, 30, 120, 4, 962);

    /* FlexiTimer: Timer2, frame_flag cada 10 ms */
    FlexiTimer_Set(10, frame_tick);
    FlexiTimer_Start();

    sei();
    joy_calibrate();

    go_stance(KB);
    _delay_ms(500);

    while (1) {
        /* Esperar el tick de 10 ms */
        if (!frame_flag) continue;
        frame_flag = 0;

        /* 1. Leer joysticks */
        j1y = dz((int16_t)ADC_Read(1) - (int16_t)joy_center[1]);
        j2y =    (int16_t)ADC_Read(2) - (int16_t)joy_center[2];
        j3  = dz((int16_t)ADC_Read(3) - (int16_t)joy_center[3]);

        /* 2. Direccion + giro */
        new_dir    = 0;
        is_turning = 0;

        if (j1y > 0) new_dir =  1;
        if (j1y < 0) new_dir = -1;
        if (j3 != 0) {
            new_dir    = (j3 > 0) ? 1 : -1;
            is_turning = 1;
        }

        /* 3. Altura con proteccion (filtro +/-1 grado/frame) */
        target_knee_off = clamp16(
            (int16_t)((int32_t)j2y * 65 / 512),
            -KNEE_OFF_MAX, KNEE_OFF_MAX);

        if (smooth_knee_off < target_knee_off) smooth_knee_off++;
        if (smooth_knee_off > target_knee_off) smooth_knee_off--;

        for (i = 0; i < 4; i++) {
            kb[i] = (uint8_t)clamp16(
                (int16_t)KB[i] + smooth_knee_off, 0, KNEE_MAX);
        }

        /* 4. FSM */
        switch (state) {

        case IDLE:
            go_stance(kb);
            if (new_dir != 0) {
                direction  = new_dir;
                seq_leg    = 0;
                seq_step   = 0;
                execute_step(SEQ[0], 0, direction, is_turning, kb);
                wait_ticks = STEP_TICKS;
                state      = SEQ_WAIT;
            }
            break;

        case SEQ_WAIT:
            if (new_dir == 0) {
                go_stance(kb);
                state = IDLE;
                break;
            }
            direction = new_dir;

            if (wait_ticks > 0) {
                wait_ticks--;
                break;
            }

            seq_step++;
            if (seq_step >= 4) {
                seq_step = 0;
                seq_leg  = (seq_leg + 1) & 3;
            }
            execute_step(SEQ[seq_leg], seq_step, direction,
                         is_turning, kb);
            wait_ticks = STEP_TICKS;
            break;
        }
    }

    return 0;
}
