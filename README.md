# StoreFlow — All-in-One Store Management System

Interactive demo using Next.js App Router, React, TypeScript, Tailwind CSS, Lucide and Recharts.

## Run locally
```bash
npm install
npm run dev
```
Open http://localhost:3000.

## Modules
Dashboard, POS cart and checkout, order history, inventory, employee directory and leave request, payroll overview, CRM and loyalty, expenses, reports and CSV export, role permission matrix, and audit log. Switch roles between Owner / Manager / Cashier / Employee to explore menu visibility.

## Structure
- app/: Next.js App Router and global styles
- components/store-app.tsx: interactive UI modules
- lib/mock-data.ts: centralized sample data

## Production gaps
This is a client-side mock prototype. Authentication, database persistence, server-side authorization, real payment processing, multi-branch isolation, legally verified payroll/tax calculation and persistent audit history are not implemented. Add a secure API and server-side access controls before production.
