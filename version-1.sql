ALTER SESSION SET NLS_TIMESTAMP_FORMAT='YYYY-MM-DD HH24:MI:SS';

-- HELPERI --
CREATE OR REPLACE FUNCTION club_id(p_name VARCHAR2)
RETURN NUMBER IS v_id NUMBER;
BEGIN
  SELECT c.club_id INTO v_id
  FROM clubs c
  WHERE c.name = p_name
  AND ROWNUM = 1;
  RETURN v_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20011, 'Club inexistent: '||p_name);
END;
/

CREATE OR REPLACE FUNCTION coach_id_by_name(p_name VARCHAR2)
RETURN NUMBER IS v_id NUMBER;
BEGIN
  SELECT ch.coach_id INTO v_id
  FROM coaches ch
  WHERE ch.full_name = p_name
  AND ROWNUM = 1;
  RETURN v_id;
EXCEPTION
  WHEN NO_DATA_FOUND THEN
    RAISE_APPLICATION_ERROR(-20012, 'Coach inexistent: '||p_name);
END;
/

-- PROCEDURI VERSIONARE --

-- version_contract --
CREATE OR REPLACE PROCEDURE version_contract(
  p_player_id   IN NUMBER,
  p_club_id     IN NUMBER,
  p_salary      IN NUMBER,
  p_shirt       IN NUMBER,
  p_valid_start IN TIMESTAMP,
  p_valid_end   IN TIMESTAMP
)
IS
BEGIN
  IF p_valid_end <= p_valid_start THEN
    RAISE_APPLICATION_ERROR(-20020, 'contract: valid_end trebuie > valid_start');
  END IF;

  UPDATE contracts
     SET transaction_end = SYSTIMESTAMP
   WHERE player_id = p_player_id
     AND club_id   = p_club_id
     AND transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS');

  -- Inseram noua versiune
  INSERT INTO contracts(
    player_id, club_id, salary, shirt_number,
    valid_start, valid_end,
    transaction_start, transaction_end
  )
  VALUES (
    p_player_id, p_club_id, p_salary, p_shirt,
    p_valid_start, p_valid_end,
    SYSTIMESTAMP,
    TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
  );
END;
/
SHOW ERRORS;

-- version_registration --
CREATE OR REPLACE PROCEDURE version_registration(
  p_player_id     IN NUMBER,
  p_club_id       IN NUMBER,
  p_competition_id IN NUMBER,
  p_status        IN VARCHAR2,
  p_valid_start   IN TIMESTAMP,
  p_valid_end     IN TIMESTAMP
)
IS
BEGIN
  IF p_valid_end <= p_valid_start THEN
    RAISE_APPLICATION_ERROR(-20021, 'registration: valid_end trebuie > valid_start');
  END IF;

  UPDATE registrations
     SET transaction_end = SYSTIMESTAMP
   WHERE player_id = p_player_id
     AND club_id   = p_club_id
     AND competition_id = p_competition_id
     AND transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS');

  -- Inseram noua versiune
  INSERT INTO registrations(
    player_id, club_id, competition_id, status,
    valid_start, valid_end,
    transaction_start, transaction_end
  )
  VALUES (
    p_player_id, p_club_id, p_competition_id, p_status,
    p_valid_start, p_valid_end,
    SYSTIMESTAMP,
    TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
  );
END;
/
SHOW ERRORS;

-- version_appearance --
CREATE OR REPLACE PROCEDURE version_appearance(
  p_match_id     IN NUMBER,
  p_player_id    IN NUMBER,
  p_club_id      IN NUMBER,
  p_role         IN VARCHAR2,
  p_minutes      IN NUMBER,
  p_goals        IN NUMBER,
  p_assists      IN NUMBER,
  p_yc           IN NUMBER,
  p_rc           IN NUMBER,
  p_valid_start  IN TIMESTAMP,
  p_valid_end    IN TIMESTAMP
)
IS
BEGIN
  IF p_valid_end <= p_valid_start THEN
    RAISE_APPLICATION_ERROR(-20022, 'appearance: valid_end trebuie > valid_start');
  END IF;

  UPDATE appearances
     SET transaction_end = SYSTIMESTAMP
   WHERE match_id = p_match_id
     AND player_id = p_player_id
     AND transaction_end = TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS');

  -- Inseram noua versiune
  INSERT INTO appearances(
    match_id, player_id, club_id,
    role, minutes_played, goals, assists,
    yellow_cards, red_cards,
    valid_start, valid_end,
    transaction_start, transaction_end
  )
  VALUES (
    p_match_id, p_player_id, p_club_id,
    p_role, p_minutes, p_goals, p_assists,
    p_yc, p_rc,
    p_valid_start, p_valid_end,
    SYSTIMESTAMP,
    TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
  );
