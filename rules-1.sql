ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS';

--------------------------------------------------------------------------------
-- 1) Helper: verifică dacă un jucător este U21 la un moment în timp (valid-time)
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_u21_at(p_player_id NUMBER, p_at TIMESTAMP)
RETURN NUMBER DETERMINISTIC
IS
  v_cnt NUMBER;
BEGIN
  SELECT COUNT(*)
    INTO v_cnt
    FROM player_department_assignments a
    JOIN club_departments d
      ON d.department_id = a.department_id
   WHERE a.player_id = p_player_id
     AND d.name = 'U21'
     AND a.valid_start <= p_at
     AND a.valid_end   >  p_at
     AND a.transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS');

  RETURN CASE WHEN v_cnt > 0 THEN 1 ELSE 0 END;
END;
/
SHOW ERRORS;

--------------------------------------------------------------------------------
-- 2) Trigger: blochează inserarea/actualizarea unui titular dacă ar lăsa echipa
--    fără niciun U21 în primul 11 al acelui meci.
--------------------------------------------------------------------------------
CREATE OR REPLACE TRIGGER trg_enforce_u21_starters
BEFORE INSERT OR UPDATE OF role, player_id, club_id, match_id, valid_start ON appearances
FOR EACH ROW
DECLARE
  v_match_ts TIMESTAMP;
  v_team_id  NUMBER;
  v_u21_cnt  NUMBER;
  v_new_is_u21 NUMBER;
BEGIN
  -- Se aplică doar când rândul devine/este 'starter'
  IF :NEW.role <> 'starter' THEN
    RETURN;
  END IF;

  -- Timpul meciului (start)
  SELECT match_date INTO v_match_ts
  FROM matches
  WHERE match_id = :NEW.match_id;

  v_team_id := :NEW.club_id;

  -- Câți titulari U21 are deja echipa, fără rândul curent (dacă este UPDATE)?
  SELECT COUNT(*) INTO v_u21_cnt
  FROM appearances a
  WHERE a.match_id = :NEW.match_id
    AND a.club_id  = v_team_id
    AND a.role     = 'starter'
    AND is_u21_at(a.player_id, v_match_ts) = 1
    AND ( :NEW.appearance_id IS NULL OR a.appearance_id <> :NEW.appearance_id );

  -- Este rândul curent U21?
  v_new_is_u21 := is_u21_at(:NEW.player_id, v_match_ts);

  -- Dacă echipa ar rămâne fără U21 și jucătorul nou NU este U21 -> blocăm
  IF v_u21_cnt = 0 AND v_new_is_u21 = 0 THEN
     RAISE_APPLICATION_ERROR(
       -20021,
       'Regula U21 încălcată: fiecare echipă trebuie să aibă cel puțin un titular U21.'
     );
  END IF;
END;
/
SHOW ERRORS;



-- meciuri în care o echipă NU are U21 printre titulari
WITH starters AS (
  SELECT a.match_id, a.club_id, a.player_id
  FROM appearances a
  WHERE a.role = 'starter'
),
u21_starters AS (
  SELECT s.match_id, s.club_id, COUNT(*) AS u21_cnt
  FROM starters s
  JOIN matches m ON m.match_id = s.match_id
  WHERE is_u21_at(s.player_id, m.match_date) = 1
  GROUP BY s.match_id, s.club_id
)
SELECT m.match_id, m.match_date,
       hc.name AS home_club,
       ac.name AS away_club,
       NVL(h.u21_cnt,0) AS home_u21_starters,
       NVL(a.u21_cnt,0) AS away_u21_starters
FROM matches m
LEFT JOIN u21_starters h ON h.match_id = m.match_id AND h.club_id = m.home_club_id
LEFT JOIN u21_starters a ON a.match_id = m.match_id AND a.club_id = m.away_club_id
JOIN clubs hc ON hc.club_id = m.home_club_id
JOIN clubs ac ON ac.club_id = m.away_club_id
WHERE NVL(h.u21_cnt,0) = 0 OR NVL(a.u21_cnt,0) = 0
ORDER BY m.match_date, m.match_id;
