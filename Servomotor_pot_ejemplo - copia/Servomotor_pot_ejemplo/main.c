#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include "servo.h"
#include "soft_servo.h"

/* ── Pin map (sin cambios) ───────────────────────────────────
   HW PWM:  HW_KNEE_S4→D6 OC0A | HW_HIP_S2→D5 OC0B | HW_KNEE_S1→D11 OC2A
   Soft:    ch0→D9 PB1(hip s1)  | ch1→D7 PD7(hip s4)  | ch2→D10 PB2(hip s3)
            ch3→D8 PB0(knee s3) | ch4→D4 PD4(knee s2)                        */
#define HW_KNEE_S4  CANAL_T0_A
#define HW_HIP_S2   CANAL_T0_B
#define HW_KNEE_S1  CANAL_T2_A
#define SW_HIP_S1   0
#define SW_HIP_S4   1
#define SW_HIP_S3   2
#define SW_KNEE_S3  3
#define SW_KNEE_S2  4

/* ── Parámetros de marcha ──────────────────────────────────── */
#define GAIT_SPEED       2     // deg/iter – BAJO para Step-Up 3.7V→5V
#define MAX_PHASE_CYCLES 280   // timeout de seguridad por sub-fase (~130 ms)
#define KNEE_BASE        45    // ángulo de stance
#define STAB_OFFSET      10    // rodillas soporte bajan X° antes del swing
#define HIP_CTR          90    // centro de cadera
#define HIP_MIN          60    // límite inferior ±30° desde centro
#define HIP_MAX          120   // límite superior
#define DEADZONE         35
#define JOY_SAMPLES      16

/* ── Arrays de estado: [0-3]=caderas s1-s4, [4-7]=rodillas s1-s4 ── */
static int16_t cur[8];
static int16_t tgt[8];

/* ── Secuencia Crawl: s1(0)→s3(2)→s2(1)→s4(3) ─────────────── */
static const uint8_t GAIT_SEQ[4] = {0, 2, 1, 3};
static uint8_t       gait_idx    = 0;

/* ── Lado por pata para yaw (+1=der, −1=izq) ────────────────── */
static const int8_t SIDE[4] = {1, -1, 1, -1};

/* ── FSM: 5 estados ──────────────────────────────────────────── */
typedef enum {
    IDLE,
    CRAWL_BALANCE,  // bajar rodillas soporte → estabilizar CoG
    CRAWL_LIFT,     // subir rodilla swing
    CRAWL_SWING,    // avanzar cadera swing
    CRAWL_PLANT     // bajar rodilla swing al piso
} GaitState;

/* ── Input flags ─────────────────────────────────────────────── */
static uint8_t flag_fwd, flag_back, flag_turn_R, flag_turn_L;

static uint16_t joy_center[4];
static uint16_t ph_cnt = 0;

/* ── ADC (sin cambios) ───────────────────────────────────────── */
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
    uint32_t s[4] = {0,0,0,0};
    for (uint8_t i = 0; i < JOY_SAMPLES; i++)
        for (uint8_t ch = 0; ch < 4; ch++) s[ch] += ADC_Read(ch);
    for (uint8_t ch = 0; ch < 4; ch++) joy_center[ch] = (uint16_t)(s[ch] / JOY_SAMPLES);
}

/* ── Helpers ─────────────────────────────────────────────────── */
static inline int16_t clamp16(int16_t v, int16_t lo, int16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}
static inline int16_t dz(int16_t v) {
    return (v > -DEADZONE && v < DEADZONE) ? 0 : v;
}

/* ── Dispatch unificado ──────────────────────────────────────── */
static void apply_servo(uint8_t idx, uint8_t deg) {
    switch (idx) {
        case 0: SoftServo_SetAngle(SW_HIP_S1,  deg); break;
        case 1: Servo_SetAngle(HW_HIP_S2,      deg); break;
        case 2: SoftServo_SetAngle(SW_HIP_S3,  deg); break;
        case 3: SoftServo_SetAngle(SW_HIP_S4,  deg); break;
        case 4: Servo_SetAngle(HW_KNEE_S1,     deg); break;
        case 5: SoftServo_SetAngle(SW_KNEE_S2, deg); break;
        case 6: SoftServo_SetAngle(SW_KNEE_S3, deg); break;
        case 7: Servo_SetAngle(HW_KNEE_S4,     deg); break;
    }
}

