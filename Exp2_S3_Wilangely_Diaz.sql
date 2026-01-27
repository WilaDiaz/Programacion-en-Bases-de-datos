-----------------ENTREGA FORMATIVA SEMANA 3--------------
-----------------WILANGELY DIAZ--------------------------
-------------PROGRAMACION EN BASES DE DATOS--------------

SET SERVEROUTPUT ON;

-----------CASO 1-----------------


VAR b_anio NUMBER;
EXEC :b_anio := EXTRACT(YEAR FROM SYSDATE) - 1;

DECLARE

TYPE t_multas IS VARRAY(7) OF NUMBER;
v_multas t_multas := t_multas(
    1200, -- 1 Cirugía General / Dermatología
    1300, -- 2 Ortopedia y Traumatología
    1700, -- 3 Inmunología / Otorrinolaringología
    1900, -- 4 Fisiatría / Medicina Interna
    1100, -- 5 Medicina General
    2000, -- 6 Psiquiatría Adultos
    2300  -- 7 Cirugía Digestiva / Reumatología
  );
  
  
  
  v_pac_run         PAGO_MOROSO.pac_run%TYPE;
  v_pac_dv          PAGO_MOROSO.pac_dv_run%TYPE;
  v_pac_nombre      PAGO_MOROSO.pac_nombre%TYPE;
  v_ate_id          PAGO_MOROSO.ate_id%TYPE;
  v_fvenc           PAGO_MOROSO.fecha_venc_pago%TYPE;
  v_fpago           PAGO_MOROSO.fecha_pago%TYPE;
  v_dias            PAGO_MOROSO.dias_morosidad%TYPE;
  v_esp             PAGO_MOROSO.especialidad_atencion%TYPE;
  v_multa_total     PAGO_MOROSO.monto_multa%TYPE;

  v_multa_dia       NUMBER := 0;
  v_pct_desc        NUMBER := 0;
  v_fecha_nac   PACIENTE.fecha_nacimiento%TYPE;
  v_edad            NUMBER := 0;
  
 


CURSOR c_morosos IS
SELECT
    p.pac_run,
    p.dv_run,
    p.apaterno || ' ' || p.amaterno || ' ' || p.pnombre || ' ' || p.snombre AS nombre_completo,
    a.ate_id,
    pa.fecha_venc_pago,
    pa.fecha_pago,
    e.nombre AS especialidad,
    p.fecha_nacimiento
FROM PAGO_ATENCION pa
JOIN ATENCION a     ON a.ate_id = pa.ate_id
JOIN PACIENTE p     ON p.pac_run = a.pac_run
JOIN ESPECIALIDAD e ON e.esp_id = a.esp_id
WHERE pa.fecha_pago IS NOT NULL
AND pa.fecha_pago > pa.fecha_venc_pago
AND EXTRACT(YEAR FROM a.FECHA_ATENCION) = :b_anio
ORDER BY pa.fecha_venc_pago ASC, p.apaterno ASC;
    
    
    
BEGIN

EXECUTE IMMEDIATE 'TRUNCATE TABLE PAGO_MOROSO';

OPEN c_morosos;
LOOP
    FETCH c_morosos INTO v_pac_run, v_pac_dv, v_pac_nombre, v_ate_id, v_fvenc, v_fpago, v_esp, v_fecha_nac; 
      EXIT WHEN c_morosos%NOTFOUND;


------reclacular edad----


v_edad := TRUNC(MONTHS_BETWEEN(SYSDATE, v_fecha_nac) / 12);

------ dias morosidad--------

v_dias := TRUNC(v_fpago - v_fvenc);

--------multa diaria segun especialidad-----


CASE
    WHEN v_esp IN ('Cirugía General','Dermatología') THEN v_multa_dia := v_multas(1);
    WHEN v_esp = 'Ortopedia y Traumatología' THEN v_multa_dia := v_multas(2);
    WHEN v_esp IN ('Inmunología','Otorrinolaringología') THEN v_multa_dia := v_multas(3);
    WHEN v_esp IN ('Fisiatría','Medicina Interna') THEN v_multa_dia := v_multas(4);
    WHEN v_esp = 'Medicina General' THEN v_multa_dia := v_multas(5);
    WHEN v_esp = 'Psiquiatría Adultos' THEN v_multa_dia := v_multas(6);
    WHEN v_esp IN ('Cirugía Digestiva','Reumatología') THEN v_multa_dia := v_multas(7);
    ELSE v_multa_dia := 1200;
END CASE;



------porcentaje dcto 3era edad-------

BEGIN 
    SELECT porcentaje_descto
    INTO v_pct_desc
FROM PORC_DESCTO_3RA_EDAD
WHERE v_edad BETWEEN anno_ini AND anno_ter;
EXCEPTION
WHEN NO_DATA_FOUND THEN
v_pct_desc := 0;
END;

----------------Monto multa final---------

v_multa_total := ROUND((v_dias * v_multa_dia) * (1 - v_pct_desc/100));


INSERT INTO PAGO_MOROSO
  (PAC_RUN, PAC_DV_RUN, PAC_NOMBRE, ATE_ID,
   FECHA_VENC_PAGO, FECHA_PAGO, DIAS_MOROSIDAD,
   ESPECIALIDAD_ATENCION, MONTO_MULTA)
VALUES
  (v_pac_run, v_pac_dv, v_pac_nombre, v_ate_id,
   v_fvenc, v_fpago, v_dias,
   v_esp, v_multa_total);

END LOOP;
CLOSE c_morosos;

COMMIT;
END;
/

SELECT * FROM PAGO_MOROSO;
    
  SELECT pac_run,
       pac_nombre,
       especialidad_atencion,
       monto_multa
