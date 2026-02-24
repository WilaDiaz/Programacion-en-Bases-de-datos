-----Formativa 5-------
--Pogramacion de BBDD--
----Wilangely Diaz----

--Requerimientos:
--Package 1 funcion + 2 variables
--Funcion almacenada




------Funcion almacenada----
----------------------------

CREATE OR REPLACE FUNCTION fn_nombre_especialidad(p_esp_id NUMBER)
RETURN VARCHAR2
IS
v_nombre ESPECIALIDAD.nombre%TYPE;
BEGIN
SELECT nombre
INTO v_nombre
FROM especialidad
WHERE esp_id = p_esp_id;

RETURN v_nombre;

EXCEPTION
WHEN NO_DATA_FOUND THEN
RETURN 'Sin especialidad';
END;
/
SHOW ERRORS;




-----PAKAGE-----
----------------


CREATE OR REPLACE PACKAGE pkg_morosidad IS
v_monto_multa       NUMBER;
v_pct_desc_3ra     NUMBER;

FUNCTION fn_desc_3ra_edad(p_pac_run NUMBER, p_fecha_atencion DATE) RETURN NUMBER;
END pkg_morosidad;
/
SHOW ERRORS;



CREATE OR REPLACE PACKAGE BODY pkg_morosidad IS

FUNCTION fn_desc_3ra_edad(p_pac_run NUMBER, p_fecha_atencion DATE)
 RETURN NUMBER
 IS
v_edad NUMBER;
v_pct NUMBER;
 BEGIN



SELECT TRUNC(MONTHS_BETWEEN(p_fecha_atencion, fecha_nacimiento)/12)
 INTO v_edad
 FROM PACIENTE
 WHERE pac_run = p_pac_run;

IF v_edad > 70 THEN
SELECT porcentaje_descto
 INTO v_pct
 FROM PORC_DESCTO_3RA_EDAD
 WHERE v_edad BETWEEN anno_ini AND anno_ter;

v_pct_desc_3ra := v_pct;
ELSE
v_pct_desc_3ra := 0;
END IF;

RETURN v_pct_desc_3ra;

EXCEPTION
WHEN NO_DATA_FOUND THEN
v_pct_desc_3ra := 0;
RETURN v_pct_desc_3ra;
WHEN OTHERS THEN
v_pct_desc_3ra := 0;
RETURN v_pct_desc_3ra;
END fn_desc_3ra_edad;
END pkg_morosidad;
/
SHOW ERRORS;




----PROCEDIMIENTO PRINCIPAL
---------------------------



CREATE OR REPLACE PROCEDURE sp_genera_pago_moroso IS

v_anio_anterior NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;


--VARRAY -multas por dia---
---------------------------

TYPE t_multas IS VARRAY(7) OF NUMBER;
v_multas t_multas := t_multas(1200,1300,1700,1900,1100,2000,2300);
--     1200, -- medicina general
--     1300, -- trauma
--     1700, -- neuro y pediatria
--     1900, -- oftalmologia
--     1100, -- geriatria
--     2000, -- Gine y Gatro
--     2300 -- dermatologia

    

    
  v_especialidad  VARCHAR2(30);
  v_dias_mora     NUMBER;
  v_multa_dia     NUMBER;
  v_pct_desc      NUMBER;
  v_obs           VARCHAR2(100);
  v_nombre_pac    VARCHAR2(50);
  v_correlativo   NUMBER := 0;
  v_err_msg       VARCHAR2(500);



  CURSOR c_moroso IS
    SELECT p.pac_run,
           p.dv_run,
           p.pnombre, p.snombre, p.apaterno, p.amaterno,
           a.ate_id,
           a.fecha_atencion,
           a.costo,
           m.esp_id,
           pa.fecha_venc_pago,
           pa.fecha_pago
    FROM  PACIENTE p
    JOIN  ATENCION a       ON a.pac_run = p.pac_run
    JOIN  MEDICO m         ON m.med_run = a.med_run
    JOIN  PAGO_ATENCION pa ON pa.ate_id = a.ate_id
    WHERE pa.fecha_pago IS NOT NULL
      AND pa.fecha_pago > pa.fecha_venc_pago
      AND EXTRACT(YEAR FROM pa.fecha_pago) = v_anio_anterior
    ORDER BY pa.fecha_venc_pago ASC, p.apaterno ASC;


BEGIN

  EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';
  EXECUTE IMMEDIATE 'TRUNCATE TABLE ERRORES_PROCESO';

  FOR r IN c_moroso LOOP
  BEGIN
 -- Nombre completo paciente
