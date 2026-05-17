#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <avr/eeprom.h>
#include <util/delay.h>
#include "soft_servo.h"
#include "flexi_timer.h"
#include "spi.h"
#include "lora.h"
#include "uart.h"

/* ── Pin map (FRENTE VIRTUAL) ──────────────────────────────────────
   SERVOS (Soft PWM, Timer1 ISR, 8 canales):

     S1 (FL — Frente Izquierda):
       ch1 SW_HIP_S1  → D3 PD3       ch0 SW_KNEE_S1 → D2 PD2

     S2 (FR — Frente Derecha):
       ch2 SW_HIP_S2  → D8 PB0       ch3 SW_KNEE_S2 → D9 PB1

     S3 (RR — Atras Derecha):
       ch4 SW_HIP_S3  → D7 PD7       ch5 SW_KNEE_S3 → D6 PD6

     S4 (RL — Atras Izquierda):
       ch6 SW_HIP_S4  → D5 PD5       ch7 SW_KNEE_S4 → D4 PD4

   LoRa SX1276 (915 MHz):
     MOSI = D11 PB3    NSS  = D10 PB2
     MISO = D12 PB4    RST  = A0  PC0
     SCK  = D13 PB5    DIO0 = A1  PC1

   Layout fisico:
            FRENTE
     S1(FL)       S2(FR)
     [  cuerpo  ]
     S4(RL)       S3(RR)
            ATRAS

   Lados:  IZQUIERDA = S1, S4   |   DERECHA = S2, S3
   ────────────────────────────────────────────────────────────────── */

/* Indices de canales soft servo */
#define SW_KNEE_S1  0
#define SW_HIP_S1   1
#define SW_HIP_S2   2
#define SW_KNEE_S2  3
#define SW_HIP_S3   4
#define SW_KNEE_S3  5
#define SW_HIP_S4   6
#define SW_KNEE_S4  7

/* ════════════════════════════════════════════════════════════════════
 *  POSTURA Y CINEMATICA 
 * ═══════════════════════════════════════════════════════════════════ */
#define HIP_CTR         90

#define KB_S1           25
#define KB_S2           25
#define KB_S3           25
#define KB_S4           25
static const uint8_t KB[4] = { KB_S1, KB_S2, KB_S3, KB_S4 };

#define KNEE_LIFT       30    /* cuanto sube la rodilla al levantar (suave) */
#define KNEE_STAB       15    /* baja la rodilla opuesta para anclar el CoG */

#define HIP_SWING_FWD   35    /* zancada adelante reducida (no resbala)     */
#define HIP_SWING_BWD   15    /* zancada atras reducida (no se desparrama)  */

#define YAW_SWING       25    /* amplitud de giro reducida (estable)        */

#define HIP_PUSH_L      15    /* empuje del cuerpo, lado izquierdo          */
#define HIP_PUSH_R      15    /* empuje del cuerpo, lado derecho            */

#define STEP_TICKS      5       /* duracion de cada sub-paso (5 × 10 ms) */
#define KNEE_MAX        85      /* tope superior de la rodilla            */
#define KNEE_OFF_MAX    35      /* limite del offset de altura            */
#define DEADZONE        50      /* zona muerta del joystick               */

/* ════════════════════════════════════════════════════════════════════
 *  LoRa — Payload (10 bytes) y watchdog
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    int16_t fwd_bwd;
    int16_t left_right;
    int16_t yaw;
    int16_t height;
    uint8_t mode;        /* 0=Manual, 1=EEPROM, 2=UART */
    uint8_t action_btn;  /* 1=REC/Play, 0=Suelto       */
} Payload_t;

#define LORA_FREQ       915000000UL
#define LORA_TIMEOUT    50      /* 50 × 10 ms = 500 ms sin senal → STOP movimiento */

static Payload_t datos_lora    = { 0, 0, 0, 0, 0, 0 };
static uint8_t   lora_watchdog = LORA_TIMEOUT;

/* ════════════════════════════════════════════════════════════════════
 *  EEPROM Macro-Grabadora (5 bytes por evento)
 * ═══════════════════════════════════════════════════════════════════ */
typedef struct {
    int8_t   j_fb;
    int8_t   j_lr;
    int8_t   j_yaw;
    uint16_t duration_ticks;     /* 0xFFFF = EOF */
} EEPROM_Macro_t;

#define EEPROM_TOTAL       1000
#define EEPROM_EVT_SIZE    sizeof(EEPROM_Macro_t)        /* 5 */
#define EEPROM_DATA_MAX    (EEPROM_TOTAL - EEPROM_EVT_SIZE)  /* 995 */
#define EOF_MARK           0xFFFF

