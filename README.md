# StoreFlow — All-in-One Store Management System

Interactive demo using Next.js App Router, React, TypeScript, Tailwind CSS, Lucide and Recharts.

## Run locally
```bash
npm install
npm run dev
```
Open http://localhost:3000.

## Modules
Dashboard KPIs and charts; POS cart, discounts, optional VAT, payment methods, checkout and printable receipt; order history and CSV export; inventory management; employees, shift summary and leave request; payroll overview; CRM/loyalty; expenses; reports; role permission matrix; audit log. Switch roles between Owner / Manager / Cashier / Employee to explore menu visibility.

## Structure
- app/: Next.js App Router and global styles
- components/store-app.tsx: interactive UI modules
- lib/mock-data.ts: centralized sample data

## Production gaps
This is a client-side mock-data prototype. Authentication, database persistence, server-side authorization, payment processing, multi-branch isolation, legally verified payroll/tax calculation, persistent audit history, and full stock movement workflows are not implemented. Implement a secure API and server-side authorization before production.
