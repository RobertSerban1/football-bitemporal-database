ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS';

-- versiuni curente (transaction_end deschis)
CREATE OR REPLACE VIEW v_open_contracts AS
SELECT *
FROM contracts
WHERE transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59');

CREATE OR REPLACE VIEW v_open_registrations AS
SELECT *
FROM registrations
WHERE transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59');

CREATE OR REPLACE VIEW v_open_appearances AS
SELECT *
FROM appearances
WHERE transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59');

-- Current valid enrollments pentru un jucator (azi)
--     valid_start <= now < valid_end
CREATE OR REPLACE VIEW v_current_valid_registrations AS
SELECT r.registration_id,
       p.player_id, p.full_name,
       c.club_id,  c.name AS club_name,
       comp.competition_id, comp.name AS competition_name,
       r.status, r.valid_start, r.valid_end,
       r.transaction_start, r.transaction_end
FROM v_open_registrations r
JOIN players p      ON p.player_id = r.player_id
JOIN clubs   c      ON c.club_id   = r.club_id
JOIN competitions comp ON comp.competition_id = r.competition_id
WHERE r.valid_start <= SYSTIMESTAMP
  AND r.valid_end   >  SYSTIMESTAMP;

-- istoricul schimbarilor de antrenor pe club
CREATE OR REPLACE VIEW v_head_coach_history AS
SELECT c.name AS club_name,
       ch.full_name AS coach_name,
       cc.role,
       cc.valid_start, cc.valid_end,
       cc.transaction_start, cc.transaction_end
FROM club_coaches cc
JOIN clubs   c  ON c.club_id  = cc.club_id
JOIN coaches ch ON ch.coach_id = cc.coach_id
ORDER BY c.name, cc.valid_start, cc.transaction_start;

-- Conflicte intre transaction time si valid time (late data)
--     transaction_start > valid_start
CREATE OR REPLACE VIEW v_late_entries AS
SELECT
  'CONTRACTS' AS table_name,
  contract_id AS row_id,
  valid_start,
  valid_end,
  transaction_start,
  transaction_end,
  CAST(transaction_start - valid_start AS INTERVAL DAY TO SECOND) AS delay
FROM contracts
WHERE transaction_start > valid_start
UNION ALL
SELECT
  'REGISTRATIONS',
  registration_id,
  valid_start,
  valid_end,
  transaction_start,
  transaction_end,
  CAST(transaction_start - valid_start AS INTERVAL DAY TO SECOND)
FROM registrations
WHERE transaction_start > valid_start
UNION ALL
SELECT
  'APPEARANCES',
  appearance_id,
  valid_start,
  valid_end,
  transaction_start,
  transaction_end,
  CAST(transaction_start - valid_start AS INTERVAL DAY TO SECOND)
FROM appearances
WHERE transaction_start > valid_start;

-- toate inregistrarile de inscriere cu versiunea curenta
CREATE OR REPLACE VIEW v_registrations_all_current AS
SELECT r.registration_id, r.player_id, r.club_id, r.competition_id,
       r.status, r.valid_start, r.valid_end,
       r.transaction_start, r.transaction_end
FROM v_open_registrations r;

-- "AS-OF" (query cu un timestamp ales)
CREATE OR REPLACE VIEW v_registrations_asof_base AS
SELECT r.*
FROM registrations r;
