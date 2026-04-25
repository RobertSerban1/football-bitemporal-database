ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS';

-- exemplu: toate inscrierile valide acum pentru orice jucator FCSB*
SELECT *
FROM v_current_valid_registrations
WHERE full_name LIKE 'FCSB Player%';

-- pentru un player_id anume:
-- SELECT * FROM v_current_valid_registrations WHERE player_id = 10;


-- Istoricul schimbărilor antrenorilor (head coach) pe club
SELECT *
FROM v_head_coach_history
WHERE club_name = 'FCSB';

-- tot istoricul:
-- SELECT * FROM v_head_coach_history;


-- conflicte între transaction_time și valid_time (late data)
--SELECT *
--FROM v_late_entries
--ORDER BY delay DESC
--FETCH FIRST 50 ROWS ONLY;

SELECT *
FROM v_late_entries
ORDER BY delay DESC
FETCH FIRST 50 ROWS ONLY;



-- Toate înscrierile care AU FOST valide într-un "semestru" ales
-- exemplu: 1 oct 2025 – 15 feb 2026
SELECT 
  r.registration_id,
  p.full_name,
  c.name          AS club_name,
  comp.name       AS competition_name,
  r.status,
  r.valid_start, 
  r.valid_end
FROM v_registrations_all_current r
JOIN players      p   ON p.player_id = r.player_id
JOIN clubs        c   ON c.club_id   = r.club_id
JOIN competitions comp ON comp.competition_id = r.competition_id
WHERE r.valid_start >= TIMESTAMP '2025-10-01 00:00:00'
  AND r.valid_end   <= TIMESTAMP '2026-02-15 00:00:00'
ORDER BY p.full_name, competition_name, r.valid_start;


-- Snapshot "Ce stia sistemul la 1 martie 2026?"
-- start <= T < end
SELECT r.*, p.full_name, c.name AS club_name, comp.name AS competition_name
FROM v_registrations_asof_base r
JOIN players p ON p.player_id = r.player_id
JOIN clubs   c ON c.club_id   = r.club_id
JOIN competitions comp ON comp.competition_id = r.competition_id
WHERE r.transaction_start <= TIMESTAMP '2026-03-01 00:00:00'
  AND r.transaction_end   >  TIMESTAMP '2026-03-01 00:00:00'
ORDER BY p.full_name, r.valid_start;
