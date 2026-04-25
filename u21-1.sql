ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS';

--------------------------------------------------------------------------------
-- 1) Funcție: este jucătorul U21 la o anumită dată?
--    Regula: U21 dacă vârsta < 22 ani la data p_date
--------------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION is_u21_at(p_player_id NUMBER, p_date DATE)
RETURN NUMBER
IS
  v_dob DATE;
BEGIN
  SELECT dob INTO v_dob
  FROM players
  WHERE player_id = p_player_id
  FETCH FIRST 1 ROWS ONLY;

  IF v_dob IS NULL THEN
    RETURN 0; -- dacă nu avem DOB, tratăm ca non-U21
  END IF;

  -- dacă la p_date nu a împlinit încă 22 ani => U21
  IF ADD_MONTHS(v_dob, 12*22) > p_date THEN
    RETURN 1;
  ELSE
    RETURN 0;
  END IF;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RETURN 0;
END;
/
SHOW ERRORS;

--------------------------------------------------------------------------------
-- 2) Vedere de audit: meciuri fără U21 în primii 11 pentru fiecare club
--    Rulează asta în rapoarte; îți listează toate încălcările regulii U21.
--------------------------------------------------------------------------------
CREATE OR REPLACE VIEW v_lineups_without_u21 AS
WITH starters AS (
  SELECT a.match_id, a.club_id, a.player_id
  FROM appearances a
  WHERE a.role = 'starter'
    AND a.transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59')
),
u21_starters AS (
  SELECT s.match_id, s.club_id, COUNT(*) AS u21_cnt
  FROM starters s
  JOIN matches m ON m.match_id = s.match_id
  WHERE is_u21_at(s.player_id, m.match_date) = 1
  GROUP BY s.match_id, s.club_id
),
count_starters AS (
  SELECT s.match_id, s.club_id, COUNT(*) AS starters_cnt
  FROM starters s
  GROUP BY s.match_id, s.club_id
)
SELECT m.match_id, m.match_date,
       hc.name AS home_club,
       ac.name AS away_club,
       COALESCE(cs_home.starters_cnt,0) AS home_starters,
       COALESCE(u_home.u21_cnt,0)      AS home_u21_starters,
       COALESCE(cs_away.starters_cnt,0) AS away_starters,
       COALESCE(u_away.u21_cnt,0)       AS away_u21_starters
FROM matches m
LEFT JOIN count_starters cs_home ON cs_home.match_id = m.match_id AND cs_home.club_id = m.home_club_id
LEFT JOIN count_starters cs_away ON cs_away.match_id = m.match_id AND cs_away.club_id = m.away_club_id
LEFT JOIN u21_starters u_home    ON u_home.match_id    = m.match_id AND u_home.club_id    = m.home_club_id
LEFT JOIN u21_starters u_away    ON u_away.match_id    = m.match_id AND u_away.club_id    = m.away_club_id
JOIN clubs hc ON hc.club_id = m.home_club_id
JOIN clubs ac ON ac.club_id = m.away_club_id
WHERE (COALESCE(cs_home.starters_cnt,0) >= 11 AND COALESCE(u_home.u21_cnt,0) = 0)
   OR (COALESCE(cs_away.starters_cnt,0) >= 11 AND COALESCE(u_away.u21_cnt,0) = 0)
ORDER BY m.match_date, m.match_id;
/

--------------------------------------------------------------------------------
-- 3) Procedură: rollover U21 -> Senior când jucătorul împlinește 22 ani
--    Bitemporal: închide valid_end la data de prag și inserează versiune nouă Senior.
--    Presupune că ai tabelele:
--      - club_departments (Senior/U21 per club)
--      - player_department_assignments (versiuni pe valid+transaction)
--------------------------------------------------------------------------------
CREATE OR REPLACE PROCEDURE rollover_u21_to_senior(p_on_date DATE)
IS
BEGIN
  /*
    Găsim jucătorii care:
      - au DOB astfel încât la p_on_date împlinesc 22 ani sau au depășit 22
      - au asignare U21 deschisă (transaction_end = ∞, valid_end = ∞)
  */
  FOR r IN (
    SELECT a.player_dept_id,
           a.player_id,
           d.club_id,
           a.valid_start, a.valid_end
    FROM player_department_assignments a
    JOIN club_departments d
      ON d.department_id = a.department_id
    WHERE a.transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59')
      AND a.valid_end       = TO_TIMESTAMP('9999-12-31 23:59:59')
      AND d.name = 'U21'
      AND EXISTS (
        SELECT 1
        FROM players p
        WHERE p.player_id = a.player_id
          AND ADD_MONTHS(p.dob, 12*22) <= p_on_date
      )
  ) LOOP
    -- 3.1 Închidem versiunea U21 pe valid_time la p_on_date - microsecunda
    UPDATE player_department_assignments
    SET valid_end       = CAST(p_on_date AS TIMESTAMP) - NUMTODSINTERVAL(1,'SECOND'),
        transaction_end = SYSTIMESTAMP    -- închidem versiunea tranzacțional
    WHERE player_dept_id = r.player_dept_id;

    -- 3.2 Inserăm Senior (noua versiune) în același club
    INSERT INTO player_department_assignments(
      player_id, department_id, note,
      valid_start, valid_end, transaction_start, transaction_end
    )
    VALUES (
      r.player_id,
      (SELECT department_id
         FROM club_departments
        WHERE club_id = r.club_id
          AND name = 'Senior'
          AND ROWNUM = 1),
      'auto-rollover-22',
      CAST(p_on_date AS TIMESTAMP),
      TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),
      SYSTIMESTAMP,
      TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
    );
  END LOOP;
