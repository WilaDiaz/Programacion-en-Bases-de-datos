SET SERVEROUTPUT ON;

/*--------------------------------------------------------
 MODULO   : Programacion en Bases de Datos
 Exp1_S1_Wilangely_Diaz
--------------------------------------------------------*/
/*---------------------------------------
CASO 1 PROGRAMA PESOS TODO SUMA
---------------------------------------*/

-----------BIND

VAR b_run_cliente       VARCHAR2(20);
VAR b_tramo1_max        NUMBER;
VAR b_tramo2_max        NUMBER;

VAR b_peso_base         NUMBER;
VAR b_extra_t1          NUMBER;
VAR b_extra_t2          NUMBER;
VAR b_extra_t3          NUMBER;

-----------VALORES SUGERIDOS

EXEC :b_tramo1_max := 1000000;
EXEC :b_tramo2_max := 3000000;

EXEC :b_peso_base := 1200;
EXEC :b_extra_t1  := 100;
EXEC :b_extra_t2  := 300;
EXEC :b_extra_t3  := 550;
EXEC :b_run_cliente := '22.558.061-8';
/* 
 El RUN del cliente se ingresa en forma parametrica
 antes de ejecutar el bloque PL/SQL
*/

DECLARE

v_ini_anio_ant DATE := TRUNC (ADD_MONTHS(SYSDATE, -12), 'yyyy');
v_fin_anio_ant DATE := ADD_MONTHS(TRUNC(SYSDATE, 'YYYY'), 0) - 1;

v_run_limpio        VARCHAR2(50);
v_numrun            NUMBER(10);
v_dvrun             VARCHAR2(1);

v_nro_cliente       CLIENTE.nro_cliente%TYPE;
v_nombre_cliente    VARCHAR2(50);
v_tipo_cliente      VARCHAR2(30);
v_run_formateado    VARCHAR2(15);

v_monto_total       NUMBER := 0;

v_factor_100k       NUMBER := 0;
v_extra_x100k       NUMBER := 0;
v_pesos_total       NUMBER := 0;


BEGIN

v_run_limpio := REPLACE (UPPER(:b_run_cliente),'.', '' );
v_numrun := TO_NUMBER(SUBSTR(v_run_limpio, 1, INSTR(v_run_limpio, '-')-1));
v_dvrun := SUBSTR (v_run_limpio, INSTR(v_run_limpio, '-') + 1,1);

----- tipo_cliente

SELECT c.nro_cliente,
SUBSTR(TRIM(c.pnombre || ' ' || NVL(c.snombre, '') || ' '|| c.appaterno || ' '|| NVL(c.apmaterno, '')), 1, 50)
AS nombre_cliente, tc.nombre_tipo_cliente,
(REGEXP_REPLACE(TO_CHAR(c.numrun), '(\d)(?=(\d{3})+(?!\d))', '\1.') || '-' || c.dvrun) AS run_fmt
INTO v_nro_cliente, v_nombre_cliente, v_tipo_cliente, v_run_formateado
FROM cliente c
JOIN tipo_cliente tc ON tc.cod_tipo_cliente = c.cod_tipo_cliente WHERE c.numrun = v_numrun
AND c.dvrun = v_dvrun;

-------------suma monto_solicitado

SELECT NVL(SUM(cc.monto_solicitado), 0)
INTO    v_monto_total
FROM    credito_cliente cc
WHERE   cc.nro_cliente = v_nro_cliente
AND     cc.fecha_solic_cred BETWEEN v_ini_anio_ant AND v_fin_anio_ant;

v_factor_100k := FLOOR(v_monto_total / 100000);

----Calculo factor 

IF UPPER(v_tipo_cliente) LIKE '%INDEPENDIENTE%' THEN 
IF v_monto_total < :b_tramo1_max THEN
v_extra_x100k := :b_extra_t1;
ELSIF v_monto_total <= :b_tramo2_max THEN
v_extra_x100k := :b_extra_t2;
ELSE
v_extra_x100k := :b_extra_t3;
END IF;
ELSE
v_extra_x100k := 0;
END IF;

v_pesos_total := v_factor_100k * (:b_peso_base + v_extra_x100k);

DELETE FROM cliente_todosuma
  WHERE nro_cliente = v_nro_cliente;


  INSERT INTO cliente_todosuma
    (nro_cliente, run_cliente, nombre_cliente, tipo_cliente, monto_solic_creditos, monto_pesos_todosuma)
  VALUES
    (v_nro_cliente, v_run_formateado, v_nombre_cliente, v_tipo_cliente, v_monto_total, v_pesos_total);

COMMIT;


DBMS_OUTPUT.PUT_LINE ('CASO 1 OK -> Cliente ' || v_nro_cliente || ' | monto='|| v_monto_total|| '| Pesos='|| v_pesos_total);

EXCEPTION
WHEN NO_DATA_FOUND THEN
DBMS_OUTPUT.PUT_LINE ('CASO 1 ERROR: RUN no encontrado en CLIENTE.');
WHEN OTHERS THEN
DBMS_OUTPUT.PUT_LINE ('CASO 1 ERROR GENERAL: ' || SQLERRM);
ROLLBACK;
END;
/



