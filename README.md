# ⚽ Bitemporal Football Database (Oracle)

## 📌 Project Overview

This project implements a **bitemporal relational database system** using **Oracle 21c**, designed to model a football club management scenario.

The database tracks:
- Players
- Clubs
- Coaches
- Contracts
- Competitions
- Matches
- Registrations
- Appearances

The main goal is to support **bitemporal data**, meaning the system keeps track of:
- **Valid time** (when the data is true in reality)
- **Transaction time** (when the data is stored in the database)

---

## 🧠 Problem Description

The task was to design and implement a relational database system that:
- Models a real-world scenario
- Supports bitemporal data tracking
- Preserves historical data (no overwriting)
- Allows advanced temporal queries

Each relevant table includes:
- `valid_start`, `valid_end`
- `transaction_start`, `transaction_end`

---

## ⚙️ Technologies Used

- Oracle Database 21c
- SQL and PL/SQL
- Oracle temporal features (`PERIOD FOR`)
- Triggers
- Stored Procedures

---

## 🏗️ Database Design

Main tables:
- `clubs`
- `players`
- `coaches`
- `contracts`
- `competitions`
- `matches`
- `registrations`
- `appearances`

Each table includes temporal attributes:

```sql
valid_start       TIMESTAMP
valid_end         TIMESTAMP
transaction_start TIMESTAMP
transaction_end   TIMESTAMP
```

Oracle temporal support is used:

```sql
PERIOD FOR valid_period (valid_start, valid_end)
```

---

## ⏳ Bitemporal Model Explained

### Valid Time
Represents when data is true in the real world.

Example:
```sql
valid_start = 2026-01-01
```

### Transaction Time
Represents when data is recorded in the system.

Example:
```sql
transaction_start = 2026-01-05
```

This allows:
- tracking delays in data entry
- reconstructing past states
- maintaining full history

---

## 🔁 Versioning Mechanism

The database does not overwrite records. Instead:

1. The old version is closed:
```sql
transaction_end = CURRENT_TIMESTAMP
```

2. A new version is inserted:
```sql
transaction_start = CURRENT_TIMESTAMP
transaction_end = NULL
```

This ensures full historical tracking.

---

## 🔧 Triggers and Procedures

### Triggers
Used to:
- automatically set transaction timestamps
- ensure data consistency
- prevent invalid temporal states

### Stored Procedures

Used for versioning logic:
- `version_contract`
- `version_registration`
- `version_appearance`

They:
- close old records
- insert updated versions

---

## 📊 Temporal Queries (Views)

The project includes views to simplify temporal queries.

### Current valid data
```sql
SELECT * FROM v_current_valid_registrations;
```

### History of changes
```sql
SELECT * FROM v_head_coach_history;
```

### Late data entry detection
```sql
SELECT * FROM v_late_entries;
```

### Data valid in a time interval
```sql
SELECT *
FROM v_registrations_all_current
WHERE valid_start <= :end_date
  AND valid_end >= :start_date;
```

### System state at a given time
```sql
SELECT *
FROM v_registrations_asof_base
WHERE transaction_start <= TIMESTAMP '2026-03-01 00:00:00'
  AND (transaction_end IS NULL OR transaction_end > TIMESTAMP '2026-03-01 00:00:00');
```

---

## 📁 Project Structure

```
.
├── delete-1.sql
├── data-1.sql
├── version-1.sql
├── views-1.sql
├── queries-1.sql
├── updates-1.sql
├── u21-1.sql
├── rules-1.sql
└── test-1.sql
```

---

## ▶️ Execution Order

The scripts must be executed in the following order:

1. `delete-1.sql` (optional – reset database)
2. `data-1.sql` (tables, triggers, initial data)
3. `version-1.sql` (versioning procedures)
4. `views-1.sql` (temporal views)
5. `queries-1.sql` (required queries)
6. `updates-1.sql` (extensions: departments, U21 rule)
7. `u21-1.sql` (additional rules)
8. `test-1.sql` (examples and testing)

---

## 💡 How the System Works

Instead of directly updating records, the system uses versioning:

- old data is not deleted
- a new version is inserted
- the previous version is closed using `transaction_end`

This ensures:
- full audit history
- accurate tracking of changes
- separation between real-world validity and system knowledge

---

## 🧾 Conclusion

This project demonstrates how bitemporal databases:
- preserve full data history
- separate real-world time from system time
- support complex temporal queries

Using Oracle 21c features, triggers, and PL/SQL procedures, the system ensures accurate and consistent temporal data management.
