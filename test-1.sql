alter session set nls_timestamp_format='yyyy-mm-dd hh24:mi:ss';

-- functii scurte ca sa nu cautam id-uri de mana
create or replace function get_player(p_name varchar2)
return number is v number;
begin
  select player_id into v from players
  where full_name = p_name and rownum=1;
  return v;
exception when no_data_found then return null;
end;
/
create or replace function get_club_of(p_id number)
return number is v number;
begin
  select club_id into v
  from contracts
  where player_id = p_id
    and transaction_end = to_timestamp('9999-12-31 23:59:59')
  fetch first 1 rows only;
  return v;
exception when no_data_found then return null;
end;
/

--------------------------------------------------------------------------------
-- a) transfer anuntat din timp
-- Mutarea e stabilita, dar devine reala (valid) mai tarziu
--------------------------------------------------------------------------------
declare
  p number := get_player('FCSB Player 02');
  c_old number := get_club_of(p);
begin
  -- contract vechi se termina real la 2026-01-31
  version_contract(p,c_old,120000,15,
                   timestamp '2025-07-15 00:00:00',
                   timestamp '2026-01-31 23:59:59');

  -- la Dinamo din februarie 2026
  version_contract(p,club_id('Dinamo București'),140000,19,
                   timestamp '2026-02-01 00:00:00',
                   timestamp '2027-06-30 23:59:59');
end;
/

select player_id,club_id,salary,shirt_number,
       valid_start,valid_end,transaction_start,transaction_end
from contracts
where player_id=get_player('FCSB Player 02')
order by transaction_start;

--------------------------------------------------------------------------------
-- b) late entry
-- Transferul s-a intamplat mai devreme, dar il bagam in sistem abia acum
--------------------------------------------------------------------------------
declare
  p number := get_player('CFR Player 01');
  c_old number := get_club_of(p);
begin
  version_contract(p,c_old,150000,10,
                   timestamp '2025-07-15 00:00:00',
                   timestamp '2026-01-31 23:59:59');

  version_contract(p,club_id('Rapid București'),160000,9,
                   timestamp '2026-02-01 00:00:00',
                   timestamp '2027-06-30 23:59:59');
end;
/

select * from v_late_entries
where table_name='CONTRACTS'
and row_id in (select contract_id from contracts
               where player_id=get_player('CFR Player 01'));

--------------------------------------------------------------------------------
-- c) corectam o greseala
-- Realitatea ramane aceeasi, doar datele din sistem se corecteaza
--------------------------------------------------------------------------------
declare
  p number := get_player('Rapid Player 01');
  c number := get_club_of(p);
  s timestamp;
  e timestamp;
begin
  select valid_start,valid_end into s,e
  from contracts
  where player_id=p
  and transaction_end=to_timestamp('9999-12-31 23:59:59');

  -- schimbam doar numarul tricoului
  version_contract(p,c,115000,77,s,e);
end;
/

select contract_id,shirt_number,valid_start,valid_end,
       transaction_start,transaction_end
from contracts
where player_id=get_player('Rapid Player 01')
order by transaction_start;

--------------------------------------------------------------------------------
-- d) scos si bagat la loc in competitie
-- Jucator scos din lista o perioada scurta (accidentat/transfer esuat)
--------------------------------------------------------------------------------
declare
  p number := get_player('FCSB Player 02');
  c number := get_club_of(p);
  l1 number;
begin
  select competition_id into l1
  from competitions where code='L1' and rownum=1;

  version_registration(p,c,l1,'deregistered',
                       timestamp '2026-02-01 00:00:00',
                       timestamp '2026-02-10 23:59:59');

  version_registration(p,c,l1,'registered',
                       timestamp '2026-02-11 00:00:00',
                       timestamp '2026-06-01 23:59:59');
end;
/

select status,valid_start,valid_end
from v_current_valid_registrations
where player_id=get_player('FCSB Player 02');

--------------------------------------------------------------------------------
-- e) regula U21 + promovare la seniori
-- Tanar joaca U21 pana la 22 ani, apoi urca la echipa mare
--------------------------------------------------------------------------------
declare
  p     number;
  c     number;
  d_u21 number;
  d_s   number;
begin
  -- identificăm clubul și departamentele prin SELECT ... INTO
  c := club_id('Dinamo București');

  select department_id
  into   d_u21
  from   club_departments
  where  club_id = c and name = 'U21' and rownum = 1;

  select department_id
  into   d_s
  from   club_departments
  where  club_id = c and name = 'Senior' and rownum = 1;

  -- inserăm jucător U21 (născut 2004-02-01 -> împlinește 22 ani la 2026-02-01)
  insert into players(full_name,dob,nationality,primary_position,
                      valid_start,valid_end,transaction_start,transaction_end)
  values('Dinamo Youth Demo', date '2004-02-01','RO','MF',
         timestamp '2025-07-15 00:00:00',
         timestamp '9999-12-31 23:59:59',
         systimestamp, to_timestamp('9999-12-31 23:59:59'))
  returning player_id into p;

  -- contract inițial
  version_contract(p, c, 30000, 99,
                   timestamp '2025-07-15 00:00:00',
                   timestamp '2026-06-30 23:59:59');

  -- până face 22 -> U21
  insert into player_department_assignments(player_id, department_id, note,
                                            valid_start, valid_end)
  values(p, d_u21, 'academy',
         timestamp '2025-07-15 00:00:00',
         timestamp '2026-02-01 00:00:00');

  -- după 22 -> Senior
  insert into player_department_assignments(player_id, department_id, note,
                                            valid_start, valid_end)
  values(p, d_s, 'promoted',
         timestamp '2026-02-01 00:00:00',
         timestamp '9999-12-31 23:59:59');
end;
/

select p.full_name,d.name dept,a.valid_start,a.valid_end
from player_department_assignments a
join players p on p.player_id=a.player_id
join club_departments d on d.department_id=a.department_id
where p.full_name='Dinamo Youth Demo'
order by a.valid_start;

SELECT * 
FROM player_department_assignments 
WHERE player_id = (SELECT player_id FROM players WHERE full_name='Dinamo Youth Demo')
ORDER BY transaction_start;

