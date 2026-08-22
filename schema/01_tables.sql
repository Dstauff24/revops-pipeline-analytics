-- ============================================================
-- revops-pipeline-analytics: schema
--
-- ALL DATA LOADED INTO THESE TABLES IS SYNTHETIC. It is produced
-- by data/generate.py and represents no real company, customer,
-- or employee.
--
-- The shape here is deliberately modeled on a CRM export rather
-- than on a clean warehouse model. Design choices are commented
-- inline, because the choices are the interesting part.
-- ============================================================

DROP TABLE IF EXISTS activities;
DROP TABLE IF EXISTS stage_history;
DROP TABLE IF EXISTS leads;
DROP TABLE IF EXISTS opportunities;
DROP TABLE IF EXISTS accounts;
DROP TABLE IF EXISTS reps;
DROP TABLE IF EXISTS territories;

-- ------------------------------------------------------------
-- territories
--
-- market_tier is the planning label the business assigns, and
-- tam_estimate is the number someone typed into a spreadsheet
-- during territory planning. Both are opinions, not measurements.
-- They are stored anyway because capacity decisions get made
-- against them (see queries/14_territory_capacity.sql).
-- ------------------------------------------------------------
CREATE TABLE territories (
    territory_id  INTEGER PRIMARY KEY,
    name          VARCHAR NOT NULL,
    region        VARCHAR NOT NULL,
    market_tier   VARCHAR NOT NULL,   -- Tier 1 / Tier 2 / Tier 3
    tam_estimate  BIGINT  NOT NULL    -- total addressable market, USD
);

-- ------------------------------------------------------------
-- reps
--
-- termination_date is nullable and that nullability drives most
-- of the hard parts of rep-level analysis. A rep who left in
-- month 7 of the year still has closed revenue on the board and
-- a full-year quota attached, so any attainment math has to
-- decide whether to prorate. See query 11.
--
-- ramp_status is the CRM's own label. It is stored, but the
-- queries derive ramp from hire_date instead, because the label
-- goes stale the moment nobody updates it. That gap is normal
-- and worth showing.
--
-- manager_id is a self reference. No foreign key is declared on
-- it (see the note at the bottom of this file).
-- ------------------------------------------------------------
CREATE TABLE reps (
    rep_id           INTEGER PRIMARY KEY,
    name             VARCHAR NOT NULL,
    hire_date        DATE    NOT NULL,
    territory_id     INTEGER NOT NULL,
    segment_focus    VARCHAR NOT NULL,   -- SMB / Mid-Market / Enterprise
    ramp_status      VARCHAR NOT NULL,   -- Ramping / Full Productivity / Terminated
    quota_annual     DECIMAL(12,2) NOT NULL,
    manager_id       INTEGER,            -- NULL for managers themselves
    termination_date DATE                -- NULL means still employed
);

-- ------------------------------------------------------------
-- accounts
--
-- segment is stored rather than derived from employee_count on
-- the fly, because that is how a CRM does it: the segment is
-- stamped at creation and then drifts as the company grows. The
-- two columns are both kept so the drift stays visible.
--
-- No unique constraint on company_name. Real CRMs collect
-- duplicates, and query 12 is built to find them.
-- ------------------------------------------------------------
CREATE TABLE accounts (
    account_id     INTEGER PRIMARY KEY,
    company_name   VARCHAR NOT NULL,
    industry       VARCHAR NOT NULL,
    employee_count INTEGER NOT NULL,
    territory_id   INTEGER NOT NULL,
    created_date   DATE    NOT NULL,
    segment        VARCHAR NOT NULL    -- SMB / Mid-Market / Enterprise
);

-- ------------------------------------------------------------
-- leads
--
-- marketing_cost_allocated is the spend attributed to this one
-- lead at capture time. It is a single-touch allocation, which
-- is the compromise most teams actually live with. Query 03
-- says so out loud in its caveat rather than pretending the
-- number is an attribution model.
--
-- converted_date and converted_opportunity_id are separately
-- nullable on purpose. A lead marked converted with no linked
-- opportunity is a real and common defect, and query 12 counts
-- how often it happens here.
-- ------------------------------------------------------------
CREATE TABLE leads (
    lead_id                  INTEGER PRIMARY KEY,
    account_id               INTEGER NOT NULL,
    source                   VARCHAR NOT NULL,
    sub_source               VARCHAR NOT NULL,
    created_date             DATE    NOT NULL,
    marketing_cost_allocated DECIMAL(10,2) NOT NULL,
    converted_date           DATE,
    converted_opportunity_id INTEGER
);

