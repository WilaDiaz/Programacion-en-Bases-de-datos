/*----------------------------------------------
SUMATIVA 1 - PROGRAMACION DE BASES DE DATOS
WILANGELY DIAZ
GENERAR CREDENCIALES 
--------------------------------------------------*/
SET SERVEROUTPUT ON;



VAR b_fecha_proceso VARCHAR2(10);
EXEC :b_fecha_proceso := TO_CHAR(SYSDATE, 'DD/MM/YYYY');


DECLARE

    v_id_emp           EMPLEADO.id_emp%TYPE;
    v_numrun_emp       EMPLEADO.numrun_emp%TYPE;
    v_dvrun_emp        EMPLEADO.dvrun_emp%TYPE;
    v_appaterno_emp    EMPLEADO.appaterno_emp%TYPE;
    v_apmaterno_emp    EMPLEADO.apmaterno_emp%TYPE;
    v_pnombre_emp      EMPLEADO.pnombre_emp%TYPE;
    v_snombre_emp      EMPLEADO.snombre_emp%TYPE;
    v_fecha_nac        EMPLEADO.fecha_nac%TYPE;
    v_fecha_contrato   EMPLEADO.fecha_contrato%TYPE;
    v_sueldo_base      EMPLEADO.sueldo_base%TYPE;
    v_estado_civil     ESTADO_CIVIL.nombre_estado_civil%TYPE;
    


v_nombre_empleado  USUARIO_CLAVE.nombre_empleado%TYPE;
v_nombre_usuario   USUARIO_CLAVE.nombre_usuario%TYPE;
v_clave_usuario    USUARIO_CLAVE.clave_usuario%TYPE;
    
    
v_fecha_proc       DATE;
v_annos_trab       NUMBER;
v_mmYYYY           VARCHAR2(6);
v_tercer_dig_run   VARCHAR2(1);
v_anio_nac_mas2    NUMBER;
v_ult3_formato     VARCHAR2(3);
v_2letras_ap       VARCHAR2(2);
v_contador         NUMBER := 0;
v_total            NUMBER;




CURSOR c_empleado IS
      SELECT  e.id_emp,
            e.numrun_emp,
            e.dvrun_emp,
            e.appaterno_emp,
            e.apmaterno_emp,
            e.pnombre_emp,
            e.snombre_emp,
            e.fecha_nac,
            e.fecha_contrato,
            e.sueldo_base,
            e.id_estado_civil,
            ec.nombre_estado_civil
FROM empleado e
JOIN estado_civil ec
     ON ec.id_estado_civil = e.id_estado_civil
WHERE e.id_emp BETWEEN 100 AND 320
ORDER BY e.id_emp;



BEGIN
    v_fecha_proc := TO_DATE(:b_fecha_proceso,'DD/MM/YYYY');
    v_mmYYYY     := TO_CHAR(v_fecha_proc,'MMYYYY');


-------SQL total empleados a procesar

    SELECT COUNT(*)
    INTO v_total
    FROM empleado
    WHERE id_emp BETWEEN 100 AND 320;
    
------SQL dinamico - limpia la tabla -----
    EXECUTE IMMEDIATE 'TRUNCATE TABLE USUARIO_CLAVE';
    
    

    FOR r IN c_empleado LOOP
        v_contador := v_contador + 1;
        
        v_id_emp          := r.id_emp;
        v_numrun_emp      := r.numrun_emp;
        v_dvrun_emp       := r.dvrun_emp;
        v_appaterno_emp   := r.appaterno_emp;
        v_apmaterno_emp   := r.apmaterno_emp;
        v_pnombre_emp     := r.pnombre_emp;
        v_snombre_emp     := r.snombre_emp;
        v_fecha_nac       := r.fecha_nac;
        v_fecha_contrato  := r.fecha_contrato;
        v_sueldo_base     := r.sueldo_base;
        v_estado_civil    := r.nombre_estado_civil;



