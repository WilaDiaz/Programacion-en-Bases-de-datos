--------actividad Sumativa--------
--------Exp2_s5_WilangelyDiaz
----------------------------------

SET SERVEROUTPUT ON;


---informe año anterior

VARIABLE b_periodo NUMBER;
EXEC :b_periodo := EXTRACT (YEAR FROM SYSDATE) - 1;
PRINT b_periodo;


DECLARE

-- Codigos obtenidos desde TIPO_TRANSACCION_TARJETA:
-- 102 = Avance en Efectivo
-- 103 = S*per Avance en Efectivo 
TYPE t_tipos IS VARRAY(2) OF NUMBER;
v_tipos t_tipos := t_tipos(102, 103);


TYPE r_det IS RECORD (
    numrun            CLIENTE.NUMRUN%TYPE,
    dvrun             CLIENTE.DVRUN%TYPE,
    nro_tarjeta       TARJETA_CLIENTE.NRO_TARJETA%TYPE,
    nro_transaccion   TRANSACCION_TARJETA_CLIENTE.NRO_TRANSACCION%TYPE,
    fecha_trans       TRANSACCION_TARJETA_CLIENTE.FECHA_TRANSACCION%TYPE,
    tipo_trans        TIPO_TRANSACCION_TARJETA.NOMBRE_TPTRAN_TARJETA%TYPE,
    monto_base        TRANSACCION_TARJETA_CLIENTE.MONTO_TRANSACCION%TYPE,
    monto_total       NUMBER,
    aporte_sbif       NUMBER
  );
  v_det r_det;
  
v_total_reg     NUMBER :=0;
v_proc_ok       NUMBER :=0;

e_sin_transacciones EXCEPTION;

CURSOR c_detalle IS
SELECT c.numrun,
c.dvrun,
tc.nro_tarjeta,
t.nro_transaccion,
t.fecha_transaccion,
tt.nombre_tptran_tarjeta AS tipo_trans,
t.monto_transaccion      AS monto_base,
tt.tasaint_tptran_tarjeta AS tasa
FROM cliente c
JOIN tarjeta_cliente tc
     ON tc.numrun = c.numrun
JOIN transaccion_tarjeta_cliente t
     ON t.nro_tarjeta = tc.nro_tarjeta
JOIN tipo_transaccion_tarjeta tt
     ON tt.cod_tptran_tarjeta = t.cod_tptran_tarjeta
WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = :b_periodo
     AND t.cod_tptran_tarjeta IN (v_tipos(1), v_tipos(2))
ORDER BY t.fecha_transaccion, c.numrun;



----solo lista los grupos mes-año

     
CURSOR c_resumen(p_periodo NUMBER) IS
SELECT TO_CHAR(t.fecha_transaccion,'MMYYYY') AS mes_anno,
       tt.nombre_tptran_tarjeta              AS tipo_trans
FROM transaccion_tarjeta_cliente t
JOIN tipo_transaccion_tarjeta tt
     ON tt.cod_tptran_tarjeta = t.cod_tptran_tarjeta
WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = p_periodo
     AND t.cod_tptran_tarjeta IN (v_tipos(1), v_tipos(2))
GROUP BY TO_CHAR(t.fecha_transaccion,'MMYYYY'),
         tt.nombre_tptran_tarjeta
ORDER BY TO_CHAR(t.fecha_transaccion,'MMYYYY'),
         tt.nombre_tptran_tarjeta;
     




TYPE t_sum IS RECORD (monto_total NUMBER, aporte_total NUMBER);
TYPE t_map IS TABLE OF t_sum INDEX BY VARCHAR2(50);
v_map t_map;

FUNCTION k(p_mes VARCHAR2, p_tipo VARCHAR2) RETURN VARCHAR2 IS
BEGIN
RETURN p_mes|| '|' ||p_tipo;
END;

BEGIN
EXECUTE IMMEDIATE 'TRUNCATE TABLE DETALLE_APORTE_SBIF';
EXECUTE IMMEDIATE 'TRUNCATE TABLE RESUMEN_APORTE_SBIF';


SELECT COUNT(*)
INTO v_total_reg
FROM transaccion_tarjeta_cliente t
JOIN tipo_transaccion_tarjeta tt
     ON tt.cod_tptran_tarjeta = t.cod_tptran_tarjeta
WHERE EXTRACT(YEAR FROM t.fecha_transaccion) = :b_periodo
  AND tt.cod_tptran_tarjeta IN (v_tipos(1), v_tipos(2));
    
IF v_total_reg = 0 THEN
RAISE e_sin_transacciones;
END IF;



----PL/SQL


