-----ENTREGA FINAL PROGRAMACION BBDD------
-------WILANGELY DIAZ---------------------

------CASO 1------

------------------
-----TRIGGER------
------------------

CREATE OR REPLACE TRIGGER trg_iud_consumo_total
AFTER INSERT OR UPDATE OF monto OR DELETE ON consumo
FOR EACH ROW

BEGIN

---insertar
IF INSERTING THEN
UPDATE total_consumos
 SET monto_consumos = monto_consumos + :NEW.monto
 WHERE id_huesped = :NEW.id_huesped;
 
 
 ---eliminar
 ELSIF DELETING THEN 
 UPDATE total_consumos
 SET monto_consumos = monto_consumos - :OLD.monto
 WHERE id_huesped = :OLD.id_huesped;
 
----actualizar
ELSIF UPDATING ('MONTO') THEN
UPDATE total_consumos
SET monto_consumos = monto_consumos + (:NEW.monto - :OLD.monto)
WHERE id_huesped = :NEW.id_huesped;

END IF;
END;
/

-----------------------------------------------
----bloque anonimo para validar el trigger-----
-----------------------------------------------

DECLARE
v_nuevo_id      NUMBER;

BEGIN
 SELECT NVL(MAX(id_consumo),0) +1
 INTO v_nuevo_id
 FROM consumo;
 
 INSERT INTO consumo (id_consumo, id_reserva,id_huesped, monto)
 VALUES(v_nuevo_id, 1587, 340006, 150);
 
 DELETE FROM consumo
 WHERE id_consumo = 11473;
 
UPDATE consumo
SET monto =95
WHERE id_consumo = 10688;

COMMIT;
END;
/


----------------------------------------
--------------CASO 2--------------------
----------------------------------------

-----------PACKAGE------------

CREATE OR REPLACE PACKAGE pkg_pagos AS
  FUNCTION fn_total_tours_usd(p_id_huesped NUMBER) RETURN NUMBER;
  END pkg_pagos;
/
  
CREATE OR REPLACE PACKAGE BODY pkg_pagos AS
    FUNCTION fn_total_tours_usd(p_id_huesped NUMBER) RETURN NUMBER IS
    v_total NUMBER;


BEGIN
    SELECT NVL(SUM(t.valor_tour * NVL(ht.num_personas,1)),0)
    INTO v_total
    FROM huesped_tour ht
    JOIN tour t ON t.id_tour = ht.id_tour
    WHERE ht.id_huesped = p_id_huesped;
    
    RETURN v_total;
EXCEPTION
    WHEN NO_DATA_FOUND THEN
RETURN 0;
  END fn_total_tours_usd;
END pkg_pagos;
/


-----funcion independiente /obtiene nombre de agencia-----

CREATE OR REPLACE FUNCTION fn_obt_agencia(p_id_huesped NUMBER)
RETURN VARCHAR2
IS 
v_agencia VARCHAR2(35);
v_id_error NUMBER;
V_MSG   VARCHAR2(300);

BEGIN
SELECT a.nom_agencia
INTO v_agencia
FROM huesped h
JOIN agencia a ON a.id_agencia = h.id_agencia
WHERE h.id_huesped = p_id_huesped;

RETURN v_agencia;
EXCEPTION
WHEN OTHERS THEN
v_msg := SQLERRM;
SELECT SQ_ERROR.NEXTVAL INTO v_id_error FROM dual;
INSERT INTO reg_errores (id_error, nomsubprograma, msg_error)
VALUES (v_id_error, 'FN_OBT_AGENCIA', v_msg);
RETURN 'NO REGISTRA AGENCIA';
END;
/


---------funcion 2 consumo del huesped-----

CREATE OR REPLACE FUNCTION fn_total_consumos_usd(p_id_huesped NUMBER)
RETURN NUMBER
IS v_total NUMBER;

BEGIN
    SELECT NVL(monto_consumos, 0)
    INTO v_total
    FROM total_consumos
    WHERE id_huesped = p_id_huesped;
RETURN NVL(v_total, 0);

EXCEPTION
WHEN NO_DATA_FOUND THEN
RETURN 0;
END;
/


-----------PROCEDIMIENTO PRINCIPAL--------------