v_nombre_pac := r.pnombre || ' ' || r.snombre || ' ' || r.apaterno || ' ' || r.amaterno;
-- Especialidad 
v_especialidad := fn_nombre_especialidad(r.esp_id);
-- Días de morosidad
v_dias_mora := TRUNC(r.fecha_pago - r.fecha_venc_pago);
-- Selección de multa por día usando IF/ELSIF 
    IF v_especialidad = 'Medicina General' THEN
       v_multa_dia := v_multas(1);
    ELSIF v_especialidad = 'Traumatologia' THEN
          v_multa_dia := v_multas(2);
    ELSIF v_especialidad IN ('Neurologia','Pediatria') THEN
          v_multa_dia := v_multas(3);
    ELSIF v_especialidad = 'Oftalmologia' THEN
        v_multa_dia := v_multas(4);
    ELSIF v_especialidad = 'Geriatria' THEN
          v_multa_dia := v_multas(5);
    ELSIF v_especialidad IN ('Ginecologia','Gastroenterologia') THEN
          v_multa_dia := v_multas(6);
    ELSIF v_especialidad = 'Dermatologia' THEN
          v_multa_dia := v_multas(7);
    ELSE
          v_multa_dia := 0;
END IF;


pkg_morosidad.v_monto_multa := v_dias_mora * v_multa_dia;
v_pct_desc := pkg_morosidad.fn_desc_3ra_edad(r.pac_run, r.fecha_atencion);

IF v_pct_desc > 0 THEN
   pkg_morosidad.v_monto_multa :=
   pkg_morosidad.v_monto_multa -
   (pkg_morosidad.v_monto_multa * v_pct_desc / 100);
    v_obs := 'Aplica desc. 3ra edad (' || v_pct_desc || '%)';
ELSE
    v_obs := 'Sin descuento';
END IF;

INSERT INTO PAGO_MOROSO(
 pac_run, pac_dv_run, pac_nombre,
 ate_id, fecha_venc_pago, fecha_pago,
 dias_morosidad, especialidad_atencion,
 costo_atencion, monto_multa, observacion
)
VALUES(
  r.pac_run, r.dv_run, v_nombre_pac,
  r.ate_id, r.fecha_venc_pago, r.fecha_pago,
  v_dias_mora, v_especialidad,
  r.costo, pkg_morosidad.v_monto_multa, v_obs
);

EXCEPTION
WHEN OTHERS THEN
v_correlativo := v_correlativo + 1;
v_err_msg := SQLERRM;
  INSERT INTO ERRORES_PROCESO(
  nro_correlativo, subprograma_error, descripcion_error
)
VALUES(
  v_correlativo,
 'sp_genera_pago_moroso (ate_id=' || r.ate_id || ')',
  v_err_msg
);
END;
END LOOP;
COMMIT;
END;
/
SHOW ERRORS;



----Triggers----
----------------


CREATE OR REPLACE TRIGGER trg_pago_atencion_fechas
BEFORE INSERT OR UPDATE ON PAGO_ATENCION
FOR EACH ROW
DECLARE
    v_fecha_at ATENCION.fecha_atencion%TYPE;
BEGIN
    SELECT fecha_atencion
      INTO v_fecha_at
      FROM ATENCION
     WHERE ate_id = :NEW.ate_id;
     
IF :NEW.fecha_venc_pago < v_fecha_at THEN
  RAISE_APPLICATION_ERROR(-20001, 'fecha_venc_pago no puede ser < fecha_atencion');
  END IF;
  IF :NEW.fecha_pago IS NOT NULL AND :NEW.fecha_pago < v_fecha_at THEN
  RAISE_APPLICATION_ERROR(-20002, 'fecha_pago no puede ser < fecha_atencion');
END IF;
END;
/
SHOW ERRORS;     
     



CREATE OR REPLACE TRIGGER trg_pago_moroso_multa
BEFORE INSERT OR UPDATE ON PAGO_MOROSO
FOR EACH ROW
BEGIN
IF :NEW.monto_multa < 0 THEN
   RAISE_APPLICATION_ERROR(-20003, 'monto_multa no puede ser negativo');
END IF;
END;
/
SHOW ERRORS;


-----ejecucion--
----------------


BEGIN
    sp_genera_pago_moroso;
END;
/



SELECT * FROM PAGO_MOROSO;
SELECT * FROM ERRORES_PROCESO;
   