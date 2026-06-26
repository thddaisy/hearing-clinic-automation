-- ============================================================
-- Hearing Clinic Automation Pipeline — PostgreSQL Schema
-- ============================================================

-- 1. Hospitals master table (multi-tenant revenue share config)
CREATE TABLE hospitals (
    hospital_id          VARCHAR(10)    PRIMARY KEY,
    hospital_name        VARCHAR(100)   NOT NULL,
    revenue_share_rate   NUMERIC(4,2)   NOT NULL,  -- hospital's share e.g. 0.50, 0.30, 0.35
    contact_name         VARCHAR(50),
    contact_email        VARCHAR(100),
    created_at           TIMESTAMP      DEFAULT NOW()
);

INSERT INTO hospitals (hospital_id, hospital_name, revenue_share_rate) VALUES
    ('H-001', 'Christchurch ENT Clinic', 0.50),
    ('H-002', 'Selwyn Hearing Centre', 0.30),
    ('H-003', 'Canterbury Audiology Associates', 0.35);


-- 2. Consultation charts (AI-parsed from PDF uploads)
CREATE TABLE consultation_charts (
    chart_id             SERIAL         PRIMARY KEY,
    hospital_id          VARCHAR(10)    REFERENCES hospitals(hospital_id),
    chart_no             VARCHAR(20)    NOT NULL UNIQUE,
    patient_name         VARCHAR(50)    NOT NULL,
    consult_date         DATE           NOT NULL,
    doctor_name          VARCHAR(50)    NOT NULL,
    audiologist_name     VARCHAR(50)    NOT NULL,
    ear_side             VARCHAR(10),                -- Left / Right / Both
    demo_model           VARCHAR(100),
    consult_note         TEXT,
    record_type          VARCHAR(25)    NOT NULL,    -- New Consultation / Fitting Completed / Repair Completed
    created_at           TIMESTAMP      DEFAULT NOW()
);


-- 3. Sales & repair transactions (manual entry via Google Sheets)
CREATE TABLE clinic_sales_records (
    record_id            SERIAL         PRIMARY KEY,
    record_date          DATE           NOT NULL,
    hospital_id          VARCHAR(10)    NOT NULL REFERENCES hospitals(hospital_id),
    patient_name         VARCHAR(50)    NOT NULL,
    chart_no             VARCHAR(20)    NOT NULL,
    doctor_name          VARCHAR(50)    NOT NULL,
    audiologist_name     VARCHAR(50)    NOT NULL,
    transaction_type     VARCHAR(25)    NOT NULL,    -- New Consultation / Fitting Completed / Repair Completed
    brand                VARCHAR(50),                -- ReSound / Phonak / Signia / Widex
    product_model        VARCHAR(100),
    ear_side             VARCHAR(10),                -- Left / Right / Both
    sale_price           NUMERIC(12,2)  DEFAULT 0,
    repair_fee           NUMERIC(12,2)  DEFAULT 0,
    memo                 TEXT,
    created_at           TIMESTAMP      DEFAULT NOW()
);


-- 4. Indexes for aggregation and settlement queries
CREATE INDEX idx_records_date         ON clinic_sales_records(record_date);
CREATE INDEX idx_records_hospital     ON clinic_sales_records(hospital_id);
CREATE INDEX idx_records_type         ON clinic_sales_records(transaction_type);
CREATE INDEX idx_records_brand        ON clinic_sales_records(brand);
CREATE INDEX idx_charts_date          ON consultation_charts(consult_date);
CREATE INDEX idx_charts_hospital      ON consultation_charts(hospital_id);


-- ============================================================
-- Settlement Query Reference
-- ============================================================

-- [1] Daily summary (for 5pm email)
-- SELECT
--     COUNT(*) FILTER (WHERE transaction_type = 'New Consultation')  AS new_consultations,
--     COUNT(*) FILTER (WHERE transaction_type = 'Fitting Completed') AS fittings_completed,
--     COUNT(*) FILTER (WHERE transaction_type = 'Repair Completed')  AS repairs_completed,
--     SUM(sale_price)  AS total_sales,
--     SUM(repair_fee)  AS total_repair_revenue
-- FROM clinic_sales_records
-- WHERE record_date = CURRENT_DATE;


-- [2] Monthly hospital settlement (per hospital, fittings only, repairs excluded)
-- SELECT
--     h.hospital_name,
--     s.record_date,
--     s.patient_name,
--     s.brand,
--     s.product_model,
--     s.ear_side,
--     s.sale_price,
--     h.revenue_share_rate,
--     ROUND(s.sale_price * h.revenue_share_rate, 0) AS hospital_share
-- FROM clinic_sales_records s
-- JOIN hospitals h ON s.hospital_id = h.hospital_id
-- WHERE s.transaction_type = 'Fitting Completed'
--   AND s.record_date >= date_trunc('month', CURRENT_DATE - interval '1 month')
--   AND s.record_date <  date_trunc('month', CURRENT_DATE)
-- ORDER BY h.hospital_name, s.record_date;


-- [3] Monthly our brand (ReSound) closing — sales share + 100% repair revenue
-- SELECT
--     s.record_date,
--     h.hospital_name,
--     s.patient_name,
--     s.product_model,
--     s.ear_side,
--     s.transaction_type,
--     s.sale_price,
--     s.repair_fee,
--     ROUND(s.sale_price * (1 - h.revenue_share_rate), 0) AS our_sales_share,
--     s.repair_fee                                         AS exclusive_repair_revenue
-- FROM clinic_sales_records s
-- JOIN hospitals h ON s.hospital_id = h.hospital_id
-- WHERE s.brand = 'ReSound'
--   AND s.record_date >= date_trunc('month', CURRENT_DATE - interval '1 month')
--   AND s.record_date <  date_trunc('month', CURRENT_DATE)
-- ORDER BY s.record_date;


-- [4] Monthly competitor closing — isolated by brand (repairs included per brand)
-- SELECT
--     s.record_date,
--     h.hospital_name,
--     s.patient_name,
--     s.brand,
--     s.product_model,
--     s.ear_side,
--     s.transaction_type,
--     s.sale_price,
--     s.repair_fee
-- FROM clinic_sales_records s
-- JOIN hospitals h ON s.hospital_id = h.hospital_id
-- WHERE s.brand IN ('Phonak', 'Signia', 'Widex')
--   AND s.record_date >= date_trunc('month', CURRENT_DATE - interval '1 month')
--   AND s.record_date <  date_trunc('month', CURRENT_DATE)
-- ORDER BY s.brand, s.record_date;