/*----------- nombre completo----------------*/


v_nombre_empleado :=
        INITCAP(v_pnombre_emp) || ' ' ||
        NVL(INITCAP(v_snombre_emp) || ' ','') ||
        INITCAP(v_appaterno_emp) || ' ' ||
        INITCAP(v_apmaterno_emp);


/*----------- PL/SQL años trabajados----------------*/
    

v_annos_trab :=
  TRUNC(MONTHS_BETWEEN(v_fecha_proc, v_fecha_contrato)/12);

/*----------- codigo NOMBRE_USUARIO----------------*/


v_nombre_usuario :=
       LOWER(SUBSTR(v_estado_civil,1,1)) ||
       LOWER(SUBSTR(v_pnombre_emp,1,3)) ||
       LENGTH(v_pnombre_emp) || '*' ||
SUBSTR(TO_CHAR(v_sueldo_base), -1) ||
  v_dvrun_emp ||
  v_annos_trab ||
CASE WHEN v_annos_trab < 10 THEN 'X' ELSE '' END;


/*----------- codigo CLAVE_USUARIO----------------*/

v_tercer_dig_run := SUBSTR(TO_CHAR(v_numrun_emp),3,1);
  v_anio_nac_mas2  := EXTRACT(YEAR FROM v_fecha_nac) + 2;
  v_ult3_formato :=
  LPAD(TO_CHAR(GREATEST(MOD(v_sueldo_base,1000)-1,0)),
3,'0'
 );


/*----------------letras segun estado civil-----------*/

IF UPPER(v_estado_civil) IN ('CASADO','ACUERDO DE UNION CIVIL') THEN
   v_2letras_ap := LOWER(SUBSTR(v_appaterno_emp,1,2));
ELSIF UPPER(v_estado_civil) IN ('DIVORCIADO','SOLTERO') THEN
   v_2letras_ap := LOWER(SUBSTR(v_appaterno_emp,1,1) ||
SUBSTR(v_appaterno_emp,-1));
ELSIF UPPER(v_estado_civil) = 'VIUDO' THEN
   v_2letras_ap := LOWER(SUBSTR(v_appaterno_emp,-3,1) ||
SUBSTR(v_appaterno_emp,-2,1));
ELSIF UPPER(v_estado_civil) = 'SEPARADO' THEN
   v_2letras_ap := LOWER(SUBSTR(v_appaterno_emp,-2,2));
        ELSE
   v_2letras_ap := LOWER(SUBSTR(v_appaterno_emp,1,2));
END IF;

-------PL/SQL generacion de clave segun reglas de negocio


v_clave_usuario :=
  v_tercer_dig_run ||
  v_anio_nac_mas2 ||
  v_ult3_formato ||
  v_2letras_ap ||
  v_id_emp ||
  v_mmYYYY;
    

v_nombre_usuario := SUBSTR(v_nombre_usuario, 1, 20);
v_clave_usuario  := SUBSTR(v_clave_usuario,  1, 20);
    
    
    
INSERT INTO usuario_clave (
   id_emp,
   numrun_emp,
   dvrun_emp,
   nombre_empleado,
   nombre_usuario,
   clave_usuario
)
VALUES (
   v_id_emp,
   v_numrun_emp,
   v_dvrun_emp,
   v_nombre_empleado,
   v_nombre_usuario,
   v_clave_usuario
);
  END LOOP;
  
  
IF v_contador = v_total THEN
  COMMIT;

  DBMS_OUTPUT.PUT_LINE('Proceso finalizado correctamente. Empleados procesados: ' || v_contador);
ELSE
    ROLLBACK;
DBMS_OUTPUT.PUT_LINE('Proceso incompleto. Procesados: ' || v_contador || ' de ' || v_total || ', Se aplico ROLLBACK.');
END IF;

END;
/


SELECT *
FROM usuario_clave
ORDER BY id_emp;