END;
/
SHOW ERRORS;

-- HELPER: adauga jucator + contract initial --
CREATE OR REPLACE PROCEDURE add_player_with_contract(
  p_full_name   IN VARCHAR2,
  p_dob         IN DATE,
  p_nat         IN CHAR,
  p_pos         IN VARCHAR2,
  p_club_name   IN VARCHAR2,
  p_salary      IN NUMBER,
  p_shirt       IN NUMBER,
  p_valid_start IN TIMESTAMP,
  p_valid_end   IN TIMESTAMP
)
IS
  v_player_id NUMBER;
  v_club_id   NUMBER;
BEGIN
  INSERT INTO players(
    full_name, dob, nationality, primary_position,
    valid_start, valid_end, transaction_start, transaction_end
  )
  VALUES(
    p_full_name, p_dob, p_nat,
    CASE UPPER(p_pos)
      WHEN 'GK' THEN 'GK'
      WHEN 'DF' THEN 'DF'
      WHEN 'MF' THEN 'MF'
      WHEN 'FW' THEN 'FW'
      WHEN 'CB' THEN 'DF' WHEN 'LB' THEN 'DF' WHEN 'RB' THEN 'DF'
      WHEN 'CM' THEN 'MF' WHEN 'DM' THEN 'MF' WHEN 'AM' THEN 'MF'
      WHEN 'LW' THEN 'FW' WHEN 'RW' THEN 'FW' WHEN 'ST' THEN 'FW'
      ELSE 'MF'
    END,
    p_valid_start, p_valid_end,
    SYSTIMESTAMP, TO_TIMESTAMP('9999-12-31 23:59:59','YYYY-MM-DD HH24:MI:SS')
  )
  RETURNING player_id INTO v_player_id;

  v_club_id := club_id(p_club_name);

  -- contract initial
  version_contract(v_player_id, v_club_id, p_salary, p_shirt, p_valid_start, p_valid_end);
END;
/
SHOW ERRORS;

-- PROTECȚII: blocăm UPDATE/DELETE directe pe tabelele bitemporale -- 
--CREATE OR REPLACE TRIGGER forbid_ud_contracts
--BEFORE UPDATE OR DELETE ON contracts
--BEGIN
--  RAISE_APPLICATION_ERROR(-20030, 'Nu se permite UPDATE/DELETE direct pe CONTRACTS. Folosește version_contract().');
--END;
--/
--SHOW ERRORS;
--
--CREATE OR REPLACE TRIGGER forbid_ud_registrations
--BEFORE UPDATE OR DELETE ON registrations
--BEGIN
--  RAISE_APPLICATION_ERROR(-20031, 'Nu se permite UPDATE/DELETE direct pe REGISTRATIONS. Folosește version_registration().');
--END;
--/
--SHOW ERRORS;
--
--CREATE OR REPLACE TRIGGER forbid_ud_appearances
--BEFORE UPDATE OR DELETE ON appearances
--BEGIN
--  RAISE_APPLICATION_ERROR(-20032, 'Nu se permite UPDATE/DELETE direct pe APPEARANCES. Folosește version_appearance().');
--END;
--/
--SHOW ERRORS;

CREATE OR REPLACE TRIGGER forbid_ud_club_coaches
BEFORE UPDATE OR DELETE ON club_coaches
BEGIN
  RAISE_APPLICATION_ERROR(-20033, 'Nu se permite UPDATE/DELETE direct pe CLUB_COACHES. Inserează noi versiuni.');
END;
/
SHOW ERRORS;
