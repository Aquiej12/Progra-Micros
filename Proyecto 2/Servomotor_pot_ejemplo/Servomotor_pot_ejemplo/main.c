/*
 * main.c
 *
 * Created: 17/05/2026
 * Author: Abner Quiej (El Terricola mas Guapo del sistema Solar)
 * Description: Robot cuadrupedo
 *              este micro NO toma decisiones. Solo:
 *              1) Recibe Payload_t por LoRa
 *              2) Aplica fb / lr / yw / height a la cinematica de marcha
 *              3) Watchdog para parar si pierde la senal
 *              Toda la inteligencia (modos, EEPROM, UART, joysticks) vive en el
 *              control (TX). El robot no diferencia entre modo Manual, EEPROM o
 *              UART: para el todo es la misma fuente de datos.
 */


/****************************************/
// Encabezado (Libraries)

#define F_CPU 16000000UL
#include <avr/io.h>
#include <avr/interrupt.h>
#include <util/delay.h>
#include "soft_servo.h"
#include "flexi_timer.h"
#include "spi.h"
#include "lora.h"
#include "uart.h"

// Indices de canales soft servo
#define SW_KNEE_S1  0
#define SW_HIP_S1   1
#define SW_HIP_S2   2
#define SW_KNEE_S2  3
#define SW_HIP_S3   4
#define SW_KNEE_S3  5
#define SW_HIP_S4   6
#define SW_KNEE_S4  7

// POSTURA Y CINEMATICA
// Postura inicial
#define HIP_CTR         90
#define KB_S1           25
#define KB_S2           25
#define KB_S3           25
#define KB_S4           25
static const uint8_t KB[4] = { KB_S1, KB_S2, KB_S3, KB_S4 };

// Parametros de movimiento
#define KNEE_LIFT       30      // cuanto sube la rodilla al levantar    
#define KNEE_STAB       15      // baja la opuesta para anclar

#define HIP_SWING_FWD   15      // zancada adelante                       
#define HIP_SWING_BWD   15      // zancada atras                          
#define YAW_SWING       15      // amplitud de giro                       

#define HIP_PUSH_L      10      // empuje del cuerpo, lado izquierdo      
#define HIP_PUSH_R      10      // empuje del cuerpo, lado derecho        

#define STEP_TICKS      5       // duracion de cada sub-paso (5 × 10 ms) 
#define KNEE_MAX        85      // tope superior de la rodilla    

// TOPE VIRTUAL DE ALTURA (anti-brownout)
#define KNEE_OFF_MAX    15      
#define KNEE_FLOOR      15      

// zona muerta del joystick
#define DEADZONE        50                   


// LoRa — Payload (10 bytes) y watchdog

typedef struct {
    int16_t fwd_bwd;
    int16_t left_right;
    int16_t yaw;
    int16_t height;
    uint8_t mode;        /* ignorado por el robot */
    uint8_t action_btn;  /* ignorado por el robot */
} Payload_t;

#define LORA_FREQ       915000000UL
#define LORA_TIMEOUT    50      

static Payload_t datos_lora    = { 0, 0, 0, 0, 0, 0 };
static uint8_t   lora_watchdog = LORA_TIMEOUT;


//TABLAS Y ESTADO DE LA FSM

static const uint8_t SEQ[4] = { 0, 2, 1, 3 };
static const uint8_t OPP[4] = { 2, 3, 0, 1 };

// S1(0)=FL y S4(3)=RL → IZQUIERDA = +1
// S2(1)=FR y S3(2)=RR → DERECHA  = -1                             
static int8_t side_mirror(uint8_t leg) {
    return (leg == 0 || leg == 3) ? 1 : -1;
}

static uint8_t  leg_offset      = 0;
static uint8_t  hip_pos[4]      = { HIP_CTR, HIP_CTR, HIP_CTR, HIP_CTR };
static int16_t  smooth_knee_off = 0;

typedef enum { IDLE, SEQ_WAIT } GaitState;

// Valores inicales
static GaitState state      = IDLE;
static uint8_t   seq_leg    = 0;
static uint8_t   seq_step   = 0;
static uint16_t  wait_ticks = 0;
static int8_t    direction  = 0;

static volatile uint8_t frame_flag = 0;
static void frame_tick(void) { frame_flag = 1; }

// HELPERS

static int16_t clamp16(int16_t v, int16_t lo, int16_t hi) {
    return v < lo ? lo : (v > hi ? hi : v);
}

static int16_t dz(int16_t v) {
    return (v > -DEADZONE && v < DEADZONE) ? 0 : v;
}

static int16_t abs16(int16_t v) { return (v < 0) ? -v : v; }



/****************************************/
// Function prototypes
/****************************************/

// Ajustar Servomotores a los angulos
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