/* ── Interpolación no bloqueante ─────────────────────────────── */
static int16_t step_toward(int16_t c, int16_t t) {
    if (c < t) { c += GAIT_SPEED; return c > t ? t : c; }
    if (c > t) { c -= GAIT_SPEED; return c < t ? t : c; }
    return c;
}
static void interp_apply(void) {
    for (uint8_t i = 0; i < 8; i++) {
        cur[i] = step_toward(cur[i], tgt[i]);
        apply_servo(i, (uint8_t)cur[i]);
    }
}

/* ── Comprobación de llegada a target (tolerancia ±GAIT_SPEED) ─ */
static uint8_t at_tgt(uint8_t idx) {
    int16_t d = cur[idx] - tgt[idx];
    return (d >= -GAIT_SPEED && d <= GAIT_SPEED);
}

/* Rodillas de soporte alcanzaron su target de balance */
static uint8_t support_knees_stable(uint8_t sleg) {
    for (uint8_t i = 0; i < 4; i++) {
        if (i == sleg) continue;
        if (!at_tgt((uint8_t)(i + 4))) return 0;
    }
    return 1;
}

/* ── Setters de targets ──────────────────────────────────────── */
static void set_stance(uint8_t ks) {
    for (uint8_t i = 0; i < 4; i++) { tgt[i] = HIP_CTR; tgt[i+4] = ks; }
}

/* Actualiza las 3 patas de soporte con push de cadera y altura de rodilla */
static void update_support(uint8_t sleg, const int16_t *bk_h, uint8_t knee_h) {
    for (uint8_t i = 0; i < 4; i++) {
        if (i == sleg) continue;
        tgt[i]   = bk_h[i];  // empuje de cadera hacia atrás
        tgt[i+4] = knee_h;   // altura de rodilla (Joy2 o STAB)
    }
}

