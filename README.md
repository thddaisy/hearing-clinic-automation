# AI-Powered N8N Pipeline for Multi-Stakeholder Hearing Clinic Settlement

## Overview

An end-to-end automation pipeline that turns unstructured daily consultation notes (PDF) and manually-logged sales records (Google Sheets) into a structured PostgreSQL database, daily operational summaries, and monthly multi-stakeholder financial settlements built using n8n, AI-based document parsing, and SQL.

## Background

During my time working as an audiologist across hearing aid clinics in Korea, I saw firsthand how much manual effort went into closing the books at month-end. Sales logs were handwritten, product codes were inconsistent across staff, and producing separate reports for the hospital, our company, and competitor brand suppliers , each with different rules and different visibility into the data, was a recurring source of errors and wasted hours.

This project rebuilds that workflow as an automated pipeline, applying the data engineering and BI skills I've developed since transitioning into analytics. It's designed around three real business rules from that environment:

1. **50/50 revenue share** between the hospital and the clinic on every hearing aid sale
2. **Multi-brand isolation** : our product line and competitor brands carried in the same clinic must be reported separately at month-end
3. **Repair revenue exception** : repair income is exclusive to the clinic and must be excluded from the hospital's 50/50 settlement, while still appearing in the clinic's own closing file

## Architecture

```
┌──────────────────┐     ┌───────────────────┐     ┌──────────────────────┐
│  PDF Chart       │     │  Google Sheet     │     │  Schedule Triggers   │
│  (Drive folder)  │     │  (daily sales log)│     │  (5pm / monthly)     │
└────────┬─────────┘     └─────────┬─────────┘     └──────────┬───────────┘
         │                         │                          │
         ▼                         ▼                          ▼
┌───────────────────────────────────────────────────────────────────────┐
│                          n8n Workflows                                │
│  1. PDF Ingestion & AI Parsing  →  PostgreSQL                         │
│  2. Daily Sync + Summary Email  →  PostgreSQL → HTML email            │
│  3. Monthly Settlement          →  PostgreSQL → 3x Excel files        │
└───────────────────────────────────────────────────────────────────────┘
         │
         ▼
┌──────────────────────────────────────────────────────────────────────┐
│                         PostgreSQL Database                          │
│  consultation_charts  |  sales_transactions                          │
└──────────────────────────────────────────────────────────────────────┘
```

*(See `docs/architecture-diagram.png` for the visual version)*

## Pipeline Components

### 1. Daily Chart Ingestion (AI Parsing)
- Detects new PDF consultation charts uploaded to a Google Drive folder
- Extracts text and passes it to an AI node (OpenAI/Gemini) with a structured-output prompt
- Parses the AI response into JSON and validates it
- Routes records via a Switch node into `New Consultation`, `Fitting Completed`, or `Repair Completed`
- Loads structured records into PostgreSQL

### 2. Daily Summary Email (Workflows 02a & 02b)

Split into two workflows to reflect real clinic operating hours across three hospitals.

**02a: AM Clinics** triggers at 13:00 NZT and covers Christchurch ENT Clinic (Monday to Friday, morning sessions).

**02b: PM Clinics** triggers at 18:00 NZT and covers Selwyn Hearing Centre (Monday, Wednesday, Friday) and Canterbury Audiology Associates (Tuesday, Thursday).

Each workflow:
- Pulls today's rows from the Google Sheets sales log (`clinic_sales_records`)
- Filters to the current date using NZT timezone (`Pacific/Auckland`)
- Skips hospitals with no activity on that day (if a clinic is not operating, no email is sent)
- Aggregates activity per hospital: new consultations, fittings completed, repairs completed, total sales revenue, and total repair revenue
- Sends a formatted HTML summary email to the supervising doctors at each hospital, signed off by the audiologist

**Key design decisions:**
- Timezone is explicitly set to `Pacific/Auckland` throughout to avoid UTC date mismatch
- Hospital metadata (name, recipient email, working days, shift) is managed in a single `hospitals` config object within the Code node, making it easy to add or update clinics without touching the workflow structure
- A clinic with zero transactions on a scheduled day still receives an email if it is a working day , reflecting the real-world expectation that a daily summary is sent regardless of volume
- Revenue share rate differs per hospital (50%, 30%, 35%) and is stored in the PostgreSQL `hospitals` master table for use in monthly settlement queries