// cambio de posición
static void go_stance(const uint8_t *kb) {
    uint8_t i;
    for (i = 0; i < 4; i++) {
        hip_pos[i] = HIP_CTR;
        set_servo(i,     HIP_CTR);
        set_servo(i + 4, kb[i]);
    }
}

//SECUENCIADOR FSM — Avance / Retroceso / Giro (diagonales)

static void execute_step(uint8_t logical_leg, uint8_t step, int8_t dir,
                         uint8_t turning, const uint8_t *kb)
{
    uint8_t leg = (uint8_t)((logical_leg + leg_offset) & 3);
    uint8_t opp = OPP[leg];
    uint8_t i;
    int16_t swing_val;
    int16_t push_val;

    switch (step) {

    case 0: // LIFT
        set_servo(leg + 4, (uint8_t)clamp16(
            (int16_t)kb[leg] + KNEE_LIFT, 0, KNEE_MAX));
        set_servo(opp + 4, (uint8_t)clamp16(
            (int16_t)kb[opp] - KNEE_STAB, 0, KNEE_MAX));
        break;

    case 1: // SWING 
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

    case 2: // PLANT
        set_servo(leg + 4, kb[leg]);
        set_servo(opp + 4, kb[opp]);
        break;

    case 3: // PUSH
        for (i = 0; i < 4; i++) {
            if (turning) {
                hip_pos[i] = (uint8_t)clamp16(
                    (int16_t)hip_pos[i] - dir * HIP_PUSH_R, 10, 170);
            } else {
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

// SECUENCIADOR DE STRAFE (movimiento lateral por pares laterales)

static void execute_step_strafe(uint8_t par, uint8_t step, int8_t dir,
                                const uint8_t *kb)
{
    uint8_t leg_a, leg_b;
    uint8_t opp_a, opp_b;
    uint8_t i;
    int16_t swing_val;

    if (par == 0) {
        // Par L: S1 (idx 0) + S4 (idx 3)
        leg_a = 0; leg_b = 3;
        opp_a = 1; opp_b = 2;
    } else {
        // Par R: S2 (idx 1) + S3 (idx 2)
        leg_a = 1; leg_b = 2;
        opp_a = 0; opp_b = 3;
    }

    switch (step) {
    case 0:
        set_servo(leg_a + 4, (uint8_t)clamp16(
            (int16_t)kb[leg_a] + KNEE_LIFT, 0, KNEE_MAX));
        set_servo(leg_b + 4, (uint8_t)clamp16(
            (int16_t)kb[leg_b] + KNEE_LIFT, 0, KNEE_MAX));
        set_servo(opp_a + 4, (uint8_t)clamp16(
            (int16_t)kb[opp_a] - KNEE_STAB, 0, KNEE_MAX));
        set_servo(opp_b + 4, (uint8_t)clamp16(
            (int16_t)kb[opp_b] - KNEE_STAB, 0, KNEE_MAX));
        break;
    case 1:
        swing_val = (int16_t)(dir * HIP_SWING_FWD);
        hip_pos[leg_a] = (uint8_t)clamp16(
            (int16_t)HIP_CTR + swing_val, 10, 170);
        hip_pos[leg_b] = (uint8_t)clamp16(
            (int16_t)HIP_CTR + swing_val, 10, 170);
        set_servo(leg_a, hip_pos[leg_a]);
        set_servo(leg_b, hip_pos[leg_b]);
        break;
    case 2:
        set_servo(leg_a + 4, kb[leg_a]);
        set_servo(leg_b + 4, kb[leg_b]);
        set_servo(opp_a + 4, kb[opp_a]);
        set_servo(opp_b + 4, kb[opp_b]);
        break;
    case 3:
        for (i = 0; i < 4; i++) {
            hip_pos[i] = (uint8_t)clamp16(
                (int16_t)hip_pos[i] - (int16_t)(dir * HIP_PUSH_R),
                10, 170);
            set_servo(i, hip_pos[i]);
        }
        break;
    }
}


/****************************************/
// Main Function

int main(void) {
    uint8_t  i;
    int16_t  fb, lr, yw, ht;
    int8_t   new_dir;
    uint8_t  is_turning;
    uint8_t  is_strafe;
    int16_t  target_knee_off;
    uint8_t  kb[4];
    uint8_t  packet_size;
    uint8_t  lora_status;
    uint8_t  print_throttle = 0;

    // UART debug 9600 baud
    UART_Init(9600);
    UART_PrintString("\r\n--- INICIANDO ROBOT RX ---\r\n");

    // LED de Enlace LoRa: PC2 (A2) como salida, inicia apagado 
    DDRC  |=  (1 << PC2);
    PORTC &= ~(1 << PC2);

    // Iniciar LoRa 
    lora_status = LoRa_Init(LORA_FREQ);
    if (lora_status != 0) {
        UART_PrintString("ERROR: Fallo comunicacion SPI LoRa\r\n");
    } else {
        UART_PrintString("LoRa OK (RX continuo)\r\n");
    }

    // Iniciar Servomotores 
    SoftServo_Init();
    SoftServo_Attach(SW_HIP_S1,  &PORTD, &DDRD, PD3, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S1, &PORTD, &DDRD, PD2, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S2,  &PORTB, &DDRB, PB0, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S2, &PORTB, &DDRB, PB1, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S3,  &PORTD, &DDRD, PD7, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S3, &PORTD, &DDRD, PD6, 30, 120, 4, 962);
    SoftServo_Attach(SW_HIP_S4,  &PORTD, &DDRD, PD5, 30, 120, 4, 962);
    SoftServo_Attach(SW_KNEE_S4, &PORTD, &DDRD, PD4, 30, 120, 4, 962);

    // Iniciar Timers + interrupciones
    FlexiTimer_Set(10, frame_tick);
    FlexiTimer_Start();
    sei();

    // Ajustar a  Postura inicial 
    go_stance(KB);
    _delay_ms(500);

    while (1) {

        // 1) Chequeo LoRa 
        if (PINC & (1 << PC1)) {
            packet_size = LoRa_ParsePacket();
            if (packet_size == sizeof(Payload_t)) {
                LoRa_ReadBytes((uint8_t *)&datos_lora, sizeof(Payload_t));
                lora_watchdog = 0;

                // LED de Enlace LoRa ON: paquete valido recibido
                PORTC |= (1 << PC2);

                // Debug: 1 print de cada 5 paquetes 
                print_throttle++;
                if (print_throttle >= 5) {
                    print_throttle = 0;
                    UART_PrintString("Pkt fb=");
                    UART_PrintInt(datos_lora.fwd_bwd);
                    UART_PrintString(" lr=");
                    UART_PrintInt(datos_lora.left_right);
                    UART_PrintString(" yw=");
                    UART_PrintInt(datos_lora.yaw);
                    UART_PrintString("\r\n");
                }
            }
        }

        // 2) Esperar tick de 10 ms 
        if (!frame_flag) continue;
        frame_flag = 0;

        // 3) Watchdog: si no llegan paquetes, parar movimiento
        if (lora_watchdog < LORA_TIMEOUT) {
            lora_watchdog++;
        } else {
            datos_lora.fwd_bwd    = 0;
            datos_lora.left_right = 0;
            datos_lora.yaw        = 0;

            // LED de Enlace LoRa OFF: se perdio el enlace 
            PORTC &= ~(1 << PC2);
        }

        // 4) Leer ejes del Payload 
        fb = dz(datos_lora.fwd_bwd);
        lr = dz(datos_lora.left_right);
        yw = dz(datos_lora.yaw);
        ht =    datos_lora.height;

        // 5) Prioridad: Avance > Strafe > Giro 
        new_dir    = 0;
        is_turning = 0;
        is_strafe  = 0;
        leg_offset = 0;

        if (abs16(fb) > DEADZONE) {
            new_dir = (fb > 0) ? 1 : -1;
        }
        else if (abs16(lr) > DEADZONE) {
            new_dir   = (lr > 0) ? 1 : -1;
            is_strafe = 1;
        }
        else if (abs16(yw) > DEADZONE) {
            new_dir    = (yw > 0) ? 1 : -1;
            is_turning = 1;
        }

        // 6) Altura: mapea height  a offset de rodilla 
        target_knee_off = clamp16((int16_t)((int32_t)ht * 65 / 512),
                                  -KNEE_OFF_MAX, KNEE_OFF_MAX);
        smooth_knee_off = target_knee_off;

        for (i = 0; i < 4; i++) {
            kb[i] = (uint8_t)clamp16(
                (int16_t)KB[i] + smooth_knee_off, KNEE_FLOOR, KNEE_MAX);
        }

        // 7) FSM de marcha 
        switch (state) {

        case IDLE:
            go_stance(kb);
            if (new_dir != 0) {
                direction  = new_dir;
                seq_leg    = 0;
                seq_step   = 0;
                if (is_strafe) {
                    execute_step_strafe(0, 0, direction, kb);
                } else {
                    execute_step(SEQ[0], 0, direction, is_turning, kb);
                }
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
            if (is_strafe) {
                execute_step_strafe((uint8_t)(seq_leg & 1), seq_step,
                                    direction, kb);
            } else {
                execute_step(SEQ[seq_leg], seq_step, direction,
                             is_turning, kb);
            }
            wait_ticks = STEP_TICKS;
            break;
        }
    }

    return 0;
}