CREATE OR REPLACE PROCEDURE sp_calcula_pagos(p_fecha IN DATE, p_tc IN NUMBER)
IS
CURSOR c_salidas IS
    SELECT r.id_huesped, h.nom_huesped || ' ' || h.appat_huesped || ' ' || h.apmat_huesped AS nombre,
    r.estadia,
    r.id_reserva
FROM reserva r
JOIN huesped h ON h.id_huesped = r.id_huesped
WHERE TRUNC(r.ingreso + r.estadia) = TRUNC(p_fecha);

v_agencia VARCHAR2(40);
v_aloj_usd NUMBER;
v_cons_usd NUMBER;
v_tours_usd NUMBER;
v_valor_personas_usd NUMBER;
v_personas NUMBER;
v_subtotal_usd NUMBER;
v_desc_consumos_usd NUMBER;
v_desc_agencia_usd NUMBER;
v_total_usd NUMBER;
v_pct_consumo NUMBER;

BEGIN
DELETE FROM detalle_diario_huespedes;
DELETE FROM reg_errores;
COMMIT;

FOR x IN c_salidas LOOP

v_agencia := fn_obt_agencia(x.id_huesped);

SELECT NVL(SUM((ha.valor_habitacion + ha.valor_minibar) * x.estadia),0)
INTO v_aloj_usd
FROM detalle_reserva dr
JOIN habitacion ha ON ha.id_habitacion = dr.id_habitacion
WHERE dr.id_reserva = x.id_reserva;

---consumo usd
v_cons_usd := fn_total_consumos_usd(x.id_huesped);


----tours usd
v_tours_usd := pkg_pagos.fn_total_tours_usd(x.id_huesped);



SELECT NVL(MAX(
CASE ha.tipo_habitacion
  WHEN 'S'  THEN 1
  WHEN 'SE' THEN 1
  WHEN 'D'  THEN 2
  WHEN 'SP' THEN 2
  WHEN 'T'  THEN 3
  WHEN 'C'  THEN 4
  ELSE 1
END
), 1)
INTO v_personas
FROM detalle_reserva dr
JOIN habitacion ha ON ha.id_habitacion = dr.id_habitacion
WHERE dr.id_reserva = x.id_reserva;


-----conversion clp a usd (Valor fijo $35.000 por persona)

v_valor_personas_usd := ROUND((35000 * v_personas) / p_tc);

---subtotal usd
v_subtotal_usd := ROUND(v_aloj_usd + v_cons_usd + v_valor_personas_usd);


----descuento consumos
SELECT NVL(MAX(pct),0)
INTO v_pct_consumo
FROM tramos_consumos
WHERE v_cons_usd BETWEEN vmin_tramo AND vmax_tramo;

v_desc_consumos_usd := ROUND(v_cons_usd * v_pct_consumo);

IF UPPER(v_agencia) LIKE '%ALBERTI%' THEN
  v_desc_agencia_usd := ROUND(v_subtotal_usd * 0.12);
ELSE
  v_desc_agencia_usd := 0;
END IF;

v_total_usd := ROUND(v_subtotal_usd - v_desc_consumos_usd - v_desc_agencia_usd);

INSERT INTO detalle_diario_huespedes
(id_huesped, nombre, agencia, alojamiento, consumos, tours, subtotal_pago, 
descuento_consumos, descuentos_agencia, total)
VALUES 
(x.id_huesped, x.nombre, v_agencia,
ROUND(v_aloj_usd * p_tc),
ROUND(v_cons_usd * p_tc),
ROUND(v_tours_usd * p_tc),
ROUND(v_subtotal_usd * p_tc),
ROUND(v_desc_consumos_usd * p_tc),
ROUND(v_desc_agencia_usd * p_tc),
ROUND(v_total_usd * p_tc));

END LOOP;

COMMIT;
END;
/

BEGIN  
   sp_calcula_pagos(TO_DATE('18/08/2021','DD/MM/YYYY'), 915);  
END;  
/



---------------------------------------------------
-------------------PRUEBAS-------------------------
---------------------------------------------------

------caso 1------

SELECT monto_consumos
FROM total_consumos
WHERE id_huesped IN (340006, 340008);

SELECT id_consumo, id_huesped, monto
FROM consumo
WHERE id_consumo IN (11473, 10688);

----caso 2-------
SELECT * FROM detalle_diario_huespedes;