END;
/
SHOW ERRORS;

--------------------------------------------------------------------------------
-- 4) DEMO: simulăm un jucător care împlinește 22 ani și rulăm rollover
--    Apoi verificăm:
--      a) asignările lui (U21 -> Senior)
--      b) regula U21 pe meciuri
--------------------------------------------------------------------------------

-- Alegem un jucător cu DOB setabil pentru demonstrație
-- (folosește un jucător existent, modificăm doar DOB printr-o versiune nouă în PLAYERS)
DECLARE
  v_player NUMBER;
  v_club   NUMBER;
BEGIN
  -- ex: luăm 'FCSB Player 03'
  SELECT player_id INTO v_player FROM players WHERE full_name='FCSB Player 03' FETCH FIRST 1 ROWS ONLY;

  -- optional: dacă vrei să-l „aduci” în U21 acum, setează DOB astfel încât să fie 21 ani și 11 luni
  -- Atenție: PLAYERS e bitemporal. Ca să corectezi DOB corect bitemporal, inserezi o versiune nouă.
  -- Ca demo simplu, dacă nu ai trigger forbid pe PLAYERS, poți face un update direct.
  UPDATE players
  SET dob = ADD_MONTHS(TRUNC(SYSDATE), - (12*21) - 11)   -- ~21 ani și 11 luni
  WHERE player_id = v_player;

  COMMIT;
END;
/

-- Asigurăm că are asignare U21 curentă (dacă a intrat la Senior prin distribuția inițială)
DECLARE
  v_player NUMBER := (SELECT player_id FROM players WHERE full_name='FCSB Player 03' FETCH FIRST 1 ROWS ONLY);
  v_club   NUMBER := (SELECT club_id   FROM contracts WHERE player_id=v_player AND transaction_end=TO_TIMESTAMP('9999-12-31 23:59:59') FETCH FIRST 1 ROWS ONLY);
  v_u21_dept NUMBER;
BEGIN
  SELECT department_id INTO v_u21_dept
  FROM club_departments
  WHERE club_id = v_club AND name='U21' AND ROWNUM=1;

  -- dacă nu are o asignare U21 curentă, îi inserăm una pentru demo
  IF NOT EXISTS (
    SELECT 1 FROM player_department_assignments
     WHERE player_id=v_player
       AND department_id=v_u21_dept
       AND transaction_end=TO_TIMESTAMP('9999-12-31 23:59:59')
       AND valid_end=TO_TIMESTAMP('9999-12-31 23:59:59')
  ) THEN
    INSERT INTO player_department_assignments(
      player_id, department_id, note,
      valid_start, valid_end, transaction_start, transaction_end
    )
    VALUES(
      v_player, v_u21_dept, 'demo-U21',
      SYSTIMESTAMP, TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS'),
      SYSTIMESTAMP, TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
    );
  END IF;
END;
/
COMMIT;

-- 4.a) Verificăm că acum e U21
SELECT p.full_name, p.dob, d.name AS department_name, a.valid_start, a.valid_end
FROM player_department_assignments a
JOIN club_departments d ON d.department_id = a.department_id
JOIN players p ON p.player_id = a.player_id
WHERE a.player_id = (SELECT player_id FROM players WHERE full_name='FCSB Player 03')
  AND a.transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59');

-- 4.b) Rulăm rollover în ziua când împlinește 22 ani
DECLARE
  v_on DATE;
BEGIN
  SELECT ADD_MONTHS(dob, 12*22) INTO v_on
  FROM players WHERE full_name='FCSB Player 03';

  -- rulează mutarea automată U21 -> Senior la data împlinirii a 22 ani
  rollover_u21_to_senior(v_on);
END;
/
COMMIT;

-- 4.c) Verificăm că a trecut la Senior bitemporal corect (U21 închis pe valid, Senior deschis)
SELECT p.full_name, d.name AS department_name, a.note,
       a.valid_start, a.valid_end, a.transaction_start, a.transaction_end
FROM player_department_assignments a
JOIN club_departments d ON d.department_id = a.department_id
JOIN players p ON p.player_id = a.player_id
WHERE p.full_name='FCSB Player 03'
ORDER BY a.valid_start, a.transaction_start;

--------------------------------------------------------------------------------
-- 5) Verificarea regulii U21 pe meciuri
--    Dacă ai populat aparițiile cu Script 3, în mod normal fiecare 11 are cel puțin un U21.
--    Dacă vrei să simulezi o încălcare, poți înlocui un U21 starter cu un senior și re-rula vederea.
--------------------------------------------------------------------------------
SELECT * FROM v_lineups_without_u21;