FROM PAGO_MOROSO
ORDER BY fecha_venc_pago;  
    



--------------------------------------
-------------CASO 2 ------------------
--------------------------------------
SELECT table_name FROM user_tables
WHERE table_name = 'MEDICO_SERVICIO_COMUNIDAD';



DECLARE
v_anio      NUMBER := EXTRACT(YEAR FROM SYSDATE) - 1;

  TYPE t_dest IS VARRAY(4) OF VARCHAR2(60);
  v_dest t_dest := t_dest(
    'Servicio de Atención Primaria de Urgencia (SAPU)',
 'Centros de Salud Familiar (CESFAM)',
 'Consultorios Generales',
 'Hospitales del área de la Salud Pública' 
  );
  
  
  ---------registro PL/SQL----------
  
TYPE r_salida IS RECORD (
  unidad            VARCHAR2(50),
  run_medico        VARCHAR2(15),
  nombre_medico     VARCHAR2(80),
  correo_inst       VARCHAR2(60),
  total_atenciones  NUMBER,
  destinacion       VARCHAR2(60)
  );
v_out r_salida;  


  v_unidad_2   VARCHAR2(10);
  v_ap2        VARCHAR2(10);
  v_run3       VARCHAR2(10);


---------cursor explicito -------------


CURSOR c_med IS
 SELECT
   u.NOMBRE                 AS unidad,
   m.MED_RUN                AS run_num,
   m.DV_RUN                 AS dv,
   m.APATERNO               AS ap,
   m.AMATERNO               AS am,
   m.PNOMBRE                AS pn,
   NVL(m.SNOMBRE,'')        AS sn,
COUNT(a.ATE_ID)          AS total_atenciones
FROM MEDICO m
JOIN UNIDAD u ON u.UNI_ID = m.UNI_ID
LEFT JOIN ATENCION a
  ON a.MED_RUN = m.MED_RUN
  AND EXTRACT(YEAR FROM a.FECHA_ATENCION) = v_anio
  GROUP BY
u.NOMBRE, m.MED_RUN, m.DV_RUN,
m.APATERNO, m.AMATERNO, m.PNOMBRE, m.SNOMBRE
ORDER BY u.NOMBRE, m.APATERNO;


BEGIN
    BEGIN
    EXECUTE IMMEDIATE 'DROP TABLE MEDICO_SERVICIO_COMUNIDAD';
  EXCEPTION
    WHEN OTHERS THEN NULL;
  END;

  EXECUTE IMMEDIATE '
    CREATE TABLE MEDICO_SERVICIO_COMUNIDAD (
      UNIDAD               VARCHAR2(50) NOT NULL,
      RUN_MEDICO           VARCHAR2(15) NOT NULL,
      NOMBRE_MEDICO        VARCHAR2(80) NOT NULL,
      CORREO_INSTITUCIONAL  VARCHAR2(60) NOT NULL,
      TOTAL_ATENCIONES     NUMBER       NOT NULL,
      DESTINACION          VARCHAR2(60) NOT NULL
    )';

FOR r IN c_med LOOP
    v_out.unidad := r.unidad;
    v_out.run_medico := TO_CHAR(r.run_num) || '-' || r.dv;
    v_out.nombre_medico := r.ap || ' ' || r.am || ' ' || r.pn ||
CASE WHEN r.sn IS NOT NULL AND TRIM(r.sn) <> '' THEN ' '||r.sn ELSE '' END;
    v_out.total_atenciones := r.total_atenciones;
    IF v_out.unidad IN ('Atención Adulto','Atención Ambulatoria') THEN
      v_out.destinacion := v_dest(1);
ELSIF v_out.unidad = 'Atención Urgencia' THEN
IF v_out.total_atenciones <= 3 THEN
        v_out.destinacion := v_dest(1);
ELSE
   v_out.destinacion := v_dest(4);
 END IF;
 ELSIF v_out.unidad IN ('Cardiología','Oncología','Paciente Crítico') THEN
v_out.destinacion := v_dest(4);
ELSIF v_out.unidad IN ('Cirugía','Cirugía Plástica') THEN
IF v_out.total_atenciones <= 3 THEN
v_out.destinacion := v_dest(1);
ELSE
v_out.destinacion := v_dest(4);
  END IF;
ELSIF v_out.unidad = 'Psiquiatría y Salud Mental' THEN
v_out.destinacion := v_dest(2);
ELSIF v_out.unidad = 'Traumatología Adulto' THEN
 IF v_out.total_atenciones <= 3 THEN
v_out.destinacion := v_dest(1);
 ELSE
v_out.destinacion := v_dest(4);
END IF;
ELSE
v_out.destinacion := v_dest(4);
END IF;

-----correo institucional-----


v_unidad_2 := UPPER(SUBSTR(REPLACE(v_out.unidad,' ',''),1,2));
v_ap2 := LOWER(SUBSTR(r.ap, -3, 2)); 
v_run3 := SUBSTR(TO_CHAR(r.run_num), -3, 3);
v_out.correo_inst := LOWER(v_unidad_2 || v_ap2 || v_run3 || '@ketekura.cl');

INSERT INTO MEDICO_SERVICIO_COMUNIDAD
(UNIDAD, RUN_MEDICO, NOMBRE_MEDICO, CORREO_INSTITUCIONAL, TOTAL_ATENCIONES, DESTINACION)
VALUES
(v_out.unidad, v_out.run_medico, v_out.nombre_medico, v_out.correo_inst, v_out.total_atenciones, v_out.destinacion);
  END LOOP;

  COMMIT;
END;
/

SELECT COUNT(*) FROM MEDICO_SERVICIO_COMUNIDAD;
SHOW USER;