FOR r IN c_detalle LOOP
BEGIN
v_det.numrun          := r.numrun;
v_det.dvrun           := r.dvrun;
v_det.nro_tarjeta     := r.nro_tarjeta;
v_det.nro_transaccion := r.nro_transaccion;
v_det.fecha_trans     := r.fecha_transaccion;
v_det.tipo_trans      := r.tipo_trans;
v_det.monto_base      := r.monto_base;

v_det.monto_total := ROUND(v_det.monto_base * (1 + (r.tasa/100)));

BEGIN
SELECT ROUND(v_det.monto_total * (porc_aporte_sbif/100))
INTO v_det.aporte_sbif
FROM tramo_aporte_sbif
WHERE v_det.monto_total BETWEEN tramo_inf_av_sav AND tramo_sup_av_sav;
EXCEPTION
WHEN NO_DATA_FOUND THEN

DBMS_OUTPUT.PUT_LINE('NO_DATA_FOUND: sin tramo para monto total=' ||v_det.monto_total);
v_det.aporte_sbif := 0;
END;

INSERT INTO detalle_aporte_sbif
(numrun, dvrun, nro_tarjeta, nro_transaccion, fecha_transaccion,tipo_transaccion, monto_transaccion, aporte_sbif)
VALUES
(v_det.numrun, v_det.dvrun, v_det.nro_tarjeta, v_det.nro_transaccion, v_det.fecha_trans,
v_det.tipo_trans, v_det.monto_total, v_det.aporte_sbif);


v_proc_ok := v_proc_ok + 1;



DECLARE
v_mes       VARCHAR2(6) := TO_CHAR(v_det.fecha_trans,'MMYYYY');
v_key       VARCHAR2(50) := k(v_mes, v_det.tipo_trans);
BEGIN
IF NOT v_map.EXISTS(v_key) THEN
v_map(v_key).monto_total :=0;
v_map(v_key).aporte_total :=0;
END IF;

v_map(v_key).monto_total := v_map(v_key).monto_total + v_det.monto_total;
v_map(v_key).aporte_total := v_map(v_key).aporte_total + v_det.aporte_sbif;
END;
EXCEPTION
WHEN VALUE_ERROR THEN

DBMS_OUTPUT.PUT_LINE('VALUE_ERROR en transacción '||r.nro_transaccion);
WHEN OTHERS THEN

DBMS_OUTPUT.PUT_LINE('OTROS: '||SQLCODE||' - '||SQLERRM);
END;
END LOOP;


--------------------------------------
--------------------------------------
--------------------------------------
--------------------------------------

FOR x IN c_resumen(:b_periodo) LOOP
DECLARE
v_key VARCHAR2(50) :=k(x.mes_anno, x.tipo_trans);
BEGIN
INSERT INTO resumen_aporte_sbif
(mes_anno, tipo_transaccion, monto_total_transacciones, aporte_total_abif)
VALUES
(x.mes_anno, x.tipo_trans,
ROUND(v_map(v_key).monto_total),
ROUND(v_map(v_key).aporte_total));
END;
END LOOP;

IF v_proc_ok = v_total_reg THEN
COMMIT;
ELSE
ROLLBACK;

DBMS_OUTPUT.PUT_LINE('ROLLBACK: procesados '||v_proc_ok||' de '||v_total_reg);
END IF;

EXCEPTION
WHEN e_sin_transacciones THEN
ROLLBACK;

DBMS_OUTPUT.PUT_LINE('No hay transacciones para el periodo.');
END;
/
------------------------------------------------------------------------
------------------------------------------------------------------------
-----------Consultas de verificacion (post-ejecución)-------------------
------------------------------------------------------------------------
------------------------------------------------------------------------



SELECT tipo_transaccion, COUNT(*) AS cantidad
FROM detalle_aporte_sbif
GROUP BY tipo_transaccion
ORDER BY tipo_transaccion;

SELECT *
FROM detalle_aporte_sbif
ORDER BY fecha_transaccion, numrun, nro_transaccion;

SELECT *
FROM resumen_aporte_sbif
ORDER BY mes_anno, tipo_transaccion;

SELECT TO_CHAR(fecha_transaccion,'MMYYYY') AS mes_anno,
       tipo_transaccion,
       SUM(monto_transaccion) AS monto_total_detalle,
       SUM(aporte_sbif)       AS aporte_total_detalle
FROM detalle_aporte_sbif
GROUP BY TO_CHAR(fecha_transaccion,'MMYYYY'), tipo_transaccion
ORDER BY mes_anno, tipo_transaccion;



SELECT mes_anno,
       tipo_transaccion,
       monto_total_transacciones,
       aporte_total_abif
FROM resumen_aporte_sbif
ORDER BY mes_anno, tipo_transaccion;