### 3. Monthly Multi-Stakeholder Settlement
- Runs on the 1st of each month, querying the previous month's data from PostgreSQL
- Generates three separate CSV reports via parallel branches:
  - **Hospital Settlement**: fittings only (`Fitting Completed`), grouped by hospital — each hospital receives only their own data via individual email
  - **ReSound Closing**: all ReSound transactions (`Fitting Completed` + `Repair Completed`) — calculates our sales share and 100% repair revenue retained by clinic
  - **Multi-Brand Closing (Internal)**: competitor brand transactions (Phonak, Signia, Widex) — isolated from hospital settlement, sent to internal management only
- CSV files generated directly in n8n Code nodes using `Buffer` and base64 encoding — no external libraries required
- All amounts formatted with thousand separators (e.g. NZD 1,000.00) for readability
- Distributes each report to the appropriate recipient via HTML email with summary table and CSV attachment

## Tech Stack

- **Orchestration**: n8n
- **Database**: PostgreSQL
- **AI Parsing**: OpenAI / Gemini (via n8n AI nodes)
- **Data Sources**: Google Sheets, Google Drive
- **Output**: HTML email, Excel (.xlsx)

## Database Schema

See [`database/schema.sql`](database/schema.sql) for full DDL. Three core tables:

- `hospitals` : master table storing hospital name, revenue share rate, and contact details
- `consultation_charts` : structured output from AI-parsed PDF charts
- `clinic_sales_records` : daily sales and repair records including brand, price, ear side, and repair fee

## Key Business Logic (SQL)

The settlement rules are handled entirely at the SQL layer rather than in workflow logic, keeping the n8n workflows clean and the business rules transparent and testable.

**Hospital Settlement**
- Filters `transaction_type = 'Fitting Completed'` only — repairs are excluded from the hospital's revenue share
- Calculates `hospital_share = sale_price × revenue_share_rate` per transaction
- Groups by `hospital_id` so each hospital receives only their own data

**ReSound Closing**
- Includes both `Fitting Completed` and `Repair Completed` for ReSound brand
- Calculates `our_sales_share = sale_price × (1 - revenue_share_rate)` — the clinic's retained portion after paying the hospital
- Repair revenue is 100% retained by the clinic (`repair_fee` passed through in full)

**Multi-Brand Closing (Internal)**
- Filters `brand IN ('Phonak', 'Signia', 'Widex')` — competitor brands only
- Includes both fittings and repairs
- No revenue share calculation applied — raw figures for internal visibility only
- Completely isolated from the hospital settlement query

## Mock Data

[`mock-data/clinic_sales_records.csv`](mock-data/clinic_sales_records.csv) contains 96 rows covering June 2026, distributed across three hospitals and all three transaction types (new consultation, fitting completed, repair completed).

Key design choices in the mock data:
- ReSound (in-house brand) accounts for the majority of fittings, reflecting a realistic clinic where the primary brand dominates
- Each patient is assigned to one hospital only, with a hospital-specific chart number prefix (P1-xxx for H-001, P2-xxx for H-002, P3-xxx for H-003) , matching how medical record numbers work in practice
- Prices are in NZD and reflect realistic New Zealand hearing aid market pricing (NZD 1,600 to NZD 8,400 depending on model and whether fitting is unilateral or bilateral)
- Repair fees are separate from sale prices, enabling the repair revenue exclusion logic in the hospital settlement query

## Workflows

Exported n8n workflow JSON files are available in [`workflows/`](workflows/) and can be imported directly into a local n8n instance:

- [`[Clinic]-01-PDF-Chart-Ingestion.json`](workflows/[Clinic]-01-PDF-Chart-Ingestion.json)
- [`[Clinic]-02a-Daily-Summary-AM.json`](workflows/[Clinic]-02a-Daily-Summary-AM.json)
- [`[Clinic]-02b-Daily-Summary-PM.json`](workflows/[Clinic]-02b-Daily-Summary-PM.json)
- [`[Clinic]-03-Monthly-Settlement.json`](workflows/[Clinic]-03-Monthly-Settlement.json)

Note: Workflows reference a local PostgreSQL instance on port 5432. Update the PostgreSQL credential in n8n before importing.

## About This Project

This project sits at the intersection of two parts of my background: clinical audiology work in Korea, and my current path toward data analytics and engineering roles in New Zealand. It's a deliberately practical example of how messy, real-world operational data (handwritten logs, scanned charts, multiple stakeholders with conflicting reporting needs) can be turned into a reliable, automated reporting pipeline.