/* Estado del grabador */
static int8_t   rec_prev_fb = 0, rec_prev_lr = 0, rec_prev_yw = 0;
static uint16_t rec_duration = 0;
static uint16_t rec_addr     = 0;

/* Estado del reproductor */
static EEPROM_Macro_t pb_event;
static uint16_t       pb_addr      = 0;
static uint16_t       pb_remaining = 0;

/* Tracking de transiciones */
static uint8_t  prev_action_btn = 0;
static uint8_t  prev_mode       = 0xFF;   /* fuerza init en 1ra iter */

/* ════════════════════════════════════════════════════════════════════
 *  TABLAS
 * ═══════════════════════════════════════════════════════════════════ */
static const uint8_t SEQ[4] = { 0, 2, 1, 3 };
static const uint8_t OPP[4] = { 2, 3, 0, 1 };

/* S1(0)=FL y S4(3)=RL → IZQUIERDA = +1
 * S2(1)=FR y S3(2)=RR → DERECHA  = -1
 * Si el robot avanza al reves, invertir los signos.                  */
static int8_t side_mirror(uint8_t leg) {
    return (leg == 0 || leg == 3) ? 1 : -1;
}

/* ════════════════════════════════════════════════════════════════════
 *  ESTADO + FRENTE VIRTUAL
 * ═══════════════════════════════════════════════════════════════════ */
static uint8_t  leg_offset      = 0;
static uint8_t  hip_pos[4]      = { HIP_CTR, HIP_CTR, HIP_CTR, HIP_CTR };
static int16_t  smooth_knee_off = 0;

typedef enum { IDLE, SEQ_WAIT } GaitState;

static GaitState state      = IDLE;
static uint8_t   seq_leg    = 0;
static uint8_t   seq_step   = 0;
static uint16_t  wait_ticks = 0;
static int8_t    direction  = 0;

static volatile uint8_t frame_flag = 0;
static void frame_tick(void) { frame_flag = 1; }

/* ════════════════════════════════════════════════════════════════════
 *  HELPERS
 * ═══════════════════════════════════════════════════════════════════ */
