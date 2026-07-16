/*
 * cinematica.c
 *
 * Motor de marcha CARTESIANO (creep gait) — ver cinematica.h.
 * Author: Abner Quiej
 */

#include "cinematica.h"
#include "soft_servo.h"

/* ======================================================================
 *  MAPA DE CANALES  (leg logico -> canal soft servo)   [igual que el main]
 * ==================================================================== */
static const uint8_t HIP_CH[N_LEGS]  = { 1, 2, 4, 6 };  /* FL, FR, RR, RL */
static const uint8_t KNEE_CH[N_LEGS] = { 0, 3, 5, 7 };

/* Lado del cuerpo: FL(0) y RL(3) = izquierda (+1); FR(1) y RR(2) = der (-1).
 * Sirve para que "+y_mm" signifique "adelante" en las 4 patas aunque los
 * servos izquierdo/derecho esten montados en espejo.                        */
static const int8_t SIDE[N_LEGS] = { +1, -1, -1, +1 };

/* ======================================================================
 *  ####  CALIBRACION  ####   (lo unico que ajustas a tu robot)
 * ==================================================================== */

/* Centro mecanico de la cadera (pie en Y=0).                                */
#define HIP_CTR          90

/* IK LINEAL: grados de cadera por cada mm de avance del pie.
 * = GRADOS_POR_MM_NUM / GRADOS_POR_MM_DEN.
 * Por defecto 1.0 (=> radio cadera-pie ~57 mm). CALIBRA asi:
 *   1) pon la cadera a 90 y marca donde queda el pie (Y=0)
 *   2) pon la cadera a 110 (=+20) y mide cuantos mm avanzo el pie -> D mm
 *   3) GRADOS_POR_MM = 20 / D   (ej: si avanzo 25 mm -> 20/25 = 0.8)         */
#define GRADOS_POR_MM_NUM   1
#define GRADOS_POR_MM_DEN   1

/* Limite de seguridad del angulo de cadera.                                 */
#define HIP_MIN          10
#define HIP_MAX          170

/* ======================================================================
 *  PARAMETROS DE MARCHA  (en mm y ticks)
 * ==================================================================== */
#define SHIFT_MM         20     /* cuanto retrocede el cuerpo por SHIFT      */
#define REACH_MM         40     /* zancada de una pata al STEP (=2*SHIFT_MM) */
#define KNEE_LIFT_DEG    30     /* cuanto sube la rodilla al levantar        */
#define KNEE_MAX         85     /* tope superior de rodilla                  */
#define STEP_TICKS       5      /* duracion de cada sub-paso (5 x 10 ms)     */

/* ======================================================================
 *  TIPOS Y TABLA DE CICLO
 * ==================================================================== */
#define ACT_STEP   0
#define ACT_SHIFT  1

typedef struct { uint8_t type; uint8_t leg; } Action;

/* Ciclo del diagrama:  STEP D, STEP C, SHIFT, STEP A, STEP B, SHIFT
 * D=RL=3  C=FL=0  A=FR=1  B=RR=2                                            */
static const Action CYCLE[] = {
    { ACT_STEP,  3 },   /* D */
    { ACT_STEP,  0 },   /* C */
    { ACT_SHIFT, 0 },
    { ACT_STEP,  1 },   /* A */
    { ACT_STEP,  2 },   /* B */
    { ACT_SHIFT, 0 },
};
#define N_ACTIONS  (sizeof(CYCLE) / sizeof(CYCLE[0]))

/* ======================================================================
 *  ESTADO
 * ==================================================================== */
static int16_t  foot_y[N_LEGS];        /* posicion del pie en Y (mm)         */
static uint8_t  knee_deg[N_LEGS];      /* angulo de rodilla plantada por pata*/
static int8_t   lifted_leg;            /* pata levantada (-1 = ninguna)      */

static int8_t   cur_dir;               /* +1 / -1 / 0                        */
static int8_t   prev_dir;
static uint8_t  act_idx;               /* accion actual dentro del ciclo     */
static uint8_t  sub_idx;               /* sub-paso dentro de la accion       */
static uint8_t  wait;                  /* ticks restantes del sub-paso       */