/* ── Main ─────────────────────────────────────────────────────── */
int main(void) {
    ADC_Init();

    /* Timer0: S4 primero (t0_ready=0 → limpia), S2 segundo (OR COM0B1) */
    Servo_Init(HW_KNEE_S4, 1024, 7, 38, 4, 962);
    Servo_Init(HW_HIP_S2,  1024, 7, 38, 4, 962);
    Servo_Init(HW_KNEE_S1, 1024, 7, 38, 4, 962);

    SoftServo_Init();
    SoftServo_Attach(SW_HIP_S1,  &PORTB, &DDRB, PB1, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S4,  &PORTD, &DDRD, PD7, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S3,  &PORTB, &DDRB, PB2, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S3, &PORTB, &DDRB, PB0, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S2, &PORTD, &DDRD, PD4, 30, 120, 4, 962);

    sei();
    joy_calibrate();

    for (uint8_t i = 0; i < 4; i++) {
        cur[i] = tgt[i] = HIP_CTR;
        cur[i+4] = tgt[i+4] = KNEE_BASE;
    }
    interp_apply();
    _delay_ms(500);

    GaitState state = IDLE;

    while (1) {
        /* ── 1. Lectura ADC + flags de evento ─────────────── */
        int16_t j1x = dz((int16_t)ADC_Read(0) - (int16_t)joy_center[0]); // yaw
        int16_t j1y = dz((int16_t)ADC_Read(1) - (int16_t)joy_center[1]); // fwd/back
        int16_t j2y =    (int16_t)ADC_Read(2) - (int16_t)joy_center[2];  // altura
        int16_t j3  =    (int16_t)ADC_Read(3) - (int16_t)joy_center[3];  // amplitud A3

        flag_fwd    = (j1y > 0);
        flag_back   = (j1y < 0);
        flag_turn_R = (j1x > 0);
        flag_turn_L = (j1x < 0);
        uint8_t moving = (flag_fwd || flag_back || flag_turn_R || flag_turn_L);

        /* ── 2. Joy2 → altura base de rodillas ────────────── */
        uint8_t ks = (uint8_t)clamp16(
            KNEE_BASE + (int16_t)((int32_t)j2y * 30 / 512), 0, 75);

        /* ── 3. A3 → amplitud dinámica del paso ───────────── */
        // Solo el lado positivo del joystick aumenta la amplitud
        int16_t amp       = clamp16(j3, 0, 511);
        int16_t hip_amp   = (int16_t)((int32_t)amp * 30 / 511); // 0–30° (dentro de ±30°)
        int16_t knee_xtra = (int16_t)((int32_t)amp * 22 / 511); // 0–22° extra de lift

        /* Altura de rodilla en swing: ks + mínimo fijo + bonus A3 */
        uint8_t ksw = (uint8_t)clamp16(
            (int16_t)ks + 28 + knee_xtra, (int16_t)ks + 15, 88);

        /* Rodilla soporte en balance: baja STAB_OFFSET para anclar CoG */
        uint8_t ks_stab = (uint8_t)clamp16((int16_t)ks - STAB_OFFSET, 0, (int16_t)ks);

        /* ── 4. Targets de cadera por pata (restringido ±30°) */
        int16_t fwd_off = flag_fwd   ?  hip_amp :
                          flag_back  ? -hip_amp : 0;
        int16_t yaw_off = flag_turn_R ?  (hip_amp >> 1) :
                          flag_turn_L ? -(hip_amp >> 1) : 0;

        int16_t sw_h[4], bk_h[4];
        for (uint8_t i = 0; i < 4; i++) {
            int16_t y = (int16_t)(yaw_off * SIDE[i]);
            sw_h[i] = clamp16(HIP_CTR + fwd_off - y, HIP_MIN, HIP_MAX);
            bk_h[i] = clamp16(HIP_CTR - fwd_off + y, HIP_MIN, HIP_MAX);
        }

        /* ── 5. FSM Crawl Gait ────────────────────────────── */
        uint8_t leg  = GAIT_SEQ[gait_idx];
        uint8_t hip  = leg;
        uint8_t knee = (uint8_t)(leg + 4);

        switch (state) {

            /* ─ IDLE ─ stance estático, Joy2 siempre activo ─ */
            case IDLE:
                for (uint8_t i = 4; i < 8; i++) tgt[i] = ks;
                if (moving) { ph_cnt = 0; state = CRAWL_BALANCE; }
                break;

            /* ─ BALANCE ─ anclar CoG antes de levantar ──────
               Rodillas soporte bajan STAB_OFFSET°.
               Cadera swing vuelve al centro (neutral).
               → Avanza cuando rodillas soporte lleguen a ks_stab */
            case CRAWL_BALANCE:
                tgt[hip]  = HIP_CTR;         // swing regresa al centro
                tgt[knee] = ks;              // swing aún en el piso
                update_support(leg, bk_h, ks_stab); // soporte: push + anclar

                if (!moving) { set_stance(ks); state = IDLE; break; }
                if (support_knees_stable(leg) || ++ph_cnt >= MAX_PHASE_CYCLES) {
                    ph_cnt = 0; state = CRAWL_LIFT;
                }
                break;

            /* ─ LIFT ─ subir rodilla swing ───────────────────
               Soporte sigue anclado (ks_stab) durante el lift.
               → Avanza cuando rodilla swing llegue a ksw        */
            case CRAWL_LIFT:
                tgt[knee] = ksw;
                tgt[hip]  = HIP_CTR;
                update_support(leg, bk_h, ks_stab);

                if (!moving) { set_stance(ks); state = IDLE; break; }
                if (at_tgt(knee) || ++ph_cnt >= MAX_PHASE_CYCLES) {
                    ph_cnt = 0; state = CRAWL_SWING;
                }
                break;

            /* ─ SWING ─ avanzar cadera swing ─────────────────
               Rodilla se mantiene arriba.  Soporte vuelve a ks
               (el ancla ya no es necesaria, la pata está en aire).
               → Avanza cuando cadera llegue a sw_h[leg]          */
            case CRAWL_SWING:
                tgt[hip]  = sw_h[leg];
                tgt[knee] = ksw;
                update_support(leg, bk_h, ks); // soporte recupera altura Joy2

                if (!moving) { set_stance(ks); state = IDLE; break; }
                if (at_tgt(hip) || ++ph_cnt >= MAX_PHASE_CYCLES) {
                    ph_cnt = 0; state = CRAWL_PLANT;
                }
                break;

            /* ─ PLANT ─ bajar rodilla swing al valor Joy2 ────
               Cadera fijada en la posición de swing.
               → Avanza cuando rodilla toque el piso (ks)
                 luego pasa al BALANCE de la siguiente pata      */
            case CRAWL_PLANT:
                tgt[knee] = ks;
                tgt[hip]  = sw_h[leg];       // hip fijo tras swing
                update_support(leg, bk_h, ks);

                if (!moving) { set_stance(ks); state = IDLE; break; }
                if (at_tgt(knee) || ++ph_cnt >= MAX_PHASE_CYCLES) {
                    ph_cnt   = 0;
                    gait_idx = (gait_idx + 1) & 3; // s1→s3→s2→s4→s1…
                    state    = CRAWL_BALANCE;        // estabiliza para la siguiente pata
                }
                break;
        }

        /* ── 6. Interpolar + aplicar (2°/iter, sin delays) ── */
        interp_apply();
    }

    return 0;
}