SELECT *
FROM cliente_todosuma
ORDER BY nro_cliente;


/*---------------------------------------
CASO 2 POSTERGACION DE CUOTAS
---------------------------------------*/

----------binds

VAR b_nro_cliente       NUMBER;
VAR b_nro_solic_credito NUMBER;
VAR b_cant_cuotas_post  NUMBER;

EXEC :b_nro_cliente := 1;
EXEC :b_nro_solic_credito := 2004;
EXEC :b_cant_cuotas_post := 1;


DECLARE

v_ini_anio_ant DATE := TRUNC(ADD_MONTHS(SYSDATE, -12), 'YYYY');
v_fin_anio_ant DATE := TRUNC(SYSDATE, 'YYYY') -1;


------datos del credito

v_nombre_credito        CREDITO.nombre_credito%TYPE;

v_ult_nro_cuota        CUOTA_CREDITO_CLIENTE.nro_cuota%TYPE;
v_ult_venc              CUOTA_CREDITO_CLIENTE.fecha_venc_cuota%TYPE;
v_ult_valor             CUOTA_CREDITO_CLIENTE.valor_cuota%TYPE;

----logica de negocio

v_tasa_pct              NUMBER(5,2) :=0;
v_cant_creditos_ant     NUMBER := 0;
v_cant_post             NUMBER;

-----Variables para nuevas cueotas

v_nueva_cuota       NUMBER;
v_nueva_fecha       DATE;
v_nuevo_valor       NUMBER(10);


----obtener tipo de credito
BEGIN
SELECT UPPER (cr.nombre_credito)
    INTO v_nombre_credito
    FROM CREDITO_CLIENTE cc
    JOIN CREDITO cr ON cr.cod_credito = cc.cod_credito
    WHERE cc.nro_solic_credito = :b_nro_solic_credito
    AND cc.nro_cliente  = :b_nro_cliente;
    
    
 
    
    
    
---- tasa y cant de cuota
 v_cant_post := :b_cant_cuotas_post;
 
  IF v_nombre_credito LIKE '%HIPOTEC%' THEN
    IF v_cant_post = 1 THEN
      v_tasa_pct := 0;
    ELSIF v_cant_post = 2 THEN
      v_tasa_pct := 0.5;
    ELSE
      v_tasa_pct := 0.5;
    END IF;

  ELSIF v_nombre_credito LIKE '%CONSUMO%' THEN
    v_tasa_pct  := 1;
    v_cant_post := 1;

  ELSIF v_nombre_credito LIKE '%AUTO%' THEN
    v_tasa_pct  := 2;
    v_cant_post := 1;

  ELSE
    v_tasa_pct := 0;
  END IF;

----obtener ultima cuota original del credito



   
SELECT MAX(nro_cuota)
    INTO v_ult_nro_cuota
    FROM CUOTA_CREDITO_CLIENTE
    WHERE nro_solic_credito = :b_nro_solic_credito;
    
SELECT fecha_venc_cuota, valor_cuota
    INTO v_ult_venc, v_ult_valor
    FROM CUOTA_CREDITO_CLIENTE
    WHERE nro_solic_credito = :b_nro_solic_credito
    AND nro_cuota   = v_ult_nro_cuota;
    
-----creditos anteriores

SELECT COUNT (DISTINCT nro_solic_credito)
INTO v_cant_creditos_ant
FROM credito_cliente
WHERE nro_cliente = :b_nro_cliente
    AND fecha_solic_cred BETWEEN v_ini_anio_ant AND v_fin_anio_ant;
    

-----si tuvo mas de un credito el año anterior, condina ultima cuota

 IF v_cant_creditos_ant > 1 THEN
UPDATE cuota_credito_cliente
   SET fecha_pago_cuota = fecha_venc_cuota,
       monto_pagado     = valor_cuota,
       saldo_por_pagar  = NULL,
       cod_forma_pago   = NULL
 WHERE nro_solic_credito = :b_nro_solic_credito
   AND nro_cuota         = v_ult_nro_cuota;
END IF;

-----generar nuevas cuotas

FOR i IN 1..v_cant_post LOOP
v_nueva_cuota := v_ult_nro_cuota + i;
v_nueva_fecha := ADD_MONTHS (v_ult_venc, i);
v_nuevo_valor := ROUND (v_ult_valor * (1 + (v_tasa_pct /100)));

INSERT INTO cuota_credito_cliente
(nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota, 
monto_pagado, fecha_pago_cuota, saldo_por_pagar, cod_forma_pago)
VALUES
(:b_nro_solic_credito, v_nueva_cuota, v_nueva_fecha, v_nuevo_valor, 
NULL, NULL, NULL, NULL);
END LOOP;
COMMIT;
END;
/



SELECT nro_solic_credito, nro_cuota, fecha_venc_cuota, valor_cuota,
       fecha_pago_cuota, monto_pagado
FROM cuota_credito_cliente
WHERE nro_solic_credito = 2004
ORDER BY nro_cuota;