-- ------------------------------------------------------------
-- opportunities
--
-- amount is nullable. Roughly one deal in twenty has no amount,
-- which is what happens when reps create a record before they
-- have a number. Every revenue aggregation in this repo has to
-- decide what to do about that, and the queries say which
-- choice they made.
--
-- stage holds the current stage. is_won is a separate nullable
-- flag rather than being derived from stage, which is how most
-- CRMs model it, and which means the two can disagree. Query 12
-- checks whether they do.
--
-- source is denormalized from the originating lead. It is
-- copied at conversion time in the source system, so it can
-- drift from leads.source. The queries join back to leads when
-- cost matters and use this column when only the label matters.
-- ------------------------------------------------------------
CREATE TABLE opportunities (
    opportunity_id      INTEGER PRIMARY KEY,
    account_id          INTEGER NOT NULL,
    rep_id              INTEGER NOT NULL,
    source              VARCHAR NOT NULL,
    created_date        DATE    NOT NULL,
    stage               VARCHAR NOT NULL,
    amount              DECIMAL(12,2),
    forecast_category   VARCHAR NOT NULL,   -- Commit / Best Case / Pipeline / Omitted
    expected_close_date DATE    NOT NULL,
    actual_close_date   DATE,
    is_won              BOOLEAN,
    loss_reason         VARCHAR
);

-- ------------------------------------------------------------
-- stage_history
--
-- One row per recorded stage change, which makes this the only
-- table that can answer "how long did deals sit in Proposal"
-- and "what fraction of Discovery deals ever reach Proposal".
-- The current stage on opportunities cannot answer either.
--
-- Two conventions matter:
--   1. Ownership changes are recorded as a row where from_stage
--      equals to_stage, with changed_by_rep_id set to the new
--      owner. That is how a reassignment shows up here.
--   2. Rows are not guaranteed to be contiguous. Reps skip
--      stages, and integrations write partial history. Query 12
--      counts the skips instead of assuming they do not exist.
-- ------------------------------------------------------------
CREATE TABLE stage_history (
    id                 INTEGER PRIMARY KEY,
    opportunity_id     INTEGER NOT NULL,
    from_stage         VARCHAR NOT NULL,
    to_stage           VARCHAR NOT NULL,
    changed_at         DATE    NOT NULL,
    changed_by_rep_id  INTEGER NOT NULL
);

-- ------------------------------------------------------------
-- activities
--
-- Calls, emails, meetings and demos logged against a deal. The
-- grain is one row per logged touch, which is the grain that
-- makes activity-to-outcome analysis possible (query 09) and
-- also the grain that makes it easy to draw a causal conclusion
-- that the data does not support. The query header says so.
--
-- Logged is not the same as happened. Email sync logs itself,
-- calls only get logged when a rep bothers. Volume by type is
-- therefore a measure of tooling as much as of effort.
-- ------------------------------------------------------------
CREATE TABLE activities (
    activity_id    INTEGER PRIMARY KEY,
    opportunity_id INTEGER NOT NULL,
    rep_id         INTEGER NOT NULL,
    activity_type  VARCHAR NOT NULL,   -- Call / Email / Meeting / Demo / Note
    activity_date  DATE    NOT NULL
);

-- ------------------------------------------------------------
-- A note on foreign keys
--
-- Primary keys are declared. Foreign keys deliberately are not.
--
-- This is not laziness. A CRM export has no enforced referential
-- integrity: you get orphaned child records, opportunities
-- pointing at merged accounts, and activities logged by reps who
-- left. Declaring the constraints here would let the loader
-- reject exactly the rows that make this dataset worth querying,
-- and would teach the wrong lesson about what arrives in a real
-- extract. Integrity is checked in SQL instead, by
-- queries/12_data_hygiene_audit.sql, which is where a RevOps
-- team checks it too.
-- ------------------------------------------------------------