static int16_t clamp16(int16_t v, int16_t lo, int16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static int16_t dz(int16_t v) {
    return (v > -DEADZONE && v < DEADZONE) ? 0 : v;
}

static int16_t abs16(int16_t v) { return (v < 0) ? -v : v; }

/* Simplifica un valor (ya pasado por dz) a −1/0/+1 */
static int8_t simplify(int16_t v) {
    if (v > 0) return  1;
    if (v < 0) return -1;
    return 0;
}

/* Dispatch: idx 0..3 = caderas, idx 4..7 = rodillas */
static void set_servo(uint8_t idx, uint8_t deg) {
    switch (idx) {
        case 0: SoftServo_SetAngle(SW_HIP_S1,  deg); break;
        case 1: SoftServo_SetAngle(SW_HIP_S2,  deg); break;
        case 2: SoftServo_SetAngle(SW_HIP_S3,  deg); break;
        case 3: SoftServo_SetAngle(SW_HIP_S4,  deg); break;
        case 4: SoftServo_SetAngle(SW_KNEE_S1, deg); break;
        case 5: SoftServo_SetAngle(SW_KNEE_S2, deg); break;
        case 6: SoftServo_SetAngle(SW_KNEE_S3, deg); break;
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
 *  GRABADORA (MODE 0 + action_btn == 1)
 * ═══════════════════════════════════════════════════════════════════ */
static void rec_write_event(int8_t fb, int8_t lr, int8_t yw, uint16_t dur) {
    EEPROM_Macro_t ev;
    if (datos_lora.mode == 1) return;   /* solo se bloquea en Reproduccion */
    ev.j_fb           = fb;
    ev.j_lr           = lr;
    ev.j_yaw          = yw;
    ev.duration_ticks = dur;
    eeprom_write_block(&ev, (void *)(uintptr_t)rec_addr, EEPROM_EVT_SIZE);
    rec_addr = (uint16_t)(rec_addr + EEPROM_EVT_SIZE);
    UART_PrintString("EEPROM Grabado!\r\n");
}

static void rec_start(int8_t fb, int8_t lr, int8_t yw) {
    if (datos_lora.mode == 1) return;   /* solo se bloquea en Reproduccion */
    rec_addr     = 0;
    rec_prev_fb  = fb;
    rec_prev_lr  = lr;
    rec_prev_yw  = yw;
    rec_duration = 0;
}

static void rec_tick(int8_t fb, int8_t lr, int8_t yw) {
    if (datos_lora.mode == 1) return;   /* solo se bloquea en Reproduccion */
    if (fb != rec_prev_fb || lr != rec_prev_lr || yw != rec_prev_yw) {
        /* Cambio: guardar estado anterior + su duracion */
        if (rec_addr + EEPROM_EVT_SIZE <= EEPROM_DATA_MAX) {
            rec_write_event(rec_prev_fb, rec_prev_lr, rec_prev_yw, rec_duration);
        }
        rec_prev_fb  = fb;
        rec_prev_lr  = lr;
        rec_prev_yw  = yw;
        rec_duration = 0;
    } else {
        if (rec_duration < 0xFFFE) rec_duration++;
    }
}

static void rec_stop(void) {
    /* Agnostico al modo: solo se aborta si NO hay grabacion activa.
     * Asi se garantiza que el EOF_MARK se escriba aunque la transicion
     * de modo ya haya cambiado datos_lora.mode a 1 (Reproduccion).      */
    if (rec_addr == 0) return;
    /* Guardar el ultimo estado todavia activo */
    if (rec_addr + EEPROM_EVT_SIZE <= EEPROM_DATA_MAX) {
        rec_write_event(rec_prev_fb, rec_prev_lr, rec_prev_yw, rec_duration);
    }
    /* Marcador EOF (siempre cabe — reservamos 5 bytes finales) */
    if (rec_addr <= EEPROM_TOTAL - EEPROM_EVT_SIZE) {
        rec_write_event(0, 0, 0, EOF_MARK);
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  REPRODUCTOR (MODE 1)
 * ═══════════════════════════════════════════════════════════════════ */
static void pb_load(void) {
    eeprom_read_block(&pb_event, (const void *)(uintptr_t)pb_addr, EEPROM_EVT_SIZE);

    if (pb_event.duration_ticks == EOF_MARK) {
        /* EOF: rebobinar al inicio */
        if (pb_addr != 0) {
            pb_addr = 0;
            eeprom_read_block(&pb_event, (const void *)0, EEPROM_EVT_SIZE);
        }
        /* Si la direccion 0 tambien es EOF → EEPROM vacia, idle */
        if (pb_event.duration_ticks == EOF_MARK) {
            pb_event.j_fb           = 0;
            pb_event.j_lr           = 0;
            pb_event.j_yaw          = 0;
            pb_event.duration_ticks = 100;
        }
    }
    pb_remaining = pb_event.duration_ticks;
}

static void pb_init(void) {
    pb_addr = 0;
    pb_load();
}

static void pb_step(void) {
    if (pb_remaining > 0) {
        pb_remaining--;
    } else {
        pb_addr = (uint16_t)(pb_addr + EEPROM_EVT_SIZE);
        if (pb_addr >= EEPROM_TOTAL) pb_addr = 0;
        pb_load();
    }
}

/* ════════════════════════════════════════════════════════════════════
 *  SECUENCIADOR FSM (intacto)
 * ═══════════════════════════════════════════════════════════════════ */
static void execute_step(uint8_t logical_leg, uint8_t step, int8_t dir,
                         uint8_t turning, const uint8_t *kb)
{
    uint8_t leg = (uint8_t)((logical_leg + leg_offset) & 3);
    uint8_t opp = OPP[leg];
    uint8_t i;
    int16_t swing_val;
    int16_t push_val;

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
            swing_val = (dir > 0) ? HIP_SWING_FWD : HIP_SWING_BWD;
            hip_pos[leg] = (uint8_t)clamp16(
                (int16_t)HIP_CTR + dir * swing_val * side_mirror(leg),
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
                    (int16_t)hip_pos[i] - dir * HIP_PUSH_R, 10, 170);
            } else {
                /* S1(0)+S4(3)=IZQ → HIP_PUSH_L | S2(1)+S3(2)=DER → HIP_PUSH_R */
                push_val = (i == 0 || i == 3) ? HIP_PUSH_L : HIP_PUSH_R;
                hip_pos[i] = (uint8_t)clamp16(
                    (int16_t)hip_pos[i] - dir * push_val * side_mirror(i),
                    10, 170);
            }
            set_servo(i, hip_pos[i]);
        }
        break;
    }
}

/* ════════════════════════════════════════════════════════════════════
 * MAIN
 * ═══════════════════════════════════════════════════════════════════ */
int main(void) {
    uint8_t  i;
    int16_t  fb, lr, yw, ht;
    int8_t   s_fb, s_lr, s_yw;
    int16_t  abs_fb, abs_lr;
    int8_t   new_dir;
    uint8_t  is_turning;
    int16_t  target_knee_off;
    uint8_t  kb[4];
    uint8_t  packet_size;
    uint8_t  cur_mode, cur_action;
    uint8_t  lora_status;
    uint8_t  print_throttle = 0;     /* imprime 1 de cada 5 paquetes */

    /* ── 1) UART debug 9600 baud ────────────────────────────────── */
    UART_Init(9600);
    UART_PrintString("\r\n--- INICIANDO ROBOT RX ---\r\n");

    /* ── 2) LORA PRIMERO (Con batería fresca, antes que los motores) */
    lora_status = LoRa_Init(LORA_FREQ);
    if (lora_status != 0) {
        UART_PrintString("ERROR: Fallo comunicacion SPI LoRa\r\n");
    } else {
        UART_PrintString("LoRa OK (RX continuo)\r\n");
    }

    /* ── 3) SERVOS DESPUÉS (Todos juntos y rápido, sin esperas) ─── */
    SoftServo_Init();
    SoftServo_Attach(SW_HIP_S1,  &PORTD, &DDRD, PD3, 30, 120, 4, 962); /* S1 FL hip  D3 */
    SoftServo_Attach(SW_KNEE_S1, &PORTD, &DDRD, PD2, 30, 120, 4, 962); /* S1 FL knee D2 */
    SoftServo_Attach(SW_HIP_S2,  &PORTB, &DDRB, PB0, 30, 120, 4, 962); /* S2 FR hip  D8 */
    SoftServo_Attach(SW_KNEE_S2, &PORTB, &DDRB, PB1, 30, 120, 4, 962); /* S2 FR knee D9 */
    SoftServo_Attach(SW_HIP_S3,  &PORTD, &DDRD, PD7, 30, 120, 4, 962); /* S3 RR hip  D7 */
    SoftServo_Attach(SW_KNEE_S3, &PORTD, &DDRD, PD6, 30, 120, 4, 962); /* S3 RR knee D6 */
    SoftServo_Attach(SW_HIP_S4,  &PORTD, &DDRD, PD5, 30, 120, 4, 962); /* S4 RL hip  D5 */
    SoftServo_Attach(SW_KNEE_S4, &PORTD, &DDRD, PD4, 30, 120, 4, 962); /* S4 RL knee D4 */

    /* ── 4) Activar Interrupciones ───────────────────────────────── */
    FlexiTimer_Set(10, frame_tick);
    FlexiTimer_Start();
    sei();

    /* ── 5) Postura inicial instantánea ──────────────────────────── */
    go_stance(KB);
    _delay_ms(500);

    while (1) {

        /* ── Chequeo LoRa no bloqueante ────────────────────────── */
        if (PINC & (1 << PC1)) {
            packet_size = LoRa_ParsePacket();
            if (packet_size == sizeof(Payload_t)) {
                LoRa_ReadBytes((uint8_t *)&datos_lora, sizeof(Payload_t));
                lora_watchdog = 0;        /* llego paquete → resetear watchdog */

                /* Debug: imprime 1 de cada 5 paquetes (~10 prints/s a 9600 baud) */
                print_throttle++;
                if (print_throttle >= 5) {
                    print_throttle = 0;
                    UART_PrintString("Pkt fb=");
                    UART_PrintInt(datos_lora.fwd_bwd);
                    UART_PrintString(" yw=");
                    UART_PrintInt(datos_lora.yaw);
                    UART_PrintString(" m=");
                    UART_PrintInt((int16_t)datos_lora.mode);
                    UART_PrintString("\r\n");
                }
            }
        }

        if (!frame_flag) continue;
        frame_flag = 0;

        /* ── Watchdog del LoRa ───────────────────────────────────
         *  Si no llegan paquetes en 500 ms, pone fwd/lr/yaw a 0 por
         *  seguridad. La altura (height) y el modo se conservan.
         * ──────────────────────────────────────────────────────── */
        if (lora_watchdog < LORA_TIMEOUT) {
            lora_watchdog++;
        } else {
            datos_lora.fwd_bwd    = 0;
            datos_lora.left_right = 0;
            datos_lora.yaw        = 0;
        }

        cur_mode   = datos_lora.mode;
        cur_action = datos_lora.action_btn;

        /* ════════════════════════════════════════════════════════
         *  Transicion de modo: si cambia, limpiar estados de REC/PB
         * ══════════════════════════════════════════════════════ */
        if (cur_mode != prev_mode) {
            /* Si veniamos grabando, cerrar la macro */
            if (prev_mode == 0 && prev_action_btn == 1) {
                rec_stop();
            }
            /* Si entramos a EEPROM, cargar evento 0 */
            if (cur_mode == 1) {
                pb_init();
            }
            prev_mode = cur_mode;
        }

        /* ════════════════════════════════════════════════════════
         *  ENTRADAS DE CONTROL segun el modo
         * ══════════════════════════════════════════════════════ */
        if (cur_mode == 0) {
            /* ── MODE 0: MANUAL ─── */
            fb = dz(datos_lora.fwd_bwd);
            lr = dz(datos_lora.left_right);
            yw = dz(datos_lora.yaw);
            ht =    datos_lora.height;
        }
        else if (cur_mode == 1) {
            /* ── MODE 1: EEPROM PLAYBACK ─── */
            pb_step();
            fb = pb_event.j_fb;
            lr = pb_event.j_lr;
            yw = pb_event.j_yaw;
            ht = 0;          /* altura neutral */
        }
        else {
            /* ── MODE 2: UART → STOP movimiento (la grabacion sigue activa) ─── */
            fb = lr = yw = 0;
            ht = 0;
        }

        /* ════════════════════════════════════════════════════════
         *  GRABACION EEPROM — activa en MODO 0 y MODO 2.
         *  En modo 2 los joysticks no mueven al robot, pero igual
         *  se pueden registrar para una macro futura.
         *  En MODO 1 (Reproduccion) las funciones rec_write_event,
         *  rec_start y rec_tick llevan guardia "if (datos_lora.mode
         *  == 1) return;". rec_stop es agnostico al modo: solo aborta
         *  si rec_addr == 0 (no hay grabacion activa) — asi puede
         *  cerrar la macro aunque ya hayamos transicionado a modo 1.
         * ══════════════════════════════════════════════════════ */
        if (cur_mode == 0 || cur_mode == 2) {
            s_fb = simplify(dz(datos_lora.fwd_bwd));
            s_lr = simplify(dz(datos_lora.left_right));
            s_yw = simplify(dz(datos_lora.yaw));

            if (cur_action == 1 && prev_action_btn == 0) {
                rec_start(s_fb, s_lr, s_yw);
            }
            if (cur_action == 1) {
                rec_tick(s_fb, s_lr, s_yw);
            }
            if (cur_action == 0 && prev_action_btn == 1) {
                rec_stop();
            }
        }

        prev_action_btn = cur_action;

        /* ════════════════════════════════════════════════════════
         *  PRIORIDAD + FRENTE VIRTUAL (unificado para ambos modos)
         * ══════════════════════════════════════════════════════ */
        abs_fb     = abs16(fb);
        abs_lr     = abs16(lr);
        new_dir    = 0;
        is_turning = 0;
        leg_offset = 0;

        if (fb > 0) new_dir =  1;
        if (fb < 0) new_dir = -1;

        if (lr != 0 && abs_lr > abs_fb) {
            new_dir    = 1;
            leg_offset = (lr > 0) ? 1 : 3;
        }

        if (yw != 0) {
            new_dir    = (yw > 0) ? 1 : -1;
            is_turning = 1;
            leg_offset = 0;
        }

        /* ════════════════════════════════════════════════════════
         *  ALTURA — filtro pasa-bajos original
         *
         *  El joystick (rango aproximado ±512) se mapea a target_knee_off
         *  en grados con ganancia 65/512. Despues el filtro acerca
         *  smooth_knee_off al target a razon de ±1° por frame (10 ms).
         *  Los limites de offset son ±KNEE_OFF_MAX (35°).
         * ══════════════════════════════════════════════════════ */
        target_knee_off = clamp16((int16_t)((int32_t)ht * 65 / 512),
                                  -KNEE_OFF_MAX, KNEE_OFF_MAX);

		smooth_knee_off = target_knee_off;

        /* Aplica el offset suavizado a las bases asimetricas de cada pata.
         * El clamp final permite el rango completo 0..KNEE_MAX.          */
        for (i = 0; i < 4; i++) {
            kb[i] = (uint8_t)clamp16(
                (int16_t)KB[i] + smooth_knee_off, 0, KNEE_MAX);
        }

        /* ── FSM ──────────────────────────────────────────────── */
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