/* ======================================================================
 *  HELPERS
 * ==================================================================== */
static int16_t clampi(int16_t v, int16_t lo, int16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

uint8_t IK_HipDeg(uint8_t leg, int16_t y_mm) {
    int32_t delta = (int32_t)y_mm * GRADOS_POR_MM_NUM / GRADOS_POR_MM_DEN;
    int16_t deg   = (int16_t)(HIP_CTR + SIDE[leg] * (int16_t)delta);
    return (uint8_t)clampi(deg, HIP_MIN, HIP_MAX);
}

/* Escribe los servos de UNA pata a partir de su estado (foot_y + lifted).   */
static void render_leg(uint8_t leg) {
    uint8_t hip  = IK_HipDeg(leg, foot_y[leg]);
    uint8_t knee = knee_deg[leg];
    if (leg == lifted_leg) {
        int16_t k = (int16_t)knee_deg[leg] + KNEE_LIFT_DEG;
        knee = (uint8_t)clampi(k, 0, KNEE_MAX);
    }
    SoftServo_SetAngle(HIP_CH[leg],  hip);
    SoftServo_SetAngle(KNEE_CH[leg], knee);
}

static void render_all(void) {
    uint8_t i;
    for (i = 0; i < N_LEGS; i++) render_leg(i);
}

/* ======================================================================
 *  API
 * ==================================================================== */
void Gait_Init(const uint8_t knee_stand[N_LEGS]) {
    uint8_t i;
    for (i = 0; i < N_LEGS; i++) {
        foot_y[i]   = 0;
        knee_deg[i] = knee_stand[i];
    }
    lifted_leg = -1;
    cur_dir = prev_dir = 0;
    act_idx = sub_idx = 0;
    wait = 0;
    render_all();
}

void Gait_SetCommand(int8_t dir, const uint8_t knee_stand[N_LEGS]) {
    uint8_t i;
    for (i = 0; i < N_LEGS; i++) knee_deg[i] = knee_stand[i];
    cur_dir = dir;

    /* Al arrancar (0 -> avanzar) reinicia el ciclo desde el principio.       */
    if (prev_dir == 0 && dir != 0) {
        act_idx = sub_idx = 0;
        wait = 0;
    }
    prev_dir = dir;
}

/* Aplica una accion+sub-paso al estado (foot_y / lifted_leg).               */
static void apply_substep(void) {
    const Action *a = &CYCLE[act_idx];
    uint8_t i;

    if (a->type == ACT_STEP) {
        switch (sub_idx) {
        case 0:  /* LIFT  */
            lifted_leg = (int8_t)a->leg;
            break;
        case 1:  /* SWING: adelanta el pie a +REACH (o -REACH si dir<0)       */
            foot_y[a->leg] = (cur_dir > 0) ? REACH_MM : -REACH_MM;
            break;
        case 2:  /* PLANT */
            lifted_leg = -1;
            break;
        }
    } else { /* ACT_SHIFT: mueve las 4 patas hacia atras -> el cuerpo avanza  */
        for (i = 0; i < N_LEGS; i++) {
            foot_y[i] = clampi(foot_y[i] - cur_dir * SHIFT_MM, -120, 120);
        }
    }
}

/* Cuantos sub-pasos tiene la accion actual.                                 */
static uint8_t substeps_of(uint8_t idx) {
    return (CYCLE[idx].type == ACT_STEP) ? 3 : 1;
}

uint8_t Gait_Tick(void) {
    /* Detenido: mantiene la postura actual, no avanza el ciclo.             */
    if (cur_dir == 0) {
        lifted_leg = -1;
        render_all();
        return 0;
    }

    if (wait > 0) {
        wait--;
        render_all();     /* re-render por si cambio la altura (knee_stand)  */
        return 1;
    }

    /* Ejecuta el sub-paso actual y programa la espera.                      */
    apply_substep();
    render_all();
    wait = STEP_TICKS;

    /* Avanza indices para el proximo sub-paso / accion / ciclo.             */
    sub_idx++;
    if (sub_idx >= substeps_of(act_idx)) {
        sub_idx = 0;
        act_idx++;
        if (act_idx >= N_ACTIONS) act_idx = 0;
    }
    return 1;
}
